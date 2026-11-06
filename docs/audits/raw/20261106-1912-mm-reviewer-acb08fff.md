サブエージェントの報告の原文。親のセッションが確かめる前のもの。ホームの道筋だけを ~ に替えた。

ステータス: 直すべき指摘あり

## 指摘

1. レビュー役には、決まりの示す手段の一つが使えない(確度は高い)。[`.claude/agents/mm-reviewer.md`](.claude/agents/mm-reviewer.md) の26行目は「Put the cases in a file under the scratchpad and let `scripts/test-hooks.sh`, or a script that reads that file, hand them to the hook」と書いている。ところが同じ定義の frontmatter は `disallowedTools: Edit, Write, NotebookEdit` で、本文でも Bash は読むだけと決めている。レビュー役がスクラッチパッドにファイルを作るには Bash の heredoc か `echo` で書くしかなく、それをやると今回止めたかった形そのものになる。もう一つ、`scripts/test-hooks.sh` は引数も外のファイルも読まない、中で完結した試験になっている(1409行を見て、ファイルから試しを読む入口は無かった)。スクラッチパッドのファイルを渡す道はそもそも無い。[`docs/harness.md`](docs/harness.md) の86行目「Edit か Write で `scripts/test-hooks.sh` かスクラッチパッドのファイルに書き」も同じで、Edit も Write も持たない `mm-reviewer` と `mm-verifier` には当てはまらない。レビュー役の段落は「フックのコードを読み、試す形を報告に並べる。試験が要るなら実装役に `scripts/test-hooks.sh` へ足してもらう」に絞るのがよい。harness.md のほうは役ごとの手段を分けて書くとよい(実装役は Edit で `scripts/test-hooks.sh` に足す、検証役は `bash scripts/test-hooks.sh` を流すだけ、レビュー役は読むだけ)。

2. 記録の回数と、誰が確認を出させたかが記録と合わない(確度は中程度)。`~/develop/mimamori/.claude/logs/usage.jsonl` で2026年11月6日の `guard-prod` の本番の D1 にかかわる `asked` は3件ある。#172 の最初のコミットより前に1件(`remote D1 SQL built at run time`)、`mm-reviewer` が動いていたあいだに1件(`SQL with DROP, DELETE, or TRUNCATE on the remote D1`)、1回目のレビューの報告が戻った後、`9bfa571` の直しより前に1件(`remote D1 SQL built at run time`)。主の行で2件、レビュー役の行で1件と読める。食い違いは3か所ある。
   - PR の本文と harness.md の「作者に確認が2回出た」は、記録では3回。
   - mm-reviewer.md の「a reviewer's probes asked the author twice」は、レビュー役の実行中の記録が1件しかない。
   - mm-implementer.md の「such lines asked the author twice」は、実装役ではなく主とレビュー役の行だった。

   3件目が別の作業の木のセッションから出た可能性は、記録に呼び出し元が残っていないので否定しきれない。それでも、レビュー役の行で2回出たとは記録から言えない。回数は「3回(主2、レビュー役1)」にするか、回数を書かずに「主とレビュー役の行で」にするのがよい。直すときは公開の記録に時刻を書かない決まりも守ること。

3. 主のセッションに決まりが届かない(確度は高い)。記録では、確認を出した行のうち2件は主の行だった。今回足した場所は3つの役の定義と [`docs/harness.md`](docs/harness.md) だけで、`CLAUDE.md` にも `.claude/skills/mm-task/SKILL.md` にも入っていない(`grep -rn test-hooks CLAUDE.md .claude/skills` で mm-task には当たらなかった)。harness.md は自動では読まれないので、主が次にフックの試験を足すときにまた同じことが起きる。`CLAUDE.md` の「検証」か「データと安全」に1行足すのがよい(フックを試すときは試す形を Bash の行に書かず、Edit で `scripts/test-hooks.sh` に書いて流す)。

4. 電話番号の例えが今のフックの動きと合わない(確度は高いが、影響は小さい)。3つの定義は「a line that holds ... a phone number asks the author or stops, even inside `echo`」と書いている。しかし [`.claude/hooks/guard-private.sh`](.claude/hooks/guard-private.sh) は `shell_words` と `command_starts` でコマンドの始まりを取り、`git commit` と gh の Issue や PR への書き込みだけを調べる(冒頭の注と1〜40行)。`echo` の中の電話番号の形では止まらない。止まる側に倒した書き方なので害は無いが、事実と違う理由を定義に書くことになる。`guard-prod.sh` の wrangler の判定は `$text` の全体に正規表現を当てる(274、315行)ので、wrangler の例は正しい。電話番号は「gh で Issue や PR に書く行やコミットの行に入ると止まる」と絞るか、外すのがよい。

5. `mm-auditor` にも要る(確度は中程度、提案)。[`.claude/agents/mm-auditor.md`](.claude/agents/mm-auditor.md) の15行目では、ハーネスの監査のときに `.claude/hooks/` と `scripts/test-hooks.sh` を読ませている。すり抜けを探す流れでレビュー役と同じ試しを手で流しうる。`mm-judge` は公開物を読むだけで、`mm-eval-curator` もフックを試す場面が無いので、要らないと見た。

## 確かめて問題なかったこと

- sub-agents の文書の引用。https://code.claude.com/docs/en/sub-agents に「Hooks from settings files, managed policy settings, and plugins all apply inside subagents, so a `PreToolUse` hook in `settings.json` also runs before every tool a subagent uses.」があり、harness.md の引用は原文どおりだった。
- [`.claude/settings.json`](.claude/settings.json) で、`guard-prod.sh`、`guard-merge.sh`、`guard-private.sh` は `Bash|Monitor` に当たり、Edit と Write には当たらない。実装役が Edit で `scripts/test-hooks.sh` に試しを書いても、これらのフックは見ない。
- [`docs/harness.md`](docs/harness.md) の45行目にあるとおり、`scripts/test-hooks.sh` はコミットのときの電話番号の検査から外れている。実装役が電話番号の形の試しをこのファイルに足してもコミットは止まらない。
- PR の「2回目のレビューのあいだ新しい確認は出ていない」は記録と合う。2回目の報告(`docs/audits/raw/20261106-1906-mm-reviewer-a81a9f9e.md`)の前後に `guard-prod` の行は無かった。
- 差分は4ファイルに8行足しただけで、フックの中身と frontmatter は変わっていない。`scripts/test-hooks.sh` が確かめる model と effort の行にも触れていない。
- このレビューでは、Bash の行に wrangler の書き込みの語、`gh pr merge`、main への push、電話番号の形を書いていない。フックの確認も止まりも出なかった。
