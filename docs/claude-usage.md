# Claude Code の使われ方

フックが記録した回数を数えたもの。最後に数えたのは 2026年11月7日。記録の仕組みは [`docs/harness.md`](harness.md) にある。

## 公開のリポジトリで数え直せる数

下の表の元の記録(`.claude/logs/`)は公開していない。次の数はコミット `06f8418` の時点のもので、公開のリポジトリで同じコマンドを流せば同じ数が出る。原文はサブエージェントが報告を返すたびに1件できるので、同じレビュー役に続きを頼んだ回も数に入る。原文を残し始めたのは2026年11月4日で、それより前のレビューは入っていない。

| 数えたもの | 数 | コマンド |
|---|---:|---|
| `docs/audits/raw/` の `mm-reviewer` の原文 | 216 | `git ls-tree --name-only 06f8418 docs/audits/raw/ \| grep -c -- '-mm-reviewer-'` |
| `docs/audits/raw/` の `mm-judge` の原文 | 6 | `git ls-tree --name-only 06f8418 docs/audits/raw/ \| grep -c -- '-mm-judge-'` |
| `docs/audits/raw/` の `mm-auditor` の原文 | 2 | `git ls-tree --name-only 06f8418 docs/audits/raw/ \| grep -c -- '-mm-auditor-'` |
| マージを除くコミット | 732 | `git rev-list --no-merges --count 06f8418` |
| そのうち `Co-Authored-By: Claude` の付いたもの | 695 | `git rev-list --no-merges --count --grep='Co-Authored-By: Claude' 06f8418` |

## サブエージェント

起動は Agent で始めた回数、再開は SendMessage で同じサブエージェントに続きを頼んだ回数(レビューの2回目以降など)。再開の相手の種類が分からなかったものは `resume` に数える。

| 名前 | 起動 | 再開 |
|---|---:|---:|
| `mm-reviewer` | 191 | 21 |
| `mm-implementer` | 87 | 50 |
| `resume` | 0 | 92 |
| `mm-verifier` | 70 | 2 |
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
