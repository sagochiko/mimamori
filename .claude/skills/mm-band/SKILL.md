---
name: mm-band
description: Explains the mm-band strip above the prompt in mimamori (time left, milestone, dev accuracy, steps waiting for the author). Use when asked what the band shows or why it is empty.
user-invocable: false
---

# mm-band

This folder is also a Claude Code mod (`mm-band@skills-dir`). It draws one line above the prompt from `CONDITIONS.md`, `eval/results.jsonl`, and `docs/human-queue.md`, and refreshes every minute and at the end of each turn.

It loads only in an interactive session started at the repository root, after the workspace trust dialog is accepted. It does not load in `claude -p`. Check it with `/plugin` (Installed tab). `claude plugin validate .claude/skills/mm-band` lists the events and API calls it uses.
