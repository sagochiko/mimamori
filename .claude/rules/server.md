---
paths:
  - "server/**"
---

# 裏側(Cloudflare Workers)の決まり

- 無料プランの範囲で動かす。1日10万リクエスト、1回の CPU 時間10ミリ秒。重い処理(Claude の判定、Managed Agents)はリクエストの中で待たず、Queues に回す。`waitUntil` はレスポンス後30秒までしか延びない
- 即答は決まった規則(`rules/`)で返し、Claude の判定はあとから重ねる。Claude が失敗するか遅れたときは規則の判定だけで知らせ、母には「確かめ中」と出す
- Claude の答えは Structured Outputs の決まった形だけを受け取る。`injection_suspected` が true なら危なさを1段重くする。通知先と共有の範囲は、Claude の答えや届いた文面では変わらない
- どの経路でも「安全です」と返さない
- 鍵は `wrangler secret put`(作者が実行する)と手元の `.dev.vars` だけ。形は `.dev.vars.example` に書く。本番の D1 への変更とデプロイは作者が確認してから行う(フックでも止めている)
- 型は `npx wrangler types` で生成し、手で書かない。テストは Vitest と `@cloudflare/vitest-plugin` で書く。外向きの通信は `@msw/cloudflare` で差し替える
- APNs への送信はデプロイした Worker で確かめる。手元の `wrangler dev` は HTTP/2 で失敗しうる
- ログに家族の印、端末の鍵、メッセージの本文を出さない
