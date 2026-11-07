// 画面に出す数字は、ここにまとめる。出典はそれぞれの行のとなりに書いた。

// 警察庁「令和7年における特殊詐欺及びSNS型投資・ロマンス詐欺の認知・検挙状況等について(確定値)」
// 2026年6月5日掲載。2026年11月7日にページを開いて数字を確かめた。
export const NPA = {
  totalOku: "1,423.1",
  fakePoliceOku: "1,005.0",
  share: "70.6", // 1,005.0 / 1,423.1
  published: "2026年6月5日公表",
  url: "https://www.npa.go.jp/bureau/safetylife/sos47/new-topics/260605/01.html",
} as const;

// eval/RESULTS.md の2026年11月7日の最新の rules と rules+claude の行(dev 114件、PR #255 の後の回)。
// 中央値(1503.7ミリ秒)は画面に出していない。
export const DEV_EVAL = {
  date: "2026年11月7日",
  cases: 114,
  rules: { miss: "10.0", missN: "6/60", fp: "0.0", fpN: "0/54" },
  claude: { miss: "1.7", missN: "1/60", fp: "7.4", fpN: "4/54" },
} as const;

// eval/RESULTS.md の holdout の2行(126件、2026年11月7日の夜に作者が1回だけ測った回、8e219db)。
// 中央値(規則と Claude 1697ミリ秒)は画面に出していない。
export const HOLDOUT: null | {
  date: string;
  cases: number;
  rules: { miss: string; missN: string; fp: string; fpN: string };
  claude: { miss: string; missN: string; fp: string; fpN: string };
} = {
  date: "2026年11月7日",
  cases: 126,
  rules: { miss: "25.8", missN: "16/62", fp: "4.7", fpN: "3/64" },
  claude: { miss: "6.5", missN: "4/62", fp: "9.4", fpN: "6/64" },
};

// docs/submission.md の「Claude Code」の節。2026年11月7日に origin/main の a916f02 で数えた値。
// 提出の前に数え直す(数え方は docs/submission.md)。
export const DEV_RECORD = {
  period: "2026年11月3日〜7日",
  reviewer: 170,
  implementer: 76,
  verifier: 61,
  hookStops: 208,
  mergedPrs: 119,
  commits: 922,
} as const;
