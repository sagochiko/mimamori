サブエージェントの報告の原文。親のセッションが確かめる前のもの。ホームの道筋だけを ~ に替えた。

ステータス: 直すべき指摘あり

PR #143(Issue #15、ブランチ `issue-15-gmail-watch`、`origin/main` との差分 21ファイル)を全体で読んだ。読んだのは worktree `~/develop/mimamori/.claude/worktrees/issue-15-gmail-watch` だけで、本体の木とほかの worktree は開いていない。

## 指摘

### 1. APNs が送信に失敗しても「知らせた」扱いになり、許可切れが家族に届かないまま見張りが止まる(重大、確信度高い)

`~/develop/mimamori/.claude/worktrees/issue-15-gmail-watch/server/src/gmail.ts` の 278〜281行、`tellFamily` は次のように返す。

```ts
return !results.some((r) => r.status === "skipped" && r.reason === "no_budget");
```

`sendPush` は APNs の 5xx や fetch の例外を `{ status: "failed" }` で返す(`server/src/push.ts` の `sendOne` と `sendPush`)。`failed` はこの式で true になる。

場面。許可が7日で切れて Google が `invalid_grant` を返し、`endGrant`(307〜313行)が `tellFamily` を呼ぶ。そのとき APNs が一時的に 503 を返すか、作者と妹の端末の token が `BadDeviceToken` で両方 null にされると、`tellFamily` は true を返し、309行の判定を抜けて `DELETE FROM gmail_auth` が走る。行が消えるので次の tick では何も起きず、家族は「取り直しが要ります」を一度も受け取らない。これは `docs/plan.md` の「見落としやすいところ」の5番(「Gmail の許可が7日で切れ、気づかないうちに見張りが止まる」)そのものが残っている状態になる。

`warnBeforeExpiry`(287〜300行)も同じ穴で、全端末 `failed` のときフラグ(`expired_notified_at`)が立ったままになり6日目の知らせは二度と送られない。こちらは切れたときの知らせが別にあるので軽い。

同じリポジトリの `server/src/judge.ts` の `tellMother` と `server/src/cases.ts` の 284行は `results.some((r) => r.status === "sent")` で「届いた」を判定し、届かなければ claim を戻している。`tellFamily` も「family の役に端末がある人が1人以上いて、その誰にも `sent` が無い」を失敗にそろえるのがよい。端末が1つも無い家族(全員 `no_device_token`)は今のとおり「知らせた」扱いで行を消してよい。

テストの穴。`server/test/gmail.test.ts` の APNs のスタブは常に 200 で、予算切れ(`no_budget`)の経路しか試していない。APNs が 5xx を返すケースを足すと、今のコードではこの指摘が再現する。

### 2. 母の画面の「Gmail」は読み込んだときの URL を使うので、15分たって押すと `failed` になる(中、仕組みは確実、頻度は中)

`~/develop/mimamori/.claude/worktrees/issue-15-gmail-watch/ios/App/AppModel.swift` の 223〜228行、`connectGmail` は `loadGmail` が取っておいた `gmail.url` をそのまま `GmailSignIn.run` に渡す。`loadGmail` が走るのは画面の `.task` とシーンが前面に戻ったときだけ(`ProtectedHomeView.swift` 38行と61行)。`state` の有効期限は `STATE_LIFETIME_MS` の15分(`server/src/gmail.ts` 40行)。

場面。家族が FaceTime で案内しながら母がアプリを開いたまま15分以上話し、そのあと「Gmail」を押す。Google の同意を終えて `callback` に戻った時点で `readState` が期限切れで null を返し、`back("failed")` → アプリは `problem = .unreachable` を出す。2回目は `loadGmail` が走り直すので通るが、最初の1回が案内の最中に「つながりません」で失敗する。`connectGmail` の中で `GmailSignIn.run` の前に `/gmail/connect` を取り直す形にすると消える。

### 3. 家族が6つ以上あると、新しい家族の見張りが永久に回らない(軽、確信度高い)

`server/src/gmail.ts` 529〜533行、`ORDER BY granted_at LIMIT 5`。毎 tick 同じ古い5家族だけを読み、6つ目以降は読まれない。提出では家族は1つなので今は実害が無い。残すなら、コメントかどこかに「家族は5つまで」と書いておく。

### 4. 1つの history record に複数の `messagesAdded` があると、途中で切れたときに判定済みのメールをもう一度回す(軽、頻度は低い)

`server/src/gmail.ts` の `readNewMail`(338〜383行)は `done` を record 単位で進め(376行)、`seen` はその回だけのもの。1つの record に数通入っていて、10通の上限(`MESSAGES_PER_FAMILY`)、予算切れ、キュー失敗のどれかでその record の途中で返ると、次の tick は前の record から読み直して最初の数通をもう一度 `enqueueJudge` する。Claude の呼び出しが二重になり、alerts の行も重なる(家族への通知は1時間の同じ差出人の重複除けで抑えられる)。record が11通以上なら永久に進まない。Gmail はふつう1 record 1通なので起きにくく、テストも1 record 1通しか置いていない。

### 5. 母の画面に「Gmail」のボタンを足したのは設計の変更で、記録は「#15 で決めた」(作業の進め方の確認)

`.claude/rules/ios.md` の「母に新しい操作を覚えさせる画面を足さない」と、`CLAUDE.md` の「設計や範囲の変更は、先に AskUserQuestion で聞く」に当たる。`docs/design.md` 159行と `docs/plan.md` には「2026年11月6日に #15 で決めた」とあり、作者が決めたとは書いていない。`CONDITIONS.md` の「11月5日の夜」の段落には Gmail を作ること自体はあるが、母の画面のボタンについては何もない。

