// ナレーションの文。字幕と同じ中身を話し言葉にした。
// scene は timeline.ts の SCENES の名前、at は場面の始まりからの秒。
// 文を変えたら npm run narration で public/narration/<id>.mp3 を作り直す。
// 母の撮影の場面(母の言葉、電話のあとの相談、母の利用)は撮影の音とぶつかるので、
// 頭に短く入れるか、入れない。
// このファイルは scripts/narration.mjs からも読むので、型の注釈のほかの TypeScript の書き方を使わない。

export const VOICE = "Kazuha";
export const RATE = "105%";

export const NARRATION = [
  {
    id: "01-opening",
    scene: "opening",
    at: 0.6,
    ssml: "特殊詐欺の被害額の約7割が、ニセ警察詐欺だ。<break time=\"300ms\"/>離れて住む母の<sub alias=\"アイフォーン\">iPhone</sub>を、家族が代わりに見守る。",
  },
  {
    id: "02-call-consult",
    scene: "callConsult",
    at: 0.3,
    ssml: "長い電話のあとに、アプリから声をかける。",
  },
  {
    id: "03-family-card",
    scene: "familyCard",
    at: 0.4,
    ssml: "家族全員の<sub alias=\"アイフォーン\">iPhone</sub>に、カードが届く。何の相談で、どれだけ危ないかが分かる。",
  },
  {
    id: "04-family-resolve",
    scene: "familyResolve",
    at: 0.5,
    ssml: "母と電話で話した家族が、解決を押す。<break time=\"200ms\"/>ほかの家族にも、それが伝わる。",
  },
  {
    id: "05-safari",
    scene: "safari",
    at: 0.3,
    ssml: "偽のページには、赤い「開かないで」を重ねる。",
  },
  {
    id: "06-sms",
    scene: "sms",
    at: 0.6,
    ssml: "知らない相手からの<sub alias=\"エスエムエス\">SMS</sub>も、母の代わりに見る。<break time=\"300ms\"/>本文に「家族には知らせないで」と書いてあっても、従わない。<break time=\"200ms\"/>むしろ詐欺の印として、危なさを上げる。",
  },
  {
    id: "07-smile",
    scene: "smile",
    at: 0.6,
    ssml: "毎朝、母の笑顔が家族に届く。家族も、笑顔で返す。<break time=\"300ms\"/>何も起きない日にも、開く理由があるようにしたかった。",
  },
  {
    id: "08-accuracy",
    scene: "accuracy",
    at: 0.6,
    ssml: "試験用の例文で測ると、規則だけでは、60件のうち6件を見逃した。<break time=\"300ms\"/><sub alias=\"クロード\">Claude</sub>を組み合わせると、見逃しは1件になった。",
  },
  {
    id: "09-dev-record",
    scene: "devRecord",
    at: 0.6,
    ssml: "開発は、すべて<sub alias=\"クロードコード\">Claude Code</sub>で進めた。<break time=\"300ms\"/><sub alias=\"イシュー\">Issue</sub>ごとに、書く役、確かめる役、レビューする役を、別のエージェントに分けている。",
  },
  {
    id: "10-limits",
    scene: "limits",
    at: 0.6,
    ssml: "ただ、電話と<sub alias=\"ライン\">LINE</sub>の中身は、アプリから見えない。<break time=\"300ms\"/>だから、母が話してくれることが要る。",
  },
] as const;
