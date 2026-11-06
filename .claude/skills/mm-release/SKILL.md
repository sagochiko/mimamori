---
name: mm-release
description: Uploads a mimamori build to App Store Connect for TestFlight - bumps the build number, archives Release, checks the archive, exports and uploads, then hands it to the internal group 「家族」, the route for a build the author checks on the iPhone (no Apple review), and, for the mother and the judges, fills in the external group 「審査員と家族」 in Chrome and presses Submit Review itself. Use for "TestFlight に上げて", "実機で確かめる版を配って", "母に新しい版を届けて", "/mm-release".
---

# Upload a build for TestFlight

## 0. Before you start

Stop and say why if any of these fails.

- The Apple account is in Xcode > Settings > Accounts (the archive in step 2 signs with it; `No Accounts` means it is missing). The upload in step 4 uses the App Store Connect API key instead and falls back to this account.
- The app record and the two TestFlight groups exist in App Store Connect (issue #34): the internal group 「家族」 and the external group 「審査員と家族」. `ASC_APP_ID` in step 5 holds the app's Apple ID instead of the `<ASC_APP_ID>` mark. Internal testers must be App Store Connect users (issue #26); the mother gets builds through the external group until she is one (issue #2).
- `grep MIMAMORI_API_HOST ios/Config/Shared.xcconfig` shows the deployed Workers host and the `/mm-deploy` smoke check passed for it. A build that points at `*.placeholder.invalid` cannot create a family, so beta review would reject it.
- The tree is clean: `git status --short` prints nothing. Look before step 1 switches branches, so changes carried over from another branch show up here. Step 1 branches from `origin/main` and never switches this tree to `main`, which another worktree may hold.

If a setting differs between the mother's build and the judges' build (planned in task 5 for the SMS network URL), release one build per audience with consecutive build numbers, and keep track of which number goes to which group.

## 1. Bump the build number

`CURRENT_PROJECT_VERSION` in `ios/project.yml` is the only place; every target's `CFBundleVersion` reads it. Use a new number for every upload.

```sh
git fetch origin
N=$(( $(git show origin/main:ios/project.yml | sed -n 's/^ *CURRENT_PROJECT_VERSION: "\([0-9]*\)"$/\1/p') + 1 ))
git switch -c release-build-$N origin/main
sed -i '' "s/^\( *CURRENT_PROJECT_VERSION: \)\"[0-9]*\"$/\1\"$N\"/" ios/project.yml
/opt/homebrew/bin/xcodegen generate --spec ios/project.yml --quiet
git add ios/project.yml ios/Mimamori.xcodeproj/project.pbxproj && git diff --cached --stat
git commit -m "chore(ios): ビルド番号を $N にする" -m "TestFlight に上げる版の番号を git の番号と一致させるため。" \
  -m "Co-Authored-By: Claude <noreply@anthropic.com>"
```

The diff is one line in `project.yml` and two in the `.pbxproj`.

## 2. Archive

Work in this session's scratchpad directory (`<scratchpad>`), not the repo.

```sh
OUT=<scratchpad>/release-$N
A="$OUT/Mimamori-$N.xcarchive"; APP="$A/Products/Applications/Mimamori.app"
xcodebuild -project ios/Mimamori.xcodeproj -scheme Mimamori -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$OUT/DerivedData" \
  -archivePath "$A" -allowProvisioningUpdates -quiet archive
```

## 3. Check the archive

```sh
/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$A/Info.plist"
for k in CFBundleVersion ITSAppUsesNonExemptEncryption MimamoriAPIBaseURL; do
  printf '%s = ' $k; /usr/libexec/PlistBuddy -c "Print :$k" "$APP/Info.plist"; done
ls "$APP/PlugIns"
find "$APP" -name '*.debug.dylib' | wc -l
find "$APP" -type f -exec strings -a {} + 2>/dev/null | grep -c -E 'ScreenshotStubTransport|mimamori-stub'
```

Expect: `$N` twice (no `ApplicationProperties` means it is not an iOS app archive and the export will fail), `ITSAppUsesNonExemptEncryption = false` (the app only uses HTTPS, so App Store Connect does not hold the build for the export compliance question), `MimamoriAPIBaseURL = https://<the deployed host>`, exactly `CallDirectory.appex MessageFilter.appex SafariExtension.appex ShareExtension.appex` (ShareExtension has been embedded since PR #186, which made it read shared screenshots and documents), `0` debug dylibs, and `0` for the DEBUG stub.

The stub check reads every file in the `.app`, not only `Mimamori`, because a Debug build of Xcode 27.1 moves the code into `*.debug.dylib` files. Measured on 2026-11-04 with simulator builds of the same scheme: Debug had 4 debug dylibs (`Mimamori.debug.dylib` and one in each embedded extension), 0 hits in `Mimamori` alone and 8 over the whole `.app`; Release had no debug dylib and 0 hits over the whole `.app`. So 8 in Debug shows the check finds the stub, and 0 here means it is gone. A debug dylib in this archive means the Release configuration was not used; stop.

## 4. Export and upload

Say in one line what is about to go up: build number, version (`MARKETING_VERSION` in `ios/project.yml`), API host, and the route of step 5: a build for the author to check goes to 「家族」 only ("処理のあと「家族」に配る"), a build for the mother and the judges also goes to 「審査員と家族」 and its review ("処理のあと「家族」に配り、「審査員と家族」の審査へ出す"). Then run the export without waiting: since 2026-11-04 the author lets uploads to App Store Connect run unasked during development, and since 2026-11-05 Claude also presses Submit Review in step 5. If a permission prompt or a hook still stops the export, do not reshape the command to get around it; report it.

The upload signs in with mimamori's App Store Connect API key, not the account saved in Xcode. The author made the key on 2026-11-07 (name `mimamori TestFlight upload`, role App Manager, key ID `FB49V3RX2C`, Issuer ID `c9406333-bd27-4369-8778-d87d66b976c5`; the IDs are not secret). `guard-secrets.sh` lets exactly two Bash lines name the key file, and only when the whole line has the shape; Claude never reads the file (no `cat`, `head`, `grep`, Read, or copy).

First, `ls ~/.appstoreconnect/private_keys/`. Only when it shows no key, move the downloaded one into place with this line, once:

```sh
mkdir -p ~/.appstoreconnect/private_keys && mv ~/Downloads/AuthKey_FB49V3RX2C.p8 ~/.appstoreconnect/private_keys/
```

Then upload. Write the archive and export paths out in full (the expanded `$A` and `$OUT/export`): the hook passes only plain words and paths, so a line with `$`, quotes, a pipe, a redirect, `;`, `&&`, a leading `cd`, or a line break is blocked, and a blocked line is reported, not reshaped. Run it as one Bash call:

```sh
xcodebuild -exportArchive -archivePath <scratchpad>/release-<N>/Mimamori-<N>.xcarchive -exportOptionsPlist ios/ExportOptions.plist -exportPath <scratchpad>/release-<N>/export -allowProvisioningUpdates -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_FB49V3RX2C.p8 -authenticationKeyID FB49V3RX2C -authenticationKeyIssuerID c9406333-bd27-4369-8778-d87d66b976c5
```

The key flags are options of `xcodebuild` itself, not keys of the export options plist: `man xcodebuild` (Xcode 27.1) lists `-authenticationKeyPath`, `-authenticationKeyID`, and `-authenticationKeyIssuerID`, and `xcodebuild -help` says `-allowProvisioningUpdates` "Requires a developer account to have been added in Xcode's Accounts settings or an App Store Connect authentication key to be specified via the -authenticationKeyPath, -authenticationKeyID, and -authenticationKeyIssuerID parameters." So `ios/ExportOptions.plist` stays as it is.

If the key route fails (the key was revoked, or its role cannot sign), the fallback is the account in Xcode > Settings > Accounts, the route used before 2026-11-07:

```sh
xcodebuild -exportArchive -archivePath "$A" -exportOptionsPlist ios/ExportOptions.plist \
  -exportPath "$OUT/export" -allowProvisioningUpdates
```

That route stops with `App Store Connect access for "<team>" is required` when Xcode's sign-in has lapsed; then the author has to sign in again in Xcode, so hand it to them with `/mm-human-queue`.

`ios/ExportOptions.plist` uses `method` = `app-store-connect` and `destination` = `upload`, so the export uploads. It keeps the build number (`manageAppVersionAndBuildNumber` = false) and leaves out `testFlightInternalTestingOnly`, because an internal-only build cannot go to the external group. If the upload is rejected, show the error lines; if App Store Connect already accepted build `$N`, bump again instead of reusing it.

After a successful upload, push the branch and open a PR so `main` carries the number: `git push -u origin release-build-$N`, then `gh pr create`.

## 5. Hand the build to its groups

There are two routes, and step 4 already said which one this build takes.

- A build for the author to check on the iPhone goes to the internal group 「家族」 only: 5a, then item 1 of 5b. Internal testing does not wait for Apple: Apple's TestFlight help ties beta review to external testers, and build 3 was in internal testing while the external review of build 2 was still pending (issue #2). Use `/mm-device` instead only when the check needs a Debug launch argument such as `-mimamori-stub`. The author decided this on 2026-11-05.
- A build for the mother and the judges also goes to the external group 「審査員と家族」, which sends it to Apple's beta review: all of 5a to 5c. Claude presses Submit Review (審査へ提出) itself; the author decided on 2026-11-05 that Claude presses it, now and from then on (「君がおしていいです。これからも」). It cannot be taken back, so check the build number and the group on the sheet before pressing.

While the mother is not an internal tester, a check build in 「家族」 does not reach her. When she becomes one, split the internal side before the next upload: one group for the author's checks and one for the mother, so a build nobody has checked does not land on her phone. Then name both groups here.

Claude does everything in Chrome and notices the end by itself. Labels are the English ones from Apple's TestFlight help; the Japanese screen shows them translated.

The app is opened by its Apple ID, never through the app list at `https://appstoreconnect.apple.com/apps`: that list shows the author's other apps, and this project keeps the author's earlier projects out of Claude's context. The Apple ID is a number, not a secret; App Store Connect shows it under App Information. Fill it in here after issue #34:

```sh
ASC_APP_ID=6830395335   # the app's Apple ID in App Store Connect (issue #34)
BUILDS="https://appstoreconnect.apple.com/apps/$ASC_APP_ID/testflight/ios"
```

Two Chrome tabs are used. The work tab is where the groups are filled in and where the Submit Review sheet stays open until 5c presses it; once the sheet is open, never reload it or navigate it, or the sheet closes with the build choice and What to Test in it and has to be filled in again. The status tab shows `$BUILDS` (the iOS builds list) and is the only tab that is reloaded. A status look reloads the status tab and reads only build `$N`'s row with `find` (its build number and status); do not use `get_page_text` or take screenshots, which would pull in the rest of the page. Between looks, run `sleep 300` with `run_in_background` and do nothing until it ends; look at most six times (30 minutes), then ask once whether to wait again.

Since 2026-11-07 the upload in step 4 uses an App Store Connect API key that the author made for mimamori during the event; Claude passes only its path to `xcodebuild` and never reads the file, which `guard-secrets.sh` enforces. Keys or code the author made before the event are not used. The waits here still stay in Chrome: calling the App Store Connect API from a shell loop would need a signed token built from the key's content, which Claude would have to read or code that would have to be written for it, and the two allowed lines cover only `xcodebuild`.

### 5a. Open the tabs and wait for processing

Load the Claude in Chrome tools in one ToolSearch call (the `chrome-browser` skill) and open `$BUILDS` in a new tab; this is the status tab.

If the sign-in page appears instead, click into its password field so that only the password is left to type, and ask the author only to sign in (password and two-factor code). Before asking, run the check below once; if it already succeeds, another tab is signed in, so reload this tab instead of asking. Then wait with `run_in_background`. The pattern is anchored to the start of the URL and includes the app's ID, so a sign-in URL that carries the same address in its query does not match, and neither does the app list. Since 2026-11-07 a signed-in page can carry the team in its path (`https://appstoreconnect.apple.com/teams/<team id>/apps/<app id>/testflight/ios`), so the pattern accepts that form too; the older one missed a finished sign-in for 30 minutes.

```sh
ASC_APP_ID=6830395335   # again here: run_in_background starts a new shell without the block above
on_app() { osascript -e 'tell application "Google Chrome" to get URL of every tab of every window' 2>/dev/null \
  | tr ',' '\n' | grep -q -E "^ *https://appstoreconnect\.apple\.com/(teams/[^/]+/)?apps/$ASC_APP_ID/testflight"; }
for i in $(seq 360); do on_app && exit 0; sleep 5; done; exit 1
```

Apple processes an upload before it can be added to a group. Read build `$N`'s row in the status tab. A build that is not in the list yet counts as processing, the same as one that shows processing; wait as above. Stop and show the status if Apple reports a processing problem or asks the export compliance question; the latter means `ITSAppUsesNonExemptEncryption` did not reach the build.

### 5b. Fill in the groups in the work tab

Open `$BUILDS` in a second new tab; this is the work tab. Fill in, without pressing anything that sends the build to Apple before 5c:

1. Internal Testing > 「家族」. If the group uses automatic distribution, build `$N` is already listed; go on. 「家族」 did on 2026-11-07: build 8 was already installed on the author's iPhone before anything was pressed, so read the group first. Otherwise use Add Builds, choose `$N`, write What to Test, and press Add. For a build the author checks, this is the end: report the build number and that it is in 「家族」, then go to step 6.
2. Test Information. Beta App Description and Feedback Email must already be filled (issue #34). The feedback address is the author's, so do not type one; if either is empty, stop and point to issue #34. Paste the review note below into Review Notes in the beta app review information and save.
3. External Testing > 「審査員と家族」 > Add Builds. Choose `$N`, go on to What to Test and write it, and tick Automatically notify testers so the mother and the judges get the build as soon as it is approved. Stop with Submit Review on the screen (Start Testing when Apple does not review this build), and leave this tab alone until 5c.

Do not save screenshots of these pages to disk, and do not paste page text that shows the account's name or email.

### 5c. Press Submit Review

Reload the status tab, read build `$N`'s status in the iOS builds list, and keep the text; it is the status before the press. In the work tab, read the sheet once with `find`: it must name build `$N` and 「審査員と家族」. If either differs, stop and report what it shows. Otherwise press Submit Review (審査へ提出), or Start Testing when that is the button, and wait as above, looking only at the status tab. The press went through when build `$N`'s status differs from the text you kept: waiting for review for the first build of a version, or testing when Apple lets a later build through without a full review. Report the status and the build number.

### What to write

```text
What to Test(「家族」と「審査員と家族」)
<この版で変わったこと>

Review Notes(審査用のメモ)
ログインは要りません。最初の画面で「家族」を選び、名前を入れて「作る」を押すと家族ができ、招待のコードが出ます。2台目では「見守られる人」を選んでそのコードを入れ、「入る」を押すと同じ家族に入れます。マイクの相談は準備中です。

No sign-in is needed. On the first screen, choose 家族 (Family), enter a name, and tap 作る (Create); a family is created and an invite code appears. On a second device, choose 見守られる人 (Protected person), enter that code, and tap 入る (Join) to join the same family. The voice consultation is not available yet.
```

Write "この版で変わったこと" from `git log --oneline` since the previous `ビルド番号を` commit, in one or two plain lines. Change the last sentence of the review note to match what the build can do. Apple's limits: the first build sent to external testing gets a full review, later builds of the same version might not; at most six builds go to review in 24 hours; one build per version can be in review at a time.

## 6. Clean up

```sh
rm -rf "$OUT"
```
