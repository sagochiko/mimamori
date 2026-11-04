# 開発のハーネス

このリポジトリでは Claude Code を開発の中心に置いている。ここではそのための仕組み(CLAUDE.md、フック、サブエージェント、skill、MCP、mod)を、何のために置いたかと一緒に並べる。審査の「モデルや機能(Skills、サブエージェント、MCP、フックなど)を目的に応じて選び、使い分けているか」に答えるための文書でもある。

考え方は2つある。1つは破ってはいけない決まりへの違反を、Claude の注意力に頼らずフックで止めること。ハッカソンのルール(期間中に書いたものだけ、権利のない素材を使わない)、精度の測り方の公正さ(最後に測る組を見ない)、本番と秘密の扱いがこれにあたる。もう1つは ISUCON2026 を1人で優勝した Yoshinori Kawasaki さんの[当日編の記事](https://zenn.dev/luvtechno/articles/isucon2026-competition-day)にある、時刻と停滞をフックが見て監査役を呼ぶ仕組みを、締切が決まったハッカソンに合わせて持ち込むこと。

## 毎回渡すもの

`CONDITIONS.md` に、締切、今のマイルストーン、進んでよい範囲、精度の測定の予算を書く。セッションを始めるたびに、フック(`session-context.sh`)がその中身を残り時間と今のマイルストーンの Issue と一緒に Claude に渡す。指示は「CONDITIONS.md を読んでから次の Issue を進めて」の1行で足りるようにしてある。

`CLAUDE.md` はリポジトリから読み取れないことだけを書き、200行未満に収めた。iOS、裏側、試験用の例文、文書の決まりは `.claude/rules/` に分けてあり、それぞれの分野のファイルを触るときだけ読み込まれる。

## フック

すべて command 型で、決定的に動く。中身は `.claude/hooks/` にあり、`scripts/test-hooks.sh` が止めるべきものを止めるかを確かめる(`make verify` に含む)。

| フック | いつ | 何をするか | なぜ |
|---|---|---|---|
| `session-context.sh` | セッション開始 | 残り時間、マイルストーン、開いている Issue、作者待ちの件数、最新の精度、`CONDITIONS.md` を渡す。作者待ちは「作者: 」の Issue を gh で数えて5分ためておき、gh に届かなければ0ではなく ? と書く | 締切を前提に判断させるため |
| `guard-secrets.sh` | ツールの実行前 | `.dev.vars`、APNs の鍵、Google の秘密、wrangler の認証を読ませない。`server/.gitignore` にも `.dev.vars` を書き、`server/` の中から始めた再帰の grep にも拾わせない | permissions の deny では `grep -r` などを取りこぼすため |
| `guard-prior-work.sh` | ツールの実行前 | 作者が以前に作ったコードのフォルダを開かせない。その一覧(`.claude/prior-work.local`)と、公開してはいけない語の一覧(`.claude/private-terms.local`)を読ませない。どちらも git に入らず本体のツリーにしかないので、worktree の中からも `git rev-parse --git-common-dir` で本体を探す。テストだけが使う一覧の差し替えの変数を Claude が設定するのも止める | 期間中に書いたものだけが対象というルールと、公開する前の個人の情報を守るため |
| `guard-holdout.sh` | ツールの実行前 | 最後に1回だけ測る組(holdout)と、分ける前の例文を読ませない。どちらも最後の測定まで `.gitignore` に入れ、再帰の grep からも外す。最後の測定は作者が鍵のファイルを置いたときだけ通す。鍵のファイルは worktree の中からも本体の木で探し、`Makefile` の側も同じ所を見る | 精度の数字を、直すときに見ていない例文で出すため |
| `guard-prod.sh` | Bash の実行前 | 削除と取り返しのつかない操作だけを見る。コマンドを `lib.sh` の `shell_words` で語に分けてから読むので、引用符で割った語(`"DE""LETE"`)も1語として読む。wrangler の削除系、D1 の time-travel の restore、force push(短いフラグの束の中の `f`、`--force`、`--force-with-lease`、`--force-if-includes`、`--mirror`、`+` で始まる refspec。git の `-c`、`-C`、`--git-dir` などと、前に付いた `timeout` や `nohup` のようなラッパーは読み飛ばし、長いフラグの省略形も見る)は止める。`wrangler secret delete`、本番の D1 で DROP、DELETE、TRUNCATE を含む SQL(`--command` の文字列、`--file` で渡す SQL ファイル、`migrations apply --remote` のときの `migrations/*.sql` の注を除いた本文。大文字小文字を問わず、`deleted_at` のような語の一部は数えない)、遠隔のブランチを消す push(`--delete`、束の中の `d`、`--prune`、`:` で始まる refspec)、main への push(宛先が `main`、`heads/main`、`refs/heads/main`、`--all`、ワイルドカードの refspec。refspec を省くか `HEAD` のときは、push の前の最後の `cd` の先と `-C` の先の作業の木のブランチか push の先が main)、`gh api` の書き込み(GET と HEAD のほかのメソッド、`-X GET` 無しの `-f`、`-F`、`--field`、`--raw-field`、`--input`、graphql の mutation とファイルや標準入力から読む問い合わせ)は作者に聞く。中身を読めない SQL(変数、`$(`、見つからないファイル、見つからないマイグレーションの置き場)も聞く。デプロイ、ロールバック、秘密の登録、作業のブランチへの push、`gh api` の読み出し、App Store Connect への送信は、2026年11月4日から何も言わずに通す | wrangler は非対話のシェルでは自分の確認を飛ばすため。permissions の規則はコマンドの文字列しか見ず、ファイルの中の SQL や、フラグの束と refspec の意味を読めないため。allow の `git push*` と `gh api *` の下で、取り返しのつかない形だけを拾う |
| `guard-merge.sh` | Bash の実行前 | `gh pr merge` の前に PR を gh で読み、レビュー役の報告(見出し「mm-reviewer の報告」で始まり、ステータスを `ステータス: ...` の行か `## ステータス` の見出しと次の行で書いたコメント)と、本文の「レビュー」の節の指摘ごとの判断(採った、採らなかった、指摘なし)の両方があるか、閉じる Issue の未チェックの項目すべてに続きの Issue の番号があるか、PR の先頭が今の `origin/main` を含むかを確かめる。コマンドはシェルの語に分けて読むので、引用符やバックスラッシュ、`VAR=値` の前置き、`gh -R`、`if`、`for`、`{ }`、`time`、`!` の中のマージも見つける。PR は `merge` のあとの最初の引数で見分け、`2>&1` のようなリダイレクトは数えない。あとで入る `--auto` は止める。jq、gh、git が答えないときは通さない(`onFailure: block`、jq が無いときは gh、`--no-verify`、`core.hooksPath` を含むコマンドだけを止める) | レビューを通していない PR と、やり残しの行き先が書かれていない Issue を、注意力に頼らずに止めるため。別の PR が入ったあとは確かめ直させるため |
| `guard-private.sh` | Bash の実行前 | `gh issue` と `gh pr` で作る、直す、コメントするときに、コマンド(題と本文)と `--body-file` の中身を、git のフックと同じ規則(下の「git のフック」)で調べる。当たったら場所と規則だけを出して止める。本文を標準入力から渡す形(このコマンドの heredoc か、直前の `cat <<EOF |` を除く `-F -`、`/dev/stdin`)、`$(` やバッククォート、変数、`$'...'` で本文を作る形、`cd` のあとの相対の本文ファイル、`bash -c` や heredoc の中の gh の書き込みは、中身を調べられないので止める。コマンドはシェルの語に分けてから読み、引用符の中の語をフラグとみなさない。`git commit --no-verify`(`-n` をまとめた短いフラグ、`$'\x2d-no-verify'` も。`env git commit` や `bash -c` の中は前の文字の判定で拾う)と、フックの置き場を `.githooks` 以外にする操作も止める。落ちたら通さない(`onFailure: block`、jq が無いときは gh を含むコマンドだけを止める) | Issue と PR はリポジトリと一緒に公開されるのに、コミットのフックは通らないため |
| `format.sh` | 編集の後 | Swift は swift-format、TypeScript は Prettier で整える | 整形の差分でレビューを汚さないため |
| `stop-gate.sh` | 応答の終わり | 変わった側(`ios/Core`、`server`)のテストを流し、落ちていたら続けさせる。Issue のブランチでコミット済みの変更も対象にする。見る木はフックの入力の `cwd`(worktree の中ならその worktree)で、比べる相手は手元の main ではなく `origin/main`。`server/` が変わったのに `node_modules` が無いときは、通さずに `npm ci` を求める。裏でサブエージェントが書いているあいだは待ち、前回通った状態から変わっていなければ何もしない | 「直りました」と言う前に確かめさせるため |
| `pacer.sh` | 応答の終わり | 記録(`transcript_path`)の最後の本筋の応答から使ったコンテキストを測り、60%と80%を超えたときに一度ずつ `/mm-handoff` を促す。自動の要約が走ったあとも一度促す。締切の節目を越えたら一度だけ切り替えを知らせる。dev の精度が3回伸びない、1つの Issue が4時間を超えた、のどちらかで監査役を呼ぶよう促す | 要約で決めたことが抜ける前に引き継ぐため。局所的な直しを続けて時間を失わないため |
| `usage-log.sh` | サブエージェント、skill、コマンド、SendMessage の後 | 名前と時刻だけを記録する。SendMessage で同じサブエージェントに続きを頼んだ回数(レビューの2回目以降)も、相手の種類ごとに数える。`make usage` で `docs/claude-usage.md` になる | どの機能をどれだけ使ったかを数字で示すため |
| `compact-flag.sh` | 自動の要約の前 | このセッションで要約が走った印を残し、次の応答の終わりに `pacer.sh` が引き継ぎを促す | 要約のあとの記憶は要約なので、引き継ぎをリポジトリの状態から作り直させるため |
| `save-report.sh` | サブエージェントの報告の後(`SubagentHandback`) | 報告の原文をそのままファイルに残す。レビュー、監査、採点は `docs/audits/raw/` に(コミットする)、ほかは `.claude/logs/reports/` に置く。worktree で動いているときも本体の木に置く。1行目に「親のセッションが確かめる前のもの」と書く。ホームの道筋(`/Users/<名前>`)は `~` に替え、そう替えたことも1行目に書く。保存に失敗しても報告は止めず、記録に残す | 親が報告を手で写すと、落としたり取り違えたりしたため(2026年11月3日に2回あった) |

## git のフック

リポジトリは提出のときに公開するので、コミットにも家族の情報を入れない仕組みを `.githooks/` に置いた。`make setup` で `core.hooksPath` を向ける(`make bootstrap` の中でも流れる)。

- `commit-msg` はコミットメッセージの形を確かめる。メッセージに電話番号の形、メールアドレス、非公開の語、作者の以前のプロジェクトの名前が入っていたら止める。マージのメッセージも調べる
- `pre-commit` はステージした差分の足した行だけを調べ、同じ規則に当たったら止める。`origin/main` を取り込むマージの途中では、マージの相手(`MERGE_HEAD`)に既にある行を調べず、このブランチと、衝突を手で解いた行だけを調べる。main の行は main に入ったときに調べてあり、取り込むたびに止まると取り込めないため(2026年11月4日に作者が決めた)

規則は [`scripts/scan-private.sh`](../scripts/scan-private.sh) の1か所にあり、`guard-private.sh` と `/mm-endgame` の公開前の調べもこれを使う。電話番号は携帯、固定、+81 の形を、全角の数字も含めて見る。メールアドレスは `noreply@anthropic.com` と `*@users.noreply.github.com` だけを通す。非公開の語は作者だけが書く `.claude/private-terms.local` に1行に1語で置き、大文字と小文字を区別せずに探す。Claude はこの一覧を読まず、当たったときも語そのものは出さず「`docs/x.md:12: private term`」のように場所と規則だけを出す。

試験用の例文とテスト(`server/test/`、`eval/cases/`、`eval/test/`、`ios/Core/Tests/`、`scripts/test-hooks.sh`)では、電話番号とメールの形を調べない。詐欺の SMS の差出人や「サポートセンター 050-…」がテストの中身そのものだからだ。電話番号の形を判定する規則(`server/src/rules/`)と、レビュー役や監査役の報告の原文(`docs/audits/raw/`)も同じ扱いにした。規則は番号の型そのものを書き、原文は試験の作り物の番号や会社の公式のアドレスを引くため(2026年11月4日に作者が決めた)。公開前の全履歴の調べ(`scripts/scan-private.sh history`)も同じ範囲で見る。各コミットが足した行を見て、マージのコミットは数えないので、main から入った行を二重に数えない。非公開の語はそこでも調べるので、家族の本当の番号やアドレスは一覧のほうに書く。バンドル ID の `com.sagochiko.mimamori` とチームの ID は公開してよいもので、止めない。

自己テスト(`scripts/test-hooks.sh`)は、本物の一覧を読まないよう、テストのときだけ差し替えの変数でダミーの一覧を渡す。worktree から本体のツリーの一覧を見つけられるかも、使い捨てのリポジトリで確かめる。`.worktreeinclude` には2つの一覧を書き、Claude Code が作る worktree にも写させる。

## サブエージェント

実装とレビューを分け、レビュー、検証、監査、採点の役には編集のツールを渡していない(Bash は git や gh で読むために持つ)。過去の受賞作で公開リポジトリを確認できた8件のうち、サブエージェントの定義を置いていたものは無かった。数を増やすより、役割と使うモデルの理由が言えるものだけを置いた。

| 名前 | モデル | 役割 |
|---|---|---|
| `mm-implementer` | Opus | 1件の Issue をテストから実装する |
| `mm-verifier` | Sonnet | ビルド、テスト、シミュレータの画面を確かめ、数字と画像だけを返す |
| `mm-reviewer` | Opus | 書いた本人と別の目で、計画のつなぎ目の約束と設計との食い違いを探す。編集のツールを持たない |
| `mm-auditor` | Opus | 停滞したときに、判断の記録を `.claude/checklists/audit.md` と突き合わせる。編集のツールを持たない |
| `mm-judge` | Opus | 審査の4基準で採点し、一番弱い証拠を挙げる。ぶれがあるので2回走らせて比べる |
| `mm-eval-curator` | Sonnet | 公開されている注意喚起から試験用の例文を集める。分ける前の置き場(`eval/cases/pool/`)にだけ書ける。フックで止めている |

## skill

ユーザー側の同じ名前の skill がプロジェクト側に勝つことを確かめたので、すべて `mm-` を付けた。

| 名前 | 何をするか |
|---|---|
| `/mm-task` | 1件の Issue を、ブランチ、実装、検証、下書きの PR、レビュー、マージ、振り返りまで回す。レビューの報告は原文を PR のコメントに残す。複数の Issue を並べるときは Issue ごとに `.claude/worktrees/` に worktree を作る。マイルストーンの終わりには監査役を判断とハーネスの両方に走らせる |
| `/mm-autopilot` | 作者がいないあいだ、今のマイルストーンの Issue を順に回す。人が要る作業は積んで先へ進む |
| `/mm-devlog` | 開発の記録を、提出フォームの設問の順で書く |
| `/mm-eval` | dev の精度を予算の範囲で測り、記録する |
| `/mm-ios-verify` | シミュレータで画面を確かめる。実機でしか確かめられないものを分ける |
| `/mm-human-queue` | 作者にしかできない作業を「作者: 」の Issue にして待たずに次へ進む。結果を聞いたらコメントに残して閉じる |
| `/mm-endgame` | コードを止めてから提出までの確認。公開の前に、全履歴と Issue、PR を個人の情報の規則で調べる |
| `/mm-handoff` | コンテキストが埋まる前に、リポジトリの状態から引き継ぎの文書を作り、新しいターミナルで新しいセッションを立ち上げ、こちらは手を止める |
| `/mm-device` | 作者の iPhone 向けに自動の署名でビルドし、入れて起動する。人が画面を見る確認は作者の Issue に回す |
| `/mm-release` | ビルド番号を上げてアーカイブし、中身を確かめ、App Store Connect に送る。母と審査員のグループへの登録と審査用のメモは Claude in Chrome で入れ、作者には Submit Review を押すことだけを頼む |
| `/mm-deploy` | 裏側を出す。出したあとの確かめ、ログ、アプリの宛先の切り替えまで。遠隔の操作は何を変えるかを1行で言ってから流し、作者に聞くのは削除を含むものだけ |

Apple Developer の登録(bundle ID、App Group、capability、端末)は、`/mm-device` と `/mm-release` の `xcodebuild -allowProvisioningUpdates` が確認なしで書き換え、何を登録したかをあとで報告する。作者が一度 `/mm-device` を通しているので、受け入れた運用だと読んでいる。App Store Connect への送信(`-exportArchive`)は、2026年11月4日から作者の承認を待たずに流す。作者の承認が要るのは TestFlight の Submit Review から先だけだ。Submit Review は Claude in Chrome のクリックなのでフックを通らず、skill の指示と、押すのは作者という段取りで守っている。`/mm-release` は、ビルドの処理と Submit Review が終わったかを Claude in Chrome で App Store Connect の画面の状態の文字を読んで確かめ、5分おきに最大6回まで見る。App Store Connect API をシェルから読めばトークンを使わずに待てるが、署名に作者が期間の前に作ったコードを使うことになり、API の鍵のファイルを Claude が読むことにもなるので採らなかった。アプリはアプリの番号で直に開き、ほかのアプリが並ぶ一覧は開かない。

2026年11月4日に作者が、開発中は削除と取り返しのつかない操作のほかは許可を待たずに進めてよいと決めた。許可待ちで開発が遅れていたためだ。[`.claude/settings.json`](../.claude/settings.json) の allow に `gh api`、`git push`、`wrangler deploy`、`rollback`、`versions`、`secret put`、`secret list`、本番の D1 の `migrations` と `execute`、`altool`、`notarytool`、乱数を作る `openssl rand` を入れ、ask には `gh api` の DELETE(`-X DELETE`、`-XDELETE`、`--method DELETE`、`--method=DELETE`)、`wrangler secret delete`、`gh pr merge --admin` を残した(シミュレータの `erase` と `delete` も残していたが、2026年11月5日に外した。「設定の範囲」の節)。permissions の文書に「Rules are evaluated in order: deny, then ask, then allow. The first match in that order determines the outcome, and rule specificity doesn't change the order.」とあるので、allow の `gh api *` があっても ask の `gh api *-X DELETE*` が先に当たる。規則が狙いどおりに当たるかは、`scripts/test-hooks.sh` の `rule` が文書の照らし方(`*` は任意の文字、末尾の ` *` は引数なしにも当たる)をまねて確かめる。

同じ日の1回目のレビューで、allow の `git push*` と `gh api *` の下では、deny の文字列から漏れた形が黙って通ると分かった(原文は [`docs/audits/raw/20261104-1515-mm-reviewer-a669a95d.md`](audits/raw/20261104-1515-mm-reviewer-a669a95d.md))。`git push -fu`、`--mirror`、`--delete main`、`HEAD:main`、`gh api -X PATCH repos/o/r -f visibility=public`、`gh api -X PUT .../merge`、graphql の mutation がその例だ。文字列の規則ではフラグの束や refspec の意味を読めないので、判定は `guard-prod.sh` に置き、deny は文字列で拾える形の予備として残した。deny の `-f` と `+` は、`fix-f` や `c++fix` のようなブランチ名に当たらないよう、前に空白を置いた形(`git push* -f`、`git push* -f *`、`git push* +*`)にした。allow にしていた `git -c credential.helper= * push*` は消した。真ん中の `*` に `branch -D main` や `-c core.sshCommand=...` が入り、push 以外の git や任意のプログラムまで黙って通すうえ、リポジトリの手順でこの形を使う所は無かった。

本番の D1 のマイグレーションは、`migrations apply --remote`(と `--preview`)のとき、cwd、`cd` と `pushd` の先、作業の木の `server/` にある `migrations/*.sql` を全部読み、注(`--` から行末まで、`/* */`。`'--'` のような文字列の中の記号は注と見なさない)を外してから DROP、DELETE、TRUNCATE の語を探し、当たれば聞く。どのファイルがまだ流れていないかは遠隔にしか分からないので、全部を読む。SQLite で表を作り直すマイグレーション(新しい表を作る、写す、`DROP TABLE` する)は、「マイグレーションは確認なし」と「本番の D1 で DROP を含む SQL は聞く」のどちらにも読めたので、2026年11月4日に聞くほうに決めた。2026年11月4日の時点の `server/migrations/` の3つのファイルは注の中にしか当たる語が無く、聞かれない(`scripts/test-hooks.sh` で確かめている)。`server/package.json` に本番のマイグレーションを流す npm のスクリプトは無いので、`npm run` の中身は見ていない。足すときは同じ判定を掛ける。

## MCP

| 名前 | 何に使うか |
|---|---|
| `claude-docs` | Claude API と Managed Agents の現行の仕様を確かめる。モデル ID やベータヘッダーを記憶で書かないため |
| `cloudflare-docs` | Workers、D1、Queues の仕様を確かめる |
| `mobilebuildmcp` | シミュレータでの UI の操作と画面の階層の取得。`xcrun simctl` にはタップが無いため |

## mod

`.claude/skills/mm-band/` はプロンプトの入力欄の上に1行を出す mod でもある。残り時間、今のマイルストーンとその期限、最新の dev の精度、作者を待っている作業(開いている「作者: 」の Issue)の件数を出す。件数はセッションのフックと同じ5分の控えを使い、gh に届かないときは ? を出す。Claude に渡している情報と同じものを作者も常に見られるようにするために置いた。対話のセッションをリポジトリの直下で始めてフォルダを信頼したときに読み込まれる。

## 設定の範囲

作者のグローバルの設定(文章の決まり、質問の仕方、使用量のガード)はそのまま読み込み、このリポジトリに関係しないプラグインと skill だけを `.claude/settings.json` で切った。グローバルを丸ごと切り離す起動の仕方(`claude --setting-sources project,local`)も試したが、使用量のガードまで消えるので採らなかった。このリポジトリで要る決まりは、すべてリポジトリの中に書いてある。

主のモデルは Opus のままにし、Fable を advisor に付ける(`advisorModel: "fable"`)。2026年11月3日に作者が決め([`docs/audits/2026-11-03-2330-best-practice-research.md`](audits/2026-11-03-2330-best-practice-research.md) の「advisor とモデル」)、2026年11月4日の夜に作者がもう一度選んで入れた。[advisor](https://code.claude.com/docs/en/advisor) によると、advisor は相談のたびに advisor のモデルの単価でトークンを使い、「The advisor model's own read of the conversation is not cached」なので、会話が長いほど1回が高くなる。プランによっては、Fable を advisor にする前に `/model fable` で使用量のクレジットで払うことへの一度きりの同意が要り、同意の前は advisor なしで動く。`advisorModel` はどの設定のファイルにも書けるキー([settings-reference](https://code.claude.com/docs/en/settings-reference) の表の Scope が「Any file」)なので、作者のユーザー設定ではなくこのプロジェクトに置いた。サブエージェントも同じ advisor を受け継ぐので、Sonnet で安く回す役(mm-verifier、mm-eval-curator)でも、相談のたびに Fable の単価がかかる。`/advisor off` は作者のユーザー設定(`~/.claude/settings.json`)にも書き込む([settings-reference](https://code.claude.com/docs/en/settings-reference) の `advisorModel`「Claude Code saves your pick to this key」)。このリポジトリではプロジェクトの値のほうが強いので次のセッションでまた付くが、ほかのプロジェクトの advisor まで消えうる。ずっと止めるときは `.claude/settings.json` から消す。調べの文書では「同意のあとで入れる」としていたが、同意の前は advisor なしで動き、費用もかからない(advisor の文書「a Fable advisor bills nothing before you give it」)ので、先に入れて、要るときに同意を頼む順にした。

母を App Store Connect の内部テスターにする招待の送り直し(#2)は、auto mode の判定が「[Permission Grant]」で止める。作者が2026年11月5日に恒久に許可し、その許可は作者のユーザー設定(`~/.claude/settings.json`)の `autoMode.allow` に英文の1つとして置いた。判定はプロジェクトの設定の `autoMode` を読まない([auto-mode-config](https://code.claude.com/docs/en/auto-mode-config) の「The classifier doesn't read `autoMode` from project settings」)ので、リポジトリには置けない。ほかの Mac で開発するときは入れ直しが要る。入っているかは `claude auto-mode config` で見る。

シミュレータを消す、初期化するコマンド(`xcrun simctl delete`、`erase`)は確認なしに通す。はじめは家族役の「mimamori iPhone」(本番の家族に入っている)を消さないよう ask にしていたが、作業のために作った一時のシミュレータを片付けるたびに確認が出て、作者が寝ているあいだの作業が止まるので、2026年11月5日の夜に作者が「全部自動にする」を選んだ。消す前に `xcrun simctl list devices` で udid を見て、家族役でないことを確かめる。家族役を消すと、端末の鍵も消えて家族から抜けられない。家族役の端末がほかに残っていれば、`make simulator` で作り直し、その端末が出す招待のコードで入り直す。招待のコードは家族役の画面(`FamilyHomeView`)でしか出せないので、今の本番の家族のように家族役がこのシミュレータ1台なら、家族を作り直して母役の iPhone も入れ直すことになる。作者の手が要るので「作者: 」の Issue にする。

コミットには `Co-Authored-By: Claude` が付く(`attribution` の設定)。放置したときの要約(`idleCompaction`)は切り、窓の上端近くの自動の要約(1M のモデルで約967K トークン)は安全網として残した。要約の前に `/mm-handoff` で移るのが本筋だからだ。

監査役とレビュー役の報告の原文は `docs/audits/raw/` にフックが残す。`docs/audits/<日時>.md` は、親がそれを確かめたうえで書いた要約と決めたことで、原文のファイルへのリンクを付ける。

## 残っている穴

フックはツールの呼び出しの文字列を見て止めるので、Bash から Python や Node のスクリプトがファイルを開く読み方までは止めきれない。OS のレベルで確実に止めるのは Claude Code のサンドボックスだが、`xcodebuild` やシミュレータとの相性を確かめていないので、ハッカソン中は入れていない。秘密は Workers の秘密の置き場を正にし、手元の `.dev.vars` には開発用の値だけを置く。

試験用の例文の置き場と holdout の守りにも、文字列の判定では止めきれない書き方が残っている。`cd eval/cases && cat */a.jsonl` のように移ってからのワイルドカードと、`{dev,x}` のようなブレース展開だ。2026年11月3日のレビューで見つかった。大文字のパス、`eval/cases` の直下のワイルドカード、例文集めの役が置き場と holdout を1行に並べる形は止めている(`scripts/test-hooks.sh`)。わざと崩した書き方をしないと通らないので、サブエージェントには止められた操作を別の書き方で通さないよう指示して補う。

個人の情報の調べは文字だけを見る。画像、PDF、スクリーンショットの中の文字は調べないので、`docs/screenshots/` に置く画面はデモ用の家族で撮る。`gh api` で書く Issue やコメントも `guard-private.sh` を通らない。Issue、PR、コメントの本文は `gh issue` と `gh pr` で書き、`gh api` では書かない(CLAUDE.md の「データと安全」)。マージの関門も `gh pr merge` しか見ない。`gh api` の書き込み(PUT でのマージも含む)と main への push は、`guard-prod.sh` が読める形なら作者に聞く。読み切れない形は聞く側に倒すが、次の段落の穴が残る。Claude Code は permissions の規則を照らす前に `timeout`、`time`、`nice`、`nohup`、`stdbuf`、`command`、`builtin`、`noglob`、フラグの無い `xargs` を外す([permissions](https://code.claude.com/docs/en/permissions) の「Wrappers」)。外さないと `timeout 60 git push -fu origin main` が allow の `git push*` に当たり、フックも見ないまま通っていた(2026年11月4日の2回目のレビューで分かった)。今は `lib.sh` の `command_starts` が同じものを読み飛ばすので、`guard-prod.sh`、`guard-merge.sh`、`guard-private.sh` の3つともラッパーの奥の git と gh を見る。`command -v` と `command -V` は引くだけなので外さない。`env git`、`env gh`、フラグの付いた `xargs`(`xargs -n1 gh ...`)は、文書のとおり規則の側でも外れず `env` や `xargs` のコマンドとして照らされる。このリポジトリの allow には当たらないので、手動のモードなら確認が出る(auto mode では分類器が見る)。関門はこの形の奥を見ない。フラグの無い `xargs` は規則の側で外れるので、その奥の git push と `gh api` は、標準入力から何が足されるか読めないとして `guard-prod.sh` が聞く。その奥の Issue と PR の書き込みは `guard-private.sh` が、マージは `guard-merge.sh` が止める。refspec を省くか `HEAD` の push で、前に `(`、`)`、`cd -`、`cd --`、`popd`、変数を含む `cd` があるときは、最後の `cd` の先を追わず、セッションの cwd と全部の `cd` と `pushd` の先のどれかが main なら聞く。

それでも残る穴がある。`git --git-dir=<main の checkout>/.git push origin HEAD` と `GIT_DIR=<main の checkout>/.git git push origin HEAD` は、作業の木から流すと main を push するのに、フックは作業の木のブランチを見て黙って通す(2026年11月4日に `guard-prod.sh` に流して確かめた)。`git config alias.p push` のような git の別名と、`bash -c "git push ..."` の中の push も見分けない。これらは、deny の文字列(`--force`、` -f`、` +`)が拾う形のほかは、作業の流れの決まりだけが止めている。GitHub の側の守りも今は無い。非公開のリポジトリでは、ブランチの保護(`gh api repos/sagochiko/mimamori/branches/main/protection`)もルールセット(`gh api repos/sagochiko/mimamori/rulesets`)も「Upgrade to GitHub Pro or make this repository public to enable this feature.」の 403 が返り、使えない(2026年11月4日に API で確かめた)。提出のためにリポジトリを公開したら、main に force push の禁止、ブランチの削除の禁止、PR を必須にするルールセットを入れる。`bash -c` と heredoc の中の gh は、文字の判定で見つけて止めるが、`bash -c "$X"` のように変数で渡す形は見えない。語に分ける処理は `eval`、エイリアス、`$` の付かない `((...))` の中の `<<` を扱わない(`$((1<<2))` は扱う)。

この文書の仕組みは、コミットの前に別のレビュー役のサブエージェント(Opus)に試させた。見つかった10件(書きかけの裏の作業中にテストの関門が走る、`cd server && grep -rn` で秘密がすり抜ける、試験の約束が計画と skill で食い違う、など)を直してからコミットした。
