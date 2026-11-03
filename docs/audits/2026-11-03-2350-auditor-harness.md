# 監査役の報告 2026年11月3日 23:50

監査役のサブエージェント(mm-auditor、Opus、編集のツールを持たない)に、その日に起きた13件の出来事と、Anthropic の文書(best-practices、memory、hooks-guide、permissions、worktrees、settings、costs、advisor、security、sub-agents、skills、sandboxing、effective-harnesses の記事)で、ハーネスを見直させた。報告の要点を親のセッションが転記した。表は報告のまま。

## 急ぎの件

worktree の `issue-8-handoff` と `harness-plumbing` が、ローカルの古い `main`(0155e24、`origin/main` より26コミット古い)から切られていた。親が確かめると、`harness-plumbing` だけがまだ古いままで、ほかは実装役が自分で取り込んでいた。原因は、GitHub でマージしたあとにローカルの `main` を合わせないまま worktree を切ったこと。

## ハーネスの変更の案

| 順 | 変更 | 失敗の種類 | 判定 |
|---|---|---|---|
| 1 | stop-gate.sh と pacer.sh が、フック入力の `cwd` から作業中のツリーを決め、`origin/main` との merge-base と比べる。node_modules が無ければ block する | 確かめずに完了 | 今すぐ |
| 2 | ガードが止めたときの文言に、正規の通し方(Write で書いて `--body-file`)を書く | 手間が見合わない | 今すぐ |
| 3 | 過去の作品の一覧も worktree で見つかるようにし、`.worktreeinclude` に書く | 例外の無い決まり | 今すぐ |
| 4 | deny に `gh repo edit*visibility*` と `gh issue delete*` を足す | 例外の無い決まり | 今すぐ |
| 5 | 実装役の定義に「作者の手順は Issue にしてから報告」「テストを消したり弱めたりしない」を足す(同じ指摘が2つの PR で出た) | 見えない情報 | 今すぐ |
| 6 | `make eval` の前に今日の回数を数えるフック(日本時間で数える) | 例外の無い決まり | M1 のあと |
| 7 | guard に `onFailure: "block"`、lib.sh は jq が無ければ止める | 例外の無い決まり | M1 のあと |
| 8 | PermissionDenied のフックで、auto mode が拒否した操作を記録する | 確かめずに完了 | M1 のあと |
| 9 | `make bootstrap` を作る | 手間が見合わない | M1 のあと |
| 10 | mm-endgame に `/security-review`、`/doctor prompt-audit`、`/usage` の書き写しを足す | 確かめずに完了 | M1 のあと |
| 11 | `permissions.blockReadsOutsideWorkingDirectories: true` | 例外の無い決まり | M1 のあと、試してから |
| 12 | サンドボックスを全面に入れる | 例外の無い決まり | やらない(締切前に道具が壊れるおそれ) |
| 13 | advisor をレビューに使う、レビュー役の `memory`、ConfigChange のフック、prompt 型のフック | なし | やらない |

## 進行中の直しへの注文

- マージの関門は、レビューの結果が本文にある場合とコメントにある場合の両方を受け付け、PR の head が `origin/main` を含むかも確かめる
- `docs/human-queue.md` を参照している約20か所を直す
- 並行の worktree では `git fetch origin` を先に流す
- ふり返りの結果は `docs/dev-log.md` に書く

## Issue ごとのふり返りの基準

確かめることは、前の PR と同じ種類の指摘があったか、フックや deny の誤検知の数、作者が判断のために割り込まれた回数、環境の手間で失った時間、チェックボックスと閉じた Issue が合っているか、レビューの往復が上限を超えたか。

変える目安は、同じ指摘が2回出たら定義か rules に1行足す、破ると取り返しがつかない決まりはフックか deny にする、誤検知が2回出たら判定を狭めるか文言に正規の道を書く、環境の手間は Makefile にまとめる。

変えない目安は、1回きりで繰り返しそうにない、判断が要り例外がある(best-practices の「a hook is for a rule with *zero* exceptions」)、締切までのコストのほうが大きい、審査にも次の Issue にも効かない。変えないと決めた件も、理由を1行 dev-log に残す。

## 見つかった食い違い(抜粋)

- `docs/harness.md` は「サブエージェントには止められた操作を別の書き方で通さないよう指示して補う」と書くが、どの定義にもその指示が無い
- mm-implementer は「main working tree で切ってある」前提だが、実際は worktree で動いている
- mm-task の「Stop after two review rounds」に対して、PR #33 は3回目の確認をしている
- 例文の形に `source_url` が無いのに、mm-eval-curator と rules/eval.md は `source_url` を求めている
- `docs/harness.md` は「決定的に動く」と書くが、jq が無いとガードが全部通る
- Stop の関門は node_modules が無いと黙って通し、worktree の変更とローカルの main の古さを見ていない

## 親のセッションの対応(2026年11月3日)

