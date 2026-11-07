---
paths:
  - "server/**"
---

# 裏側(Cloudflare Workers)の決まり

- 無料プランの範囲で動かす。1日10万リクエスト、1回の CPU 時間10ミリ秒。重い処理(Claude の判定、Managed Agents)はリクエストの中で待たず、Queues に回す。`waitUntil` はレスポンス後30秒までしか延びない。例外は母の声の相談(`POST /consult`)で、母が画面で待つ1往復なので、リクエストの中で Claude を待つ(15秒で打ち切り、規則だけで答える)。規則でニセ警察の筋書きと決まった相談は、Claude を待たずに答えて家族に知らせる。2026年11月4日に作者が決めた
- 即答は決まった規則(`rules/`)で返し、Claude の判定はあとから重ねる。Claude が失敗するか遅れたときは規則の判定だけで知らせ、母には「確かめ中」と出す。メールだけは、規則が確か(`confident`)な段階のほかは、知らせずに判定のキューの再試行で Claude の答えを3回目の受け取りまで待ち、それでも答えが無ければ規則の段階と「確かめ中」で知らせる(2026年11月7日、#249、PR #250。`docs/design.md` の Gmail の段落)。SMS、メール、ページで規則も段階を決めず Claude も答えなかったものは、誰にも知らせない(#137)
- Claude の答えは Structured Outputs の決まった形だけを受け取る。`injection_suspected` が true なら危なさを1段重くする。通知先と共有の範囲は、Claude の答えや届いた文面では変わらない
- どの経路でも「安全です」と返さない
- 鍵は Workers の秘密の置き場(`wrangler secret put`)と手元の `.dev.vars` だけ。形は `.dev.vars.example` に書く。値は作者が入れ(#30)、Claude は値を読まず、書かず、表示しない。`TOKEN_ENC_KEY` のような乱数を `openssl rand` からパイプで直に `wrangler secret put` に渡すのはよい
- 本番の D1 への変更とデプロイは、開発中は作者の確認を待たずに進める(2026年11月4日に決めた)。本番の D1 で DROP、DELETE、TRUNCATE を含む SQL と `wrangler secret delete` は `guard-prod.sh` が作者に聞かせ、wrangler の削除系と D1 の time-travel の restore は止める
- 型は `npx wrangler types` で生成し、手で書かない。テストは Vitest と `@cloudflare/vitest-plugin` で書く。外向きの通信は `@msw/cloudflare` で差し替える
- APNs への送信はデプロイした Worker で確かめる。手元の `wrangler dev` は HTTP/2 で失敗しうる
- ログに家族の印、端末の鍵、メッセージの本文を出さない
