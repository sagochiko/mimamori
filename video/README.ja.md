# デモ動画

Built with Claude Japan 2026 に出すデモ動画(3分以内)を [Remotion](https://www.remotion.dev/) で作る。2026年11月7日に下書きを作り、母の場面は2026年11月8日に撮って差し込む。場面の順と秒数は [`docs/design.md`](../docs/design.md) の「デモの流れ(3分)」の表に合わせた。ナレーションと BGM は入れず、画面の文字で伝える。

## 秒数と撮影のファイル

秒数、撮影のファイル名、撮影の上に重ねる字幕は [`src/timeline.ts`](src/timeline.ts) だけで決める。画面に出す数字は [`src/numbers.ts`](src/numbers.ts) にまとめた。撮影の長さが枠と違ったら、`SCENES` の `from` と `to` を直す。合計は今178秒で、180秒を超えないようにする。

## 明日撮って置くファイル

`video/public/footage/` に次の名前で置くと、そのまま動画に入る。無いうちは「ここに母の iPhone の撮影」の枠が出る。縦の録画はそのまま真ん中に収まる(`objectFit: contain`)。音は撮影の音をそのまま使う。

| ファイル | 場面 | 枠の長さ | 撮るもの |
|---|---|---:|---|
| `01-mother-words.mp4` | 10〜15秒 | 5秒 | 母がスマホや電話で困っていることを、母本人の言葉で話すところ |
| `02-call-consult.mp4` | 15〜52秒 | 37秒 | 試験用のニセ警察の電話のあと、声かけに母がそのまま話し、答えと家族の通知が出るまで。母と家族の iPhone を並べて撮る |
| `03-safari.mp4` | 72〜85秒 | 13秒 | 母が Safari で試験用の偽の警告ページを開き、赤い「開かないで」が全面に重なるまで |
| `04-sms.mp4` | 85〜110秒 | 25秒 | 試験用の詐欺の SMS が母の iPhone に届き、家族の iPhone にカードが出るまで。無ければ体験モードの録画が入る |
| `05-smile.mp4` | 110〜125秒 | 15秒 | 母の笑顔が家族に届き、家族が笑顔を返すところ。無ければ図が入る |

15〜60秒の場面は、[`docs/design.md`](../docs/design.md) の「デモの流れ(3分)」のとおり、Debug のビルドを起動の引数 `-mimamori-followup-min-seconds 10` で起動すると短い電話で撮れる。同じ日に撮り直すときは `-mimamori-followup-reset` も足す。

撮影には母の顔と声が映るので、`public/footage/` と `public/assets/` の中身は `.gitignore` でリポジトリに入れない。元の撮影は `~/mimamori-video/` に置く。

撮影と別に、次の枠も明日埋める。

- 最後に測る組(holdout)の数字。測ったら [`src/numbers.ts`](src/numbers.ts) の `HOLDOUT` を `null` から数字に替える
- 母の利用から直した1点と、母、妹、作者で試した観察。[`src/scenes/Accuracy.tsx`](src/scenes/Accuracy.tsx) の `Observation` の枠に [`docs/mother-feedback.md`](../docs/mother-feedback.md) から選んで書く
- 母の言葉の字幕。[`src/timeline.ts`](src/timeline.ts) の `MOTHER_WORDS_CAPTIONS`
- 開発の記録の数(`DEV_RECORD`)は2026年11月7日に `a916f02` で数えた値なので、提出の前に [`docs/submission.md`](../docs/submission.md) の数え方で数え直す

## 書き出し

```sh
cd video
npm ci
npm run assets
npx remotion render Demo ~/mimamori-video/demo-20261108.mp4
```

`npm run assets` は体験モードの録画(`~/mimamori-video/demo-tour-20261107-cut.mp4`)を `public/assets/demo-tour.mp4` に写す。家族のカード、解決、SMS の場面はこの録画から切り出している。映るのは体験モードの試験用の文だけで、本番の家族の画面は使っていない。

場面ごとのコマを確かめるときは、次のように書き出す。

```sh
npx remotion render Demo out/frames --frames=240,1005,1680,1980,2355,2925,3525,3975,4350,4920,5310 --image-format=png
```

画面で見ながら直すときは `npm run dev` で Remotion Studio を開く。書き出しが終わったら `rm -rf node_modules out` で消す(`npm ci` でまた入る)。

## ライセンス

Remotion は [Remotion License](https://github.com/remotion-dev/remotion/blob/main/LICENSE.md) で、個人(an individual)は Free License で無料で使える。2026年11月7日に LICENSE.md を読んで確かめた。

文字は Google Fonts の [Noto Sans JP](https://fonts.google.com/noto/specimen/Noto+Sans+JP) を `@remotion/google-fonts` で読み込む。ライセンスは [SIL Open Font License 1.1](https://github.com/google/fonts/blob/main/ofl/notosansjp/OFL.txt)。

音楽と効果音は使っていない。
