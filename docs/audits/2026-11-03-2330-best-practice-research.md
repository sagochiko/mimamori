# Anthropic の推奨の調べもの 2026年11月3日 22:30〜24:00

作者の問いに答えるために、Claude Code に詳しい調べ役のサブエージェント(claude-code-guide、Sonnet)と親のセッションが、一次情報で確かめたこと。決めたことは、それぞれの決め先に書いてある。

## 作者待ちの作業の置き場

長く動くエージェントの進み具合は、リポジトリの中のファイルと git の履歴に残し、次のセッションはそれを読んでから始める、と勧めている(「the git logs and progress files to get up to speed」、[Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents))。コードの外の情報は CLI で読ませるのが楽だとも書いている(「Some of what Claude can't see lives in another system entirely, like your issue tracker」、[best practices](https://code.claude.com/docs/en/best-practices))。人にしかできない手順の置き場に触れたページは、読んだ範囲には無かった。

ブランチを並べて進めるこのリポジトリでは、ファイルにすると本体のフォルダのブランチで見える中身が変わるので、作者と決めて `作者:` の Issue にした。

## フックと、指示の2つの種類

best practices は、CLAUDE.md や skill のようにモデルが読んで判断するものと、フックや deny のように Claude Code が毎回実行するものを分け、後者を「The deterministic kind is for when you want to make sure certain things *always* happen (or never happen), no matter what the model decides.」としている。prompt 型と agent 型のフックは別のモデルに判断させるので決定的ではない、とも書いている。

セッションが思いどおりにいかない原因は4つに分けられている。読めない情報が欠けている、確かめる手段が無い、破ってはいけない決まりが破られた、手間が見合わない。CLAUDE.md に足すきっかけは「Claude makes the same mistake a second time」などで、食い違う指示は定期的に見直して消すよう勧めている([memory](https://code.claude.com/docs/en/memory))。Issue ごとの振り返りは、この4つで分ける形にした。

## advisor とモデル

advisor は Claude Code の公式の機能で、`--advisor`、`/advisor`、`advisorModel` で付ける。`--advisor` は「It doesn't list `--advisor` in `claude --help`.」とあり、手元の 2.1.317 でも受け付けた。相談の時機は Claude が決め、方針を決める前、同じエラーが続くとき、終える前に相談しがち([advisor](https://code.claude.com/docs/en/advisor))。X の投稿の `--subagents haiku` は存在せず、手元でもエラーになった。サブエージェントの既定のモデルは `CLAUDE_CODE_SUBAGENT_MODEL` で変える。

モデルの選び方は「If you're unsure which model to use, start with Claude Opus 5.5 for most workloads.」。Fable 5.1 は難しい推論と長い自律作業向け([models overview](https://platform.claude.com/docs/en/about-claude/models/overview))。100万トークンあたり、Fable 5.1 は入力10ドルと出力50ドル、Opus 5.5 は4ドルと20ドル、Sonnet 5.5 は2ドルと10ドル。Fable はプランによって利用クレジットから払い、最初に一度同意が要る。

作者は、主のモデルを Opus のままにし、Fable の advisor を常に付けると決めた。同意のあとで、このプロジェクトの `.claude/settings.json` に入れる。

## コンテキスト

1M の窓のモデルは、約967Kトークンで自動で要約される(「at about 967K tokens by default」、[model-config](https://code.claude.com/docs/en/model-config))。自動の要約をオフにすると、上限でエラーになって止まる。20万トークンを超えた会話は、1時間ほど放置すると、キャッシュが切れる直前に要約される。これは `idleCompaction` で止められる([settings-reference](https://code.claude.com/docs/en/settings-reference))。関係ない作業のあいだでは `/clear` を勧め、履歴が要らないなら新しいセッションのほうが安いとしている([best practices](https://code.claude.com/docs/en/best-practices))。

作者と決めたのは次のとおり。要約の前に新しいセッションへ移る。60%を超えたら次の Issue の区切りで、80%を超えたら区切りを待たずに移る。割合は応答の終わりのフックが会話の記録から測る(この方法で、主のセッションは2026年11月3日 23:44 に64%だった)。放置の要約は止め、自動の要約は保険としてオンのまま残す。作者に `/clear` や `/compact` を頼まず、引き継ぎは `/mm-handoff` で Claude が新しい窓を開いて行う。
