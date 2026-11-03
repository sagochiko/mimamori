---
name: mm-endgame
description: Final checklist for submitting mimamori to Built with Claude Japan 2026, from code freeze to the 20:00 deadline on 2026-11-08. Use when the pacer hook announces code freeze, or when asked to prepare the submission ("仕上げ", "提出の準備").
---

# Endgame

The deadline is in `CONDITIONS.md`. After it, nothing can change. Work top to bottom and tick each item in your reply.

1. Scope: dropped features are listed in `docs/design.md` with the reason. No half-built feature is reachable from the demo.
2. Holdout: open a "作者:" issue with `/mm-human-queue` asking the author to create `.claude/state/holdout.unlock` (the file name goes in the body file, not the title or the command). After the author does it, run `make eval-holdout` once for both modes and copy the numbers into the README. Do not tune afterwards. Then remove the `eval/cases/holdout/*` and `eval/cases/pool/*` lines from `.gitignore` and commit the cases, so judges can see what was measured.
3. Usage numbers: `make usage` regenerates `docs/claude-usage.md` (subagents, skills, commands, hook blocks).
4. Judge: run `mm-judge` twice and compare. Fix the cheapest weak point it names, if time allows.
5. README (English) and README.ja.md, per task 16 of `docs/plan.md`: theme, the scam numbers with direct links to the National Police Agency figures, the story, what we can and cannot see, holdout numbers, what changed after the mother used it, three dev-log entries, how judges can try it (TestFlight link, demo mode), data handling, and how Claude Code was used (link `docs/harness.md` and `docs/claude-usage.md`).
6. Demo script: follow the 3-minute flow in `docs/design.md`. The first 15 seconds say whose problem, what problem, how it is solved. Only real, running features.
7. Submission form drafts in `docs/submission.md`: project summary, the Claude products used, the hardest moment (pick one entry from `docs/dev-log.md`, keep its five-part order), impressions and one improvement.
8. License: ask the author which license to add (they decided to choose before submission), and add `LICENSE` before the repository goes public.
9. Public: the repository becomes public at submission. Before that, search the history for secrets and family data (`git log -p | grep -n -i -E "token|secret|@gmail|090-|080-"`) and ask the author to switch visibility. Never switch it yourself.
10. After submission: delete `node_modules` and `build/DerivedData`.
