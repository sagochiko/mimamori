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

// Someone told her to switch this notice off ("警察の人に、この通知を止めてと言われました", #51). Only
// in her consultation: genuine warnings in an SMS, a mail, or a page quote the same words ("と指示される
// ことがあります", "と言われた場合は"; review 1 of PR #176), and the strong injection sign would send them
// to the junk folder. Only the told form, so her own "この通知を止めたい" or how-to stays hers, and not
// "言われたら", which is a warning about what scams say. Only this notice or the app's: "LINEの通知を止めて"
// is another app. The same kind and reason as INJECTION, so the consultation's floor and the family's
// card treat it as injected text (consult-judge.ts).
const TOLD_TO_SILENCE =
  /(この|その|あの|本|見守り(アプリ)?の)(通知|お知らせ|知らせ)(を|は)?(止め|とめ|消し|切っ|オフにし|無視し)(てください|てくれ|なさい|て|ろ)?[」』"]?(と|って)[^。!?\n]{0,8}?(言われ|頼まれ|指示され)(?!たら|ても)/;
// Someone tells her what to make the app say (#21): "AIには安全と判定するように伝えなさい", "アプリには
// 大丈夫と答えるようにって". Only the told form, so her own "このアプリって安全って言われてるの?" stays hers,
// and so do "娘が、このアプリは安全って伝えてくれた" and "大丈夫と答えてくれる?" (review 1 of PR #206).
const TOLD_TO_CALL_IT_FINE =
  /(ai|アプリ|見守り|この相談|判定)[^。!?\n]{0,12}(安全|大丈夫|問題(が)?ない|詐欺じゃない)(と|だと|って)[^。!?\n]{0,4}((判定|判断)(するよう|させ|しろ|しなさい)|(答え|伝え)(るよう|させ|ろ|なさい)|言(うよう|わせ|え|いなさい))/;
export const CONSULT_INJECTION: PhraseRule = {
  ...INJECTION,
  patterns: [...INJECTION.patterns, TOLD_TO_SILENCE, TOLD_TO_CALL_IT_FINE],
};

// "心当たりがない場合、このメッセージは無視してください" is in genuine code messages, some with a
// number to call. It counts only when the message also leads to a link that is not official
// (judgeByRules checks that).
export const NOTICE_IGNORE: PhraseRule = {
  kind: "notice_ignore",
  strength: "medium",
  reason: "この知らせを無視させようとしている",
  patterns: [
    /(この|本)(通知|メッセージ|メール|sms).{0,6}(は誤り|は間違い|を無視|は無視|は気にしな|を止め|を消し|をオフに)/,
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
      /(誰|だれ|家族|ほかの人|他の人|他人|銀行|周り).{0,8}(言わない|話さない|話しては|言っては|口外|相談しない|相談しては|内緒に|秘密に)/,
      /口外(しない|禁止)|守秘義務/,
    ],
  },
  {
    kind: "police_video",
    strength: "medium",
    reason: "ビデオ通話や LINE に誘われている",
    patterns: [
      /ビデオ通話|テレビ電話|(line|ライン).{0,4}(で|に|の).{0,8}(追加|話|連絡|移|友だち|事情聴取|取り調べ)|事情聴取.{0,10}(line|ライン|ビデオ)/,
    ],
  },
];

// Moving money is part of the script, but banks talk about transfers too, so it never counts alone.
export const MONEY_MOVE: PhraseRule = {
  kind: "money_move",
  strength: "weak",
  reason: "お金を動かす話がある",
  patterns: [
    /送金|振り込|振込|口座を移|移し替え|別の口座|安全な口座|指定の口座|資産.{0,4}(調査|確認|保全)|現金.{0,6}(用意|渡|預|送)/,
  ],
};

