サブエージェントの報告の原文。親のセッションが確かめる前のもの。ホームの道筋だけを ~ に替えた。

ステータス: 直すべき指摘あり

5219889 で直した4か所(23行の冒頭の「ただし」の文、157行、189行、201行の前半)は、コードと合っている。ただ、同じ [`docs/harness.md`](docs/harness.md) に、11月8日より前の「聞く」がまだ3か所残っている。前の報告で私が挙げ漏らしたものも含む。文書だけの食い違いで、挙動には響かない。

## 指摘

1. 23行の表の同じセルが、前半と後半で逆のことを言っている。確かさは高い。
   前半は「main への push、遠隔のブランチの削除、本番の D1 の DROP や DELETE、secret の削除、`gh api` の DELETE は聞かずに通して `passed:` を記録に残す」と書く。ところが同じセルの後半は「`wrangler secret delete`、本番の D1 で DROP、DELETE、TRUNCATE を含む SQL(…)、遠隔のブランチを消す push(…)、main への push(…)、`gh api` のうち、DELETE、PR のマージ、リポジトリの公開、main の書き換え、中身を読めない呼び出しは作者に聞く」で終わる。続く「中身を読めない SQL(変数、`$(`、見つからないファイル、見つからないマイグレーションの置き場)も聞く」も古い。今のコードでは、これらの理由は `keep_ask` に当たらず `passed:` で通る。
   直し方。後半の「は作者に聞く」を「を見る(どれを聞き、どれを通すかは上のとおり)」のような書き方にする。あるいは、聞く形(`gh api` のマージ、公開、main の書き換え、読めない `gh api`、xargs の後ろの push)と通す形を分けて書く。「も聞く」は「も見て、通す」にする。

2. 117行の本番の D1 のマイグレーションの段落が「DROP、DELETE、TRUNCATE の語を探し、当たれば聞く」のままになっている。確かさは高い。373行の `ask "remote D1 migration with DROP, ..."` は `gh api` で始まらないので、今は通す。「当たれば `passed:` を記録に残して通す」にする。

3. 201行の段落の終わりが「…セッションの cwd と全部の `cd` と `pushd` の先のどれかが main なら聞く」のままになっている。確かさは高い。同じ段落の前半は 5219889 で「main への push は、2026年11月8日から聞かずに通す」に直っている。なので、この文も「main なら `passed:` を記録に残す」に合わせる。同じ段落の「その奥の git push と `gh api` は、標準入力から何が足されるか読めないとして `guard-prod.sh` が聞く」は、今のコード(xargs の後ろの push と `gh api` は確認を残す)と合っているので直さなくてよい。

## 確かめて問題なかったこと

- 23行の冒頭に足した文。main 宛ての `gh api` の DELETE(`git/refs/heads/main`、`branches/main`)、graphql の `deleteRef`、xargs の後ろの push を聞くこと、残す理由が出たら作者に見せる理由をその文にすること。どれも [`.claude/hooks/guard-prod.sh`](.claude/hooks/guard-prod.sh) の 3e9abb3 の `ask()`、`DELETEREF` を `moves` に入れたところ、DELETE の main の `elif` と合っている。
- 157行の「main 宛ての `gh api` の DELETE だけは main の書き換えとして聞く」は、新しい `elif` と合っている。
- 189行の main の書き換えの一覧に `deleteRef` と「main 宛ての DELETE」が入り、コードと合っている。
- 201行の前半の「`gh api` でのマージは…作者に聞く。main への push は、2026年11月8日から聞かずに通す」は、コードと合っている。
- [`CLAUDE.md`](CLAUDE.md) は 5219889 で変わっていない。28行の「`gh api` の DELETE…は聞かずに通す」は、main 宛ての例外を書いていない粗い書き方だ。ただ、同じ行に「`gh api` での main の書き換えは作者に聞く」もあるので、矛盾まではしていない。[`.claude/skills/mm-deploy/SKILL.md`](.claude/skills/mm-deploy/SKILL.md) の「DROP、DELETE、TRUNCATE は聞かずに通して `passed:` を残す」もコードと合っている。
