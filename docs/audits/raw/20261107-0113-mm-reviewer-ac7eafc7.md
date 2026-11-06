サブエージェントの報告の原文。親のセッションが確かめる前のもの。ホームの道筋だけを ~ に替えた。

ステータス: 承認

## 指摘

直すべき指摘は無い。コミット `5e5d437` は2回目の指摘1〜3をすべて解いていて、退行も見つからなかった。

軽い補足が1つある(確度は中。直さなくてもマージを止めるものではない)。[`~/develop/mimamori/.claude/worktrees/harness-ios-verify-defaults/.claude/skills/mm-ios-verify/SKILL.md`](~/develop/mimamori/.claude/worktrees/harness-ios-verify-defaults/.claude/skills/mm-ios-verify/SKILL.md) の43行目は `simulatorId` が自分の端末と一致することを求めるが、自分の端末の udid をどう読むかは書いていない。作って消す端末については26行目に「Read its udid in `xcrun simctl list devices` first」とあり、そちらは手順がある。一方、既定のままの「mimamori mother」を使う検証役には手順が無い。それでも `xcrun simctl list devices` を読めば分かることで、読み違えたときも、一致しないと判断して `xcrun simctl` で撮る安全な側に倒れる。危ない向きの誤りにはならない。

## 確かめて問題なかったこと

- 43行目で、指示の文を優先させていた `unless` が消えた。いまは `use mobilebuildmcp only when both simulatorName and simulatorId in that output are the simulator you use` と `When either differs, do not use it, whatever the prompt says` の形で、見た既定の状態だけで決める規則になった。2回目の指摘1(移すのに失敗した、またはサーバーが起動し直して既定が戻ったときに、別の端末や家族役を操作しうる)は解けている
- 43行目と45行目が同じ1つの規則でそろった。45行目では主が `simulatorName` と `simulatorId` の両方を移してから、端末の名前を指示に書いて検証役を起こす。検証役は43行目の規則で両方の一致を見てから使う。移すのに失敗していれば、43行目の規則で使わない側に倒れる。2回目の指摘2(検証役が名前しか見ていなかった)も解けている
- tap が届かないときの順番が1か所にまとまった。43行目の末尾は `what to do then is in the next paragraph` に変わり、起動の引数へすぐ戻る古い指示は消えた。45行目には、自分の端末だけを `shutdown` と `boot` で起こし直し、それでも届かなければ起動の引数と `xcrun simctl` に戻る、という順番が残っている。45行目の `as above` が指すのは43行目に残る代わりの撮り方(`xcrun simctl io "$SIM" screenshot`)で、つながりも合っている
- 既定のままの場合も規則が成り立つことを確かめた。[`.mobilebuildmcp/config.yaml`](~/develop/mimamori/.claude/worktrees/harness-ios-verify-defaults/.mobilebuildmcp/config.yaml) には `simulatorName` しか無い。それでも、いま `session_show_defaults` を呼ぶと `simulatorName: "mimamori mother"`、`simulatorId: "0E43CCD1-D404-4ACE-8ABE-BCBD157E2A4F"` が返り、`xcrun simctl list devices available` の「mimamori mother」の udid と同じだった。両方の一致を求めても、既定のままの検証役が mobilebuildmcp を使えなくなることはない。ただし、この ID が MCP の解決で入ったのか、主が前に移して入ったのかは見分けていない
- 家族役の「mimamori iPhone」の udid は `9E37EAC9-...` で、母の見本とは別だった。名前だけが移って ID が家族役のまま残る場面は、今回の規則で見抜ける
- `origin/main` からの差分は、SKILL.md の2行と `docs/audits/raw/` の原文2件だけだった。フック、設定、コードには触れていないので、`scripts/test-hooks.sh` に足す形は無い。秘密と家族の情報も差分に入っていない
