---
name: mm-devlog
description: Adds a dated entry to docs/dev-log.md when something in mimamori's development surprised us, an approach was dropped, or Claude's suggestion was overruled. Use right when it happens ("記録して", "dev-log に残して"), and from /mm-task.
---

# Write a dev-log entry

`docs/dev-log.md` is the evidence that this entry was built during the event with Claude Code at the center, and the source for the submission form question "the hardest moment". Write entries as they happen; memory fades by Sunday.

Append at the end, newest last. The example below is made up to show the format; it is not a real result.

The heading is the date and a title, with no time of day. The repository goes public, and a time on a weekday from ten to noon or from one to seven in the afternoon would read as the author working on this during their job; the commit hook stops such a time in documents (`scripts/scan-private.sh`, issue #116). When the hour matters to the story, say 午後 or 夜 in the text.

```markdown
## 2026年11月3日 Message Filter の待ち時間 (#5)

知らない相手からの SMS を、サーバーの判定で迷惑フォルダに回すところを作っていた。

Claude Code には「サーバーで 1秒、3秒、5秒と遅らせて、迷惑フォルダに回る境目を見て」と頼んだ。

3秒を超えると、判定を待たずに通常の受信箱へ届いた(実機で各5回)。

計画では5秒まで待つ前提で、規則と Claude の判定を1回の問い合わせで返すつもりだった。

即答は規則だけで返し、Claude の判定はキューで後から家族に知らせる形に分けた。Claude は待ち時間を延ばす設定を探す案を出したが、iOS 側で変えられないので採らなかった。使ったのは mm-implementer、mm-verifier、guard-prod フック。
```

Write five short paragraphs in this fixed order, without labels: what you were building, how you asked Claude (quote the instruction), what happened (facts and numbers), how it differed from what you expected, and how you dealt with it (the option taken, options dropped and why, and any Claude suggestion you did not take). End the last paragraph with the Claude Code features actually used.

The order follows the submission form's question about the hardest moment. Keep each paragraph short and concrete. Quote commands and numbers instead of describing them.

Never write family names, phone numbers, addresses, mail, or the content of real consultations. Use "母", "妹", "作者".

Do not invent failures to make the log look busy. One honest entry a day is enough; three good ones go in the README.
