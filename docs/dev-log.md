# 開発の記録

期間中にぶつかった問題、捨てた案、Claude の提案を採らなかった場面を、起きたときに書く。書き方は [`.claude/skills/mm-devlog/SKILL.md`](../.claude/skills/mm-devlog/SKILL.md) にある。各記録の5つの段落は、提出フォームの「開発中に一番詰まった場面」の設問の順(何を作ろうとしたか、Claude にどう頼んだか、何が起きたか、期待と何が違ったか、どう対処したか)に揃えている。

## 2026年11月3日 10:40 ハーネスの設計 (#1)

アプリのコードに入る前に、Claude Code の設定一式(CLAUDE.md、サブエージェント、skill、フック、MCP)をこのリポジトリに作っていた。作ったのは開発期間(2026年11月2日 12:30 から)の2日目の2026年11月3日の午前で、コミットは `d52f630`(11:57)。審査の「Claude の活用」では Skills、サブエージェント、MCP、フックを目的に応じて使い分けているかを見る、とキックオフで説明があった。

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

## 2026年11月3日 22:00 パーソナルボイスが日本語で作れない (#3)

初日の実機の確認(タスク1)のうち、家族の返事をその人の声で母に届ける仕組みを確かめようとしていた。計画では、家族の iPhone のパーソナルボイスで返事を音声ファイルに書き出し、母の iPhone で流すつもりだった。

作者は「実機でしか確かめられない項目は `/mm-human-queue` で `docs/human-queue.md` に積み、待たずに #4 と #5 へ進む」と指示していた。Claude Code は、実機が無くても調べられる項目を、調べものの役のサブエージェント(Sonnet)に先に調べさせた。

サブエージェントは約30の URL を読み、パーソナルボイスを作れる言語は3つだけだと返した。Claude Code が別のサブエージェントで原文を読み直すと、Apple の iOS 27 の提供状況のページの「Accessibility: Personal Voice」の欄にあるのは English (United States)、Mandarin Chinese (China mainland)、Spanish (Mexico) だけだった。日本語は VoiceOver などほかの欄にはあるが、この欄には無い。パーソナルボイスの音声をバッファに書き出そうとするとスピーカー再生に落ちる、という2023年のフォーラムの報告も見つかった。

計画では、確かめるのは音声ファイルに書き出せるかどうかだけで、日本語で作れることは前提にしていた。

Claude Code は、家族が自分の声を録って送る案を勧めた。録音なら言語に関係なく本人の声になり、まず文字の返事を通してから足せば、1〜2時間で済むという見立てだった(推測)。作者はいったん録音を選んだが、そのあと「家族の声は日本語無理そうならやめますか」と聞き直した。Claude Code が、日本語で使えないのは声を合成するパーソナルボイスだけで、録音なら使えると説明した。そのうえで作者は録音もやめ、家族の返事は文字で送り、母の iPhone の普通の読み上げの声で読む形に決めた。デモの「妹の声で返事が届く」は「妹の名前つきで返事が届いて読み上げられる」に変えた。使ったのは調べものと原文の確認のサブエージェント(Sonnet)2つ、AskUserQuestion、`/mm-human-queue`。

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
