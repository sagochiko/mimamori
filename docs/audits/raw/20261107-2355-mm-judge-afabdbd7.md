サブエージェントの報告の原文。親のセッションが確かめる前のもの。ホームの道筋だけを ~ に替えた。

ステータス: 完了

## 点数と重み付きの合計

今の `main`(`cc2e9ee`)を、[`docs/judging.md`](~/develop/mimamori/docs/judging.md) の細目で採点した。主に読んだのは [`README.md`](~/develop/mimamori/README.md)、[`README.ja.md`](~/develop/mimamori/README.ja.md)、[`docs/submission.md`](~/develop/mimamori/docs/submission.md)、[`video/README.ja.md`](~/develop/mimamori/video/README.ja.md)、`video/src/`、[`eval/RESULTS.md`](~/develop/mimamori/eval/RESULTS.md)、[`docs/dev-log.md`](~/develop/mimamori/docs/dev-log.md)、[`docs/mother-feedback.md`](~/develop/mimamori/docs/mother-feedback.md) で、コードと Issue も少し突き合わせた。holdout の例文のフォルダは開いていない。

| 基準 | 重み | 点 | 理由 |
|---|---:|---:|---|
| インパクト | 30% | 7 | 警察庁の確定値(ニセ警察が約70.6%)と実在の母から始まっていて筋は具体的だ。ただ、母が使った記録は1人が1日だけで、主役のニセ警察の場面を母本人ではまだ通していない |
| デモ | 25% | 5 | 審査員が1台で試せる体験モードはコードにあり、作りも丁寧だ。ただ、審査で「唯一」の手段とされる動画が今は下書きで、母の撮影は0本、観察の場面は点線の仮の枠のまま描かれる |
| Claude の活用 | 25% | 8 | Haiku と Sonnet の使い分け、構造化出力とウェブ検索を2回の呼び出しに分けた理由、Managed Agents の文を家族に出さず URL の origin だけを取る作り、フック17本と役6つのハーネスが、どれもコードと記録で裏付けられている |
| 深さと実行力 | 20% | 7 | テストの数、dev と holdout を分けて合わせ込みを自分で認めた精度の記録、105件の開発の記録と、磨いた跡ははっきりある。ただ、母の実機では SMS の判定が家族に届かない作りのままで、そのことが README に書かれていない |

重み付きの合計は 7×0.30 + 5×0.25 + 8×0.25 + 7×0.20 = 2.10 + 1.25 + 2.00 + 1.40 = 6.75 になる。

採点の前に確かめたこと。

- 体験モードが出る条件は `MimamoriSMSFamilyToken` が `demo` のときだけ([`ios/Core/Sources/MimamoriCore/DemoTour.swift`](~/develop/mimamori/ios/Core/Sources/MimamoriCore/DemoTour.swift) の `isOn`)。Release の設定は [`ios/Config/Shared.xcconfig`](~/develop/mimamori/ios/Config/Shared.xcconfig) で、ここが `MIMAMORI_SMS_FAMILY_TOKEN = demo` になっている([`ios/project.yml`](~/develop/mimamori/ios/project.yml) の16〜17行)。なのでコードの上では、TestFlight の版にも「体験」が出る。README と提出の下書きは「TestFlight の版で出るかは #187」とぼかしているが、ここは実機で一度見れば消せる。
- holdout を測ったあと(`8e219db..HEAD`)に、`server/src/rules`、`consult-judge.ts`、`claude.ts` を変えたコミットは無かった。README の107行の「holdout のあとで規則と指示文は直さない」は、今のところ守られている。
- 「安全です」と言わせない決まりは、`server/src/consult-judge.ts` の472行と476行の指示文、それに決まった文への置き換えとして入っている。`/sms/demo` は `server/src/sms.ts` の `DEMO_TOKEN` で分けてあり、家族には届かない。
- `.verify.log` の終わりには、例文の仕組みの試験が19件通ったと出ていた。README のほかのテストの数(サーバー側1,785件、`ios/Core` 333件)は、README に書かれたコマンドでの値で、私は数え直していない。

## 基準ごとの一番弱い証拠

### インパクト

一番弱いのは、ハッカソンのあとも誰がどんな場面で使い続けるかの証拠だ。[`docs/mother-feedback.md`](~/develop/mimamori/docs/mother-feedback.md) の記録は「2026年11月7日 誘導なしの初めての相談」の1件しかない。#251 で直したあと母が困らなくなったかも、母を相手にした試しのニセ警察の電話(#46)も、まだ記録が無い。審査員は README の「What her use changed」とこのファイルを見る。

一番上がる変更は、11月8日の撮影で母と試しのニセ警察の電話を通したら、その結果(何回試して、どこで止まったか)をこのファイルと README の「What her use changed」に日付つきで2〜3文足すこと。

### デモ

一番弱いのは動画そのものだ。`video/public/footage/` は空で、`video/public/footage-sim/` にも `01` と `02` しか無い。[`video/src/scenes/Accuracy.tsx`](~/develop/mimamori/video/src/scenes/Accuracy.tsx) の `Observation` には、今も「ここに母の利用から直した1点を入れる」の点線の枠がある。README の19行は `<!-- Demo video: link goes here. -->` のままだ。

ナレーションと絵が食い違う場所も2つある。

