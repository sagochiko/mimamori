サブエージェントの報告の原文。親のセッションが確かめる前のもの。ホームの道筋だけを ~ に替えた。

ステータス: 直すべき指摘あり

## 指摘

### 1. 43行目に足した「unless」が、`session_show_defaults` で見た既定より指示の文を優先させる(確度: 高い。この直しで入った退行)

[`~/develop/mimamori/.claude/worktrees/harness-ios-verify-defaults/.claude/skills/mm-ios-verify/SKILL.md`](~/develop/mimamori/.claude/worktrees/harness-ios-verify-defaults/.claude/skills/mm-ios-verify/SKILL.md) の43行目は、いま次の文になっている。

```text
So when its simulatorName is not the simulator you use, do not use mobilebuildmcp unless the main session wrote in your prompt that it moved the defaults to that simulator
```

主が既定を移して `simulatorName` が自分の端末と一致していれば、前半の条件はそもそも成り立たない。なので `unless` が働くのは、指示には「移した」とあるのに、見た既定は別の端末を指している場合だけになる。いちばん危ない場面で、文の上では使ってよいことになってしまう。

具体的な場面を挙げる。主が既定を「mimamori check-13」へ移したと書いて検証役を起こした。ところが `session_set_defaults` が失敗していたか、MCP のサーバーが起動し直して既定が `.mobilebuildmcp/config.yaml` の「mimamori mother」に戻っていた。検証役は `session_show_defaults` で食い違いに気づくが、`unless` に従って tap と `screenshot` を続ける。その結果、並べて動く別の作業の木が使っている「mimamori mother」を操作し、違う端末の画面を報告する。既定が家族役のまま残っていたなら、家族の画面が文脈に入る。

直し方は、条件を見た状態だけにすること。たとえば「`session_show_defaults` の `simulatorName` と `simulatorId` の両方が自分の端末と一致するときだけ mobilebuildmcp を使う。食い違えば指示に何とあっても使わず、そう報告する」と書く。これで1回目の指摘2(43行目と45行目の食い違い)も解ける。45行目では主が名前を書いて起こすので、一致すれば使い、一致しなければ使わないという1つの規則でそろう。

### 2. 検証役の側の確かめが `simulatorName` だけで、`simulatorId` を見ていない(確度: 中)

45行目では、主が `simulatorName` と `simulatorId` の両方を移して両方を戻すと書いた。1回目の指摘3は、主の側では直っている。一方で、43行目の検証役が確かめるのはまだ `simulatorName` だけだ。名前だけが移って id が前の端末(家族役を含む)のまま残った場合、検証役はそれを見抜けない。id が勝つかどうかは、1回目と同じく確かめていない。指摘1の直しで、名前と id の両方を見る形にすれば一緒に片づく。

### 3. tap が届かないときの順番を、43行目の末尾が古いまま言っている(確度: 中、軽い)

45行目は、まず自分の端末だけを `shutdown` と `boot` で起こし直し、それでもだめなら起動の引数と `xcrun simctl` に戻る、という順番を書いた。これは求めていた順番どおりだ。ただ43行目の末尾には `when that happens, reach the state with launch arguments and shoot with xcrun simctl` が残っている。先に43行目を読んだ検証役は、起こし直しを飛ばして起動の引数へ進む。43行目の末尾を「45行目の手順で起こし直し、だめなら起動の引数」とするか、末尾の指示を消して日付の事実だけを残すとそろう。

## 確かめて問題なかったこと

- 既定を移す先は、45行目で「このために作った端末」に限られている(`never one of unknown history, never "mimamori iPhone"`)。1回目に挙げた「the iPhone 17 Pro」は例から消えた。12行目と [`~/develop/mimamori/.claude/worktrees/harness-ios-verify-defaults/docs/harness.md`](~/develop/mimamori/.claude/worktrees/harness-ios-verify-defaults/docs/harness.md) の145行目にある、撮ってよい端末の決まりとも合う。報告が戻ったら端末を消す一文もある
- 45行目は、移すときも戻すときも `simulatorName` と `simulatorId` の両方を扱い、`persist` を使わない。12行目の書き方と同じだった
- 並べて動く検証役の条件として、`only while no other verifier is using mobilebuildmcp, since the defaults act for the whole session` が入った。起こすのは主なので、主の側でこの条件を確かめられる
- 起こし直すのは自分の端末だけで、「mimamori mother」は別の作業の木が使っているかもしれない、という断りが入った。その後で起動の引数に戻る順番も45行目にある
- 12行目は家族役を主の確かめにだけ使うと書き、45行目は検証役の tap に家族役を使わないと書く。範囲が違うので食い違いではない
- `origin/main` からの差分は SKILL.md の2行と `docs/audits/raw/` の原文1件だけ。フック、設定、コードには触れていないので、`scripts/test-hooks.sh` に足す場合は無い。秘密と家族の情報も差分に入っていない
- 1回目の指摘5について、PR #189 の本文の「レビュー」の節はまだ「(レビューのあとで書く)」のままだった。主が予定しているとおり、落とし穴の裏づけは検証役の原文が `docs/audits/raw/` に残らない仕組みのため、主の会話に戻った報告にしか無いことを、そこに書く必要がある
