---
name: mm-screen-guide
description: Makes a picture of tap-by-tap steps for something the author or the mother does on an iPhone (Settings, Shortcuts automations, TestFlight, permission prompts) - goes through the same screens on the mother-role simulator (iOS 26.5), screenshots each one, and marks where to tap. Use before handing a person steps on a phone screen, when text steps would be hard to follow ("手順を画像で", "スクショで手順を作って", "シミュレータで撮って手順に").
---

# Steps as a picture

The author found text-only steps hard to follow (2026-11-05). Before asking someone to tap through iPhone screens, go through the same screens yourself on a simulator, screenshot each, and send one picture with a red ring and number on every tap. `/mm-human-queue` still decides whether the step becomes an "作者:" issue; this skill makes what goes in it.

## 1. Use "mimamori mother"

Shoot every guide on "mimamori mother" (iPhone 17 Pro, iOS 26.5), for the author's phone and the mother's alike. Both are an ordinary iPhone 16 (the author said on 2026-11-05 that any ordinary iPhone model will do). The mother's runs iOS 26.5.2 (#24), so her screens match. The author's ran iOS 27.2 on 2026-11-05, and no simulator on this Mac shows iOS 27 on an ordinary iPhone: the iOS 27.1 runtime runs only the folding iPhone Duo, whose displays differ and whose taps missed (`Makefile`, `simulator`; `docs/dev-log.md`). So read the phone's version first (`xcrun devicectl list devices`, then `xcrun devicectl device info details --device <udid>` and its `OS Version` line), and when it is not 26, say on the picture that it was shot on 26.5 and that the screens may differ. On 2026-11-05 the Shortcuts automation took four screens on 26.5 and one on 27.2.

Never use "mimamori iPhone": it is the family role, joined to the production family (`docs/harness.md`, "設定の範囲").

Check the language (`xcrun simctl spawn <udid> defaults read -g AppleLanguages`). If it is not Japanese, launch the app with `-AppleLanguages "(ja)" -AppleLocale ja_JP` after the bundle id.

Some system apps are not in the simulator. On 2026-11-05 the iOS 26.5 one had no Phone (`com.apple.mobilephone`); Shortcuts (`com.apple.shortcuts`) and Settings (`com.apple.Preferences`) were there. Check with `xcrun simctl listapps <udid>`. When the steps pick a missing app, shoot that screen with another app and say so on the picture; the person picks the real one.

## 2. Drive it

In the main session, run `session_show_defaults` first and look at what it prints: the repository's default is "mimamori mother" (`.mobilebuildmcp/config.yaml`), and the session may have moved it already. Then point mobilebuildmcp at the simulator for this guide with `session_set_defaults` (`simulatorName` and `simulatorId`, never `persist`). Step 4 sets them back to "mimamori mother". A subagent may not change the defaults (`guard-mcp.sh`); it asks the main session.

Open the app with `xcrun simctl launch <udid> <bundle id>`. For each screen, screenshot before acting:

```sh
xcrun simctl io <udid> screenshot <scratchpad>/guide/NN.png
```

Then act, and write down the `x` and `y` the tap or touch result prints. Those are points; the picture needs pixels, so note the scale too (screenshot width ÷ the screen's width in points: 3 on an iPhone 17 Pro, 1206 px ÷ 402 pt). The script refuses a mark that falls outside the screenshot, which is what a pixel given in place of a point usually does.

What the tools did on 2026-11-05:

- A row that `snapshot_ui` lists only as text (no `tap` action) is pressed with `touch` on its ref, `down` and `up` both true
- `swipe` on a sheet's list did nothing. `gesture` with preset `scroll-up` and `delta` 200 moved the list on (the content goes up)
- `type_text` takes US keyboard characters only. For Japanese, tap the keys of the on-screen romaji keyboard one by one with `batch` (t, u, u, t, i) and then the candidate (通知) in the bar. `xcrun simctl pbcopy` did not reach the field's paste menu
- After each navigation, take a fresh `snapshot_ui`; refs change

Stop at the last screen before anything that sends, buys, or changes an account. A simulator has no real accounts, but the picture must not show a step the person should not take.

## 3. Build the picture

Write a spec next to the screenshots, then run the script that comes with this skill:

```json
{"title": "電話が閉じたら通知するオートメーションの作り方",
 "notes": ["iOS 26.5 のシミュレータで撮った。…"],
 "scale": 3,
 "steps": [{"image": "01.png", "marks": [[202, 803, "1"]], "caption": ["下の「オートメーション」を押す"]}]}
```

```sh
python3 -I "${CLAUDE_SKILL_DIR}/annotate.py" <scratchpad>/guide/spec.json <scratchpad>/guide/out.png
python3 -I "${CLAUDE_SKILL_DIR}/annotate.py" --self-test
```

`marks` are the points from step 2 and a label, numbered in the order the person taps across the whole guide. One screen can carry several marks; its caption then names each by its number (⑤, ⑥). Captions are one action per line in the words on the screen, in the plain form (「押す」, not 「押してください」). The script wraps a line that is too long and never starts a line with a closing bracket, but break long captions yourself where the meaning breaks.

The title is the goal, not a heading with a colon. The notes say which simulator version it was shot on, which screen used a stand-in app, and what to do when the phone looks different.

## 4. Check, send, clean up

- Look at the picture yourself before sending: cut it into pieces with `sips --cropOffset <y> 0 -c <h> <w> out.png --out part.png` and read each. Every caption inside its tile, every ring on its target, numbers in order
- Send it with `SendUserFile` (`display: "render"`), and give the same steps in text in the message, one line per tap, so they can be searched and quoted
- Set the mobilebuildmcp defaults back to "mimamori mother" (`session_set_defaults` with its `simulatorName` and `simulatorId`), not to what step 2 printed, which may be a family-role default someone forgot to set back: a later verifier builds on the default and may not change it itself
- Delete the screenshots in the scratchpad once the person is done. Leave "mimamori mother" itself, but undo what the steps changed on it (an automation, a permission, an extension's switch), or write on the issue what is left: a later verifier shoots the app on this simulator
- If a screen on the phone turned out different, write what differed on the issue the steps belong to, with both versions