- [`video/src/narration.ts`](~/develop/mimamori/video/src/narration.ts) の `06-sms` は、本文の「家族には知らせないで」に従わないと話す。ところが代わりに流す体験モードの SMS には、その一文が無い。`04-sms.mp4` が撮れなければ、話していることと画面が合わなくなる。
- 同じファイルの `08-accuracy` は、dev の「60件のうち6件を見逃した」「1件になった」だけを話す。dev は README 自身が合わせ込みを認めた組で、holdout では規則だけで62件中16件、Claude を足しても62件中4件を見逃した。画面には holdout も出るが、声で聞こえるのは良いほうの数だけになる。

一番上がる変更は、撮影の素材を差し込んで、仮の枠が1コマも残らない状態で書き出し、README と提出の下書きにリンクを入れること。`Observation` に入れるのは、mother-feedback にある「知らないアプリの相談が家族に回った。そこで写真を求める聞き返しに直した(#251)」の1点で足りる。

### Claude の活用

一番弱いのは、「どの経路でも安全と言わない」の守り方の一部が、今も語の一覧に頼っていることだ。`server/src/consult-judge.ts` の472行は禁止語を並べ、当たった文を決まった文に置き換える作りになっている。提出の下書きの「1つだけ直せるなら」にも、#51、#53、#183 でレビューのたびに抜ける言い換えが見つかったと書いてある。母への1段階と2段階の答えは決まった文にしてあるが(#188)、3段階の答えと会話の答えは網に頼っている。ただ、この弱さは作者が自分で書いていて、隠してはいない。

一番上がる変更は、README の「Claude inside the app」に、自由な文を家族に出さない作りへ切り替えた判断(#183 の4回のレビューで URL の origin だけにした話)を1文で前に出すこと。今は表の下の長い段落に埋もれていて、創造的な使い方として読まれにくい。

### 深さと実行力

一番弱いのは、母の実機の SMS が家族に届かない作りのままなのに、README がそれを書いていないことだ。

- [`ios/App/AppConfig.swift`](~/develop/mimamori/ios/App/AppConfig.swift) のコメントと、開いたままの #133 によれば、母も審査員と同じ `demo` の版を受け取っている。母の SMS の拡張は `/sms/demo` に問い合わせるので、危ない SMS が届いても家族には知らせが行かない。
- README の「What it notices without her doing anything」の SMS の行は「Built (#10). On-device check pending (#139)」としか書かず、「Claude's judgment reaches her and the family」と言い切っている。提出の概要も「知らない相手からの SMS … は、母が何もしなくても見張る」と書く。
- `grep -n "133" README.md README.ja.md docs/submission.md` は何も返さなかった。

README の主張と、母の手元で実際に動く作りが食い違っている。

一番上がる変更は、README の SMS の行と [`docs/submission.md`](~/develop/mimamori/docs/submission.md) に「母の今の版は審査員と同じ `demo` の問い合わせ先で、母の SMS はまだ家族に届かない(#133)」と1文足すこと。母の版を分けて配るのは締切までに間に合わないかもしれないが、書くだけなら数分で済む。

## 上位3つの変更

1. 動画を仮の枠なしで書き出し、リンクを README と提出の下書きに入れる(デモ、25%)。撮影を差し込むのに加えて、[`video/src/scenes/Accuracy.tsx`](~/develop/mimamori/video/src/scenes/Accuracy.tsx) の `Observation` に #251 の1点を書く。`04-sms.mp4` が撮れなければ、[`video/README.ja.md`](~/develop/mimamori/video/README.ja.md) にある手順どおり、`06-sms` のナレーションから「家族には知らせないで」の文を外す。動画が無いままだとデモは5点にとどまる。素材が揃えば7〜8点まで見込める。
2. ナレーションの `08-accuracy` に holdout の数を入れ、古くなった指示を直す(デモと深さ)。今は合わせ込んだ dev の「1件」だけを声で言っている。「最後に1回だけ測った組では、62件のうち4件を見逃した」を足し、`npm run narration -- 08-accuracy` で作り直す。あわせて [`video/README.ja.md`](~/develop/mimamori/video/README.ja.md) の41行の「`HOLDOUT` を `null` から数字に替える」を消す。[`video/src/numbers.ts`](~/develop/mimamori/video/src/numbers.ts) には、もう holdout の数字が入っている。
3. README と提出の下書きの食い違いを2つ直す(深さと、審査員の試しやすさ)。1つ目は、SMS の行に #133 の限界を1文足すこと(上の「深さと実行力」)。2つ目は、作者の iPhone にある TestFlight の版で「体験」が出るかを一度見て、出れば README の141行と提出の下書きの末尾にある「TestFlight の版で出るかは #187」を消すこと。コードの上では Release も `demo` なので、出るはずだ。審査員の手順から「出るか分からない」が消えると、試す人が迷わなくなる。

ついでに数え直すものもある。[`video/src/numbers.ts`](~/develop/mimamori/video/src/numbers.ts) の `DEV_RECORD` と提出の下書きの数は `a916f02` の時点の値だ。今の [`docs/claude-usage.md`](~/develop/mimamori/docs/claude-usage.md) は `06f8418` で数えていて、レビュー役の起動は191回、マージを除くコミットは732になっている。動画、README、提出の下書きの数がばらばらにならないよう、提出の前にまとめて数え直したい。

