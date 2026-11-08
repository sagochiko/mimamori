# Claude Code の使われ方

フックが記録した回数を数えたもの。最後に数えたのは 2026年11月8日。記録の仕組みは [`docs/harness.md`](harness.md) にある。

## 公開のリポジトリで数え直せる数

下の表の元の記録(`.claude/logs/`)は公開していない。次の数はコミット `c9366d0` の時点のもので、公開のリポジトリで同じコマンドを流せば同じ数が出る。原文はサブエージェントが報告を返すたびに1件できるので、同じレビュー役に続きを頼んだ回も数に入る。原文を残し始めたのは2026年11月4日で、それより前のレビューは入っていない。

| 数えたもの | 数 | コマンド |
|---|---:|---|
| `docs/audits/raw/` の `mm-reviewer` の原文 | 298 | `git ls-tree --name-only c9366d0 docs/audits/raw/ \| grep -c -- '-mm-reviewer-'` |
| `docs/audits/raw/` の `mm-judge` の原文 | 10 | `git ls-tree --name-only c9366d0 docs/audits/raw/ \| grep -c -- '-mm-judge-'` |
| `docs/audits/raw/` の `mm-auditor` の原文 | 2 | `git ls-tree --name-only c9366d0 docs/audits/raw/ \| grep -c -- '-mm-auditor-'` |
| マージを除くコミット | 977 | `git rev-list --no-merges --count c9366d0` |
| そのうち `Co-Authored-By: Claude` の付いたもの | 936 | `git rev-list --no-merges --count --grep='Co-Authored-By: Claude' c9366d0` |

## サブエージェント

起動は Agent で始めた回数、再開は SendMessage で同じサブエージェントに続きを頼んだ回数(レビューの2回目以降など)。再開の相手の種類が分からなかったものは `resume` に数える。

| 名前 | 起動 | 再開 |
|---|---:|---:|
| `mm-reviewer` | 249 | 21 |
| `mm-implementer` | 110 | 50 |
| `resume` | 0 | 160 |
| `mm-verifier` | 86 | 2 |
| `web-fetch` | 29 | 1 |
| `general-purpose` | 21 | 1 |
| `mm-judge` | 12 | 0 |
| `claude-code-guide` | 4 | 0 |
| `mm-auditor` | 3 | 0 |
| `mm-eval-curator` | 2 | 0 |

## skill

| 名前 | 回数 |
|---|---:|
| `mm-handoff` | 17 |
| `mm-task` | 12 |
| `mm-release` | 10 |
| `mm-deploy` | 8 |
| `mm-devlog` | 7 |
| `mm-human-queue` | 4 |
| `mm-device` | 3 |
| `mm-screen-guide` | 2 |
| `ios-app-ui` | 2 |
| `writing-guide` | 1 |
| `remotion-best-practices` | 1 |
| `plugin-authoring` | 1 |
| `open-session` | 1 |
| `mm-eval` | 1 |
| `mm-endgame` | 1 |
| `mac-disk-usage` | 1 |

## スラッシュコマンド

| 名前 | 回数 |
|---|---:|
| `mm-autopilot` | 2 |

## フックが止めた、または確認に回した

| 名前 | 回数 |
|---|---:|
| `guard-prod` | 91 |
| `guard-holdout` | 85 |
| `guard-private` | 58 |
| `guard-prior-work` | 40 |
| `guard-merge` | 36 |
| `guard-secrets` | 31 |
| `report-form` | 10 |
| `guard-mcp` | 5 |

## テストの関門(Stop フック)

| 名前 | 回数 |
|---|---:|
| `stop-gate` | 30 |
| `keep-going` | 3 |

## 期間

最初の記録は2026年11月3日、最後の記録は2026年11月8日(日本時間)。
