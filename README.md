# mimamori

mimamori is an iOS app with a Cloudflare Workers backend. It watches an elderly mother's iPhone for scams without her having to notice them. It answers her phone questions in a chat she can talk to, and lets the family trade a smile every morning. When she cannot tell that something is wrong, the family finds out and calls her.

Built during [Built with Claude Japan 2026](https://cerebralvalley.ai/e/built-with-claude-japan2026) (November 2 to 8, 2026) for theme 2, "本来、誰にでも届くべきものを" (what should reach everyone). Today only people with a tech-savvy relative close by get this kind of protection. mimamori is for families who live apart.

[日本語版](README.ja.md)

This README describes what runs on 2026-11-06. Where something is not built yet, it says so.

<!-- Screenshots of the mother's and the family's iPhone go here (taken on the demo build, not on the real family). -->
<!-- Demo video: link goes here. -->

## Why fake-police scams

In 2025, special fraud (特殊詐欺) in Japan took 142.31 billion yen, the highest in the ten years shown in the agency's press release. Fake-police scams (ニセ警察詐欺) took 100.50 billion yen of it, or about 70.6%. The National Police Agency publishes both amounts. The 70.6% is our own division of the two; the agency itself gives the scam's share of reported cases, 39.6%. Sources: the agency's [final figures for 2025](https://www.npa.go.jp/bureau/safetylife/sos47/new-topics/260605/01.html) and the agency's press release of 2026-05-22 ([PDF](https://www.npa.go.jp/bureau/criminal/souni/tokusyusagi/hurikomesagi_toukei2025.pdf)). A [correction (PDF)](https://www.npa.go.jp/bureau/criminal/souni/tokusyusagi/teisei_sagi2025.pdf) fixes one graph on page 14 of the awareness material (「バナー等広告の主な当初接触ツールの推移」, how banner ads first reached victims). It does not change these figures.

The scammer calls and says her bank account was used in a crime. Then they tell her to keep it secret and to move her money to prove she is innocent. An iPhone app cannot listen to calls or read LINE, and the caller has told her to tell no one. So the app comes to her after the call and asks.

## The main scene

1. A call of three minutes or more ends while the app is open. The app asks her: "さっきの電話、大丈夫だった？" (Was that call just now all right?).
2. She says, in her own words, that the police called about her account.
3. Rules on the server recognize the fake-police script (police, account used in a crime, keep it secret, a video call, moving money). They answer at once with level 1: hang up and check with the family before sending any money.
4. Every family member's iPhone gets a card with the level, a one-line topic ("警察を名乗る電話の相談", a consultation about a call from someone claiming to be the police), and what the AI told her. The card has two buttons, Call and Resolve.
5. Whoever talks to her presses Resolve, and the others see who resolved it. If nobody does within 30 minutes, the family is reminded and her screen says the family has not answered yet, call them if it is urgent.

On 2026-11-04 the author ran this on his own iPhone, playing the mother, with a simulator as the family. The notice reached the family about one second after the consultation was sent (#57). That first try came out at level 2. After the fix in #72, the author confirmed level 1 and the fixed answer on his iPhone (#77). The check with two real iPhones is still waiting for the author (#48, #31).

## What it notices without her doing anything

| Channel | How | State on 2026-11-06 |
|---|---|---|
| SMS from unknown senders | iOS Message Filter extension. Apple sends the message to our server, and rules answer at once. Only clear scams go to the junk folder; everything else is delivered, and Claude's judgment reaches her and the family | Built (#10). On-device check pending (#139) |
| Gmail | The server reads new mail in her inbox every 5 minutes (read-only scope) | Built (#15). Waiting for the Google Cloud setup and her consent (#144) |
| Web pages in Safari | A Safari extension sends the page to the server and lays a warning over dangerous pages | Built (#16). Checked on the author's iPhone (#145) |
| Phone calls | The app sees that a call ended only while it is in the foreground. It also asks once a day at a time she can change in Settings | Built (#99). The call itself is never visible |
| DNS (bank sites after a warning, remote-control apps) | Planned as a DoH resolver | Not built (#11) |
| LINE, iMessage, call audio | Not visible to any app | Cannot be done |

What it cannot protect is part of the design. The app never hears the call. In the main scene she still has to answer the question after the call, or start the chat herself. When the app is suspended, it cannot know a call ended (Apple DTS confirms this; see [`docs/design.md`](docs/design.md)), which is why the daily question exists. Other browsers and in-app browsers do not run the Safari extension.

## How a notice travels

- Her side. Local notifications ask about the call and the day. Her chat goes to `POST /consult`.
- The server. Rules decide in milliseconds. Claude adds a judgment and a reason (SMS, mail, and pages go through Cloudflare Queues). The case is stored in D1, and the server sends APNs pushes to every family device.
- The family side. One card per case, the same for everyone, with no owner or assignee. Level 3 sends no push. The same sender or domain is grouped to one notice an hour.

There are three levels: 1 "don't open it", 2 "wait until you check with the family", and 3 "probably fine, but stop if asked for money or a PIN". The app never says "safe" on any path. If no family device got the notice, her answer says "家族に届いていません。急ぐなら電話して" (the family did not get this; call them if it is urgent) instead of "I told your family", and the server retries every 5 minutes.

Text inside SMS, mail, pages, and her messages is treated as data. A message that says "don't tell the family" or "stop this warning" cannot change who is told. The rules count such a sentence as a scam sign and raise the message to level 1.

## Claude inside the app

| Step | Model | Why |
|---|---|---|
| Instant answer | Rules, no model | Answers in under a millisecond on the dev set, and still works when Claude is down |
| Judging SMS, mail, pages | Claude Haiku 5.5 (`claude-haiku-5-5`), Structured Outputs | Fast and cheap for every message. The reply is a fixed shape (level, reason, one line for her), so nothing in it can change who is told |
| Her chat | Claude Sonnet 5.5 (`claude-sonnet-5-5`) | She waits on screen, so the server waits up to 15 seconds and then answers by rules alone. It remembers the last few turns, so "それってどういうこと？" (what does that mean?) works |
| Research and a summary for the family | Claude Managed Agents | Being built (#12) |

Family cards never quote her words or the message she received. The topic is a fixed line or a line of 20 characters or fewer that Claude writes itself. If that line copies 8 or more characters from the source, it is replaced. The reasons were legal and practical; see the dev log entry below.

## Accuracy

Measured on the dev set, 114 examples across SMS, mail, pages, and spoken consultations, with scam and genuine messages plus injection examples. How it is measured, and the counts fixed before measuring, are in [`eval/README.md`](eval/README.md). Every run is a line in [`eval/RESULTS.md`](eval/RESULTS.md).

| Method | Missed scams | Genuine messages flagged | Unneeded family notices | Median time | Measured |
|---|---:|---:|---:|---:|---|
| Rules only | 28.3% (17/60) | 0.0% (0/54) | 0 | 0.04 ms | 2026-11-06 |
| Rules + Claude | 0.0% (0/60) | 7.4% (4/54) | 4 | 1845 ms | 2026-11-05 |

The rules + Claude line was measured before #137 changed which SMS, mail, and pages reach Claude. That run sent more unflagged examples to Claude than production does now, so its miss rate is lower than production would be. A new run is waiting on the author (#181). The first rules + Claude run flagged 36 of 54 genuine messages. The prompt itself defined level 2 as "suspicious or undecided", and Claude followed it. After the fix, 4 of 54 were flagged (#109).

<!-- Holdout result (measured once before submission) goes here, rules only vs rules + Claude. -->

## Her data

- Her chat stays on her iPhone, up to 50 messages and at most 30 days. The file is unreadable while the phone is locked and is left out of iCloud and Mac backups. The server keeps no chat log.
- Cases, notices, and smile photos are deleted automatically after 30 days, every day at a fixed time.
- Smile photos are shared only inside the family and never sent to Claude.
- SMS, mail, and pages judged level 3 leave no record, so the server does not become a copy of her inbox.
- "Delete everything" exists on the server (`DELETE /families/me`). It removes the family's data, revokes Gmail access, and deletes Managed Agents sessions. The button in the app is not built yet.
- Secrets live in Workers secrets. This repository holds only test examples, with no real messages or family details.

## Not built yet

DNS (#11), the weekly review (#18), the morning alarm that stops when she smiles (#17), reading screenshots and fake documents (#13; the Share extension that would receive them is an empty stub), the list of scam phone numbers (the Call Directory extension is also an empty stub), the app's own checkups such as low storage (#19, #20), and the demo mode for judges (#100). Managed Agents is being built (#12).

<!-- How judges can try it: TestFlight link and demo mode steps go here. -->

## What her use changed

<!-- From docs/mother-feedback.md, once she has used it. -->
<!-- What the mother, the sister, and the author saw when trying the same consultation goes here. These observations come from one family, and the app makes no claim about older people in general. -->

## Built during the hackathon

Every line of code here was written in this repository after the kickoff on 2026-11-02. The first commit is dated 2026-11-03. On 2026-11-06, `origin/main` had 688 commits (533 without merges, 496 of them co-authored by Claude). There were 84 merged pull requests and 94 issues (61 closed). The tests were 1,505 server tests (Vitest) and 256 `ios/Core` tests (`swift test`). The pre-hackathon design was copied in on 2026-11-03; [`docs/design.md`](docs/design.md) says what changed and why.

## From the development log

[`docs/dev-log.md`](docs/dev-log.md) has 74 dated entries. Three of them shaped the product:

- 2026-11-04. We dropped "take ownership" and "reply to her" from the family screen. While someone owned a case, the AI only told her that person was looking, and her spoken replies reached no one. Relaying messages between users and forwarding her first 30 characters were also close to examples in the Ministry of Internal Affairs and Communications' telecom business manual. Now everyone sees the same card and calls her.
- 2026-11-04. The first on-device test crashed when she pressed the microphone (a Swift 6 isolation check in the speech permission callback). The main line came out at level 2, not 1, because "警察から電話" (a call from the police) was not part of the script rules. The eval had not caught it because it ran consultations through the SMS rules. Both were fixed, and the eval now measures consultations on the real path (#57, #72, #74).
- 2026-11-05. The 36 false alarms came from our prompt, not from Claude being cautious. Level 2 now requires a concrete sign of a scam (#109).

## How Claude Code built it

The harness is the setup that lets Claude Code build this under hackathon rules. It is described in [`docs/harness.md`](docs/harness.md), with the project rules in [`CLAUDE.md`](CLAUDE.md) and everything else in [`.claude/`](.claude/). Hooks block rule-breaking actions, such as opening the author's earlier projects, reading the holdout set, reading secrets, or merging an unreviewed PR. Each issue goes through separate implementer, verifier, and reviewer subagents, and the reviewer's report is kept on the PR. Counts from the hook log, 2026-11-03 to 2026-11-06, are in [`docs/claude-usage.md`](docs/claude-usage.md): 132 reviewer launches and 21 resumes, 64 implementer launches, 50 verifier launches, and 195 actions that hooks blocked or sent to the author. The 150 review reports are kept unedited in [`docs/audits/raw/`](docs/audits/raw/).

## Repository

```text
ios/      iOS app, extensions (Message Filter, Safari, Share, Call Directory), and the Core Swift package
server/   Cloudflare Workers (TypeScript, D1, R2, Queues, Cron)
eval/     test examples and the accuracy runs
docs/     design, plan, development log, harness
.claude/  the Claude Code harness
```

The design ([`docs/design.md`](docs/design.md)) and the plan ([`docs/plan.md`](docs/plan.md)) are in Japanese.
