# Demo video

The demo video (under 3 minutes) for Built with Claude Japan 2026, made with [Remotion](https://www.remotion.dev/). The draft was made on 2026-11-07; the scenes with the mother are filmed on 2026-11-08 and dropped in. The full guide in Japanese is [`README.ja.md`](README.ja.md).

- Timing, footage file names, and captions live in [`src/timeline.ts`](src/timeline.ts); on-screen numbers live in [`src/numbers.ts`](src/numbers.ts).
- Put footage in `public/footage/` (`01-mother-words.mp4`, `02-call-consult.mp4`, `03-safari.mp4`, `04-sms.mp4`, `05-smile.mp4`). Until a file exists, 01 and 02 play a simulator recording from `public/footage-sim/`, 04 plays the demo-tour recording, 05 shows a diagram, and 03 shows a label. Footage stays out of git.
- Narration is Amazon Polly (Japanese neural voice Kazuha). The lines live in [`src/narration.ts`](src/narration.ts); the generated mp3 files are committed in `public/narration/`. Regenerate with `AWS_PROFILE=<profile> npm run narration`. Polly output is "Your Content" under section 50.2 of the AWS Service Terms. No music.

```sh
cd video
npm ci
npm run assets
npx remotion render Demo ~/mimamori-video/demo-20261108.mp4
```

Remotion is used under the [Remotion License](https://github.com/remotion-dev/remotion/blob/main/LICENSE.md) (free for individuals). The font is [Noto Sans JP](https://fonts.google.com/noto/specimen/Noto+Sans+JP), licensed under the [SIL Open Font License 1.1](https://github.com/google/fonts/blob/main/ofl/notosansjp/OFL.txt).
