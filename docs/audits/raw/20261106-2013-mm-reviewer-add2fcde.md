サブエージェントの報告の原文。親のセッションが確かめる前のもの。ホームの道筋だけを ~ に替えた。

ステータス: 承認

## 指摘

直すべき指摘は無い。軽いもの(マージを止めない)を2つだけ挙げる。

1. 解決と送信がほぼ同時に起きると、解決済みの相談に最初の知らせが出る(確度は高い。ただ影響は小さい)。場所は `~/develop/mimamori/.claude/worktrees/issue-49-handoff-rest/server/src/cases.ts` の234行から240行。`state != 'resolved'` は取る UPDATE の時点でしか見ていない。取ったあと `sendCaseNotice` の `membersOf` から `sendPush` までのあいだに妹が「解決」を押すと、知らせはそのまま家族に届き、`family_notified_at` も立つ。家族は「1段階」の知らせと「(名前)が解決」の知らせをほぼ同時に受け取る。母に届く文言や共有の範囲は変わらず、窓も1回の送信の間だけなので、今の形で足りると思う。気になるなら、知らせ済みにする UPDATE に `AND state != 'resolved'` を足すかどうかを見る程度でよい。
2. `~/develop/mimamori/.claude/worktrees/issue-49-handoff-rest/docs/dev-log.md` に足した節の最後の段落(`使ったのは mm-implementer、…Vitest。`)のすぐ次の行に、空行を挟まず次の `## 2026年11月6日 言い回しの網は…` が続いている。表示は崩れないが、ほかの節と揃わない。

## 確かめて問題なかったこと

- 4の直し。`sendFirstNotices` の SELECT はもともと `c.state != 'resolved'` で絞っていた(379行)。だから穴はキューのやり直し(`openCase` から `tellFamily`)の経路だけで、取る UPDATE に条件を足せばその経路が塞がる。30分の見張り(448行、460行)、`resolveCase`(413行)、`openConsultCase`(`consult.ts` の138行)と同じ `!= 'resolved'` で揃っていて、古い `'accepted'` の行は解決していない側に数える。Issue には `AND state = 'notified'` と書いてあるが、引き受けの状態は `e44b03a` で無くなったので、今は `!= 'resolved'` が合っている。
- 解決済みの相談の後の流れ。`tellFamily` は `"already"` を返し、`openCase` は投げずに相談を返す。`judge.ts` の299行はそれを `"done"` と読み、やり直しを止める。母の新しい相談は `openConsultCase` が解決済みの相談を拾わないので新しい相談になり、この変更で家族への知らせが黙って消えることはない。
- 試験が本当に落ちるか。リポジトリの外の写し(scratchpad、確かめたあと消した)で3通り変えて試した。
  - `state != 'resolved'` を外すと「a retried openCase on a case the family resolved …」の1件が落ちた
  - 取る条件(`family_notice_claimed_at` の比較)を外すと、同時に取りにいく試験が `expected … length of 1 but got 2` で落ちた。`Promise.allSettled` の2本は実際に交互に走っていて、順に流れて通るだけの試験ではない
  - `break` を `continue` にすると、枠の試験が1件落ちた
  - 元のコードでは `npx vitest run test/cases.test.ts` が43件すべて通った
- 枠の試験の組み方。a は端末2台、b も2台、c は1台(妹の端末を消してある)で、枠は3。`break` を `continue` にすれば c に届いてしまう組み方なので、止まる動きを見分けられる。次の Cron の回で b と c に届くところまで見ている。
- PR 本文の1、2、5の判断はコードで見て正しかった。
  - 1。`e44b03a` も `26e2df9` も main に入っている(`git merge-base --is-ancestor` で確かめた)。引き受けと返事は `cases.ts` の6行から13行のとおり外され、`relays` は読み書きされない
  - 2。`family_notified_at` は届いたときだけ、取った印を放すのと同じ UPDATE で立つ(244行から248行)。途中で例外になっても残るのは `family_notice_claimed_at` だけで、知らせ済みにはならない。`CLAIM_TTL_MS` を過ぎれば次の送り手が引き継ぐ
  - 5。`consult.ts` の262行が `familyWasTold` を見て `NOT_REACHED` に置き換える。iOS は `CaseCards.swift` の139行が `familyWasTold` の無いあいだ「家族に届いていません」を出す
- 計画との食い違い。`docs/plan.md` の `openCase` の説明に足した1文は実装と合っている。知らせる相手(家族だけで、母には送らない)、知らせの中身(段階と要約の1行)、AI がいつも母に答えることは、どれも変わっていない。
- 差分は4ファイルだけで、マージのコミットが別の変更を運んでいないことを確かめた。秘密、家族の実データ、時刻は入っていない。`ios/Core` にも触れていない。メッセージの文が通知の相手や段階を変える経路も増えていない。

