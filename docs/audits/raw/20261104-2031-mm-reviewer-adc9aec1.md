サブエージェントの報告の原文。親のセッションが確かめる前のもの。ホームの道筋だけを ~ に替えた。

## ステータス
approve。止めるほどの欠陥は見つからなかった。指摘1は不具合ではなく、#34 で決めたことに付いてくる副作用で、作者に伝えるために挙げる。

## 指摘(重い順)

1. 英語の端末では、OS が出す文字がアプリの中で英語になる。重さは低から中、確かさは高い。
   場所は `ios/App/Info.plist` の15〜19行(`CFBundleLocalizations` に en を足したところ)、`ios/project.yml` 59行、5つのターゲットの `en.lproj/`。
   アプリが自分で書いた文字(`Text("家族")` など)は日本語のまま変わらない。Localizable の表がどこにも無いので、キーそのものが表示されるためだ。変わるのは OS が出す文字のほう。`en.lproj` を置くとアプリが en で動くようになり、システムの文字が英語に切り替わる。
   シミュレータで確かめた。端末の言語は ja-JP で、起動の引数 `-AppleLanguages (en)` で英語の端末に見立てた。家族の画面の戻るボタンの名前を UI の木から読んだ。
   - このブランチを en で起動すると `Back`
   - このブランチを ja で起動すると `戻る`
   - origin/main をビルドして en で起動すると `戻る`(今は ja しか無いので、英語の端末でもアプリは日本語で動く)

   同じ理由で、次のものも英語の形になるはずだ。ただしこれは推測で、画面では見ていない。
   - 招待の期限(`FamilyHomeView.swift` 63行)と知らせの時刻(`CaseCardView.swift` 94行)は `Date.FormatStyle` が `Locale.current` を使うので、「11月5日 15:00」が「Nov 5, 3:00 PM」のような形になる
   - `ShareLink` のシート、権限のダイアログのボタン、VoiceOver が読むシステムの部品

   名前入力の画面より先へ進めなかったので、日付の表示は確かめていない。type_text で文字が入らなかった。
   en の地域を残すかぎり、この副作用は避けられないと考えている。`CFBundleLocalizations` から en を外しても、`en.lproj` があるだけでバンドルの言語に en が入る。この点は Apple の文書では確かめておらず、推測だ。
   母の iPhone は日本語なので影響は無い。英語の端末で見る人(審査員など)には、日本語の画面に英語の戻るボタンや日付が混ざる。取れる道は2つある。
   - (Recommended) このままにする。#34 に「英語の端末は mimamori」と決めてある
   - en をやめる。英語の端末でも名前は「みまもり」になる

   どちらにするかは作者が決めることだ。

その他に直すべき指摘は無い。

## 確かめて問題なかったこと

- 宛先の1行で、API の宛先と2つの `messagefilter:` の両方が変わる。ブランチをビルドした成果物で見た。
  - `MimamoriAPIBaseURL => https://mimamori.sago3.workers.dev`
  - `Mimamori.app-Simulated.xcent` と `MessageFilter.appex-Simulated.xcent` がどちらも `messagefilter:mimamori.sago3.workers.dev`
- 古いホストやプレースホルダーは残っていない。リポジトリ全体を `placeholder.invalid|MIMAMORI_API_HOST|workers.dev|messagefilter` で grep した。`ios/` に残りは無い。`.claude/skills/mm-device/SKILL.md` 35行と `mm-release/SKILL.md` 14行は「まだプレースホルダーなら」という条件の文なので、直さなくてよい
- 本番の宛先は Worker が答えている。`GET /cases` は 401 と `{"error":"device_key_required"}`、`/` は JSON の 404 だった。`/.well-known/apple-app-site-association` は 404 で、これは mm-deploy に書いてあるとおりタスク5で作る
- `.pbxproj` は `project.yml` から生成したものと同じ。HEAD の `ios` を scratchpad に展開し、XcodeGen 2.45.4 で `xcodegen generate` を流した。リポジトリの `.pbxproj` と `diff -q` で比べて一致した
- `InfoPlist.strings` は Apple のやり方どおりに置かれている。各ターゲットの `ja.lproj` / `en.lproj` にあり、XcodeGen が PBXVariantGroup にまとめ、Resources の段に入れている。ビルドしたアプリと3つの拡張(CallDirectory、MessageFilter、SafariExtension)には、`ja.lproj` の `みまもり` と `en.lproj` の `mimamori` がどちらも入っていた
- ShareExtension はもともとアプリに入れていない。`project.yml` 45行の決まりどおりで、この PR の前から同じだ
- 開発の言語は ja のまま変わっていない。`developmentRegion` と `DEVELOPMENT_LANGUAGE` は ja、`CFBundleDevelopmentRegion` も ja、knownRegions は en が増えただけだ
- 音声の部分は端末の言語に引きずられない。`SFSpeechRecognizer(locale: ja-JP)` と `AVSpeechSynthesisVoice(language: "ja-JP")` で日本語に決め打ちしてある
- マイクと音声認識の説明文は `en.lproj` に無いので、Info.plist の日本語に戻る
- 公開してはいけない情報は入っていない。差分には人の名前、メール、電話番号が無い。`sago3` は workers.dev のサブドメインだけだ
- この PR が触っていない約束は崩れていない。危なさの段階、通知する相手、注入された文、家族のカードの中身、`ios/Core` が import するもの、はどれも変わっていない

## 検証

- `make verify`: ios/Core swift test、server typecheck、server vitest、eval typecheck、eval node test、hooks self-test がすべて ok
- `xcodebuild` でシミュレータ向けにビルドした。ブランチも origin/main も exit 0。DerivedData は指定された scratchpad の下に置いた
- シミュレータ「mimamori iPhone」で、ブランチを ja と en、main を en で起動し、上の戻るボタンを比べた

## 懸念と未完了

- 英語の端末での日付の形と ShareLink のシートは、画面で見ていない(指摘1)
- 実機のホーム画面と設定アプリに出る名前は見ていない。PR に書いてあるとおり、`/mm-device` のときに見る
- 範囲の外だが、Safari 拡張の `manifest.json` の `"name": "mimamori"` は変わっていない。Safari の中の拡張のメニューにどちらの名前が出るかは確かめていない

## 引き継ぎ

- 指摘1は、そのままにするか en をやめるかを作者に聞く。PR のレビューの節に書くときは「再現した(戻るボタンの名前)」と「推測(日付)」を分けて書く
- シミュレータにはこのブランチのビルドを入れ直してある。DerivedData-review68、比べるための main のビルド、展開した作業用のフォルダ、スクリーンショットは消した。木には何も変更していない

## 詳細レポートのパス
なし