// A caller who says he is the police, in her own words ("警察から電話", "警察署の人から"). It is a
// part of the script only in a consultation (consult.ts, #72), and only next to one of POLICE_SCRIPT:
// genuine warnings from banks and the police write "警察を名乗る電話" next to "口座が犯罪に使われて
// いる", so SMS, mail, and pages never count it. Speech recognition may drop the comma after it.
const POLICE_NAME = "(警察(署|官|庁)?|警視庁|[都道府県]警|刑事|おまわりさん|お巡りさん)";
/** The police named at all ("これ、警察から"): a short question with it points at something (consult-judge.ts, #114). */
export const POLICE_WORD = new RegExp(POLICE_NAME);
// Whose account the caller talks about, right after 警察から: あなたの口座, うちの口座, お前の口座. A name
// before 名義 (息子名義の口座) is taken in the pattern itself.
const WHOSE = "あなた|あんた|お宅|おたく|私|わたし|うち|お前|おまえ|自分";
// Bodies that scams name other than the police, so a name between 警察 and 名乗る is not the police.
const OTHER_BODY = "銀行|役所|弁護士|会社|郵便局|年金|税務署";
// Not the words of a warning she passes on ("警察を名乗る詐欺", "警察をかたる電話に注意"; PR #80 review).
const NOT_A_WARNING = "(?!詐欺|手口|[^。!?\\n]{0,2}にご?(注意|気をつけ|気を付け))";
export const POLICE_CALLER: PhraseRule = {
  kind: "police_caller",
  strength: "medium",
  reason: "警察を名乗る相手から連絡があった",
  patterns: [
    // 警察から電話, 警察署から連絡, 警視庁からかかってきた
    new RegExp(`${POLICE_NAME}から[^。!?\\n]{0,4}(電話|連絡|着信|かかって|言われ)`),
    // 警察から、口座が… / 警察から 名義… / 警察から、いや警察の… / 警察からあなたの口座が…: what the
    // caller said, or her correcting herself, comes right after から, with a pause or without one
    // (#81). A pause alone is not enough (PR #105 review): 警察から、聞いたんやけど and 警察から、落とし物の
    // 通帳が are how she heard of it, and 警察からのお知らせ is a notice.
    new RegExp(
      `${POLICE_NAME}から[、,\\s]*(?=いや|((${WHOSE})(の|に|が|は)?[、,\\s]*)?(口座|名義|逮捕|容疑|捜査)|[^、,\\s。!?\\n]{1,4}名義)`,
    ),
    // 警察署の人から, 警察官を名乗る人から, 警察を名乗る電話が, 警察って人が, 県警の者で
    new RegExp(
      `${POLICE_NAME}(の|を名乗る|と名乗る|って名乗る|だと名乗る|って(いう|言う)?|という|と言う|だという|だって(いう|言う)?)(人|方|者|男性?|女性?|相手|電話)(から|が|で)`,
    ),
    // 警察署の人だって言う電話, 警察だという電話, 警察ですって電話
    new RegExp(
      `${POLICE_NAME}(の(人|方))?((だ|です)(って|と)(いう|言う|名乗る)?|(って|と)(いう|言う|名乗る))(電話|人|相手)`,
    ),
    // 警察名乗る電話が来て, 警察を名乗った人, 警察を名乗られて: saying he is the police is the
    // caller, whatever particle speech recognition keeps or drops after it (#78). Words may come
    // between the name and 名乗る (#81): 警察署の人と名乗る, 警視庁の捜査二課を名乗る, 県警の、何とか課の
    // 何とかって名乗る. Not another body's name in between: 警察署に行く途中で、銀行員を名乗る.
    new RegExp(
      `${POLICE_NAME}((?!${OTHER_BODY})[^。!?\\n]){0,15}?(を|と|って|だと)?名乗(る|って|り|った|られ)${NOT_A_WARNING}`,
    ),
    // 警察をかたる, 警察官を騙る, 警察かたる電話 (#81). 語る is how speech recognition may write かたる,
    // and only after を or と: 警察官が語った話 is the police talking.
    new RegExp(`${POLICE_NAME}(の人|の者|署員)?を?(かた|騙)(る|って|り|った|られ)${NOT_A_WARNING}`),
    new RegExp(`${POLICE_NAME}(の人|の者|署員)?(を|と)語(る|って|り|った|られ)${NOT_A_WARNING}`),
    // 警察を乗る, 警察って乗る, 警察を載った: 名乗る as speech recognition wrote it on the author's
    // iPhone, with な dropped (#114), and 載る for the same sound. 乗る only right after を or って,
    // which riding does not take: 警察の車に乗る, パトカーに乗って. Not after と, which riding takes
    // (警察官と乗った車で, review of PR #117), and not 乗り越える. 載る only right after を: after って
    // it is something shown or printed (画面に警察って載ってた, second round of that review).
    new RegExp(`${POLICE_NAME}(の人|の者|署員)?(を(乗|載)|って乗)(る|って|り(?!越)|った|られ)${NOT_A_WARNING}`),
    // 警察の名前で電話, 警察の名前をかたって, 警察みたいな人から, 警察っぽい男 (#81)
    new RegExp(`${POLICE_NAME}の名(前)?(で|を(使|かた|騙|語|名乗)(って|い|う|った|る)${NOT_A_WARNING})`),
    new RegExp(`${POLICE_NAME}(みたいな|っぽい|のような|らしき)(人|方|者|男|女|相手|電話|声)`),
  ],
};