1〜5、9、進行中の直しへの注文、ふり返りの基準、`docs/human-queue.md` の参照の直しは、ハーネスの土台の直し(ブランチ `harness-plumbing`)に入れた。6〜8、10、11 は M1 のあとに回し、Issue にした。12 と 13 はやらない。理由は表のとおり。

## Anthropic の文書の推奨と、このリポジトリでの状態

監査役が、文書を節ごとに読んで分けた表。足りないものから並べている。sub-agents、skills、hooks のリファレンス、sandboxing は末尾を読み切れておらず、長く動くエージェントの記事は要約で読んだ(監査役の申告)。

| 文書 | 推奨(短い引用) | 状態 | 足すもの |
|---|---|---|---|
| worktrees | フックは作業中のファイルの道筋を入力の `cwd` から読む(監査役の言い換え) | 足りない | Stop の関門と pacer が作業中のツリーを `cwd` で決める |
| best-practices、worktrees | 「list the gitignored files you need in a `.worktreeinclude`」 | 足りない | 2つの非公開の一覧を `.worktreeinclude` に書く |
| best-practices | 「add `onFailure: "block"`」 | 足りない | ガードに付ける(#36) |
| best-practices | 「keep the install command in `CLAUDE.md`」 | 足りない | `make bootstrap` と CLAUDE.md の1行 |
| worktrees | 24時間以内に fetch していれば古いまま切られる | 足りない | worktree を切る前に `git fetch origin` |
| worktrees | 「Add `.claude/worktrees/` to your `.gitignore`」 | 足りない | 1行 |
| memory | 「Claude makes the same mistake a second time」 | 足りない | 同じ指摘が2つの PR で出たものを実装役の定義に足す |
| memory | 「Review your CLAUDE.md files… periodically」、`/doctor prompt-audit` | 足りない | マイルストーンの終わりの点検と mm-endgame(#36) |
| best-practices | 「If something has to happen every time, make it a hook, a deny rule」 | 一部 | 精度の測定の予算(#36)、公開の切り替えと Issue の削除の deny |
| permissions | 引数を縛る Bash の書き方は壊れやすい | 一部 | 本番は guard-prod がある。gh の削除と公開の切り替えが残る |
| best-practices | 「A reviewer… will always find *something*」 | 足りない | マイルストーンのあいだは、低い指摘を別の Issue に回す |
| security | `/security-review`、`/permissions` で権限を見直す | 足りない | mm-endgame(#36) |
| costs | `/usage` の内訳 | 足りない | 提出前に `docs/claude-usage.md` へ書き写す |
| effective-harnesses | 始める前に基本のテストを流して、元からの不具合を見つける | 足りない | ブランチを切った直後に `make verify` |
| effective-harnesses | テストを消したり書き換えたりしない | 足りない | 実装役の定義に足す |
| sub-agents | 頼むときに決まりをもう一度書く | 足りない | 止められた操作を別の書き方で通さないことを定義に入れる |
| permissions | `blockReadsOutsideWorkingDirectories` | 足りない(要確認) | 試してから入れる(#36) |
| sandboxing | 既定ではオフ | 入れていない(理由は harness.md) | 締切前に道具が壊れるおそれがあるので入れない |
| best-practices | CLAUDE.md を短く保つ | 入っている | 88行 |
| best-practices、memory | rules の `paths:` | 入っている | `.claude/rules/*.md` |
| best-practices | チームの手順は skill に | 入っている | mm-task、mm-endgame など |
| best-practices | Stop フックで確かめを強制する | 入っている(穴あり) | 穴は上の1つ目 |
| hooks-guide | 要約のあとに SessionStart で入れ直す | 入っている | matcher が無いので compact でも動く |
| hooks-guide | `stop_hook_active` | 入っている | stop-gate.sh、pacer.sh |
| permissions | Read の deny は Edit と Write も止める | 入っている | PR #23 のあと自己テストで確かめている |
| sub-agents | `tools`、`disallowedTools`、`model`、`maxTurns` | 入っている | `.claude/agents/*.md` |
| sub-agents | `memory: project` | 当てはまらない | レビュー役に書き込みが付いてしまう |
| skills | SKILL.md は500行まで | 入っている | 最長で57行 |
| skills | 手順の前にコマンドの結果を差し込む書き方 | 足りない(任意) | mm-task の先頭で fetch と Issue の取得を差し込む |
| costs | CLI を使う、テストの出力を絞る、単純な役に安いモデル | 入っている | gh、verify.sh、検証役と例文集めは Sonnet |
| security | 信頼できない文はデータとして扱う | 入っている | CLAUDE.md、rules/eval.md |
| security | MCP は信頼できる提供元のもの | 入っている | 公式の2つと、版を固定した mobilebuildmcp |
| advisor | 独立した確かめが要る場面の組み合わせ | 当てはまらない | レビューは mm-reviewer で足りる。主のセッションに Fable の advisor を付けるのは作者が決めた |
| effective-harnesses | 機能の一覧、進み具合のファイル、1回に1機能 | 入っている | Issue のチェックボックス、dev-log と PR の本文、1 Issue に1ブランチ |
