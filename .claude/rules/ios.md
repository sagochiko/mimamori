---
paths:
  - "ios/**"
---

# iOS の決まり

- テストできる中身は `ios/Core`(Swift Package)に置き、Swift Testing で書く。`ios/Core` は Foundation だけを使い、IdentityLookup、NetworkExtension、CallKit、ARKit などの iOS 専用フレームワークは import しない。`swift test` が macOS で走らなくなるため。フレームワークを呼ぶ部分は、App や各拡張の薄いアダプタに置く
- `.pbxproj` を手で書き換えない。ターゲットやファイルの追加は、プロジェクトの生成元(XcodeGen などを入れた場合はその設定ファイル)か Xcode で行う
- 画面の文言は最小限にする。残すのは固有名詞、数値、1語の動詞のボタン、数値や切り替えの意味を伝える名札。説明文、補足、選択肢の上の見出し、空の状態の2行目は置かない。消した説明は `accessibilityLabel` と `accessibilityHint` に残す
- 母の画面は大きなマイクのボタン1つと、家族からの笑顔と知らせだけにする。母に操作を覚えさせる画面を足さない
- コードはすべて期間中に一から書く。作者が以前に作ったコードは開かない
- シミュレータで確かめられない拡張機能(Message Filter、DNS の設定、Safari の拡張、Call Directory)は、実機の確認を「作者: 」の Issue にする(`/mm-human-queue`)
- 鍵(`deviceKey`)はキーチェーン、拡張と共有するものは App Group に置く。家族の印(`familyToken`)はログに出さない
