サブエージェントの報告の原文。親のセッションが確かめる前のもの。ホームの道筋だけを ~ に替えた。

ステータス: 完了

直すべき指摘なし。下の2件は低い深刻度で、マージを止めるほどではない。

## 指摘

1. 深刻度は低。場所は [`docs/harness.md`](docs/harness.md) の101行(「1回のセッションで止めるときは `/advisor off`」)。`/advisor off` はこのセッションだけでなく、作者のユーザー設定にも書き込む。
   - 文書で確かめた。settings-reference の `advisorModel` の項に「Claude Code saves your pick to this key in `~/.claude/settings.json`」とある(https://code.claude.com/docs/en/settings-reference)。settings の優先順位は「managed settings, command line, project local, shared project, user」の順(https://code.claude.com/docs/en/settings)。
   - そこから推測できることがある。このリポジトリでは、プロジェクトの `"fable"` がユーザー設定より強い。だから次のセッションでは advisor がまた付く。「1回のセッションで止める」という書き方は、結果としては合う。ただし作者のユーザー設定に `advisorModel` が入っていた場合、`/advisor off` はほかのプロジェクトの advisor まで消す。反対に、このリポジトリで `/advisor opus` を選んで既定を変えたつもりでも、ここではプロジェクトの値に負けて変わらない。
   - 直すなら、「止めるのはこのセッションだけで、ユーザー設定にも書かれる。ずっと止めるときは `.claude/settings.json` から消す」と1文足す程度でよい。
   - 確かめていないこともある。セッションの途中で `/advisor off` を打ったとき、プロジェクトの値より実行中の選択が勝つかどうかは、文書にはっきりした記述が無かった。作者のユーザー設定に `advisorModel` があるかどうかも読めていない(下の「懸念と未完了」に理由を書いた)。

2. 深刻度は低。場所は [`.claude/settings.json`](.claude/settings.json) の3行と、PR の「作者に頼むこと」。順番が監査の決定と逆になっている。
   - [`docs/audits/2026-11-03-2330-best-practice-research.md`](docs/audits/2026-11-03-2330-best-practice-research.md) の23行は「同意のあとで、このプロジェクトの `.claude/settings.json` に入れる」と書いている。PR は先に設定を入れて、同意が要るかどうかは次のセッションで見る形にした。
   - 実害はないと文書で確かめた。advisor の文書に「With Fable already saved as your `advisorModel`, Claude Code sends requests without the advisor」とある。費用についても「a Fable advisor bills nothing before you give it」とある(https://code.claude.com/docs/en/advisor)。
   - 直すなら、PR の本文か harness.md に「同意の前に入れても advisor なしで動くので、順を入れ替えた」と一言残すと、監査の決定との食い違いが記録に残る。

## 確かめて問題なしとしたもの

- `advisorModel` の書き方と置き場所は文書と合う。advisor の文書には、settings に書く例として `{"advisorModel": "opus"}` がある。値は「`fable`, `opus`, or `sonnet`」か完全なモデル ID。settings-reference では Scope が「Any file」で、「`Any file` means all four」と説明があり、Project(`.claude/settings.json`)も含む。差分は `.claude/settings.json` の3行目に `"advisorModel": "fable",` を足した1行だけ。`python3 -I -c 'import json;json.load(open(".claude/settings.json"));print("ok")'` を流すと `ok` が出た。
- 組み合わせは成り立つ。advisor の文書の表で、主が「Opus 5 or Opus 5.5」の行は「Fable, Opus 5 or later」を受け付ける。サブエージェントは opus が4つ、sonnet が2つ(`.claude/agents/*.md` の `model:` の行)。Sonnet 5.5 の行も Fable を受け付けるので、どのサブエージェントでも組み合わせの確認は通る。
- harness.md に書いた事実は文書と一致した。
  - キャッシュについて、文書に「The advisor model's own read of the conversation is not cached」とある(引用は原文どおり)。
  - 同意について、「one-time consent to bill Fable usage to usage credits」と「doesn't apply Fable as the advisor until you have accepted」がある。
  - サブエージェントについて、「Subagents inherit the configured advisor」がある。
  - 止め方について、「run `/advisor off`」がある。
  - Scope が「Any file」であることは上に書いたとおり。
- PR の「作者に頼むこと」も文書と合う。文書に「Claude Code records the consent and saves Fable as your selected model」とあるので、同意のあとに `/model opus` で主のモデルを戻す手順は要る。
- 権限は緩めていない。差分は `advisorModel` の1行と harness.md の2行だけで、`permissions`、`hooks`、`env` には触れていない。`grep` を流しても、プロジェクトの `.claude/settings.json` に `env`、`DISABLE`、`TELEMETRY` の類は無かった。文書によると、feature flag を取りに行かない設定があると advisor は止まるが、プロジェクトの設定にはそれが無い。
- CLAUDE.md の「設定を変える前に code.claude.com の文書を確かめる」には沿っている。advisor と settings-reference を確かめ、その結果を harness.md に書いている。費用がかかる変更なので、作者に AskUserQuestion で聞いたと PR に書いてある。聞いた記録そのものは確かめていない。

## 懸念と未完了

- フックに止められた操作がある。`.claude/settings.json` の env を調べる grep と同じコマンドの中で、`ls .claude/settings.local.json` と `~/.claude/settings.json` の grep も流した。それが PreToolUse の Bash フック(command hook 3)に止められた。理由は「the author's private lists ... and local settings stay out of Claude's context」。決まりに従い、別の手段では読み直していない。そのため、作者のユーザー設定とローカル設定に `advisorModel` や `CLAUDE_CODE_DISABLE_ADVISOR_TOOL`、`DISABLE_TELEMETRY` が入っているかは確かめていない。入っていると、このプロジェクトの設定があっても advisor は付かない(文書には「`CLAUDE_CODE_DISABLE_ADVISOR_TOOL` turns the advisor off, and this key can't turn it back on」とある)。作者が自分のユーザー設定を見るか、次のセッションの起動時に「Advisor Tool (experimental) is on」の通知が出るかで確かめられる。
- 費用は harness.md に書かれていない。サブエージェントも Fable の advisor を受け継ぐので、Sonnet の mm-verifier や mm-eval-curator のように安く回すつもりの役でも、相談のたびに Fable の単価がかかる。harness.md の「受け継ぐ」という記述は正しいので、指摘にはしなかった。

確かめた文書は https://code.claude.com/docs/en/advisor 、https://code.claude.com/docs/en/settings-reference(`advisorModel` の項は272〜284行目)、https://code.claude.com/docs/en/settings(優先順位の節)。読んだファイルは ~/develop/mimamori/.claude/worktrees/harness-advisor-fable/.claude/settings.json 、~/develop/mimamori/.claude/worktrees/harness-advisor-fable/docs/harness.md 、~/develop/mimamori/.claude/worktrees/harness-advisor-fable/docs/audits/2026-11-03-2330-best-practice-research.md 。
