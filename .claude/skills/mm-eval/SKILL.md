---
name: mm-eval
description: Measures mimamori's scam detection accuracy on the dev set and records it, within the daily budget. Use after changing rules or prompts ("精度を測って", "make eval"), never on the holdout set.
---

# Measure accuracy on the dev set

1. Count today's dev runs that called Claude, by the date in Japan as `eval/run.ts` does: `grep '"set":"dev"' eval/results.jsonl | grep '"mode":"rules+claude"' | grep -c "\"ts\":\"$(TZ=Asia/Tokyo date +%Y-%m-%d)"`. Runs in `rules` mode do not call Claude and do not count. Stop if it reached `eval_dev_runs_per_day` in `CONDITIONS.md` (`eval/run.ts` also refuses then). Batch at least two changes per run.
2. Run `make eval`. It runs `eval/run.ts --set dev` in both modes (`--mode rules`, then `--mode rules+claude`), prints a short summary, and appends one line per mode to `eval/results.jsonl` and a row to `eval/RESULTS.md`.
3. Compare with the previous run under the same conditions (same mode, same case count). A difference of one case is noise; say so instead of calling it progress.
4. Look at the misses and false alarms one by one in `eval/out/dev-latest.json`, fix rules or prompts, and note the change in the `notes` field of the next run.

The holdout set (`eval/cases/holdout`) is off limits; a hook blocks it. It runs once before submission, after the author creates `.claude/state/holdout.unlock` (`make eval-holdout`).

## Contract for eval/run.ts

The contract is fixed in task 4 of `docs/plan.md`; this only adds how runs are recorded.

- `--set dev|holdout`, `--mode rules|rules+claude`
- Cases are `{ id, source, sender, domain, text, url, expected_level, is_scam, note }`, one per line in `eval/cases/<set>/*.jsonl`
- Output per run: `{ misses, miss_rate, false_alarms, false_alarm_rate, unneeded_family_pushes, p50_latency_ms, by_source }`
- Prints only totals; never prints holdout case text
- Appends to `eval/results.jsonl` the output plus `ts`, `set`, `mode`, `git_sha`, `n`, `notes`. The pacer hook and the band compare only `mode == "rules+claude"` runs
- Appends a row to `eval/RESULTS.md` with the same numbers, for people
