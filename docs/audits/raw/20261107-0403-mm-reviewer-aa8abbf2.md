サブエージェントの報告の原文。親のセッションが確かめる前のもの。ホームの道筋だけを ~ に替えた。

ステータス: 承認

## 指摘

直すべき指摘は無い。1つだけ書き添えておく。

1. Claude を入れた精度はまだ測っていない(確度は高い、マージは止めない)。今回の [`eval/RESULTS.md`](~/develop/mimamori/.claude/worktrees/issue-193-prompt/eval/RESULTS.md) の行は `rules` の測定で、プロンプトを読まないので、この変更の影響は数字に出ない。言い回しの変化が判定(段階、kind、`injection_suspected`)を動かす筋は見当たらなかった。判定の段落(段階、印、筋書き、handoff、注入)は1文も変わっていない。読み上げの範囲を Claude に伝えても、kind を help 寄りにする誘いにはならない。それでも、確かめは #181 での `rules+claude` の測り直し待ちになる。PR は `Refs #193` なので Issue は開いたまま残り、2つ目のチェックとして追える。

## 確かめて問題なかったこと

- プロンプトの323行目の段落を一文ずつ `decidePlan`(`server/src/consult-judge.ts` の871〜1005行目)と突き合わせた。
  - 「読み上げるのは help の action だけ」は合っている。`claude.action` を `reply` に使うのは1004行目の1か所だけで、そこに来るのは help の答えだけになる。scam は 972行目(段階2以上)と 979行目(段階3の `LOW_CONCERN_ACTION`)で決まった文になる。
  - scam が全段階で決まった文になることも確かめた。handoff と案内しない話題の枝(949行目)でも決まった文になる。`pointsAtNothing` の枝(927行目)は `ASK_AGAIN_REPLY` を返す。
  - 家族のカードに Claude の basis と action が出ないことも確かめた。`basis` は 453行目と467行目で受け取るだけで、ほかのどこにも使われていない(`grep -rn basis server/src`)。カードの1行(topic の選び方、859〜868行目)の候補は topic、reasons、規則の reasons だけで、action は入らない。
  - help の答えを決まった文に替える条件の並びも、コードの枝と対応している。プロンプトの「メッセージ、電話、リンクの相談」は 981〜987行目の `CONTACT` と `rule.reasons`、「詐欺の心配が見えたとき」は 972行目の段階2以上、「案内しない話題」と「答えきれないとき」は 949行目の `sensitive`、`handoff` と 997行目の `!usable` にあたる。
- 329行目と331行目に残っている「これらが入った文は本人に読み上げず、決まった文に置き換えます」も、今のコードどおりだった。`usable` が `soundsSafe`、`REASSURING`、`TOLD_CLAIM` を見ている。2つ目のコミットで「判定の言葉が入った文を置き換える」を消したのは正しい。`usable` には判定の言葉の網が無い。
- スキーマは `description` の文字だけが変わり、型、enum、`required`、`additionalProperties` はそのままだった(差分で確かめた)。
- 画像の相談も同じ `SYSTEM_PROMPT` を使う(357〜359行目で注記を差し込むだけ)。スキーマも `...CONSULT_SCHEMA.properties` から作るので、直した文がそのまま届く。
- 足した試験は落ちうる形になっている。古い文が残っていないこと(`not.toContain`)と、新しい文が入っていること(`toContain`)を見ている。PR の本文にも、直す前に落ちたと書いてある。画像のスキーマの `action.description` を `toBe` で比べる行は、作りからして同じものになるので意味は薄いが、害はない。`npx vitest run test/consult.test.ts` は `603 passed` だった。
- 家族の通知先、共有の範囲、段階を下げる経路には手が入っていない。「安全」と返さない決まりと注入の段落も変わっていない。秘密、実在の家族のデータ、外から写したものは差分に無い。

関係するファイルは次の2つ。
- `~/develop/mimamori/.claude/worktrees/issue-193-prompt/server/src/consult-judge.ts`
- `~/develop/mimamori/.claude/worktrees/issue-193-prompt/server/test/consult.test.ts`
