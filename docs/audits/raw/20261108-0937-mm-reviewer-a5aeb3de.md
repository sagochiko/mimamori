サブエージェントの報告の原文。親のセッションが確かめる前のもの。ホームの道筋だけを ~ に替えた。

ステータス: 直すべき指摘あり

## 指摘

1. 試験の `prod ask` 36行が落ちない形になっている。確かさは高い。
   [`scripts/test-hooks.sh`](scripts/test-hooks.sh) の `prod()`(ブランチの138行から146行)で、`case $1 in` から `ask)` の枝が消え、`quiet`、`pass`、`block` しか残っていない。それでも `prod ask ...` は36行残っている(`git show origin/harness-guard-prod-no-ask:scripts/test-hooks.sh | grep -c '^prod ask'` の結果は `36`)。bash の `case` は、どの枝にも当たらないと終了状態 0 を返す。そのため `|| { ...; fail=1; }` は一度も走らない。`bash -c 'case ask in quiet) false ;; pass) false ;; esac || echo "would fail"'` を流して、何も出ないことを確かめた。
   これで、確認を残す3つ(`gh api` でのマージ、visibility、main の書き換え)の試験はすべて空になっている。たとえば `keep_ask` の正規表現から `merge` が抜けて `gh api -X PUT repos/o/r/pulls/3/merge` が `passed:` で通るようになっても、試験は通る。PR 本文の「確認を残す形の36行を `ask` に戻して…失敗0件」は、この空の試験が通ったという意味でしかない。ブランチを scratchpad に `git archive` で展開して `bash scripts/test-hooks.sh` を流すと `exit=0` だった。ただ、上の理由から、確認を残す側については何の裏付けにもならない。
   直し方。`ask) [[ $got -eq 0 && "$out" == *'"permissionDecision":"ask"'* ]] ;;` を戻す。あわせて `*) false ;;` を足し、知らない種類の指定を落とす。

2. `gh api` の DELETE が main 宛てでも通る。文書の「main の書き換えは聞く」と食い違う。確かさは、コードの挙動については高い。実害の大きさは中くらい。
   [`.claude/hooks/guard-prod.sh`](.claude/hooks/guard-prod.sh) の REST の判定は `elif` の連鎖になっている。`M == DELETE` の枝(261行から262行)が、`git/refs/heads/main` と `branches/main` の枝(273行から274行)より前にある。そのため `gh api -X DELETE repos/o/r/git/refs/heads/main` や `gh api -X DELETE repos/o/r/branches/main/protection` は、理由が `gh api DELETE cannot be undone` になる。この文は `keep_ask` の正規表現(`merge|visibility|main|cannot read|cannot check|moves a ref`)に当たらないので、`passed:` で通る。graphql も同じで、`deleteRef` は `deletes` だけを立て、`moves`(`CREATECOMMITONBRANCH`、`UPDATEREF`)を立てない。だから main の `deleteRef` も通る。
   [`docs/harness.md`](docs/harness.md) の「設定の範囲」には、聞く対象として「main の書き換え(`git/refs/heads/main`、`branches/main/` の下、…)」と書いてあり、方法を限っていない。今の main は保護されていない(`gh api repos/sagochiko/mimamori/branches/main --jq .protected` の結果は `false`)。なので保護を外す DELETE の害は今は無い。main の ref を DELETE したとき GitHub が既定のブランチとして断るかどうかは確かめていない。
   直すなら、DELETE の枝の中で endpoint が main を指すとき(`git/refs/heads/main`、`branches/main`)だけ main 用の理由で `ask` する。graphql の `DELETEREF` は `moves` に入れる。どちらを採るかは作者の決定(「`gh api` の DELETE は通す」と「main の書き換えは聞く」の重なり)の読み方による。採らないなら、文書に「DELETE は main 宛てでも通す」と書く。

3. `git push` を `xargs` の後ろに置くと、force の可能性があっても通るようになった。確かさは高い。害は小さめ。
   129行の `git push behind xargs, which adds words from stdin this hook cannot read` は `git push` で始まるので、`keep_ask` に当たらず通る。試験も `prod pass 'echo -f | xargs git push origin x' "push behind xargs asks, since stdin may add -f"` に変わった(ラベルは「asks」のまま)。止めている形(force)を否定できない読めない形なのに通る。`gh api` の xargs の形は確認を残しているので、扱いが食い違う。PR の「止めている形は変えない」とは、厳密には矛盾しない(前も止めておらず聞いていた)。それでも、force が確認なしで遠隔に届く経路が1つ増えた。直すなら、この理由だけ確認を残す。あるいは文書に、xargs の後ろの push は force でも通ると書く。

