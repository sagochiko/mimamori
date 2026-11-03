---
name: mm-human-queue
description: Queues a step only the author can do (real iPhone checks, Apple Developer or App Store Connect, TestFlight, talking with the mother, unlocking the holdout) in docs/human-queue.md and moves on instead of waiting. Use whenever work hits such a step.
---

# Queue a step for the author

Append one line to `docs/human-queue.md` under "待っているもの":

```markdown
- [ ] 2026年11月3日 15:10 #5 実機で SMS の拡張を有効にする。設定 > メッセージ > 不明な差出人 > mimamori をオン。試験用の番号から「テスト」と送り、迷惑フォルダに入るかを返事する
```

Each line says what to do, where, and what result to report back, so the author can do it from the phone in one go. One step per line. If the step blocks an issue, add the `needs-human` label to that issue.

Then continue with another issue that does not depend on it. When the author is away, send one push notification (PushNotification) for a batch of new steps, not one per step.

When the author ticks a line, move it to "終わったもの" with the result they reported, remove `needs-human` from the issue, and resume it.
