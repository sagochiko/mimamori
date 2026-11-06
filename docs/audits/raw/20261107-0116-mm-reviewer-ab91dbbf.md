サブエージェントの報告の原文。親のセッションが確かめる前のもの。ホームの道筋だけを ~ に替えた。

ステータス: 直すべき指摘あり

## 指摘

1. ニセ警察の筋書きに届かない警察の相談で「電話を切って」が消えた(確度: 高い。実際に流して確かめた)

   [`server/src/consult-judge.ts`](server/src/consult-judge.ts) の919〜922行で、1段階と2段階の警告がいつも `LIKE_SCAM_BASIS + SCAM_ACTION` になった。母がまだ電話の最中で、筋書きの部品が1つだけの相談をすると、Claude が「電話を切って」と書いても母には届かない。worktree で `judgeConsult` を直接呼んだ結果は次のとおり。

   ```text
   知らない番号から電話があった。警察だって | script false | 詐欺の手口と似ているところがあります。お金や暗証番号の話には応じず、家族に確かめて | L 1 true
   警察を名乗る人から電話が来てる | script false | (同じ文) | L 1 true
   警察から電話。今話してる | script false | (同じ文) | L 1 true
   ```

   直す前は、ここで Claude の「電話を切って」が読まれていた(試験の1764行と2794行の変更前の期待がそう)。主役の場面の最初の一言や、筋書きを話したあとの「それってどういうこと?」(2172行、2925行)がこの分かれに入る。[`docs/design.md`](docs/design.md) の291行のデモの台本は「AI が筋書きを見抜いて『電話を切って』と返し」で、筋書きに届かない言い方で撮るとこれと食い違う。PR の「失うもの」が挙げているのは「続き」の答えだけで、最初の一言の分かれは書かれていない。直し方の案としては、`said` のどこかに筋書きの警察の部品があるとき(`scriptParts` の `police`、または `pointsBackAtScript`)は、1段階と2段階の答えを決まった `MATCH_BASIS + POLICE_ACTION` にする方法がある。どちらも決まった文なので、注入された文に引かれる心配は増えない。直さずに採るなら、design.md の291行とデモで話す言葉が筋書き(`policePlan`)に届くことを確かめ、PR に書いてほしい。

2. 試験の1409行が守っていた場面が、詐欺の経路では起きなくなった(確度: 中。重くない)

   1409行の試験は、母の言葉に決まった文の前半(「詐欺の手口と似ているところがありますって出たけど」)を足した形に書き換えられた。`repeats` による守りはまだ試験されている。外すと `AI_REPLY_ON_CARD` の期待と `expectNothingOf` が落ちる。ただ、Claude の文が母の言葉を写して `cases.ai_reply` に入る経路が残るのは、母に開いた相談があるときのスマホの案内(`reply: claude.action`、942行と [`server/src/consult.ts`](server/src/consult.ts) の283行)だけになった。その経路で写した文がカードに出ないことを確かめる試験は無い。plan.md の「母の言葉を家族の知らせに切り出さない」に当たるので、help の分かれでこの試験を1件足すとよい。

3. 文書の小さな食い違い(確度: 高い。軽い)

   design.md に足した文は「1段階と2段階(答えきれないときの2段階を含む)は『…家族に確かめて』…だけを返し」と書いている。ところが、案内しない話題や `handoff` の警告(899行)は、そのあとに「。家族に伝えました」が付く。1行足せば合う。

   プロンプト(315行)とスキーマ(238行、242行)の「basis と action は本人に読み上げます」を残した扱いは、この PR では妥当だと見た。食い違いは「読まれると思って書くのに読まれない」向きなので、母の安全は弱まらない。help の `action` は今も読み上げる。ただ PR の「残したこと」にあるだけでは忘れやすいので、`make eval` で測り直す Issue にしておくとよい。

## 確かめて問題なかったこと

- decidePlan のどの分かれでも、詐欺の答えに Claude の文が入らないこと。`npx tsx -e` で `judgeConsult` を直接呼んで確かめた。印を付けた `basis` と `action` を入れ、7つの言葉(メッセージ、振込、前を指す問い、スマホの困りごと、警察の筋書き、家族に知らせないでの文、「これ何」)、3つの前のやり取り、段階1〜3、`handoff` のあり・なし、`injection_suspected` のあり・なし、画像のあり・なしを組み合わせた。504回のうち、答えに印が入ったのは0回。Claude の答えが無い(`null`)ときも0回だった。出た答えは決まった6種類(1・2段階の警告、その「家族に伝えました」付き、3段階の1行、`HANDOFF_REPLY`、`ASK_AGAIN_REPLY`、筋書きの `MATCH_BASIS + POLICE_ACTION`)と、`UNANSWERED_REPLY` だけだった
- 段階、家族への知らせ、記録、`sign`、`reasons` は変わっていない。差分で変わったのは各 `return` の `reply` の値と、`readable`、`lowConcernReply`、`claudeSpeaks`、使われなくなった `talksJudgment` の import を消したことだけ。`talksJudgment` は今も [`server/src/claude.ts`](server/src/claude.ts) の158行で使われている
- `policePlan` は変わっていない。主役の筋書きの答えは今も「詐欺で使われる説明と一致しています。送金せず、いったん電話を切って家族に確かめて」で、上の組み合わせでも `script true` のときはこの文が出た。help の分かれ(927〜942行)、聞き返し(870〜881行)、画像の網も変わっていない
- 1671行の28件(`advice`)。詐欺の側は決まった1行の期待に変わった。「家族に確かめて」を `TOLD_CLAIM` が止めすぎないかは、1685行の同じ28件の help の試験が今も確かめている。`claims` の試験(1583行、1599行)も、読まれないことを今も確かめている
- #121 の詐欺の側の試験(3174行、3222行、3266行)。詐欺の答えでは判定の言葉がもう読まれないので、期待が決まった文になるのは筋が通る。判定の言葉を止める守りは、`talksJudgment` を使わない help の側では前から対象外だった
- 新しい40件の試験は、答えそのものと Claude の文が入っていないこと、段階、家族への push の有無を見ていて、壊れれば落ちる形になっている
- 3段階まで広げた判断は妥当だと見た。3段階は家族に知らせが行かないので、誘導された勧めが読まれても誰も気づけない。網では「リンクを開いて」と「リンクは開かないで」を分けられない。どちらも PR の説明と dev-log のとおり
- `npx vitest run test/consult.test.ts` は590件すべて通った。`npx tsc --noEmit` はエラーなし
- 秘密、家族の実データ、外から写したもの、`ios/Core` は差分に無い。eval/RESULTS.md に足した1行は規則だけの経路の行で、答えの文だけの変更なので数字が動かないのは筋が通る

関係するファイル
- ~/develop/mimamori/.claude/worktrees/issue-188-text-warning/server/src/consult-judge.ts
- ~/develop/mimamori/.claude/worktrees/issue-188-text-warning/server/src/consult.ts
- ~/develop/mimamori/.claude/worktrees/issue-188-text-warning/server/test/consult.test.ts
- ~/develop/mimamori/.claude/worktrees/issue-188-text-warning/docs/design.md
