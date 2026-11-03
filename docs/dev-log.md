# 開発の記録

期間中にぶつかった問題、捨てた案、Claude の提案を採らなかった場面を、起きたときに書く。書き方は [`.claude/skills/mm-devlog/SKILL.md`](../.claude/skills/mm-devlog/SKILL.md) にある。各記録の5つの段落は、提出フォームの「開発中に一番詰まった場面」の設問の順(何を作ろうとしたか、Claude にどう頼んだか、何が起きたか、期待と何が違ったか、どう対処したか)に揃えている。

## 2026年11月3日 10:40 ハーネスの設計 (#1)

開発を始める前に、Claude Code の設定一式(CLAUDE.md、サブエージェント、skill、フック、MCP)をこのリポジトリに作っていた。審査の「Claude の活用」では Skills、サブエージェント、MCP、フックを目的に応じて使い分けているかを見る、とキックオフで説明があった。

Claude Code には要件、作りたいアプリ、Claude Code の最新の機能を踏まえて、要件と深さに必要な設定を作るよう頼んだ。調べものは3つのサブエージェント(Sonnet)に分け、Claude Code の機能、過去の受賞作とハーネスの考え方、iOS と Workers の道具を並行で調べさせた。

調べた結果、公開リポジトリを確認できた過去の受賞作8件のうち、`.claude/agents/` を置いていたものは0件、フックを置いていたものは1件だった。同じ名前の skill は、ユーザー側(`~/.claude/skills`)がプロジェクト側に勝つことも、`claude -p` で実測して分かった。Workers のテストの道具は旧名が非推奨になっており、wrangler は非対話のシェルでは本番の D1 への変更を確認なしで流すことも、ソースで確かめた。

計画を書いた2026年11月1日の時点では、プロジェクトの skill を好きな名前で置けば使われると思っていた。テストの道具も旧名のままで、本番への変更は wrangler 自身の確認で止まる前提だった。

プロジェクトの skill とサブエージェントには `mm-` を付けて名前の衝突を避けた。本番の D1 への変更とデプロイはフックで必ず作者に確認させ、holdout と、作者が以前に作ったコードのフォルダもフックで読めなくした。グローバルの設定を丸ごと切り離す案(`--setting-sources project,local`)もあったが、使用量ガードや質問の決まりまで消えるので採らず、関係ないプラグインと skill だけをプロジェクトの設定で切った。ISUCON2026 の優勝記事を参考に、締切の節目と停滞をフックが見て、監査役のサブエージェントを呼ぶよう促す仕組みも入れた。使ったのは Agent ツールの並行サブエージェント、`claude -p` での設定の実測、WebFetch。

## 2026年11月3日 11:50 ハーネスのレビューで見つかった穴 (#1)

コミットの前に、作ったハーネス(フック、permissions、サブエージェント、skill)が意図どおりに止めるかを確かめようとしていた。

Claude Code には、書いた本人とは別のレビュー役のサブエージェント(Opus)を立て、フックに入力を流して試し、実際に壊れるものだけを挙げるよう頼んだ。

10件の指摘が返った。重かったのは3つで、裏でサブエージェントが書きかけのときにテストの関門が走って書きかけのコードを止めること、`cd server && grep -rn KEY .` のように `server/` の中から再帰で探すと `.dev.vars` の中身が読めてしまい、フックは通してしまうこと、`cd eval/cases && cat holdout/a.jsonl` のような書き方で holdout を読めることだった。どれもレビュー役が手元で再現していた。

フックはツールの呼び出しの文字列を見れば止められると考えていた。Claude のシェルの grep は、探し始めたディレクトリの `.gitignore` しか見ないことは知らなかった。

テストの関門は、Stop フックに渡る `background_tasks` に動いているサブエージェントがあれば待つようにし、ブランチでコミット済みの変更も見るようにした。秘密は `server/.gitignore` にも書き、holdout と分ける前の例文は最後の測定まで `.gitignore` に入れて、再帰の grep から外した。フックの自己テスト(`scripts/test-hooks.sh`)に再現の4件を足し、`make verify` で毎回流す。Bash から別の言語のスクリプトがファイルを開く読み方は、フックでは止めきれないので、残っている穴として `docs/harness.md` に書いた。使ったのは、レビュー役のサブエージェント、PreToolUse と Stop のフック、`make verify`。

## 2026年11月3日 22:00 外向きの通信の差し替えが素通りする (#4)

裏側の土台で、「すべて消す」が Gmail の許可の取り消しと Managed Agents のセッションの削除を呼ぶところのテストを書いていた。どちらも本物の Google と Anthropic を叩かせたくない。

Claude Code の実装役には「テストは Vitest と `@cloudflare/vitest-plugin` で書き、外向きの通信は `@msw/cloudflare` で差し替える」と、`.claude/rules/server.md` の決まりのまま頼んだ。

`@msw/cloudflare` 0.2.0 の `setupNetwork()` は引数を取らず、msw 3.0.3 の既定は `onUnhandledFrame: "warn"` だった。差し替えを書き忘れた呼び出しは警告を出して本物のサーバーへそのまま出ていく。試しに差し替えの無い `fetch("https://example.com/probe-unhandled")` を流すと、警告のあと本物の example.com から 404 が返った。もう1つ、Cloudflare の文書は `readD1Migrations` を `@cloudflare/vitest-plugin/config` から読むと書いているが、1.5.1 のパッケージにはその入口が無く、本体(`@cloudflare/vitest-plugin`)からしか読めなかった。

