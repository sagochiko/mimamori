---
name: mm-release
description: Uploads a mimamori build to App Store Connect for TestFlight - bumps the build number, archives Release, checks the archive, exports and uploads after the author approves, then tells the author which build to add to the mother's internal group and the judges' external group and what to write for beta review. Use for "TestFlight に上げて", "母に新しい版を届けて", "/mm-release".
---

# Upload a build for TestFlight

## 0. Before you start

Stop and say why if any of these fails.

- The Apple account is in Xcode > Settings > Accounts (signing and upload both use it; `No Accounts` means it is missing).
- The app record and the two TestFlight groups exist in App Store Connect (issue #34). Internal testers must be App Store Connect users, so the mother is a user of the account (issue #26).
- `grep MIMAMORI_API_HOST ios/Config/Shared.xcconfig` shows the deployed Workers host and the `/mm-deploy` smoke check passed for it. A build that points at `*.placeholder.invalid` cannot create a family, so beta review would reject it.
- `main` is up to date and the tree is clean: `git switch main && git pull --ff-only && git status --short`.

If a setting differs between the mother's build and the judges' build (planned in task 5 for the SMS network URL), release one build per audience with consecutive build numbers, and keep track of which number goes to which group.

## 1. Bump the build number

`CURRENT_PROJECT_VERSION` in `ios/project.yml` is the only place; every target's `CFBundleVersion` reads it. Use a new number for every upload.

```sh
N=$(( $(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\([0-9]*\)"$/\1/p' ios/project.yml) + 1 ))
git switch -c release-build-$N
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
strings -a "$APP/Mimamori" | grep -c -E 'ScreenshotStubTransport|mimamori-stub'
```

Expect: `$N` twice (no `ApplicationProperties` means it is not an iOS app archive and the export will fail), `ITSAppUsesNonExemptEncryption = false` (the app only uses HTTPS, so App Store Connect does not hold the build for the export compliance question), `MimamoriAPIBaseURL = https://<the deployed host>`, exactly `CallDirectory.appex MessageFilter.appex SafariExtension.appex` (ShareExtension is built but not embedded), and `0` for the DEBUG stub. A Debug build of the same check prints 8, so 0 means the stub is gone, not that the check is broken.

## 4. Export and upload (the author approves)

Tell the author in one line what is about to go up: build number, version (`MARKETING_VERSION` in `ios/project.yml`), API host. Then run the export. The hook (`guard-prod.sh`) and the `ask` rule make the author approve it; never reshape the command to get around them. If they decline, stop.

```sh
xcodebuild -exportArchive -archivePath "$A" -exportOptionsPlist ios/ExportOptions.plist \
  -exportPath "$OUT/export" -allowProvisioningUpdates
```

`ios/ExportOptions.plist` uses `method` = `app-store-connect` and `destination` = `upload`, so the export uploads. It keeps the build number (`manageAppVersionAndBuildNumber` = false) and leaves out `testFlightInternalTestingOnly`, because an internal-only build cannot go to the external group. If the upload is rejected, show the error lines; if App Store Connect already accepted build `$N`, bump again instead of reusing it.

After a successful upload, push the branch and open a PR so `main` carries the number: `git push -u origin release-build-$N`, then `gh pr create`.

## 5. Tell the author what to do in App Store Connect

Fill in the brackets and send it as it is. Labels are the English ones from Apple's TestFlight help; the Japanese screen shows them translated.

```text
ビルド <N>(<version>)を App Store Connect に送った。処理が終わると TestFlight タブに出る。

母のグループ(内部テスト、審査なし)
1. TestFlight > Internal Testing > <母のグループ> > Add Builds で <N> を選ぶ
2. What to Test に「<この版で変わったこと>」と書いて Add
   (グループで Enable automatic distribution を選んであれば、この手順なしで入る)

審査員のグループ(外部テスト)
1. Test Information の Beta App Description と Feedback Email が空なら先に入れる
2. TestFlight > External Testing > <審査員のグループ> > Add Builds で <N> を選ぶ
3. What to Test に「<この版で変わったこと>」と書き、Submit Review を押す
4. 審査用のメモ(Review Notes)には下の文を貼る

ログインは要りません。最初の画面で「家族」を選び、名前を入れて「作る」を押すと家族ができ、招待のコードが出ます。2台目では「見守られる人」を選んでそのコードを入れ、「入る」を押すと同じ家族に入れます。マイクの相談は準備中です。

No sign-in is needed. On the first screen, choose 家族 (Family), enter a name, and tap 作る (Create); a family is created and an invite code appears. On a second device, choose 見守られる人 (Protected person), enter that code, and tap 入る (Join) to join the same family. The voice consultation is not available yet.
```

Write "この版で変わったこと" from `git log --oneline` since the previous `ビルド番号を` commit, in one or two plain lines. Change the last sentence of the review note to match what the build can do. Apple's limits: the first build sent to external testing gets a full review, later builds of the same version might not; at most six builds go to review in 24 hours; one build per version can be in review at a time.

## 6. Clean up

```sh
rm -rf "$OUT"
```
