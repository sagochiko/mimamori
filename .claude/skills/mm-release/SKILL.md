---
name: mm-release
description: Uploads a mimamori build to App Store Connect for TestFlight - bumps the build number, archives Release, checks the archive, exports and uploads after the author approves, then fills in the mother's internal group and the judges' external group in Chrome and leaves only Submit Review to the author. Use for "TestFlight に上げて", "母に新しい版を届けて", "/mm-release".
---

# Upload a build for TestFlight

## 0. Before you start

Stop and say why if any of these fails.

- The Apple account is in Xcode > Settings > Accounts (signing and upload both use it; `No Accounts` means it is missing).
- The app record and the two TestFlight groups exist in App Store Connect (issue #34). Internal testers must be App Store Connect users, so the mother is a user of the account (issue #26).
- `grep MIMAMORI_API_HOST ios/Config/Shared.xcconfig` shows the deployed Workers host and the `/mm-deploy` smoke check passed for it. A build that points at `*.placeholder.invalid` cannot create a family, so beta review would reject it.
- `python3 .claude/skills/mm-release/beta_state.py 1` prints a state or `NO_BUILD`, not `is not visible to the API key`. Step 5 waits on it (see there). If the app is not visible, say so before archiving; step 5 then falls back to slower checks in Chrome.
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

Expect: `$N` twice (no `ApplicationProperties` means it is not an iOS app archive and the export will fail), `ITSAppUsesNonExemptEncryption = false` (the app only uses HTTPS, so App Store Connect does not hold the build for the export compliance question), `MimamoriAPIBaseURL = https://<the deployed host>`, exactly `CallDirectory.appex MessageFilter.appex SafariExtension.appex` (ShareExtension is built but not embedded), `0` debug dylibs, and `0` for the DEBUG stub.

The stub check reads every file in the `.app`, not only `Mimamori`, because a Debug build of Xcode 27.1 moves the code into `*.debug.dylib` files. Measured on 2026-11-04 with simulator builds of the same scheme: Debug had 4 debug dylibs (`Mimamori.debug.dylib` and one in each embedded extension), 0 hits in `Mimamori` alone and 8 over the whole `.app`; Release had no debug dylib and 0 hits over the whole `.app`. So 8 in Debug shows the check finds the stub, and 0 here means it is gone. A debug dylib in this archive means the Release configuration was not used; stop.

## 4. Export and upload (the author approves)

Tell the author in one line what is about to go up: build number, version (`MARKETING_VERSION` in `ios/project.yml`), API host. Then run the export. The hook (`guard-prod.sh`) and the `ask` rule make the author approve it; never reshape the command to get around them. If they decline, stop.

```sh
xcodebuild -exportArchive -archivePath "$A" -exportOptionsPlist ios/ExportOptions.plist \
  -exportPath "$OUT/export" -allowProvisioningUpdates
```

`ios/ExportOptions.plist` uses `method` = `app-store-connect` and `destination` = `upload`, so the export uploads. It keeps the build number (`manageAppVersionAndBuildNumber` = false) and leaves out `testFlightInternalTestingOnly`, because an internal-only build cannot go to the external group. If the upload is rejected, show the error lines; if App Store Connect already accepted build `$N`, bump again instead of reusing it.

After a successful upload, push the branch and open a PR so `main` carries the number: `git push -u origin release-build-$N`, then `gh pr create`.

## 5. Fill in both groups and leave Submit Review to the author

The author does one thing here: press Submit Review, because it sends the build to Apple's beta review and cannot be taken back. Claude does everything before it in Chrome and notices the end by itself. Labels are the English ones from Apple's TestFlight help; the Japanese screen shows them translated.

The waits read the App Store Connect API through `beta_state.py`. The build's `externalBuildState` (its `buildBetaDetail`, Apple's ExternalBetaState) moves from `PROCESSING` to `READY_FOR_BETA_SUBMISSION` when processing ends and leaves `READY_FOR_BETA_SUBMISSION` when the review is submitted. It does not depend on the screen language, and a shell loop reads it with two GETs per poll, so waiting costs no tokens. The Chrome page was not chosen: AppleScript gives a shell only the tab URLs and titles, which do not show the build's state, and reading the page text from AppleScript needs Chrome's "Allow JavaScript from Apple Events", which lets local scripts run JavaScript in every tab. Checking the page with Claude in Chrome works but spends tokens on each look, so it is only the fallback. `beta_state.py` signs in through the author's `app-store-connect` skill in `~/.claude/skills`, which finds the API key itself; the script only reads and never names or prints the key.

