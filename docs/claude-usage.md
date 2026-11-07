# Claude Code の使われ方

フックが記録した回数を数えたもの。最後に数えたのは 2026年11月7日。記録の仕組みは [`docs/harness.md`](harness.md) にある。

## サブエージェント

起動は Agent で始めた回数、再開は SendMessage で同じサブエージェントに続きを頼んだ回数(レビューの2回目以降など)。再開の相手の種類が分からなかったものは `resume` に数える。

| 名前 | 起動 | 再開 |
|---|---:|---:|
| `mm-reviewer` | 186 | 21 |
| `mm-implementer` | 85 | 50 |
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
| `mm-task` | 10 |
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
| `ios-app-ui` | 1 |

## スラッシュコマンド

| 名前 | 回数 |
|---|---:|
| `mm-autopilot` | 2 |

## フックが止めた、または確認に回した

| 名前 | 回数 |
|---|---:|
| `guard-prod` | 58 |
| `guard-private` | 48 |
| `guard-prior-work` | 38 |
| `guard-secrets` | 27 |
| `guard-holdout` | 23 |
| `guard-merge` | 19 |
| `report-form` | 5 |
| `guard-mcp` | 4 |

## テストの関門(Stop フック)

| 名前 | 回数 |
|---|---:|
| `stop-gate` | 27 |
| `keep-going` | 3 |

## 期間

最初の記録は2026年11月3日、最後の記録は2026年11月7日(日本時間)。
