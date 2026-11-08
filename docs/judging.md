# 審査基準と、その証拠の置き場所

キックオフ(2026年11月2日)で示された審査基準の細目と、それぞれの証拠がこのリポジトリのどこにあるかを表にした。`mm-judge` はこの表で採点する。マイルストーンを閉じるたびに「証拠」の列を更新する。

| 基準 | 細目 | 証拠 |
|---|---|---|
| インパクト(30%) | 課題が自分の暮らしや日本の具体的な現場から出発しているか | `docs/design.md` の「何を作るか」「この形に決めた理由」 |
| | テーマ2の場合、届いていなかった具体的な人を想定し、その人を阻んでいた壁を取り除いているか | 同上。母という実際の使い手 |
| | 誰が、どんな場面で、どれくらい困っているかが具体的か | 警察庁の確定値([`README.md`](../README.md) の「Why fake-police scams」、[`docs/design.md`](design.md))、母の利用の記録([`docs/mother-feedback.md`](mother-feedback.md) の2026年11月7日の誘導なしの初めての相談、[`README.md`](../README.md) の「What her use changed」) |
| | ハッカソン後も誰がどんな場面で使い続けるかを言えるか | 母の利用の記録は2026年11月7日の1日分([`docs/mother-feedback.md`](mother-feedback.md))で、使い続けたと言えるだけの日数はまだ無い |
| デモ(25%) | 「誰の、どんな課題を、どう解決するか」が冒頭で明確か | [`docs/design.md`](design.md) の「デモの流れ(3分)」、[`README.md`](../README.md) の冒頭と「The main scene」 |
| | 前提知識のない人でも、操作の流れで価値が分かるか | 体験モード。審査員のビルドの最初の画面の「体験」から、通話のあとの声かけ、ニセ警察の相談、家族に届くカード、「解決」と「30分後」、SMS の判定を1台で試せる。手順は [`README.md`](../README.md) の「How judges can try it」(日本語は [`README.ja.md`](../README.ja.md) の「審査員の試し方」)、作りは [`ios/App/Views/DemoView.swift`](../ios/App/Views/DemoView.swift) と [`ios/Core/Sources/MimamoriCore/DemoTour.swift`](../ios/Core/Sources/MimamoriCore/DemoTour.swift)(#100)。TestFlight の版で出るかは #187。本物の流れは、2026年11月7日に作者の iPhone(母の役、ビルド9)と家族の役のシミュレータで、相談、家族への通知とカード、「解決」まで通した(#48 のコメント、[`README.md`](../README.md) の「The main scene」)。2台目の家族の iPhone と「電話する」はまだ |
| | 最後まで見たくなる動画か | 動画(未) |
| Claude の活用(25%) | 基本を超えた創造的な使い方を見せているか | 作品の中の Claude の使い分け([`README.md`](../README.md) の「Claude inside the app」、[`docs/design.md`](design.md))、ハーネス([`docs/harness.md`](harness.md)) |
| | Claude Code を開発の中心に据え、何が可能になったかを示せているか | [`README.md`](../README.md) の「Built during the hackathon」と「How Claude Code built it」の数、[`docs/dev-log.md`](dev-log.md)、[`docs/claude-usage.md`](claude-usage.md)、コミットの Co-Authored-By、PR のレビュー記録と [`docs/audits/raw/`](audits/raw/) |
| | モデルや機能(Skills、サブエージェント、MCP、フック)を目的に応じて使い分けているか | `.claude/`、`CLAUDE.md` のモデルの表、`docs/harness.md` |
| 深さと実行力(20%) | 試行錯誤を重ねて磨き上げた跡が見えるか | [`README.md`](../README.md) の「From the development log」と「Accuracy」、[`docs/dev-log.md`](dev-log.md)、[`eval/RESULTS.md`](../eval/RESULTS.md) の推移、Issues と PR |
| | 設計と実装がしっかりしていて丁寧か | テスト(数は README の「Built during the hackathon」)、[`docs/plan.md`](plan.md) のつなぎ目の約束、README の「Tried on the author's iPhone」「Built, not yet tried on a real iPhone」「Not built yet」で、実機で確かめた範囲と作った範囲を分けて書いたこと |
| | 困っている人が安心してそのまま使える形か | 母が手助けなしで使えたかの記録は、2026年11月7日に誘導なしで相談した日の記録(相談は2回で、1回目は家族に回った。[`docs/mother-feedback.md`](mother-feedback.md))。作者の iPhone を母の役にした2026年11月7日の確かめは、#48(主役の流れ)、#200(空き容量の声かけ)、#187(写真からの共有)のコメントと、[`README.md`](../README.md) の「Tried on the author's iPhone」。データの扱い([`README.md`](../README.md) の「Her data」) |

運営はキックオフで、深さと実行力は「リポジトリの中まで見て判断する」と説明した。デモ動画は作ったものを伝える「唯一と言って過言ではない」手段だとも話していた。
