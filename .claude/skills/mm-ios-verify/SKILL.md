---
name: mm-ios-verify
description: Builds the mimamori iOS app, runs it on the simulator, and captures screenshots, and lists what only a real device can check. Use to see a screen or confirm a UI change ("画面を確認して", "シミュレータで撮って").
---

# Check the iOS app

This Mac has Xcode 27.1 at `/Applications/Xcode-27.1.0.app`. There is no Simulator.app; the author opens simulators in Device Hub (`open "/Applications/Xcode-27.1.0.app/Contents/Applications/DeviceHub.app"`). `xcrun simctl` works from the shell.

## Simulator

```sh
make simulator
xcrun simctl boot "mimamori iPhone" 2>/dev/null || true
```

`make simulator` creates "mimamori iPhone" once, on the iOS 27.1 runtime, with the first iPhone device type that runtime supports. On 2026-11-03 that was iPhone Duo, the only one it listed; a type the runtime does not list fails with "Incompatible device". iPhone Duo folds, so say which display a screenshot shows.

## Build, install, launch

```sh
xcodebuild -project ios/Mimamori.xcodeproj -scheme Mimamori \
  -destination 'platform=iOS Simulator,name=mimamori iPhone' \
  -derivedDataPath build/DerivedData -quiet build
xcrun simctl install "mimamori iPhone" build/DerivedData/Build/Products/Debug-iphonesimulator/Mimamori.app
xcrun simctl launch --terminate-running-process "mimamori iPhone" <bundle id>
```

For taps and the UI tree, use the `mobilebuildmcp` MCP (`ui-automation`). Use the demo family token so nothing reaches the real family.

## Screenshot

```sh
mkdir -p docs/screenshots
xcrun simctl io "mimamori iPhone" screenshot docs/screenshots/$(date +%Y%m%d-%H%M)-<screen>.png
```

Look at the image before reporting. Check the screen text rule: no explanatory sentences, no headings above choices, no second line on empty states. Explanations belong in accessibility labels.

## What the simulator cannot check

Message Filter, DNS settings (NEDNSSettingsManager), the Safari extension, Call Directory, real APNs delivery, Personal Voice, and the call observer need a real iPhone. Hand each to the author as a "作者:" issue with `/mm-human-queue`: what to open, what to do, what result to report.
