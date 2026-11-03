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