差し替えを書かなければ通信は止まると思っていた。文書の入口もそのまま使える前提だった。

`test/network.ts` で `network.configure({ onUnhandledFrame: "error" })` を呼び、差し替えの無い通信はテストを落とすようにした。設定ファイルは workers-sdk の D1 の例に合わせて本体から読む。msw を外して `fetch` を手で差し替える案もあったが、決まりと公式の推奨から外れるので採らなかった。使ったのは mm-implementer、cloudflare-docs の MCP、`npx vitest run`。

## 2026年11月3日 22:00 Safari の拡張が入ったアプリがビルドできない (#5)

アプリと4つの拡張(Message Filter、Safari、共有、Call Directory)の土台を、XcodeGen の `ios/project.yml` から生成して、シミュレータ向けにビルドしようとしていた。

Claude Code の実装役には「`ios/project.yml` を正にして、拡張は中身の無いスタブでよいからビルドが通るところまで」と頼んだ。

Safari の拡張の `manifest.json` を、`Resources` という名前のフォルダごとバンドルに入れる書き方(`type: folder`)にしたところ、`xcodebuild` が16秒で `Couldn't load Info dictionary for ... SafariExtension.appex` で止まった。appex の中には `Info.plist` がちゃんと入っていた。

`Info.plist` が無いという意味だと思って中身を調べたが、原因は別だった。iOS のバンドルの一番上に `Resources` というフォルダがあると、CFBundle がそれを古い形のバンドルとして読み、`Resources/` の中に `Info.plist` を探しにいく。

フォルダごと入れるのをやめ、ファイルを1つずつバンドルの一番上へ写す書き方にして、ビルドは通った(作り直しから16秒)。フォルダの名前を変える案は、Safari が `manifest.json` をバンドルの一番上で探すので採らなかった。同じ確認の中で、`make simulator` が iOS 27.1 のランタイムに機種を作れない(`Incompatible device`)ことも分かり、今あった iOS 26.5 の iPhone 17 Pro で代わりに確かめた。使ったのは mm-implementer、`xcodebuild`、MobileBuildMCP の画面の操作。

## 2026年11月4日 00:50 シェルの語に分けるとフックが11秒かかった (PR #38)

ハーネスの直しの PR で、レビュー役が挙げた関門の穴を塞いでいた。`--body 'use -F or --body-file x'` のように本文の中の語をフラグと取り違えて止める一方で、`cat bad.md | gh issue create -F -` のように標準入力から渡す本文は素通りしていた。

Claude Code の実装役には「引用符の中の語をフラグとみなさない形に直せるなら直す。安全に直せないときは、直さずに報告に書く」と頼んだ。

最初に bash だけでコマンドをシェルの語に分ける関数を書いた。フックは `#!/bin/bash` で動くので、macOS では bash 3.2 になる。3.2 では `${s:i:1}` で1文字ずつ読むと文字列の長さの2乗で遅くなり、4万文字の引数1つで12秒、1600行の heredoc を持つ `gh issue create` では関門だけで11秒かかった。同じ作業の中で、テストとドキュメントを Bash の heredoc で書き換えようとしたところ、2回とも holdout の守りに止められた。書く文の中に、鍵のファイルの名前と最後の測定の make の目標が入っていたため。

ふだんの Bash 3.2 でも文字列の扱いは普通に速いと思っていた。ハーネスの文を直すだけで holdout の守りに当たることも考えていなかった。

語に分ける部分は awk に移し、同じ1600行の heredoc で0.2秒になった。守りに止められた書き換えは、止めた理由の文のとおり、その語を含む所だけを Edit で書いた。別の書き方で Bash を通す案は採らなかった。親から聞いた、レビュー役が原文をファイルに書き直すときも同じ守りに当たる件は、`/mm-task` の手順6に、止められた語だけを(伏せた)にすると書き足した。使ったのは mm-implementer、PreToolUse のフック、`scripts/test-hooks.sh`。

## 2026年11月4日 08:20 関門の判定が自分の正規表現で止まらなくなった (PR #38)

PR #38 の2回目のレビューの直しで、`env git commit` や `bash -c "git commit ..."` のように語に分けても見えない commit を、前の文字の判定で拾い直すところを書いていた。

Claude Code の実装役には、親から「`--no-verify` と `core.hooksPath` は、語に分けた判定で commit の頭が見つからなかったときに前の文字の判定に落とす」と頼まれていた。

自己テストが120秒を過ぎても終わらず、止めた。文字の判定のループで、`[[ "$rest" =~ $commit_re ]]` の当たりを `BASH_REMATCH[0]` から削る前に、`-n` を探す別の `=~` を挟んでいた。その2つ目の `=~` が `BASH_REMATCH` を上書きし、`rest` が短くならずに回り続けた。

`BASH_REMATCH` は当たった直後に使う値だと分かっていたつもりで、ループの中の別の判定で消えることまでは考えていなかった。フックは `onFailure: block` で30秒で切れるので、そのまま入っていたら、commit を含む Bash がすべて止まっていたはずだ。

当たりと引数を先に変数に写してから次の判定をする形に直し、自己テストは10秒で終わるようになった。同じ回のレビューの再現の入力62件を流し直し、止めるべきものが止まり、通すべきものが通ることを表にした。使ったのは mm-implementer、`scripts/test-hooks.sh`、TaskStop。