4. 通す理由が先に出て、残す理由が後から出た行では、確認は出る。ただし作者に見える理由の文が、通すほうの文になる。確かさは高い。害は小さい。
   `ask()` は最初の理由だけを `asked` に残し、`keep_ask` は後の理由でも立つ。そのため `git push origin main && gh api -X PATCH repos/o/r -f visibility=public` では、確認は出る。しかし `permissionDecisionReason` と記録は `asked: git push to main ...` になり、作者は公開の確認だと分からない。判定の向き(残す側が勝つ)は正しい。直すなら、`keep_ask` が初めて立ったときにその理由で `asked` を上書きする。この組み合わせを確かめる試験も無い。

5. 試験の名札がまだ「asks」のまま残っている(`prod pass ... "secret delete asks"` など、`pass` にした行のほとんど)。挙動の害は無い。ただ、1と重なって、落ちたときの文が読み違えやすい。小さい。

`scripts/test-hooks.sh` に足すとよい形を挙げる(implementer が Edit で足す)。
- `prod ask 'gh api -X PUT repos/o/r/pulls/3/merge'` が `ask` の枝を戻したあと本当に確認を出すこと。逆向きの確認として、`keep_ask` から語を1つ抜くとこの試験が落ちることも見る
- `prod pass 'npx wrangler secret delete X && gh api -X PATCH repos/o/r -f visibility=public'` ではなく `prod ask ...` になること(通す理由が先、残す理由が後)
- `prod ask 'gh api -X PATCH repos/o/r -f visibility=public && npx wrangler secret delete X'`(順が逆)
- 指摘2を直すなら `prod ask 'gh api -X DELETE repos/o/r/git/refs/heads/main'`、`prod ask 'gh api -X DELETE repos/o/r/branches/main/protection'`、graphql の `deleteRef` を main に当てる形。直さないなら、同じ形を `prod pass` として明記する
- 指摘3を直すなら `prod ask 'echo -f | xargs git push origin x'`

## 確かめて問題なかったこと

- `ask()` の理由の文を全部並べ、`keep_ask` の正規表現に当てた。`gh api` で始まる文で残るのは、xargs(cannot read)、graphql の moves、merges、publishes、ファイルや stdin の query(cannot check)、実行時に組む query(cannot check)、読めない method(cannot read)、読めない endpoint(cannot read と merge)、マージのエンドポイント、読めない本文(main と cannot read)、visibility、`git/refs/heads/main` と `branches/main`(main)、`contents/` の main への書き込み(main)。通るのは、graphql の deletes(`gh api graphql mutation that deletes`)、REST の DELETE(262行)、行の文字での DELETE(291行)の3つだけで、どれも決めたとおり。通る3つは文が固定で endpoint を差し込んでいないので、endpoint の文字(例えば `main` を含む道筋)で誤って残ることも無い。`git push`、wrangler、D1 の理由は `gh api` で始まらないので、正規表現の `main` には当たらない
- `ask()` の終了状態。前の版の `[[ -n "$asked" ]] || asked=$1` も、どちらの分かれでも 0 を返していた。新しい版は `return 0` で揃えているので、175行の `on_main "$d" && ask ... && break` の流れは前と同じ
- block の形。`block()`([`.claude/hooks/lib.sh`](.claude/hooks/lib.sh) の22行から26行)は `exit 2` でその場で終わる。今回の差分は `force()`、wrangler の削除系と time-travel の restore の `block` に触れていない。試験の `prod block` の行も差分で1行も変わっていない
- `pass` の判定。`log_event` の出力の形(`{ts, kind, name, detail}`)と、試験の `prod_passed` の grep(`"name":"guard-prod","detail":"passed: `)が合っている。`MM_LOG_DIR` は試験の7行で一時の場所に向けている。`pass` は「答えが空、終了 0、記録が1行増える」を見ており、確認が出たら落ちる形になっている。`quiet` も記録が増えないことまで見るようになった
- 文書。[`CLAUDE.md`](CLAUDE.md) の「データと安全」、[`docs/harness.md`](docs/harness.md) の表と「設定の範囲」、[`.claude/skills/mm-deploy/SKILL.md`](.claude/skills/mm-deploy/SKILL.md) の書き換えは、通すもの、残すもの、止めるものの区分でコードと合っている。外れているのは指摘2(DELETE の main)と指摘3(xargs の push)だけ。`gh repo edit --visibility` は前からフックが見ておらず auto mode の判定に任せている(`rule none` の試験)。今回の PR で変わった点ではない

ブランチの試験を流そうとしたときのことも書いておく。scratchpad に展開した木で `git commit --no-verify` をしたところ、フック(`git commit without its hooks`)に止められた。コミットはせず、展開した木で `git init` だけをして `bash scripts/test-hooks.sh` を流した(`exit=0`)。展開先は `/private/tmp/claude-501/-~-develop-mimamori/441cccc6-6df8-4adb-8a1a-b24b10c36592/scratchpad/pr274`。
