---
name: mm-ios-verify
description: Builds the mimamori iOS app, runs it on the simulator, and captures screenshots, and lists what only a real device can check. Use to see a screen or confirm a UI change ("画面を確認して", "シミュレータで撮って").
---

# Check the iOS app

This Mac has Xcode 27.1 at `/Applications/Xcode-27.1.0.app`. There is no Simulator.app; the author opens simulators in Device Hub (`open "/Applications/Xcode-27.1.0.app/Contents/Applications/DeviceHub.app"`). `xcrun simctl` works from the shell.

## Simulator

Check screens on a simulator that is not in the production family: "mimamori mother" (iPhone 17 Pro, iOS 26.5), the mother's sample, or one you create for this check and delete afterwards. Never shoot or check screens on "mimamori iPhone": it is the family role and is joined to the production family, so its screens can show family names, smiles, and real consultations (`docs/harness.md`, "設定の範囲"). Use it only to check the family side against production: the main session moves the mobilebuildmcp defaults to it with `session_set_defaults` (never `persist`), and when that check ends it sets them back to "mimamori mother" (`simulatorName` and `simulatorId`) before any other work. Never join "mimamori mother" to the production family; check the joining flow with the stub or on a simulator you create and delete.

```sh
xcrun simctl list devices available | grep -q "mimamori mother" || \
  xcrun simctl create "mimamori mother" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5
xcrun simctl boot "mimamori mother" 2>/dev/null || true
```

iOS 26.5 because on this Mac the iOS 27.1 runtime supports only iPhone Duo, whose folding outer display does not look like the mother's iPhone; the app targets iOS 26.0, so 26.5 runs it. The author chose this on 2026-11-04. Anything that only iOS 27 changes goes to the real-iPhone check.

When another task's build is on "mimamori mother" (parallel worktrees), do not overwrite it. Create a simulator of your own, use its name below, and delete it when done. Read its udid in `xcrun simctl list devices` first and make sure it is not "mimamori iPhone":

```sh
xcrun simctl create "mimamori check-<issue>" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5
xcrun simctl delete "mimamori check-<issue>"
```

## Build, install, launch

```sh
SIM="mimamori mother"
xcodebuild -project ios/Mimamori.xcodeproj -scheme Mimamori \
  -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath build/DerivedData -quiet build
xcrun simctl install "$SIM" build/DerivedData/Build/Products/Debug-iphonesimulator/Mimamori.app
xcrun simctl launch --terminate-running-process "$SIM" com.sagochiko.mimamori \
  -mimamori-stub -mimamori-stub-joined protected
```

There is no demo family yet. Two walls keep screenshots away from the real family: the simulator is outside the production family, and `-mimamori-stub` (Debug only) answers every API call with made-up data and keeps the device key in memory. Use both. `-mimamori-stub-joined protected` or `family` starts on that home screen. Put a screen into the state you need with the other launch arguments in `ios/App/Debug/ScreenshotStubTransport.swift` (`-mimamori-stub-chat police`, `-mimamori-stub-draft <text>`, `-mimamori-stub-notices-open`, `-mimamori-stub-camera-open`, and others) rather than by tapping.

For taps and the UI tree, use the `mobilebuildmcp` MCP (`ui-automation`). The repository's default is "mimamori mother" (`.mobilebuildmcp/config.yaml`), but the main session may have moved it. Before the first mobilebuildmcp call, run `session_show_defaults`. Its UI tools (`screenshot`, `snapshot_ui`, `tap`, `batch`, `launch_app_sim`, and the rest) take no simulator argument and always act on the default. So when its `simulatorName` is not the simulator you use, or you use a simulator you created, do not use mobilebuildmcp: reach the state with launch arguments and shoot with `xcrun simctl io "$SIM" screenshot`. A `screenshot` or `snapshot_ui` on the family role would put family names and smiles into the context. If the default is "mimamori iPhone", say so in the report; the main session sets it back (a subagent cannot change the defaults, `guard-mcp.sh`). On 2026-11-06 the main session saw its taps and scrolls not reach the app on "mimamori mother"; when that happens, reach the state with launch arguments and shoot with `xcrun simctl`.

## Screenshot

```sh
xcrun simctl io "$SIM" screenshot <scratchpad>/$(date +%Y%m%d)-<screen>.png
```

Checking shots go to the scratchpad. Only a picture meant for the repository (README, submission) goes to `docs/screenshots/`, and only one shot with `-mimamori-stub` on a simulator outside the production family: the commit hooks read text, not images.

Look at the image before reporting. Check the screen text rule: no explanatory sentences, no headings above choices, no second line on empty states. Explanations belong in accessibility labels.

## What the simulator cannot check

Message Filter, DNS settings (NEDNSSettingsManager), the Safari extension, Call Directory, real APNs delivery, Personal Voice, and the call observer need a real iPhone. Hand each to the author as a "作者:" issue with `/mm-human-queue`: what to open, what to do, what result to report.
