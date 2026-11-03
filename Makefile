# One-command entry points. Claude Code and the author use the same commands.

.PHONY: setup verify eval eval-split eval-holdout usage apple-skills simulator

# Once per clone: use the repository's git hooks (the commit convention in .githooks/commit-msg).
setup:
	@git config core.hooksPath .githooks && echo "git hooks: .githooks"

# Tests for whatever exists so far. Short output; details go to .verify.log.
verify:
	@scripts/verify.sh

# Accuracy on the dev set, rules only and rules plus Claude (the contract in task 4 of docs/plan.md).
# Each run appends to eval/results.jsonl and eval/RESULTS.md.
eval:
	@cd server && npx tsx ../eval/run.ts --set dev --mode rules && npx tsx ../eval/run.ts --set dev --mode rules+claude

# Move whole scam patterns from eval/cases/pool into dev or holdout.
eval-split:
	@cd server && npx tsx ../eval/split.ts

# The one final measurement. A hook blocks it until the author creates .claude/state/holdout.unlock.
eval-holdout:
	@test -f .claude/state/holdout.unlock || { echo "holdout is locked: the author creates .claude/state/holdout.unlock"; exit 1; }
	@cd server && npx tsx ../eval/run.ts --set holdout --mode rules && npx tsx ../eval/run.ts --set holdout --mode rules+claude

# Which subagents, skills, commands, and hook blocks Claude Code used. Writes docs/claude-usage.md.
usage:
	@scripts/usage-report.sh > docs/claude-usage.md && echo "wrote docs/claude-usage.md"

# Apple's SwiftUI skills from Xcode, kept local (they are Apple's content and .gitignored).
apple-skills:
	@tmp=$$(mktemp -d) && xcrun agent skills export --output-dir "$$tmp" --replace-existing >/dev/null && \
	for s in swiftui-specialist swiftui-whats-new-27 modernize-tests; do rm -rf .claude/skills/$$s; cp -R "$$tmp/$$s" .claude/skills/; done && \
	rm -rf "$$tmp" && echo "exported Apple skills into .claude/skills (ignored by git)"

simulator:
	@xcrun simctl list devices available | grep -q "mimamori iPhone" || \
	xcrun simctl create "mimamori iPhone" com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-1
	@xcrun simctl list devices available | grep "mimamori iPhone"
