# Claude Code の使われ方

フックが記録した回数を数えたもの。最後に数えたのは 2026年11月7日。記録の仕組みは [`docs/harness.md`](harness.md) にある。

## 公開のリポジトリで数え直せる数

下の表の元の記録(`.claude/logs/`)は公開していない。次の数は、公開のリポジトリだけで同じコマンドを流せば数え直せる。

| 数えたもの | 数 | コマンド |
|---|---:|---|
| `docs/audits/raw/` の `mm-reviewer` の原文 | 215 | `ls docs/audits/raw/*-mm-reviewer-*.md \| wc -l` |
| `docs/audits/raw/` の `mm-judge` の原文 | 6 | `ls docs/audits/raw/*-mm-judge-*.md \| wc -l` |
| `docs/audits/raw/` の `mm-auditor` の原文 | 2 | `ls docs/audits/raw/*-mm-auditor-*.md \| wc -l` |
| マージを除くコミット | 730 | `git rev-list --no-merges --count HEAD` |
| そのうち `Co-Authored-By: Claude` の付いたもの | 693 | `git rev-list --no-merges --count --grep='Co-Authored-By: Claude' HEAD` |

## サブエージェント

起動は Agent で始めた回数、再開は SendMessage で同じサブエージェントに続きを頼んだ回数(レビューの2回目以降など)。再開の相手の種類が分からなかったものは `resume` に数える。

| 名前 | 起動 | 再開 |
|---|---:|---:|
| `mm-reviewer` | 189 | 21 |
| `mm-implementer` | 86 | 50 |
| `resume` | 0 | 89 |
| `mm-verifier` | 69 | 2 |
| `web-fetch` | 24 | 1 |
| `general-purpose` | 14 | 1 |
| `mm-judge` | 8 | 0 |
| `claude-code-guide` | 4 | 0 |
| `mm-auditor` | 3 | 0 |
| `mm-eval-curator` | 2 | 0 |

## skill

| 名前 | 回数 |
|---|---:|
| `mm-handoff` | 13 |
| `mm-task` | 11 |
| `mm-release` | 7 |
| `mm-deploy` | 7 |
| `mm-devlog` | 6 |
| `mm-human-queue` | 4 |
| `mm-device` | 3 |
| `writing-guide` | 1 |
| `plugin-authoring` | 1 |
| `open-session` | 1 |
| `mm-screen-guide` | 1 |
| `mm-eval` | 1 |
| `mac-disk-usage` | 1 |
| `ios-app-ui` | 1 |

## スラッシュコマンド

| 名前 | 回数 |
|---|---:|
| `mm-autopilot` | 2 |

## フックが止めた、または確認に回した

| 名前 | 回数 |
|---|---:|
| `guard-prod` | 60 |
| `guard-private` | 50 |
| `guard-prior-work` | 39 |
| `guard-secrets` | 27 |
| `guard-holdout` | 23 |
| `guard-merge` | 21 |
| `report-form` | 5 |
| `guard-mcp` | 4 |

## テストの関門(Stop フック)

| 名前 | 回数 |
|---|---:|
| `stop-gate` | 27 |
| `keep-going` | 3 |

## 期間

最初の記録は2026年11月3日、最後の記録は2026年11月7日(日本時間)。
