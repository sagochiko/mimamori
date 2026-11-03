# One-command entry points. Claude Code and the author use the same commands.

.PHONY: setup bootstrap verify eval eval-split eval-holdout usage apple-skills simulator

# Once per clone: use the repository's git hooks (the commit convention in .githooks/commit-msg).
setup:
	@git config core.hooksPath .githooks && echo "git hooks: .githooks"

# Once per fresh checkout or git worktree, before `make verify`: the git hooks, the server's
# dependencies (a worktree has no node_modules), and a check that XcodeGen is there for ios/project.yml.
bootstrap: setup
	@if [ -f server/package-lock.json ]; then cd server && npm ci --no-audit --no-fund --loglevel=error && echo "server: npm ci done"; fi
	@if [ -f ios/project.yml ] && [ "$$(uname)" = Darwin ]; then \
	  if command -v xcodegen >/dev/null; then echo "ios: $$(xcodegen --version)"; \
	  else echo "ios: xcodegen is missing (brew install xcodegen); ios/Mimamori.xcodeproj is generated from ios/project.yml"; exit 1; fi; fi

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

# The simulator the skills use, always named "mimamori iPhone", on the iOS 27.1 runtime. The device
# type is the first iPhone that runtime supports. A runtime accepts only its own device types: on
# 2026-11-03 iOS 27.1 listed only iPhone Duo, and iPhone 18 Pro failed with "Incompatible device".
SIM_RUNTIME := com.apple.CoreSimulator.SimRuntime.iOS-27-1
simulator:
	@xcrun simctl list devices available | grep -q "mimamori iPhone" || { \
	  type=$$(xcrun simctl list runtimes -j | jq -r --arg r "$(SIM_RUNTIME)" \
	    '.runtimes[] | select(.identifier == $$r and .isAvailable) | .supportedDeviceTypes[] | select(.productFamily == "iPhone") | .identifier' | head -1); \
	  [ -n "$$type" ] || { echo "the $(SIM_RUNTIME) runtime is missing or supports no iPhone (xcrun simctl list runtimes)"; exit 1; }; \
	  xcrun simctl create "mimamori iPhone" "$$type" $(SIM_RUNTIME) >/dev/null && echo "created mimamori iPhone ($$type)"; }
	@xcrun simctl list devices available | grep "mimamori iPhone"
