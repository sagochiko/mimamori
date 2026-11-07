# デモ動画

Built with Claude Japan 2026 に出すデモ動画(3分以内)を [Remotion](https://www.remotion.dev/) で作る。2026年11月7日に下書きを作り、母の場面は2026年11月8日に撮って差し込む。場面の順と秒数は [`docs/design.md`](../docs/design.md) の「デモの流れ(3分)」の表に合わせた。画面の文字に、Amazon Polly で作ったナレーションを重ねる。BGM は入れない。

## ナレーション

文は [`src/narration.ts`](src/narration.ts) にまとめた。字幕と同じ中身を話し言葉にしてある。母の撮影の場面は撮影の音とぶつからないよう、頭に短く入れるか入れない。母の言葉と母の利用の場面には入れていない。声は Polly の日本語の neural の声 Kazuha で、SSML の prosody で速さを105%にした。生成した mp3 は `public/narration/` に置き、リポジトリに入れる。

文を変えたら、次で作り直す。作り直すと、各 mp3 が場面の枠に収まるかの表が出て、はみ出すと止まる。

```sh
AWS_PROFILE=<プロファイル> npm run narration
```

Polly で作った音声は、AWS Service Terms の50.2(AI Services)に「The output that you generate using AI Services is Your Content」とあり、使う側のコンテンツになる(2026年11月7日に確かめた)。

## 秒数と撮影のファイル

秒数、撮影のファイル名、撮影の上に重ねる字幕は [`src/timeline.ts`](src/timeline.ts) だけで決める。画面に出す数字は [`src/numbers.ts`](src/numbers.ts) にまとめた。撮影の長さが枠と違ったら、`SCENES` の `from` と `to` を直す。合計は今178秒で、180秒を超えないようにする。

## 明日撮って置くファイル

`video/public/footage/` に次の名前で置くと、そのまま動画に入る。無いうちは「ここに母の iPhone の撮影」の枠が出る。縦の録画はそのまま真ん中に収まる(`objectFit: contain`)。音は撮影の音をそのまま使う。

| ファイル | 場面 | 枠の長さ | 撮るもの |
|---|---|---:|---|
| `01-mother-words.mp4` | 10〜15秒 | 5秒 | 母がスマホや電話で困っていることを、母本人の言葉で話すところ |
| `02-call-consult.mp4` | 15〜52秒 | 37秒 | 試験用のニセ警察の電話のあと、声かけに母がそのまま話し、答えと家族の通知が出るまで。母と家族の iPhone を並べて撮る |
| `03-safari.mp4` | 72〜85秒 | 13秒 | 母が Safari で試験用の偽の警告ページを開き、赤い「開かないで」が全面に重なるまで |
| `04-sms.mp4` | 85〜110秒 | 25秒 | 試験用の詐欺の SMS が母の iPhone に届き、家族の iPhone にカードが出るまで。字幕に合わせ、SMS の本文に「家族には知らせないで」を入れる。無ければ体験モードの録画が入る(こちらの SMS にはその一文が無い) |
| `05-smile.mp4` | 110〜125秒 | 15秒 | 母の笑顔が家族に届き、家族が笑顔を返すところ。無ければ図が入る |

15〜60秒の場面は、[`docs/design.md`](../docs/design.md) の「デモの流れ(3分)」のとおり、Debug のビルドを起動の引数 `-mimamori-followup-min-seconds 10` で起動すると短い電話で撮れる。同じ日に撮り直すときは `-mimamori-followup-reset` も足す。

`footage/` に本物が無いあいだは、`public/footage-sim/` の同じ名前の仮の動画が流れ、右上に「シミュレータの画面(撮影で差し替え)」と出る。仮の動画は2026年11月7日に、母役のシミュレータ「mimamori mother」で Debug のビルドを起動の引数 `-mimamori-stub -mimamori-stub-joined protected -mimamori-stub-cases none` で起動して撮った。裏側に繋がない偽の通信(`ScreenshotStubTransport`)なので、本番の家族には何も届かない。01 は母の画面、02 は警察を名乗る電話の相談(`-mimamori-stub-draft` で入れた文を送り、決まった1段階の答えが出るまで)。シミュレータは通話も SMS も受けられず、Safari の拡張も動かないので、02 は電話のあとの声かけを映さず相談の画面から始まる。04 は体験モードの録画、03 は「Safari の画面(撮影で差し替え)」の札だけにした。05 は図にした。シミュレータの1台では、家族の側に届くところも返す笑顔も映らないため。作り物の警告の画面は置いていない。仮の動画はリポジトリに入れる。

撮影には母の顔と声が映るので、`public/footage/` と `public/assets/` の中身は `.gitignore` でリポジトリに入れない。元の撮影は `~/mimamori-video/` に置く。

撮影と別に、次の枠も明日埋める。

- 母、妹、作者で試した観察。[`src/scenes/Accuracy.tsx`](src/scenes/Accuracy.tsx) の `Observation` には、2026年11月7日の [`docs/mother-feedback.md`](../docs/mother-feedback.md) の記録(#251 の直しと、母1人が2回相談したこと)を入れてある。撮影の日に試した人と回数が増えたら、2つ目の枠を書き換える
- 母の言葉の字幕。[`src/timeline.ts`](src/timeline.ts) の `MOTHER_WORDS_CAPTIONS`
- `04-sms.mp4` を撮れなかったときは、体験モードの録画の SMS に「家族には知らせないで」が無いので、その文に従わないと言う文を外す。ナレーション [`src/narration.ts`](src/narration.ts) の `06-sms` と、[`src/scenes/FamilyScenes.tsx`](src/scenes/FamilyScenes.tsx) の `SmsFallback` の字幕から消し、`npm run narration -- 06-sms` で作り直す
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

ナレーションは Amazon Polly で作った(上の「ナレーション」の節)。音楽と効果音は使っていない。