### 5a. Wait for processing

Run `python3 .claude/skills/mm-release/beta_state.py $N` once; expect `NO_BUILD` or `PROCESSING`. Then wait with `run_in_background`:

```sh
S=.claude/skills/mm-release/beta_state.py
for i in $(seq 60); do
  st=$(python3 "$S" "$N") || exit 2
  case "$st" in NO_BUILD|PROCESSING) sleep 30 ;; *) echo "$st"; exit 0 ;; esac
done; exit 1
```

`READY_FOR_BETA_SUBMISSION` is the expected end. `MISSING_EXPORT_COMPLIANCE` means `ITSAppUsesNonExemptEncryption` did not reach the build, and `PROCESSING_EXCEPTION` means Apple could not process it; show the state and stop. Exit 1 is the 30 minute limit: ask once whether to wait again. Exit 2 means the API call failed; show its stderr line.

### 5b. Fill in the groups in Chrome

Load the Claude in Chrome tools in one ToolSearch call (the `chrome-browser` skill), open a new tab at `https://appstoreconnect.apple.com/apps`, and go to the app's TestFlight tab.

If the sign-in page appears instead, click into its password field so that only the password is left to type, and ask the author only to sign in (password and two-factor code). Before asking, run the check below once; if it already succeeds, another tab is signed in, so reload this tab instead of asking. Then wait with `run_in_background`. The pattern is anchored to the start of the URL, so a sign-in URL that carries `/apps` in its query does not match.

```sh
on_apps() { osascript -e 'tell application "Google Chrome" to get URL of every tab of every window' 2>/dev/null \
  | tr ',' '\n' | grep -q '^ *https://appstoreconnect\.apple\.com/apps'; }
for i in $(seq 360); do on_apps && exit 0; sleep 5; done; exit 1
```

Then fill in, without pressing any button that sends the build to testers outside the family's group or to Apple:

1. Internal Testing > the mother's group. If the group uses automatic distribution, build `$N` is already listed; go on. Otherwise use Add Builds, choose `$N`, write What to Test, and press Add. Claude presses this one: it reaches only the mother's internal group, which is what this skill is for.
2. Test Information. Beta App Description and Feedback Email must already be filled (issue #34). The feedback address is the author's, so do not type one; if either is empty, stop and point to issue #34. Paste the review note below into Review Notes in the beta app review information and save.
3. External Testing > the judges' group > Add Builds. Choose `$N`, go on to What to Test and write it, and tick Automatically notify testers so the judges get the build as soon as it is approved. Stop with Submit Review on the screen (Start Testing when Apple does not review this build). Do not press it.

Do not save screenshots of these pages to disk, and do not paste page text that shows the account's name or email.

### 5c. Hand over the one press

Run `python3 "$S" "$N"` once; it must print `READY_FOR_BETA_SUBMISSION`. If it prints something else, the build already moved on; report that instead of asking. Then ask in one line ("Submit Review を押してください。終わったら自動で続けます") and wait with `run_in_background`:

```sh
for i in $(seq 120); do
  st=$(python3 "$S" "$N") || exit 2
  [ "$st" != READY_FOR_BETA_SUBMISSION ] && { echo "$st"; exit 0; }
  sleep 15
done; exit 1
```

Expect `WAITING_FOR_BETA_REVIEW` for the first build of a version, or `IN_BETA_TESTING` or `BETA_APPROVED` when Apple lets a later build through without a full review. Report the state and the build number. Exit 1 is the 30 minute limit: ask once whether to wait again.

If step 0 found that the API key cannot see the app, no shell state shows the press. Then look at the build's status in the judges' group with Claude in Chrome after each `sleep 300` run with `run_in_background`, at most six times, and do not look in between.

### What to write

```text
What to Test(母のグループと審査員のグループ)
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