// More of the fake-police script as she tells it (#21), from the National Police Agency's warnings
// on ニセ警察詐欺 and キャッシュカード詐欺盗. Consultation only, like POLICE_CALLER: genuine warnings
// in an SMS, a mail, or a page quote these lines, and the parts there stay as POLICE_SCRIPT has them.
// A warning she passes on skips them as it skips POLICE_SCRIPT (judgeByRules, scriptParts).
// These parts are weaker evidence than POLICE_SCRIPT: the police do call victims, witnesses, and
// families about her name, her card, or someone held (review 1 of PR #206). So they count towards the
// script, which is level 1 without asking Claude, only next to a part of POLICE_SCRIPT itself; alone,
// however many, they are one medium sign, level 2 at most, and Claude decides (judgeByRules).
const NOT_SENT = "[^。!?\\n]";
// Not about her family or the post: 息子が逮捕されそう, クレジットカードを息子が取りに来る,
// 郵便局の人が古い通帳を回収しに来る (review 1 of PR #206).
const KIN_OR_POST = "(息子|娘|孫|夫|主人|旦那|嫁|兄|弟|姉|妹|家族|郵便|配達|宅配)";
const NOT_AFTER_KIN = `(?<!${KIN_OR_POST}${NOT_SENT}{0,12})`;
const NOT_BEFORE_KIN = `(?!${NOT_SENT}{0,20}${KIN_OR_POST})`;
// Not a line she called herself: 110番にかけたら, 自分で警察署に電話して.
const NOT_HER_CALL = `(?<!(110|かけたら|かけて|自分で|自分から|こちらから)${NOT_SENT}{0,12})`;
// Not a card she lost: the police or a 交番 calling about one she dropped or left is genuine.
const NOT_LOST = `(?<!(落と|拾|忘れ)${NOT_SENT}{0,12})`;

