// Phrases that scams use, written from the public warnings of the National Police Agency, the
// Council of Anti-Phishing Japan, IPA, and the National Consumer Affairs Center. Text is matched
// after NFKC normalization and lowercasing, so full-width letters and digits match too.
// Matching a phrase only adds a reason; the text itself never changes what the rules do otherwise.

export type Strength = "strong" | "medium" | "weak";

export interface PhraseRule {
  kind: string;
  strength: Strength;
  reason: string;
  patterns: readonly RegExp[];
}

// Text that tries to switch the warning off or keep the family out. It raises the level, never lowers it.
export const INJECTION: PhraseRule = {
  kind: "injection",
  strength: "strong",
  reason: "警告を止めさせようとする文がある",
  patterns: [
    /(警告|判定|アラート|この通知).{0,6}(は誤り|は間違い|は誤検知|を無視|は無視|を止め|を消し|をオフに|は気にしな)/,
    // "Don't tell your family" in particular: the family is who this app tells. "誰にも言わないで"
    // is the scam's general secrecy and lives in POLICE_SCRIPT.
    /(家族|息子|娘|子ども|子供).{0,4}(に|には|にも)?.{0,3}(知らせないで|言わないで|話さないで|伝えないで|相談しないで|内緒|秘密)/,
    /ignore (all |any )?(the )?(previous|prior|above) instructions/,
    /system prompt|システムプロンプト/,
  ],
};

// Parts of the fake-police script (警察庁「ニセ警察詐欺」の注意喚起). Two or more parts are level 1.
export const POLICE_SCRIPT: readonly PhraseRule[] = [
  {
    kind: "police_account_crime",
    strength: "medium",
    reason: "口座が犯罪に使われたという話がある",
    patterns: [
      /口座.{0,12}(犯罪|悪用|不正に使|詐欺に使|事件に使)/,
      /(犯罪|事件|詐欺).{0,10}(口座|名義).{0,8}(使|関与|悪用)/,
      /マネーロンダリング|マネロン|資金洗浄/,
    ],
  },
  {
    kind: "police_arrest",
    strength: "medium",
    reason: "逮捕や捜査をほのめかす話がある",
    patterns: [/逮捕状|あなた.{0,6}逮捕|逮捕され(る|ます)|捜査の対象|容疑がかか|容疑者になっ|被疑者になっ/],
  },
  {
    kind: "police_innocence",
    strength: "medium",
    reason: "潔白を証明させる話がある",
    patterns: [/潔白|無実を証明|関与していないことを証明/],
  },
  {
    kind: "police_secrecy",
    strength: "medium",
    reason: "ほかの人に話さないよう言われている",
    patterns: [
      /(誰|だれ|家族|ほかの人|他の人|他人|銀行|周り).{0,8}(言わない|話さない|話しては|言っては|口外|相談しない|相談しては|内緒|秘密)/,
      /口外(しない|禁止)|守秘義務/,
    ],
  },
  {
    kind: "police_video",
    strength: "medium",
    reason: "ビデオ通話や LINE に誘われている",
    patterns: [/ビデオ通話|テレビ電話|(line|ライン).{0,4}(で|に|の).{0,8}(追加|話|連絡|移|友だち|事情聴取|取り調べ)|事情聴取.{0,10}(line|ライン|ビデオ)/],
  },
];

// Moving money is part of the script, but banks talk about transfers too, so it never counts alone.
export const MONEY_MOVE: PhraseRule = {
  kind: "money_move",
  strength: "weak",
  reason: "お金を動かす話がある",
  patterns: [/送金|振り込|振込|口座を移|移し替え|別の口座|安全な口座|指定の口座|資産.{0,4}(調査|確認|保全)|現金.{0,6}(用意|渡|預|送)/],
};

