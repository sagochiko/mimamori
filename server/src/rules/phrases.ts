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
    // "この通知は無視して" and "この通知をオフに" are in NOTICE_IGNORE: genuine messages say them too.
    // Saying this notice is wrong is not something a genuine message does.
    /(警告|判定|アラート).{0,6}(は誤り|は間違い|は誤検知|を無視|は無視|を止め|を消し|をオフに|は気にしな)/,
    /(この|本)通知.{0,6}(は誤り|は間違い|は誤検知)/,
    // "Don't tell your family" in particular: the family is who this app tells. Only the forms that
    // tell someone not to tell, so "家族には内緒のごほうび" or "子どもの秘密基地" do not match. Up to
    // 8 characters may sit between, for "ご家族や銀行の方には" or "家族を含め誰にも". "教えないで" is
    // left out: banks and code messages say "ご家族にも教えないで" about a PIN or a code.
    // "誰にも言わないで" is the scam's general secrecy and lives in POLICE_SCRIPT.
    /(家族|息子|娘|子ども|子供|家の人|身内)[^。、!?「」\n]{0,8}?((知らせ|言わ|話さ|伝え|相談し)ない(で|よう)|(知らせる|言う|話す|伝える|相談する)な(?![らどのかんしり])|(内緒|秘密)に(して|しと|しておい))/,
    /ignore (all |any )?(the )?(previous|prior|above) instructions/,
    /system prompt|システムプロンプト/,
  ],
};

// "心当たりがない場合、このメッセージは無視してください" is in genuine code messages, some with a
// number to call. It counts only when the message also leads to a link that is not official
// (judgeByRules checks that).
export const NOTICE_IGNORE: PhraseRule = {
  kind: "notice_ignore",
  strength: "medium",
  reason: "この知らせを無視させようとしている",
  patterns: [/(この|本)(通知|メッセージ|メール|sms).{0,6}(は誤り|は間違い|を無視|は無視|は気にしな|を止め|を消し|をオフに)/],
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
      /(誰|だれ|家族|ほかの人|他の人|他人|銀行|周り).{0,8}(言わない|話さない|話しては|言っては|口外|相談しない|相談しては|内緒に|秘密に)/,
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

// A caller who says he is the police, in her own words ("警察から電話", "警察署の人から"). It is a
// part of the script only in a consultation (consult.ts, #72), and only next to one of POLICE_SCRIPT:
// genuine warnings from banks and the police write "警察を名乗る電話" next to "口座が犯罪に使われて
// いる", so SMS, mail, and pages never count it. Speech recognition may drop the comma after it.
const POLICE_NAME = "(警察(署|官)?|警視庁|[都道府県]警)";
export const POLICE_CALLER: PhraseRule = {
  kind: "police_caller",
  strength: "medium",
  reason: "警察を名乗る相手から連絡があった",
  patterns: [
    // 警察から電話, 警察署から連絡, 警視庁からかかってきた
    new RegExp(`${POLICE_NAME}から[^。!?\\n]{0,4}(電話|連絡|着信|かかって|言われ)`),
    // 警察署の人から, 警察官を名乗る人から, 警察って人が, 県警の者で
    new RegExp(`${POLICE_NAME}(の|を名乗る|と名乗る|って名乗る|だと名乗る|って(いう|言う)?|という|と言う|だという|だって(いう|言う)?)(人|方|者|男性?|女性?|相手)(から|が|で)`),
    // 警察署の人だって言う電話, 警察だという電話
    new RegExp(`${POLICE_NAME}(の(人|方))?(だ|です)?(って|と)(いう|言う|名乗る)(電話|人|相手)`),
  ],
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

// CREDENTIAL in a message that is only a verification code: typing a one-time code in is what it
// is for, so only that is left out. A PIN, a card or account number, or a password typed in or sent,
// and a code handed to someone, still count.
export const CREDENTIAL_FROM_CODE: PhraseRule = {
  kind: "credential",
  strength: "medium",
  reason: "暗証番号やパスワードを求めている",
  patterns: [
    /(暗証番号|(?<!ワンタイム)パスワード|カード番号|セキュリティコード|口座番号).{0,15}?(入力|教え|伝え|送信|送っ|返信|記入)(?!しない|ない|ません|させ)/,
    /(認証コード|確認コード|ワンタイムパスワード|コード|番号).{0,20}?(教え|伝え|送信|送っ|返信)(?!しない|ない|ません|させ|しま|され|した|不要|専用|元)/,
  ],
};

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

/** Where the rule matches in the text, as [start, end). Two rules over one phrase are one sign. */
export function matchSpans(rule: PhraseRule, text: string): Array<[number, number]> {
  const spans: Array<[number, number]> = [];
  for (const pattern of rule.patterns) {
    const global = new RegExp(pattern.source, pattern.flags.includes("g") ? pattern.flags : `${pattern.flags}g`);
    for (const m of text.matchAll(global)) spans.push([m.index, m.index + m[0].length]);
  }
  return spans;
}

// Something that may be a phone number: starts with 0 or +, with or without separators. Japanese
// text writes them with a long dash or brackets too: 03ー1234ー5678, 03(1234)5678. Text is NFKC
// normalized first, so full-width brackets arrive as ( ). Broad on purpose: it only stops a message
// from passing as a bare verification code.
export const PHONE_NUMBER =
  /(?<!\d)(\(?0\d{1,4}[-\s‐−ー()]{0,2}\d{1,4}[-\s‐−ー()]{0,2}\d{3,4}|\+\d[\d\s‐−ー()-]{8,}\d)(?!\d)/;