/** A consultation-only part of the script (#21). */
export interface ConsultPart extends PhraseRule {
  /** The POLICE_SCRIPT kind it words more widely, or its own kind for a new part. */
  part: string;
  /** Counts only when her words also have a caller who says he is the police (POLICE_CALLER). */
  needsCaller?: boolean;
}
const widen = (kind: string, patterns: readonly RegExp[], needsCaller = false): ConsultPart => {
  const rule = POLICE_SCRIPT.find((r) => r.kind === kind)!;
  return { ...rule, kind: `${kind}_more${needsCaller ? "_caller" : ""}`, part: kind, patterns, needsCaller };
};
export const CONSULT_MORE_PARTS: readonly ConsultPart[] = [
  // 逮捕しに行く, 逮捕されたくなかったら, 身柄を拘束, 勾留. Not 拘束 alone: 仕事で拘束される is her day.
  widen("police_arrest", [
    new RegExp(
      `${NOT_AFTER_KIN}(逮捕(しに|に)(行|来|伺|向か)|逮捕(する|します|されちゃ|されそう|されたく)|身柄を|拘束されたく|勾留)`,
    ),
  ]),
  // Being suspected of a crime, only from a caller who says he is the police: 私が悪いことしたって娘に
  // 言われた is a quarrel.
  widen(
    "police_arrest",
    [new RegExp(`(${WHOSE})が${NOT_SENT}{0,4}(悪いこと|犯罪|(?<!謝)罪)${NOT_SENT}{0,8}(言われ|疑われ)`)],
    true,
  ),
  // Papers shown on LINE: 逮捕状をLINEで送ってきた, ラインで警察手帳を見せられた. Only the papers the
  // script shows, not photos, which the family sends on LINE every day.
  widen("police_video", [
    new RegExp(`(line|ライン)で${NOT_SENT}{0,12}(書類|令状|逮捕状|身分証|警察手帳|手帳)${NOT_SENT}{0,6}(見せ|送|届)`),
    /(書類|令状|逮捕状|身分証|警察手帳|手帳)を?(line|ライン)で(見せ|送)/,
  ]),
  // 人に言っちゃだめ, 周りの人に話しちゃいけない, as she says it. Not about a PIN or a code, which
  // banks tell her to keep to herself.
  widen("police_secrecy", [
    new RegExp(
      `(?<!(暗証|パスワード|コード|番号)${NOT_SENT}{0,10})(誰|だれ|人|家族|他人|銀行|周り)(に|にも|には)${NOT_SENT}{0,4}(言っちゃ|話しちゃ|しゃべっちゃ|言ったら|話したら|しゃべったら)(いけない|いかん|だめ|ダメ|あかん)`,
    ),
  ]),
  {
    // 携帯の契約が犯罪に使われた, マイナンバーが悪いことに使われた: what the caller says is used in
    // the crime, other than her account. Not 個人情報 or 不正利用 on their own, which genuine
    // security notices from banks and carriers talk about.
    kind: "police_identity_crime",
    part: "police_identity_crime",
    strength: "medium",
    reason: "携帯や名義が犯罪に使われたという話がある",
    patterns: [
      new RegExp(
        `(携帯|スマホ|電話の契約|契約|マイナンバー|通帳|キャッシュカード|名義)${NOT_SENT}{0,8}(犯罪|事件|詐欺|悪いこと)に(使われ|使っ|利用され)`,
      ),
    ],
  },
  {
    // 捜査であなたの名前が出た, 犯人がわたしの名前を言ってる, 押収した資料にあなたの名義. Only her own
    // name next to the crime: 町内会の名簿に私の名前 is not the script.
    kind: "police_named",
    part: "police_named",
    strength: "medium",
    reason: "事件に名前が出ているという話がある",
    patterns: [
      new RegExp(
        `(事件|捜査|犯人|容疑者|詐欺グループ|犯罪グループ|犯行グループ|押収)${NOT_SENT}{0,12}(${WHOSE})の(名前|名義)`,
      ),
      new RegExp(`(${WHOSE})の(名前|名義)${NOT_SENT}{0,12}(犯人|容疑者|犯罪|事件|詐欺グループ|犯罪グループ)`),
    ],
  },
  {
    // An automated call that leads to someone who says he is the police. Not an automated line with
    // no police in it, such as a bank's, and not a line she called herself (110番にかけたら).
    kind: "police_ivr",
    part: "police_ivr",
    strength: "medium",
    reason: "自動音声のあとで警察を名乗る相手につながった",
    patterns: [
      new RegExp(
        `${NOT_HER_CALL}(自動音声|音声ガイダンス|ガイダンス|機械の声|録音の声)${NOT_SENT}{0,30}${POLICE_NAME}`,
      ),
      new RegExp(`${NOT_HER_CALL}\\d番?を押${NOT_SENT}{0,15}${POLICE_NAME}`),
    ],
  },
  {
    // Someone coming to her home for her card or bankbook (キャッシュカード詐欺盗). Not her going to
    // pick up a lost card ("受け取りに来てください", "取りに来られますか"), a card she dropped or left
    // somewhere, a card sent by post, or her family or the post office coming for one.
    kind: "card_pickup",
    part: "card_pickup",
    strength: "medium",
    reason: "カードや通帳を人が受け取りに来る話がある",
    patterns: [
      new RegExp(
        `${NOT_LOST}${NOT_AFTER_KIN}(カード|通帳)${NOT_BEFORE_KIN}${NOT_SENT}{0,20}(取りに|預かりに|受け取りに|回収しに|回収に)(来る|来ます|行く|行きます|伺|参)`,
      ),
      new RegExp(
        `${NOT_LOST}${NOT_AFTER_KIN}(カード|通帳)${NOT_BEFORE_KIN}${NOT_SENT}{0,15}(人|者|職員|警察官|銀行員)が(来る|来ます|家に|うちに|伺|行く|行きます)`,
      ),
    ],
  },
];
/** The kinds of CONSULT_MORE_PARTS, which never make the script on their own. */
export const CONSULT_MORE_KINDS: ReadonlySet<string> = new Set(CONSULT_MORE_PARTS.map((p) => p.kind));
/** The consultation-only parts in these words, as the parts they are (#21). */
export function moreParts(text: string, caller: boolean): ConsultPart[] {
  return CONSULT_MORE_PARTS.filter((p) => (!p.needsCaller || caller) && matchSpans(p, text).length > 0);
}
/**
 * MONEY_MOVE as a consultation reads it (#21): money to have ready for the police (保釈金, 示談金),
 * being asked how her money moves (預金の状況を教えて), and moving it to an account. Still weak, and
 * still a part of the script only next to a police part.
 */