export const CONTENT_RULES: readonly PhraseRule[] = [
  {
    kind: "support_scam",
    strength: "strong",
    reason: "ウイルスの偽の警告から電話をかけさせる",
    patterns: [
      /(ウイルス|ウィルス|トロイ|マルウェア|ハッキング|ハッカー|感染|システムが破損|損傷).{0,60}(電話|サポートセンター|お問い合わせ|連絡).{0,30}0\d{1,4}-?\d{1,4}-?\d{3,4}/,
      /0\d{1,4}-?\d{1,4}-?\d{3,4}.{0,30}(ウイルス|ウィルス|感染|ハッキング)/,
    ],
  },
  {
    kind: "remote_app",
    strength: "strong",
    reason: "遠隔操作のアプリを入れさせようとしている",
    patterns: [
      /(anydesk|teamviewer|quicksupport|クイックサポート|リモートサポート|遠隔操作|遠隔サポート|画面共有).{0,20}(インストール|入れて|入れる|ダウンロード|アプリ)/,
    ],
  },
  {
    kind: "profile_install",
    strength: "strong",
    reason: "構成プロファイルを入れさせようとしている",
    patterns: [/(構成)?プロファイル.{0,15}(インストール|ダウンロード|許可して)/],
  },
  {
    kind: "gift_card",
    strength: "strong",
    reason: "電子マネーやギフトカードで払わせようとしている",
    patterns: [/(電子マネー|ギフトカード|プリペイドカード|apple ?gift ?card|google ?play ?(ギフト)?カード|itunes ?カード).{0,15}(買|購入|番号|コード)/],
  },
  {
    kind: "credential",
    strength: "medium",
    reason: "暗証番号やパスワードを求めている",
    patterns: [
      /(暗証番号|パスワード|カード番号|セキュリティコード|認証コード|確認コード|ワンタイムパスワード|口座番号).{0,15}?(入力|教え|伝え|送信|送っ|返信|記入)(?!しない|ない|ません|させ)/,
    ],
  },
  {
    kind: "fake_virus",
    strength: "medium",
    reason: "ウイルスに感染したという警告がある",
    patterns: [/(ウイルス|ウィルス|トロイ|マルウェア).{0,10}(感染|検出|見つか)|ハッキングされ/],
  },
  {
    kind: "subscription_trap",
    strength: "medium",
    reason: "無料のあとに毎週の課金がある",
    patterns: [/\d+日間?(無料|無償).{0,30}(毎週|週額|1週間あたり|週ごと)/],
  },
  {
    kind: "prize_refund",
    strength: "medium",
    reason: "当選や還付金で誘っている",
    patterns: [/(当選|還付金|給付金|未払い金|返金|ポイント).{0,20}(受け取|手続|申請|こちら|url|失効)/],
  },
];

// Phrases that need a link to a host that is not official before they count.
export const LINK_BAIT: readonly PhraseRule[] = [
  {
    kind: "delivery_bait",
    strength: "medium",
    reason: "宅配の不在の知らせをかたっている",
    patterns: [/(不在|お届け|配達|お荷物|荷物|配送).{0,20}(持ち帰|できませんでした|できません|再配達|保管|確認|住所)/],
  },
  {
    kind: "storage_bait",
    strength: "medium",
    reason: "容量がいっぱいだと急がせている",
    patterns: [/(ストレージ|容量|icloud).{0,10}(いっぱい|不足|満杯|上限)/],
  },
];

export const URGENCY: PhraseRule = {
  kind: "urgency",
  strength: "weak",
  reason: "急がせる言い回しがある",
  patterns: [
    /至急|本日中|今日中|\d+時間以内|直ちに|ただちに|今すぐ|速やかに|最終(通知|警告|案内)|法的(措置|手続)|差し押さえ|強制(解約|退会)/,
    /(アカウント|口座|カード|サービス|利用).{0,8}(停止|制限|凍結|ロック|無効)/,
    /不正(な)?(アクセス|ログイン|利用)/,
  ],
};

// "認証コード: 123456" with nothing else to it. Real ones must not be hidden from the mother.
export const OTP_ONLY = /(認証|確認|ワンタイム|セキュリティ)(コード|番号|パスワード)|verification code|\bcode\b/;
export const OTP_DIGITS = /(^|\D)\d{4,8}(\D|$)/;

export function matches(rule: PhraseRule, text: string): boolean {
  return rule.patterns.some((pattern) => pattern.test(text));
}
