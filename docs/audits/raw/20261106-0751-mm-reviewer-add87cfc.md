サブエージェントの報告の原文。親のセッションが確かめる前のもの。ホームの道筋だけを ~ に替えた。

ステータス: 直すべき指摘あり

## 指摘

1. 引用の文脈が違う(確度は高い。文書を取って照合した)。`~/develop/mimamori/.claude/worktrees/harness-autopilot-opus/.claude/skills/mm-autopilot/SKILL.md` の13行目は、`availableModels` が Opus を除いた場合の説明として `rejects a --model selection of it like any other excluded model` を model-config から引いている。この文は model-config に確かにあるが、場所は「Add a custom model option」の節で、`ANTHROPIC_CUSTOM_MODEL_OPTION` で足したカスタムのモデルが allowlist に無いときの話。skill が書いている場面(allowlist が `opus` を除く)については、同じ文書の「Restrict model selection」の節がこう言っている。

   > `--model` flag, `ANTHROPIC_MODEL`, or the `model` setting: Claude Code replaces the value at startup with a warning naming both the requested and substituted models, and the session starts on the default model

   つまり `--model opus` が弾かれる形は「エラーで拒否」ではなく「起動時に既定のモデルへ置き換えて警告」で、読んだ人がエラーを探しても見つからない。「Opus でないなら2度目の引き継ぎをしない」という skill の結論は、置き換えでも同じ結果になるので崩れない。直し方は、引用を上の「replaces the value at startup ...」の文に替えるか、引用を外して「置き換えられて既定のモデルで始まる」とだけ書く。1行の文書の直しで、動きは変わらない。

2. 細かい点(任意)。`docs/dev-log.md` の新しい項の末尾(116行目)と次の `## 2026年11月6日 続きの問いのカードの題を…` の見出し(117行目)のあいだに空行が無い。表示は崩れないが、ほかの項と形が揃っていない。

## 確かめて問題なかったこと

- `git diff origin/main...HEAD` を全体読んだ。変更は `mm-autopilot`、`mm-handoff` の skill、`CLAUDE.md`、`docs/harness.md`、`docs/dev-log.md`、`scripts/test-hooks.sh` の6ファイル。
- 引用の照合(model-config を2回に分けて全文取得)。`/model saves your choice as the default for new sessions by writing the model field in your user settings` は原文と一致。`On another model, that level doesn't apply. To pick a subagent's level, set effort in its definition.` も一致。`docs/harness.md` 78行目の「advisor の effort は model-config に書かれていない」は、末尾まで読んでも advisor の言及が `advisorModel` と `--advisor` の allowlist の扱いだけだったので、そのとおり。`--model` が起動したセッションにだけ当たるという説明も、原文の `The --model flag and ANTHROPIC_MODEL environment variable apply only to the session you launch with them.` と合う。
- `bash scripts/test-hooks.sh` は出力なしで終了コード0。照合が弱まっていないかは、一時コピーで `mm-handoff/SKILL.md` の `model=opus` を `model=fable` に書き換えて流し、`skill test failed: mm-handoff starts every new main session with --model opus` で落ちることを見た。否定の grep の `model=fable\|--model fable` が両方の形に当たることも、サンプルを流して確かめた(`alt-match OK`)。この Mac の `grep` は ugrep 7.8.4 に向いているので、作者の環境の grep で同じ判定になる前提。
- 残っている Fable の言及は意図どおりのものだけ。`mm-reviewer`、`mm-auditor`、`mm-judge` の frontmatter と表の行、`.claude/settings.json` の `advisorModel` と `modelSettings["claude-fable-5-1"]`、`mm-endgame` の judge の行、経緯の文。`.claude/hooks`、`CONDITIONS.md`、`docs/plan.md` に Fable は無い。handoff と autopilot の skill に `--model fable` と `model=fable` は残っていない。
- `CLAUDE.md` の表(主は両方 Opus)、`docs/harness.md` 76行目、2つの skill の記述が食い違っていない。`/mm-handoff` はどちらの場合も `model=opus` で起動し、`mm-autopilot` の「引き継ぎで始まったのに Opus でないなら2度目は移らない」は残っている。
- 新しい窓が始まったかを見る流れ。`scripts/handoff-started.sh` は変えておらず、スクリプトの頭の説明(API のエラーの行、許可の確認の前に書かれる呼び出し、同じ `tool_use_id` の `tool_result`)と、書き換えた skill の step 5 の理由づけが一致している。exit 1 の autopilot の枝は、新しい窓を止めてこのセッションで続け、最後の要約にモデルと「窓が始まらなかった」ことを書く形に揃っていて、外した Fable の同意の `/mm-human-queue` への言及はどこにも残っていない。
- 計画や設計の約束(段階、通知先、30日の削除など)、SMS や DNS や注入の5つの落とし穴、秘密や家族の情報、`ios/Core` のフレームワークには、この PR は触れていない。