export const CONSULT_MONEY_MOVE: PhraseRule = {
  ...MONEY_MOVE,
  patterns: [
    ...MONEY_MOVE.patterns,
    new RegExp(
      `保釈金|示談金|供託金|(お金|現金|預金|貯金|資産|財産)の(動き|流れ|状況|残高)${NOT_SENT}{0,6}(教え|調べ|確認|聞か)|口座に移`,
    ),
  ],
};

// She passes on a warning that she heard, read, or saw (#81): from the police, a bank, the family, TV,
// a leaflet. The script's parts in such words are what the warning describes, not what was said to
// her ("ラジオで聞いた、潔白を証明しろって電話はニセモノやって"). Her own doubt about a call she got
// ("詐欺かも", "詐欺だと思う", "詐欺じゃないよね") is not a warning passed on. Each pattern may take
// the words she quotes it with ("…って言われた", "…と書いてあった"), so those are not counted as a
// call she got (RECEIVED_CONTACT). The caller's own stock lines are left out (PR #105 review), only in
// the forms he says them, so the warning words themselves stay: "口座が犯罪に使われてるから気をつけて"
// (right after a part of the script), "最近詐欺が多いから調べてる", "ほかの電話には出ないで", "銀行が何か
// 言っても信用しないで" are what he says to her, not a warning she heard.
const QUOTED =
  "((って|と|て)?[^。!?\\n]{0,4}?(言われ|言って|言うて|ゆうて|話して|聞い|書いて|教えて|教わ|注意され)[^。!?\\n]{0,3})?";
