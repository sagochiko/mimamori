---
name: mm-band
description: Explains the mm-band strip above the prompt in mimamori (time left, milestone, dev accuracy, steps waiting for the author). Use when asked what the band shows or why it is empty.
user-invocable: false
---

# mm-band

This folder is also a Claude Code mod (`mm-band@skills-dir`). It draws one line above the prompt from `CONDITIONS.md`, `eval/results.jsonl`, and the number of open "作者:" issues (label `needs-human`, counted with `gh` and cached for 5 minutes in `.claude/state/author-waiting`, the same cache the session hook uses), and refreshes every minute and at the end of each turn. "作者待ち ?" means gh could not be reached; run `gh auth status`.

It loads only in an interactive session started at the repository root, after the workspace trust dialog is accepted. It does not load in `claude -p`. Check it with `/plugin` (Installed tab). `claude plugin validate .claude/skills/mm-band` lists the events and API calls it uses.
