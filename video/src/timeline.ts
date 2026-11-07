// 動画の秒数と、撮影を差し込むファイルの名前は、このファイルだけで決める。
// 順と秒数は docs/design.md の「デモの流れ(3分)」の表に合わせた。
// 撮影の長さが違ったら、ここの from と to を直す。合計は 180 秒以内に収める。

export const FPS = 30;
export const WIDTH = 1920;
export const HEIGHT = 1080;

export type Scene = {
  readonly from: number; // 秒
  readonly to: number; // 秒
};

export const SCENES = {
  // 0〜15秒
  opening: { from: 0, to: 10 },
  motherWords: { from: 10, to: 15 },
  // 15〜60秒
  callConsult: { from: 15, to: 52 },
  familyCard: { from: 52, to: 60 },
  // 60〜85秒
  familyResolve: { from: 60, to: 72 },
  safari: { from: 72, to: 85 },
  // 85〜110秒
  sms: { from: 85, to: 110 },
  // 110〜125秒
  smile: { from: 110, to: 125 },
  // 125〜150秒
  accuracy: { from: 125, to: 140 },
  observation: { from: 140, to: 150 },
  // 150〜180秒(3分ちょうどを避け、2秒の余裕を残す)
  devRecord: { from: 150, to: 166 },
  limits: { from: 166, to: 178 },
} as const satisfies Record<string, Scene>;

export const TOTAL_SECONDS = Math.max(
  ...Object.values(SCENES).map((s) => s.to),
);

export const frames = (sec: number) => Math.round(sec * FPS);
export const startOf = (s: Scene) => frames(s.from);
export const lengthOf = (s: Scene) => frames(s.to - s.from);

// public/footage/ に置く撮影。置けばそのまま入り、無いうちは枠を出す。
// what は枠に出す「何を撮るか」の1行。
export const FOOTAGE = {
  motherWords: {
    file: "footage/01-mother-words.mp4",
    what: "母がスマホや電話で困っていることを、母本人の言葉で話す",
  },
  callConsult: {
    file: "footage/02-call-consult.mp4",
    what: "試験用のニセ警察の電話のあと、声かけに母がそのまま話し、答えと家族の通知が出るまで。母と家族の iPhone を並べて撮る",
  },
  safari: {
    file: "footage/03-safari.mp4",
    what: "母が Safari で試験用の偽の警告ページを開き、赤い「開かないで」が全面に重なるまで",
  },
  sms: {
    file: "footage/04-sms.mp4",
    what: "試験用の詐欺の SMS が母の iPhone に届き、家族の iPhone にカードが出るまで(無ければ体験モードの録画を使う)",
  },
  smile: {
    file: "footage/05-smile.mp4",
    what: "母の笑顔が家族に届き、家族が笑顔を返すところ(無ければ図を出す)",
  },
} as const;

// 体験モードの録画(試験用の文だけが映る)。リポジトリには入れず、npm run assets で写す。
export const TOUR = {
  file: "assets/demo-tour.mp4",
  // 録画の中の秒。相談の答えと家族のカード
  familyCardFrom: 7.6,
  // 未解決のカードから「解決にする」を押して「家族が解決」になるまで
  resolveFrom: 8.5,
  // SMS を送って「迷惑」とカードが出るまで
  smsFrom: 26.5,
} as const;

// 撮影の上に重ねる字幕。秒は場面の始まりからの秒。
export const CALL_CONSULT_CAPTIONS = [
  { from: 0, to: 12, text: "長い電話のあとにアプリから声をかける" },
  { from: 12, to: 24, text: "母はそのまま話すだけでいい" },
  { from: 24, to: 37, text: "AI が筋書きを見抜いて「電話を切って」と返す" },
] as const;

export const SAFARI_CAPTIONS = [
  { from: 0, to: 13, text: "偽のページには赤い「開かないで」を重ねる" },
] as const;

export const MOTHER_WORDS_CAPTIONS = [
  { from: 0, to: 5, text: "(母の言葉を字幕にして入れる)" },
] as const;
