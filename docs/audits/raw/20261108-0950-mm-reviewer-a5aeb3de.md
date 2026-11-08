サブエージェントの報告の原文。親のセッションが確かめる前のもの。ホームの道筋だけを ~ に替えた。

ステータス: 直すべき指摘あり

コードと試験は、前の報告の指摘1から4がすべて直っている。残っているのは、3e9abb3 で変えた挙動を文書が追いかけていないことだけだ。

## 指摘

1. [`docs/harness.md`](docs/harness.md) が 3e9abb3 の挙動と合っていない。確かさは高い。害は小さい(文書だけ)。
   3e9abb3 が変えたのは [`.claude/hooks/guard-prod.sh`](.claude/hooks/guard-prod.sh) と [`scripts/test-hooks.sh`](scripts/test-hooks.sh) だけで、文書は 08fe7eb のままになっている(`git diff 08fe7eb origin/harness-guard-prod-no-ask -- docs CLAUDE.md .claude/skills` は空)。ずれているのは次の4か所。
   - 23行の表。通す形として「main への push」と「`gh api` の DELETE」を言い切っている。今は、xargs の後ろの push と、main 宛ての `gh api` の DELETE(`git/refs/heads/main`、`branches/main`)は確認を残す。
   - 157行。「`gh api` の DELETE は…今は聞かずに通し」とあり、main 宛ての例外が書かれていない。
   - 189行。graphql で main を書き換える形として `createCommitOnBranch` と `updateRef` だけを挙げている。`deleteRef` が抜けており、DELETE で main を消す形にも触れていない。
   - 201行。「`gh api` の書き込み(PUT でのマージも含む)と main への push は、`guard-prod.sh` が読める形なら作者に聞く」とある。今は main への push を通すので、逆のことが書いてある。この行は main の版にもあり(`git show main:docs/harness.md` で該当の文が1件)、今回の PR で古くなったのに直されていない。

   直し方。23行と157行に「main 宛ての `gh api` の DELETE と xargs の後ろの push は聞く」と足す。189行に `deleteRef` と main 宛ての DELETE を足す。201行は、main への push を通すと書き換える。[`CLAUDE.md`](CLAUDE.md) の28行は「`gh api` の DELETE…は聞かずに通し」の粒度で書いてある。そこに例外を足すかは、23行と揃えればよい。

2. 試験の名札が「asks」のまま残っている(前の報告の指摘5、直していないと聞いている)。`prod pass 'gh api -iX DELETE repos/o/r/x' "-X inside a cluster of short flags asks"` のように、通るものを確かめる行の名札が「asks」になっている。挙動には響かない。落ちたときに読み違えやすいだけなので、直さずにマージしても困らない。

足すとよい試験の形を1つ挙げる(implementer が Edit で足す)。順の組み合わせの2件は、確認が出ることしか見ていない。そのため、`ask()` が残す側の理由で `asked` を上書きするところは確かめていない。`out` に `visibility` の文が入ることを見る種類の判定を1件足すと、作者に見える理由まで押さえられる。

## 確かめて問題なかったこと

- `ask()` の上書き。残す理由が初めて出たとき `((keep_ask)) || asked=$1` で上書きし、2つ目以降の残す理由では上書きしない。通す理由が先、残す理由が後の行では、作者に見える理由が残す側の文になる。`return 0` はそのままなので、`&& break` の流れも変わらない。
- xargs の後ろの push。`"$1" == "git push behind xargs"*` で確認を残す。試験の2件(`echo -f | xargs git push origin x` と `echo main | xargs git push origin`)は `ask` に替わった。
- main 宛ての DELETE。新しい `elif` は、一般の DELETE の枝より前にある。理由の文に `main` を含むので `keep_ask` が立つ。endpoint の形は、既存の main の判定(273行から274行)と同じ正規表現を使っている。別ブランチの DELETE は `pass` のまま(新しい試験の `repos/o/r/git/refs/heads/x`)。
- graphql の `DELETEREF`。`moves=1` に入り、「commits or moves a ref」の文で確認を残す。既存の2件(`graphql` と `/graphql`)が `ask` に替わり、新しい1件も足された。
- 試験の判定。`prod()` に `ask)` の枝と `*) false ;;` が戻ったので、`prod ask` の行は落ちうる形になった。種類の書き間違いも落ちる。冒頭に `prod ask 'gh api -X PUT repos/o/r/pulls/3/merge'` を置いており、`ask` の枝が生きていることも押さえている。
- 試験の実行。origin/harness-guard-prod-no-ask(3e9abb3)を `git archive` で `/private/tmp/claude-501/-~-develop-mimamori/441cccc6-6df8-4adb-8a1a-b24b10c36592/scratchpad/pr274b` に展開し、`git init` だけをして `bash scripts/test-hooks.sh` を流した。失敗の行は出ず、`exit=0` だった。
- block の形。3e9abb3 は `block`、`force()`、wrangler の削除系の判定に触れていない。`prod block` の行も変わっていない。
- 確かめていないこと。`keep_ask` から `merge` を抜くと試験が落ちるかは、私も確かめていない(書き換えができないため)。ただ、`ask)` の枝の判定は `"permissionDecision":"ask"` を見ている。`merge` が抜ければマージの文は `passed:` になり答えが空になるので、冒頭の試験が落ちる。これはコードを読んで確かめた。
