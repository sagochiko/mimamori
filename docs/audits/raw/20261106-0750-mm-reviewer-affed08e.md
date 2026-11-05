サブエージェントの報告の原文。親のセッションが確かめる前のもの。ホームの道筋だけを ~ に替えた。

ステータス: 直すべき指摘あり

mm-reviewer の2回目の報告(PR #154、Issue #110、作業の木 `~/develop/mimamori/.claude/worktrees/issue-110-ios-verify-sim`、先頭 `20bbcce`)。直しのコミット `d7d0f30` の差分(`.claude/skills/mm-ios-verify/SKILL.md` の12行と43行、`docs/harness.md` の141行)と、1回目の原文 `docs/audits/raw/20261106-0738-mm-reviewer-a1a8975b.md`、`.claude/skills/mm-screen-guide/SKILL.md` の22行と手順4、`.claude/hooks/guard-mcp.sh`、`.mobilebuildmcp/config.yaml` を読んだ。merge のコミット `20bbcce` はハーネスの4つのファイルに変更を持ち込んでいない(`git diff d7d0f30 20bbcce --stat` が空)。

## 指摘

### 1. 43行の逃げ道「毎回 `simulatorId` に udid を渡す」は、mobilebuildmcp の道具に存在しない(直すべき、確からしさ 高)

`~/develop/mimamori/.claude/worktrees/issue-110-ios-verify-sim/.claude/skills/mm-ios-verify/SKILL.md` の43行は、既定が自分の端末でなければ「pass your simulator's udid as `simulatorId` on every call, or stop and report it」と書き、作って消す端末でも同じ方法を取れと書く。しかし、このセッションで読み込んだ `mobilebuildmcp@2.7.1`(`.mcp.json` の指定)の道具の schema には、`screenshot`、`snapshot_ui`、`tap`、`touch`、`gesture`、`batch`、`wait_for_ui`、`launch_app_sim`、`install_app_sim`、`build_run_sim` のどれにも `simulatorId` が無い。あるのは `session_set_defaults` だけで、それはサブエージェントには `guard-mcp.sh` が止める。

入っている実装でも確かめた。`~/.npm/_npx/b998b4270960e258/node_modules/mobilebuildmcp/build/mcp/tools/ui-automation/snapshot_ui.js` は公開の schema を次のように作り、`simulatorId` を外した strict なオブジェクトにしている。

```js
const publicSchemaObject = z.strictObject(
  snapshotUiSchema.omit({ simulatorId: true }).shape
);
```

端末は `build/utils/typed-tool-factory.js` の `createSessionAwareHandler` が session の既定から補う。`simulatorId` を引数に付ける道が戻るのは config の `disableSessionDefaults` を立てたときだけで(`build/utils/environment.js` の41行)、`.mobilebuildmcp/config.yaml` にその設定は無い。

起きること。検証役が43行どおり `simulatorId` を付けて呼ぶと、schema に無い引数なので呼び出し自体が通らない(Claude Code 側の入力の検査か、strict な zod のどちらかで止まる)。黙って家族役へ落ちることは無いので漏れの道ではないが、skill が主として示す逃げ道が使えず、検証役は「止めて報告」しか取れない。「サブエージェントは作った端末では udid を渡す」という文も同じく成り立たないので、作って消す端末では mobilebuildmcp の UI 操作はそもそも使えない。1回目の指摘1は「止めて報告」の側だけで閉じていて、udid の側は閉じていない。

直し方は1〜2文。既定の `simulatorName` が自分の端末でないとき、または自分で作った端末を使うときは、mobilebuildmcp は使わず、起動の引数で状態を入れて `xcrun simctl io "$SIM" screenshot` で撮る(43行の末尾にすでにある逃げ道)。既定が家族役だったことは報告に書き、主が戻す。

同じ誤りが、この PR の差分に入っている2か所にも元からある(今回の直しで入ったものではない)。`.claude/skills/mm-screen-guide/SKILL.md` の22行「it passes the udid or asks the main session」と、`.claude/hooks/guard-mcp.sh` の止めるメッセージ「or pass the simulator's udid on each call」。PR が両方のファイルを触っているので、同じコミットで「udid」の文を消して「主に頼む」だけにするとよい。

### 2. `mm-screen-guide` の手順4は「手順2で控えた値」に戻すので、主が家族役から戻し忘れたまま手順2に入ると、家族役を既定に戻す(低、確からしさ 中)

`mm-ios-verify` の12行は「終わったら "mimamori mother" に戻す」と端末の名前で書き、`mm-screen-guide` の22行と手順4は「`session_show_defaults` で控えた値に戻す」と書く。ふつうの道では12行が先に守られて控えた値は "mimamori mother" なので食い違いではない。12行がすでに破られていた場合だけ、手順4が家族役を忠実に既定へ戻し、そのあとの検証役は指摘1の「止めて報告」に頼ることになる。手順4を「"mimamori mother" に戻す」と名前で書けば2つの skill が同じ言い方になる。止める要因ではない。

## 確かめて問題なかったこと

- 1回目の指摘2は閉じた。`docs/harness.md` の141行は「母の見本と確かめ用の端末では、起動に `-mimamori-stub` を付け」をまず置き、家族役の文をそのあとにしたので、本番の確かめでスタブを付ける読みはできない
- 1回目の指摘3は閉じた。「母の見本は本番の家族に入れない。参加の流れは、スタブか作って消す端末で確かめる」が `docs/harness.md` の141行と `mm-ios-verify` の12行の両方にある
- 43行の `session_show_defaults` は `guard-mcp.sh` が意図して通している(コメントの「session_show_defaults is not matched and stays open」と `case` の対象)ので、検証役が既定を見る手順は実行できる
- `mm-ios-verify` の12行の「`session_set_defaults`(never `persist`)で移し、終わったら `simulatorName` と `simulatorId` で戻す」は、`mm-screen-guide` の22行と手順4の書き方(同じ2つの鍵、`persist` を使わない)と揃っていて、`session_set_defaults` の schema に `simulatorName` と `simulatorId` と `persist` が実在する
- `d7d0f30` は `mm-ios-verify` の `xcrun simctl` の経路(32〜38行、48行)に触れていない。`SIM="mimamori mother"` のまま、既定に依らず正しい端末に向く
- 直しで足した文に秘密、家族の名前、電話、メール、実際の文面は無い。動くコードと `ios/Core` は触っていない。通知先、共有の範囲、段階を変える経路も無い(文書だけの変更)
- 1回目の「確かめて問題なかったこと」(`docs/screenshots` が空、`mimamori iPhone` の参照が「使わない」の文だけ、起動の引数が `ScreenshotStubTransport.swift` に実在)は、今回の差分で変わらない