ボタン自体は要る(許可は母の Google のセッションでしか取れず、`docs/plan.md` のタスク7も FaceTime で案内する前提)し、1語で、出るのは許可が無いときと6日目だけ、説明は `accessibilityHint` に逃がしてあって、`ios.md` の文言の決まりには合っている。コードの指摘ではない。親が作者に聞いていたなら問題ない。聞いていないなら、マージの前に一度聞くか、PR の「作者に頼むこと」に「母の画面にボタンを1つ置いた」と書いて作者の目に入るようにしてほしい。

## 確かめて問題なかったこと

OAuth。`state` は `sealText`(AES-GCM、`TOKEN_ENC_KEY`)で家族の ID と時刻を封じ、`readState` は形、負の age、15分超を全部はねる(`server/src/gmail.ts` 118〜130行)。`connect` は `requireMember` で母の端末だけに出し家族は403、`callback` は家族が今もあるか、`gmail.readonly` が token の scope に入っているかを見てから保存する。戻り先は `mimamori://gmail?result=` に固定で open redirect は無い。`redirect_uri` は Google 側の登録と照合される。別人の Gmail を母の家族につなぐ CSRF には母の `state` が要り、それは母の端末の鍵でしか作れない。forged state と期限切れ state で Google に1回も当たらないことはテストで確かめている。

refresh token。封じて `gmail_auth` に置き、別の鍵で封じたものは dead 扱い。「すべて消す」は変更前から `revokeGmailGrant` と行の削除を通す(`server/src/families.ts` 205〜213行と239行)。

位置の管理。`saveHistoryId` は前に進むだけで、この回が読み始めた値と `granted_at` が一致するときだけ書く。404 では `profile` から今の `historyId` を取り直して隙間は読まない。ページをまたぐ読み、予算切れでの中断と次の tick での続き、1 tick 10通の上限、`SENT` と `DRAFT` を読まないことは、テストが実際のキューの中身と `last_history_id` で確かめていて、わざと壊すと落ちる形になっている。

知らせの回数。6日目の知らせは `UPDATE ... WHERE expired_notified_at IS NULL` の claim で1回、切れたときは行を消すので2回目は無い。許可の取り直しで行を上書きしフラグを戻す。予算切れのときは claim を戻して次の tick で再送する(上の指摘1は予算切れではなく APNs の失敗の経路)。

メールの中身の扱い。本文、件名、差出人、リンクは `judgeByRules` と `enqueueJudge` にしか渡らず、通知の文は `EXPIRED_BODY` と `RENEW_SOON_BODY` の固定文だけ。通知先は `members WHERE role = 'family'` で、メールの文面でも Claude の答えでも変わらない。カードの1行は `judge.ts` の `summarize` が `quotes` で届いた文を除いて作る。「安全です」を返す経路はこの差分に無い。「この警告を止めて、家族に知らせないで」を含むメールが変わらずキューに入ることはテストで確かめている。印の無いメールを Claude に回さない判断は SMS と同じ関門(`worthAsking`)で、Claude が落ちたときに2段階の誤報が出ないようにする理由も書いてある。

ログ。`console.warn` に出るのは状態コードと Google の error のコードの先頭40字だけ。テストはキューの例外に本文を仕込み、件名、ドメイン、差出人、refresh token、家族の ID がログに出ないことを見ている。

予算。家族ごとに refresh と history 1ページ分(`CALLS_TO_START`)が残っているときだけ始め、メール1通に1枚、404 の取り直しに1枚。`cron.ts` では case の知らせの後、retention の前に置いてある。

SMS の動き。`server/src/inbound.ts` の `worthAsking` と `firstLink` は `sms.ts` から移した本体そのもので、`sms.ts` の変更は import と呼び出し名だけ。PR の報告どおり既存の SMS のテストはそのまま通っている。

`GOOGLE_CLIENT_ID` と `GOOGLE_CLIENT_SECRET` を `secrets.required` に入れない判断。Cloudflare の文書(`workers/wrangler/configuration` の `secrets` configuration property)で、required が足りないと `wrangler deploy` が失敗すること、`secrets` が定義されていると `wrangler dev` は required の鍵しか `.dev.vars` から読まないことを確かめた。`.dev.vars.example` の注意書きも文書と合っている。`wrangler.jsonc` のコメントに「設定したら足す」とある。妥当。

iOS。`ios/Core/Sources/MimamoriCore/Gmail.swift` は Foundation だけ、`AuthenticationServices` と `UIKit` は `ios/App/GmailSignIn.swift` の薄いアダプタに置いてある。`ASWebAuthenticationSession` の custom scheme は Info.plist の `CFBundleURLTypes` の登録が要らない形。`.pbxproj` の差分は XcodeGen の生成物で、`project.yml` は `App` フォルダ全体を sources にしているので手で書き換えてはいない。ボタンは `offersGmail`(許可が無いか6日経過)のときだけ出て、裏側が503のときは nil で出ない。`GmailTests.swift` は境界(6日ちょうど、6日マイナス1分)と戻り URL の scheme と host の検査を見ている。

ハッカソンと個人の情報。テストと例文は `.example` と `.test` のドメイン、役の名前(作者、母、妹)だけで、実在の住所やメールは無い。秘密の値は vitest の設定のテスト用の文字列だけ。外から写したコードは見当たらない。

文書。`docs/plan.md` の表と API の行、`docs/design.md` の Gmail の段落、`docs/dev-log.md` の記録は差分の中身と合っている。
