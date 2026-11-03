---
name: mm-device
description: Builds the mimamori app for the author's paired iPhone with automatic signing, installs it, and launches it. Use to put the current branch on the real phone ("実機に入れて", "iPhone で動かして", "/mm-device"). Checks that need a person looking at the phone still go to an 作者: issue.
---

# Put the app on the paired iPhone

Signing is automatic (team `CTK4XXPWH9` in `ios/project.yml`). `xcodebuild` reaches the developer portal through the Apple account in Xcode > Settings > Accounts. If the build prints `No Accounts: Add a new account in Accounts settings.`, stop: the author signs in there, then run the build again. The first signed build registers the five bundle IDs, the App Group `group.com.sagochiko.mimamori`, and the Push Notifications, App Groups, and Associated Domains capabilities. Report what it registered and any `doesn't include the ... capability` lines word for word.

Builds go to this session's scratchpad directory, not the repo. `<scratchpad>` below means that directory.

## 1. Find the phone

```sh
xcrun devicectl list devices --filter "Reality = 'physical'" \
  --hide-default-columns --columns Identifier --columns Model --columns State
```

Take the UDID from the Identifier column (drop ` (UDID)`). `available (paired)` is enough; the Wi-Fi tunnel opens on the next command. If no physical device is listed, the phone is not paired with this Mac; ask the author to pair it. Do not write the device's name anywhere; it can contain a person's name.

```sh
UDID=<udid>
DD=<scratchpad>/DerivedData-device
APP="$DD/Build/Products/Debug-iphoneos/Mimamori.app"
```

## 2. Build

```sh
xcodebuild -project ios/Mimamori.xcodeproj -scheme Mimamori -configuration Debug \
  -destination "platform=iOS,id=$UDID" -derivedDataPath "$DD" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration -quiet build
```

`-allowProvisioningDeviceRegistration` registers the phone in the portal if it is not there yet. A Debug build registers its push token as `sandbox` and talks to `MIMAMORI_API_HOST` in `ios/Config/Shared.xcconfig`; while that is still `*.placeholder.invalid`, every API call fails on purpose (`/mm-deploy` sets the real host).

## 3. Install, retrying once on a dropped connection

The Wi-Fi tunnel sometimes closes right after it opens. Retry once only when the log mentions a disconnect; report any other failure as it is.

```sh
xcrun devicectl device install app --device "$UDID" "$APP" > "$DD/install.log" 2>&1; rc=$?
if [ $rc -ne 0 ] && grep -qi 'disconnect' "$DD/install.log"; then
  xcrun devicectl device install app --device "$UDID" "$APP" > "$DD/install.log" 2>&1; rc=$?
fi
cat "$DD/install.log"; echo "install exit=$rc"
```

## 4. Launch

```sh
xcrun devicectl device process launch --device "$UDID" --terminate-existing com.sagochiko.mimamori
```

To see the screens with canned data before the host exists, add `-- -mimamori-stub` (Debug builds only). If the launch fails, check `xcrun devicectl device info lockState --device "$UDID"`; with `passcodeRequired: true`, ask the author to unlock the phone and run the launch line again.

## 5. Clean up

```sh
rm -rf "$DD"
```

## What this does not check

Message Filter, the Safari extension, Call Directory, DNS settings, real APNs delivery, and anything else that needs someone looking at the phone. Write each as an `作者:` step with `/mm-human-queue`: what to open, what to do, what result to report.
