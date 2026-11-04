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
# The unlock is looked up in the main tree, as guard-holdout.sh does, also from a git worktree.
eval-holdout:
	@main=$$(dirname "$$(git rev-parse --path-format=absolute --git-common-dir)") && test -f "$$main/.claude/state/holdout.unlock" || \
	  { echo "holdout is locked: the author creates .claude/state/holdout.unlock in the main tree"; exit 1; }
	@cd server && npx tsx ../eval/run.ts --set holdout --mode rules && npx tsx ../eval/run.ts --set holdout --mode rules+claude

# Which subagents, skills, commands, and hook blocks Claude Code used. Writes docs/claude-usage.md.
usage:
	@scripts/usage-report.sh > docs/claude-usage.md && echo "wrote docs/claude-usage.md"

# Apple's SwiftUI skills from Xcode, kept local (they are Apple's content and .gitignored).
apple-skills:
	@tmp=$$(mktemp -d) && xcrun agent skills export --output-dir "$$tmp" --replace-existing >/dev/null && \
	for s in swiftui-specialist swiftui-whats-new-27 modernize-tests; do rm -rf .claude/skills/$$s; cp -R "$$tmp/$$s" .claude/skills/; done && \
	rm -rf "$$tmp" && echo "exported Apple skills into .claude/skills (ignored by git)"

# The simulator the skills use, always named "mimamori iPhone": an iPhone 17 Pro on iOS 26.5. On this
# Mac the iOS 27.1 runtime supports only iPhone Duo (iPhone 18 Pro fails with "Incompatible device"),
# and a folding phone's outer display is not what the mother's iPhone looks like. The app targets
# iOS 26.0, so 26.5 runs it; what only iOS 27 changes is checked on the real iPhone. The author chose
# this on 2026-11-04. An older "mimamori iPhone" of another type stops the target with its udid; it
# is not deleted, so a screenshot is never taken on the wrong device.
SIM_RUNTIME := com.apple.CoreSimulator.SimRuntime.iOS-26-5
SIM_TYPE := com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
simulator:
	@xcrun simctl list devices available | grep -q "mimamori iPhone" || { \
	  xcrun simctl create "mimamori iPhone" $(SIM_TYPE) $(SIM_RUNTIME) >/dev/null || { \
	    echo "could not create $(SIM_TYPE) on $(SIM_RUNTIME) (xcrun simctl list runtimes)"; exit 1; }; \
	  echo "created mimamori iPhone"; }
	@other=$$(xcrun simctl list devices available -j | jq -r --arg t "$(SIM_TYPE)" \
	  '.devices[][] | select(.name == "mimamori iPhone" and .deviceTypeIdentifier != $$t) | "\(.udid) \(.deviceTypeIdentifier)"') || { \
	  echo "could not read the simulator list (jq and xcrun simctl list devices -j)"; exit 1; }; \
	  [ -z "$$other" ] || { echo "a \"mimamori iPhone\" of another device type exists; delete it with xcrun simctl delete <udid> and run make simulator again:"; \
	    echo "$$other"; exit 1; }
	@xcrun simctl list devices available | grep "mimamori iPhone"
