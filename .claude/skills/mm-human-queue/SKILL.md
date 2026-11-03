---
name: mm-human-queue
description: Hands a step only the author can do (real iPhone checks, Apple Developer or App Store Connect, TestFlight, talking with the mother, registering secrets, unlocking the holdout) to the author as a GitHub issue titled "作者: ...", and moves on instead of waiting. Use whenever work hits such a step, and when the author reports the result of one.
---

# Hand a step to the author

Each step only the author can do is one GitHub issue (the author decided this on 2026-11-03). `docs/human-queue.md` only points here now. The open ones:

```sh
gh issue list --label needs-human --state open --json number,title -q '.[] | select(.title | startswith("作者:")) | "#\(.number) \(.title)"'
```

## Open the issue

1. Write the body with the Write tool to a file in this session's scratchpad directory, for example `<scratchpad>/author-step.md`. Do not put the body on the command line: `guard-secrets.sh` and `guard-holdout.sh` read the Bash command text, so a body that names `.dev.vars` or the holdout unlock file is blocked there. The author approved `--body-file` for this on 2026-11-03, for bodies that name secret files and never hold their contents. Never write a key, a token, or anything about the family in the body; the repository and its issues become public.

   The body, in Japanese, says what to do and where, so the author can do it from the phone in one go, why it is needed, what to report back, and which issue it belongs to:

   ```markdown
   実機で SMS の拡張を有効にする。設定 > メッセージ > 不明な差出人 > mimamori をオンにし、試験用の番号から「テスト」と送る。

   迷惑フォルダに振り分ける判定が実機で動くかが、これで分かる。

   返事は、迷惑フォルダに入ったかどうかをこの Issue のコメントに書く。

   関連 #5
   ```

2. Create the issue and put it on the board:

   ```sh
   gh issue create --title "作者: <short summary>" --label needs-human --assignee sagochiko \
     --milestone "<milestone in CONDITIONS.md>" --body-file <scratchpad>/author-step.md
   scripts/board.sh <new number> Todo
   ```

   Keep file names out of the title, since the title is on the command line. One step per issue. The label goes on the author's issue only; the issue that waits for it is linked by the `関連 #n` line, and `/mm-task` step 1 looks for that line.

3. Continue with another issue that does not depend on it. When the author is away, send one push notification (PushNotification) for a batch of new steps, not one per step.

## When the author reports back

The author answers in the chat or in a comment on the issue.

1. If the answer came in the chat, add it to the issue as a comment, written the same way (`gh issue comment <n> --body-file <file>`). Write only what a public repository may show: the result, never family names, numbers, addresses, or real messages.
2. Close it: `gh issue close <n>`, then `scripts/board.sh <n> Done`.
3. Resume the issue named in its `関連` line.