const WARNING_PATTERNS = [
  // 気をつけて, 気ぃつけや, 用心して, 注意してください, 気をつけなあかん: "電話が多いから気をつけて",
  // "〜って電話、気をつけて". Not right after a part of the script and から or ので ("口座が犯罪に使われ
  // てるから気をつけて", "逮捕状が出てるので注意して"): the caller says that.
  "(?<!(使われ|悪用され|出|なっ|かかっ)(て(る|いる|います|ます)?|と(る|ります))(から|ので|し)、?)(気をつけ|気を付け|気ぃつけ|用心し|注意し)(て|や|なさい|ましょう|な(あかん|いと|きゃ|けれ)|ないと)",
  // 〜に注意, 〜にご注意, 注意喚起
  "にご?注意|注意喚起|注意を呼びかけ",
  // What the police or a bank never do: 警察が〜ことはありません, 警察は絶対せえへん. Only with the body
  // as the subject: "協力すれば逮捕されることはない" is what the caller says.
  "(警察|警察官|銀行|役所|郵便局)(が|は)[^。!?\\n]{0,20}?(ことは(絶対)?(ない|ありません|ございません|ありえ|あらへん)|絶対に?(せえへん|せーへん|しない|しません)(?!で))",
  // 〜は詐欺だから, 詐欺ですって, ニセモンやって (not 詐欺だと思う)
  "(詐欺|ニセ(モン|もん|モノ|もの|物)|にせもの|偽物|偽者)(だ|です|や|なん(だ|や|です))(から|って|と(?!\\s*(思|おも)))",
  // 全部詐欺, みんなニセモン. Not 全部詐欺グループの仕業, which the caller says.
  "(全部|ぜんぶ|みんな|すべて|全て)が?(詐欺|ニセ|偽)(?!グループ|集団|団|師|犯|事件|に使)",
  // 〜って詐欺が増えてる. Not the caller's "最近詐欺が多いから調べてる", "詐欺が多発してて、あなたの口座が".
  "詐欺[^。!?\\n]{0,4}(増え|多い|多発|流行|はや)(?![^。!?\\n]{0,8}(調べ|捜査|調査|確認|あなた|あんた|お宅|おたく))",
  // 〜って電話には出ないで, 〜って電話、出たらあかん, 知らない番号には出ないで. Not "ほかの電話には出ないで" or "家から出ないで",
  // which the caller says.
  "(?<!(ほか|他|別|よそ)の?\\s?)(電話|でんわ|番号)(に|には|にも|は)?[、,\\s]?出(ないで|んといて|んとって|ちゃだめ|たらあかん|ないよう)",
  // Where she saw or heard it. テレビ電話 is the script's video call, not TV.
  "テレビ(?!電話)|ニュース|ラジオ|新聞|広報|回覧板|チラシ|ちらし|ポスター|貼り紙|張り紙|はり紙|掲示|パンフ|講習|防犯(?!課)",
];
const PASSED_ON_WARNING: readonly RegExp[] = WARNING_PATTERNS.map((p) => new RegExp(`(${p})${QUOTED}`));

// A call, a message, or words that came to her ("電話があって", "電話きて", "かかってきた", "言われた",
// "名乗る人から"). Not the conditional of a warning ("電話が来たら", "言われても").
const RECEIVED_CONTACT: readonly RegExp[] = [
  /(電話|でんわ|連絡|着信|メール|sms|ショートメール|ライン|line|手紙|はがき|ハガキ)(が|も)?(あ(って(?!も)|った(?!ら)|りまし)|来(て(?!も)|た(?!ら)|まし)|き(て(?!も)|た(?!ら)|まし)|入って(た|る|き)|届(いて|いた(?!ら)|きまし))/,
  /(かかって|かけて|送られて|送って)(き|来)(て(?!も)|た(?!ら)|まし)/,
  /(言われ|聞かれ|頼まれ|見せられ)(て(?!も)|た(?!ら)|まし)/,
  /名乗(る|った|って)[^。!?、\n]{0,5}?から/,
  /から(電話|連絡|着信)で/,
];

/**
 * How she tells it: in her own words about what came to her ("own"), passing on a warning she heard
 * ("passed_on"), or both, as when she got the call and also says what TV warned about ("mixed").
 * `text` is normalized (NFKC, lower case). Only for consultations.
 */
export type Telling = "own" | "passed_on" | "mixed";
export function tellingOf(text: string): Telling {
  const warned = spansOf(PASSED_ON_WARNING, text);
  if (warned.length === 0) return "own";
  const received = spansOf(RECEIVED_CONTACT, text).filter(([s, e]) => !warned.some(([ws, we]) => s < we && ws < e));
  return received.length > 0 ? "mixed" : "passed_on";
}

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
    patterns: [
      /(電子マネー|ギフトカード|プリペイドカード|apple ?gift ?card|google ?play ?(ギフト)?カード|itunes ?カード).{0,15}(買|購入|番号|コード)/,
    ],
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
  return spansOf(rule.patterns, text);
}

function spansOf(patterns: readonly RegExp[], text: string): Array<[number, number]> {
  const spans: Array<[number, number]> = [];
  for (const pattern of patterns) {
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
