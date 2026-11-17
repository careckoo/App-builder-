// JavaScript copy of SarfiCore/BankMessageParser.swift + Categorizer.swift.
// Used by the clickable prototype and by parser.test.mjs to check the rules without a Mac.
// Keep the two in step: when a rule changes in Swift, change it here too.

const IGNORE = ["otp", "one time password", "one-time password", "verification code", "do not share",
  "activation code", "declined", "insufficient", "failed", "unsuccessful", "offer", "offers", "win",
  "رمز التحقق", "كلمة المرور لمرة واحدة", "رمز التفعيل", "لا تشارك", "مرفوضة", "رفض", "غير كاف", "عرض خاص",
  // Payment reminders and prize draws: no money moved.
  // Not a bare "reminder": "Set a reminder in our app" sits under real purchase alerts.
  "minimum payment due", "minimum amount due", "minimum due", "min. due", "min due", "is due on",
  "payment reminder", "friendly reminder", "this is a reminder", "please pay",
  "الحد الأدنى", "تذكير", "مستحق الدفع", "مستحقة الدفع", "تاريخ الاستحقاق", "اربح", "السحب على", "جوائز", "جائزة",
  // Purchase-approval codes ("Use 482913 to authorise your purchase of AED 500 at AMAZON.AE").
  "to authorise", "to authorize", "is your code", "your code is", "passcode", "secure code"];
const REFUND = ["refund", "refunded", "reversal", "reversed", "cashback", "مسترد", "استرداد", "استرجاع", "عكس"];
const WITHDRAWAL = ["atm", "cash withdrawal", "withdrawn", "withdrawal", "سحب نقدي", "سحب", "صراف"];
const INCOME = ["credited", "has been deposited", "deposit", "received", "salary", "transfer from", "inward",
  "تم إيداع", "تم ايداع", "إيداع", "ايداع", "راتب", "استلام", "تم استلام", "حوالة واردة", "أضيف", "اضيف"];
const TRANSFER_OUT = ["transferred to", "transfer to", "sent to", "remittance", "outward", "tfr to",
  "تحويل إلى", "تحويل الى", "حوالة صادرة", "تم تحويل"];
const PURCHASE = ["debited", "used for", "purchase", "purchased", "spent", "paid", "payment", "pos", "charged", "transaction of",
  "trx", "txn", "approved", "recharge", "recharged",
  "تم خصم", "خصم", "شراء", "عملية شراء", "مشتريات", "دفع", "تم استخدام", "تم الدفع"];
const STRONG_INCOME = ["credited", "deposited", "salary", "تم إيداع", "تم ايداع", "راتب", "حوالة واردة", "إلى حسابك", "to your account"];
const STRONG_DEBIT = ["debited", "تم خصم", "used for", "purchase", "شراء"];

const CURRENCIES = [["AED","AED"],["Dhs.","AED"],["Dhs","AED"],["DHS","AED"],["Dh","AED"],["درهم","AED"],["د.إ","AED"],["د.ا","AED"],
  ["USD","USD"],["US$","USD"],["دولار","USD"],["EUR","EUR"],["GBP","GBP"],["SAR","SAR"],["ريال","SAR"],
  ["INR","INR"],["PKR","PKR"],["EGP","EGP"],["QAR","QAR"],["OMR","OMR"],["KWD","KWD"],["BHD","BHD"]];
const BALANCE_MARKERS = ["balance", "bal", "avl", "avlbal", "avail", "available", "limit", "outstanding", "due",
  "الرصيد", "رصيد", "المتاح", "الحد", "المستحق"];
const NUM = String.raw`([0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]{1,3})?|[0-9]+(?:\.[0-9]{1,3})?)`;
const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const CUR = CURRENCIES.map(c => esc(c[0])).join("|");

// A credit-card bill paid from the person's own account: not income, not spending.
const CARD_PAYMENT = [/\b(?:payment|paid)\b.{0,80}?\b(?:for|to|towards) (?:your )?(?:credit )?card\b/,
  /\bcredit card (?:bill )?payment\b/, /\bcredit card\b.{0,30}?\bpayment\b.{0,80}?\b(?:received|credited)\b/,
  /\bcard (?:bill )?payment\b.{0,60}?\b(?:received|credited)\b/, /\bpayment received for your (?:credit )?card\b/,
  /\bcredited to (?:your )?credit card\b/,
  /سداد (?:ال)?بطاق/, /سداد.{0,60}?(?:لبطاقت|(?:إلى|الى) بطاقت)/, /تم استلام دفعة.{0,80}?بطاق/];
// A merchant named after "at" / لدى / عند makes it a purchase ("card payment of AED 30 at STARBUCKS").
// Not a date or phone number ("credited at 16/11/26", "call us at 600…") and not "with us at ADCB".
const MERCHANT_AT = /(?<!\bus )\bat\s+(?!us\b|your\b|the\b|any\b)[^\s0-9+(]|(?:لدى|عند)\s+[^\s0-9+(]/;
const isCardPayment = lower => !MERCHANT_AT.test(lower) && CARD_PAYMENT.some(re => re.test(lower));

// Money moved between the person's own accounts, into or out of a fixed deposit or savings, or cash
// put into a CDM (already counted when it was withdrawn). Not income, not spending.
const OWN_TRANSFER = [/\bfrom your (?:a\/c|account|acct)\b.*\bto your (?:a\/c|account|acct)\b/,
  /\bto your (?:a\/c|account|acct)\b.*\bfrom your (?:a\/c|account|acct)\b/,
  /\bown (?:a\/c|account|accounts|acct)\b/, /\bbetween (?:your|own) accounts\b/,
  /\b(?:fixed|term) deposit\b/, /\bsavings? spaces?\b/,
  /\b(?:transfer(?:red)?|moved|sent|tfr)\b.{0,40}?\b(?:to|into|from)\b.{0,15}?\bsavings? (?:account|a\/c|pot)\b/,
  /\bcdm\b/, /\bcash deposit\b/,
  /من حسابك.*(?:إلى|الى) حسابك/, /بين حساباتك/, /وديعة/, /(?:إيداع|ايداع) نقدي/,
  /(?:تحويل|حول).{0,40}?حساب (?:ال)?(?:توفير|ادخار)/];
const isOwnTransfer = lower => OWN_TRANSFER.some(re => re.test(lower));

// ASCII keywords match on word edges ("pos" must not hit "deposit", "atm" not "treatment").
// Arabic keywords stay plain substrings, because Arabic attaches prefixes like و / ب / ال.
const ASCII = /^[\x00-\x7f]+$/;
const wordRe = new Map();
function hasWord(s, w) {
  if (!ASCII.test(w)) return s.includes(w);
  let re = wordRe.get(w);
  if (!re) { re = new RegExp(`(?<![a-z0-9])${esc(w)}(?![a-z0-9])`); wordRe.set(w, re); }
  return re.test(s);
}
const has = (s, words) => words.some(w => hasWord(s, w));

export function normalize(s) {
  let out = "";
  for (const ch of s) {
    const c = ch.codePointAt(0);
    if (c >= 0x0660 && c <= 0x0669) out += String(c - 0x0660);
    else if (c >= 0x06F0 && c <= 0x06F9) out += String(c - 0x06F0);
    else if (ch === "٫") out += ".";
    else if (ch === "٬" || ch === "،") out += ",";
    else if (/[ \n\t\r]/.test(ch)) out += " ";
    else out += ch;
  }
  return out.replace(/ +/g, " ").trim();
}

function kindFor(lower) {
  if (has(lower, REFUND)) return "refund";
  if (isOwnTransfer(lower)) return "ownTransfer";
  if (has(lower, WITHDRAWAL)) return "withdrawal";
  if (isCardPayment(lower)) return "cardPayment";
  if (has(lower, TRANSFER_OUT) && !lower.includes("إلى حسابك") && !lower.includes("to your account")) return "transferOut";
  if (has(lower, STRONG_INCOME) && !has(lower, STRONG_DEBIT)) return "income";
  if (has(lower, PURCHASE)) return "purchase";
  if (has(lower, INCOME)) return "income";
  return null;
}

function isoFor(token) {
  const t = token.trim().toLowerCase();
  return (CURRENCIES.find(c => c[0].toLowerCase() === t) || [0, "AED"])[1];
}

function allAmounts(text) {
  const found = [];
  const pats = [[new RegExp(`(${CUR})\\s?${NUM}`, "gi"), 0], [new RegExp(`${NUM}\\s?(${CUR})`, "gi"), 1]];
  for (const [re, mode] of pats) {
    for (const m of text.matchAll(re)) {
      const start = m.index, end = m.index + m[0].length;
      const numStr = mode === 0 ? m[2] : m[1];
      const curStr = mode === 0 ? m[1] : m[2];
      const value = parseFloat(numStr.replace(/,/g, ""));
      if (isNaN(value)) continue;
      if (!found.some(f => f.start < end && start < f.end)) found.push({ value, iso: isoFor(curStr), start, end });
    }
  }
  return found.sort((a, b) => a.start - b.start);
}

function precededByBalance(m, text) {
  const before = text.slice(Math.max(0, m.start - 28), m.start).toLowerCase();
  // Whole words for English markers: "BALI RESTAURANT" and "UNLIMITED BURGERS" are merchants.
  return has(before, BALANCE_MARKERS);
}

function transactionAmount(text) {
  const all = allAmounts(text);
  const m = all.find(a => !precededByBalance(a, text));
  if (m) return [m.value, m.iso];
  const f = text.match(new RegExp(`(?:مبلغ|amount of|amt)\\s?:?\\s?${NUM}`, "i"));
  if (f) return [parseFloat(f[1].replace(/,/g, "")), all[0]?.iso || "AED"];
  return null;
}

function balance(text) {
  const b = allAmounts(text).filter(a => precededByBalance(a, text));
  if (b.length) return b[b.length - 1].value;
  // "Avl. card bal is 4852.54": a balance with no currency next to it.
  const f = cap(String.raw`(?:\bbal(?:ance)?|الرصيد|رصيد)\.?\s*(?:is\s*|:\s*)?` + NUM, text);
  return f ? parseFloat(f.replace(/,/g, "")) : null;
}

const cap = (pattern, text) => { const m = text.match(new RegExp(pattern, "i")); return m ? m[1] : null; };

function isAccountReference(s) {
  const l = s.toLowerCase();
  return l.startsWith("your ") || l.includes("account") || l.includes("card ending") || l.includes("حساب") || l.includes("بطاق");
}

function cleanMerchant(s) {
  let name = s.replace(/^[ ,.\-:]+|[ ,.\-:]+$/g, "");
  // "at the DUBAI MALL" -> "DUBAI MALL".
  if (name.toLowerCase().startsWith("the ")) name = name.slice(4).trim();
  const comma = name.indexOf(",");
  if (comma >= 0) name = name.slice(0, comma);
  for (const tail of [" AE", " UAE", " ARE", " ABU DHABI", " DUBAI", " SHARJAH", " AL AIN"]) {
    if (name.toUpperCase().endsWith(tail)) name = name.slice(0, -tail.length);
  }
  return name.trim();
}

function merchant(text) {
  const stops = String.raw`(?=\s+on\s|\s+from\s|\s+with\s+card|\s+has\s|\s+(?:was|is)\s|\s+من\s+(?:حساب|بطاق)|\s+بتاريخ|\s+في\s+[0-9]|\s+بقيمة|\s+[0-9]{1,2}[/-]|\.\s|\.$|(?:,\s*|\s+)(?:avl|avail|available|bal\b|balance|الرصيد|رصيد)|\s+(?:for\s+)?(?:${CUR})\s?[0-9]|$)`;
  const pats = [String.raw`\bat\s+(.+?)`, String.raw`لدى\s+(.+?)`, String.raw`عند\s+(.+?)`, String.raw`\bto\s+(.+?)`,
    String.raw`إلى\s+(.+?)`, String.raw`\bfrom\s+(.+?)`, String.raw`\bfor\s+([A-Z][A-Za-z0-9 &*'.-]{2,})`];
  for (const p of pats) {
    let name = cap(p + stops, text);
    if (name) {
      name = cleanMerchant(name);
      if (name.length >= 2 && !/^[0-9.,]+$/.test(name) && !isAccountReference(name)) return name;
    }
  }
  return null;
}

function incomeSource(text) {
  const p = cap(String.raw`\(([^)]{2,30})\)`, text); if (p) return p;
  const f = cap(String.raw`\bfrom\s+(.+?)(?=\s+on\s|\.\s|\.$|,|$)`, text); if (f) return cleanMerchant(f);
  const a = cap(String.raw`من\s+(.+?)(?=\s+بتاريخ|\.\s|\.$|،|,|$)`, text); if (a && !a.includes("حساب")) return cleanMerchant(a);
  if (text.toLowerCase().includes("salary") || text.includes("راتب")) return "Salary";
  return null;
}

const cardLast4 = text => cap(String.raw`(?:ending(?:\s+with)?|x{2,}|\*+|\bno\.?|رقم|المنتهية ب|المنتهي ب)\s*[x*]*\s*([0-9]{3,4})\b`, text);

// Same list and order as SarfiCore/BankDirectory.swift.
const BANKS = [["First Abu Dhabi Bank","بنك أبوظبي الأول",["FAB","FABBANK"]],["ADCB","بنك أبوظبي التجاري",["ADCB","ADCBAlert"]],
  ["ADIB","مصرف أبوظبي الإسلامي",["ADIB"]],["Emirates NBD","الإمارات دبي الوطني",["EmiratesNBD","ENBD"]],["Liv.","ليف",["Liv","LIVBANK"]],
  ["Dubai Islamic Bank","بنك دبي الإسلامي",["DIB"]],["Mashreq","المشرق",["Mashreq","MashreqNEO"]],
  ["Commercial Bank of Dubai","بنك دبي التجاري",["CBD"]],["RAKBANK","بنك رأس الخيمة",["RAKBANK"]],
  ["Emirates Islamic","الإمارات الإسلامي",["EIB","EmiratesIsl"]],["Wio","ويو",["Wio"]],["Al Hilal Bank","مصرف الهلال",["AlHilal"]],
  ["NBF","بنك الفجيرة الوطني",["NBF"]],["HSBC UAE","إتش إس بي سي",["HSBC"]],["Tabby","تابي",["tabby"]],["Tamara","تمارا",["Tamara"]]];

function bankName(sender, lower) {
  const s = (sender || "").toLowerCase();
  // The sender exactly, or as a whole word ("AD-ADCB", "alerts@adcb.com"), never inside another name.
  const b = (s && BANKS.find(b => b[2].some(id => s === id.toLowerCase() || hasWord(s, id.toLowerCase()))))
    // In the body, whole words only: "liv" inside "delivered" is not Liv.
    || BANKS.find(b => b[2].some(id => hasWord(lower, id.toLowerCase())));
  return b ? { en: b[0], ar: b[1] } : null;
}

// True for an OTP, promo, reminder or failed payment. Also used on an email's subject.
export const isIgnorable = text => has(normalize(text).toLowerCase(), IGNORE);

export function parse(raw, sender) {
  const text = normalize(raw);
  const lower = text.toLowerCase();
  if (has(lower, IGNORE)) return null;
  const amt = transactionAmount(text);
  if (!amt || !(amt[0] > 0)) return null;
  const kind = kindFor(lower);
  if (!kind) return null;
  return {
    amount: amt[0], currency: amt[1], kind,
    merchant: kind === "income" ? incomeSource(text) : kind === "cardPayment" || kind === "ownTransfer" ? null : merchant(text),
    cardLast4: cardLast4(text), balanceAfter: balance(text), bank: bankName(sender, lower)
  };
}

// ---- Categories -------------------------------------------------------------

export const CATEGORIES = {
  groceries: ["Groceries", "بقالة", "🛒"], dining: ["Restaurants & cafés", "مطاعم ومقاهي", "☕️"],
  delivery: ["Food delivery", "توصيل طعام", "🛵"], transport: ["Taxi & transport", "تاكسي ومواصلات", "🚕"],
  fuel: ["Fuel", "وقود", "⛽️"], shopping: ["Shopping", "تسوق", "🛍️"], bills: ["Utilities", "كهرباء وماء", "💡"],
  telecom: ["Mobile & internet", "جوال وإنترنت", "📶"], health: ["Health", "صحة", "💊"],
  entertainment: ["Entertainment", "ترفيه", "🎬"], subscriptions: ["Subscriptions", "اشتراكات", "🔁"],
  travel: ["Travel", "سفر", "✈️"], education: ["Education", "تعليم", "🎓"], family: ["Family & home", "الأسرة والمنزل", "🏠"],
  cash: ["Cash", "نقد", "💵"], transfer: ["Transfers", "تحويلات", "↔️"], income: ["Income", "دخل", "💰"],
  installments: ["Buy now, pay later", "تقسيط", "🗓️"], charity: ["Charity", "صدقة وتبرعات", "🤲"], other: ["Other", "أخرى", "•"]
};

const RULES = [["talabat","delivery"],["deliveroo","delivery"],["noon food","delivery"],["careem food","delivery"],
  ["instashop","groceries"],["kibsons","groceries"],["noon minutes","groceries"],["carrefour","groceries"],["lulu","groceries"],
  ["spinneys","groceries"],["waitrose","groceries"],["union coop","groceries"],["abu dhabi coop","groceries"],["choithrams","groceries"],
  ["grandiose","groceries"],["nesto","groceries"],["al maya","groceries"],["baqala","groceries"],["supermarket","groceries"],
  ["hypermarket","groceries"],["كارفور","groceries"],["لولو","groceries"],["تعاونية","groceries"],["بقالة","groceries"],
  ["starbucks","dining"],["tim hortons","dining"],["costa","dining"],["mcdonald","dining"],["kfc","dining"],["shake shack","dining"],
  ["restaurant","dining"],["cafe","dining"],["café","dining"],["coffee","dining"],["مطعم","dining"],["مقهى","dining"],["كافيه","dining"],
  ["careem","transport"],["uber","transport"],["rta","transport"],["salik","transport"],["darb","transport"],["itc","transport"],
  ["parking","transport"],["mawaqif","transport"],["nol","transport"],["taxi","transport"],["كريم","transport"],["سالك","transport"],["مواقف","transport"],
  ["adnoc","fuel"],["enoc","fuel"],["eppco","fuel"],["emarat","fuel"],["petrol","fuel"],["أدنوك","fuel"],
  ["taqa","bills"],["addc","bills"],["aadc","bills"],["dewa","bills"],["sewa","bills"],["fewa","bills"],["etihad wa","bills"],
  ["empower","bills"],["tabreed","bills"],["طاقة","bills"],["ديوا","bills"],
  ["etisalat","telecom"],["e&","telecom"],["du","telecom"],["virgin mobile","telecom"],["اتصالات","telecom"],
  ["netflix","subscriptions"],["spotify","subscriptions"],["apple.com","subscriptions"],["osn","subscriptions"],["shahid","subscriptions"],
  ["youtube","subscriptions"],["anghami","subscriptions"],["icloud","subscriptions"],["amazon prime","subscriptions"],["disney","subscriptions"],
  ["chatgpt","subscriptions"],["claude","subscriptions"],
  ["amazon","shopping"],["noon","shopping"],["namshi","shopping"],["shein","shopping"],["ikea","family"],["centrepoint","shopping"],
  ["max fashion","shopping"],["h&m","shopping"],["zara","shopping"],["mall","shopping"],["sharaf dg","shopping"],["jumbo","shopping"],
  ["virgin megastore","shopping"],["ace","family"],["home centre","family"],
  ["pharmacy","health"],["aster","health"],["life pharmacy","health"],["boots","health"],["hospital","health"],["clinic","health"],
  ["seha","health"],["mediclinic","health"],["صيدلية","health"],["مستشفى","health"],
  ["vox","entertainment"],["reel cinema","entertainment"],["novo","entertainment"],["ferrari world","entertainment"],["yas","entertainment"],
  ["louvre","entertainment"],["playstation","entertainment"],["steam","entertainment"],
  ["emirates","travel"],["etihad","travel"],["flydubai","travel"],["air arabia","travel"],["booking.com","travel"],["hotel","travel"],
  ["airbnb","travel"],["طيران","travel"],["فندق","travel"],
  ["school","education"],["university","education"],["academy","education"],["مدرسة","education"],["جامعة","education"],
  ["tabby","installments"],["tamara","installments"],["postpay","installments"],["تابي","installments"],["تمارا","installments"],
  ["red crescent","charity"],["dar al ber","charity"],["الهلال الأحمر","charity"],["صدقة","charity"],["زكاة","charity"]];

// Whole words for English keywords (NOVOTEL is not "novo", AFTERNOON TEA is not "noon"), allowing a
// plural or possessive "s" (RESTAURANTS, MCDONALD'S). Arabic keywords stay substrings.
const ruleHit = (m, key) => hasWord(m, key) || (ASCII.test(key) && (hasWord(m, key + "s") || hasWord(m, key + "'s")));

// `learned`: { "merchant name, lower-case": category } from the person's own corrections.
// Exact name first, then the longest learned name found as whole words.
export function categorize(t, learned = {}) {
  if (t.kind === "income" || t.kind === "refund") return "income";
  if (t.kind === "withdrawal") return "cash";
  if (t.kind === "cardPayment" || t.kind === "ownTransfer") return "transfer";
  if (!t.merchant) return t.kind === "transferOut" ? "transfer" : "other";
  const m = t.merchant.toLowerCase();
  if (Object.hasOwn(learned, m)) return learned[m];
  const keys = Object.keys(learned).filter(k => k && hasWord(m, k.toLowerCase())).sort((a, b) => b.length - a.length);
  if (keys.length) return learned[keys[0]];
  const hit = RULES.find(r => ruleHit(m, r[0]));
  return hit ? hit[1] : (t.kind === "transferOut" ? "transfer" : "other");
}

// ---- Email text (mirrors MessageText in SarfiCore/TransactionSources.swift) -------------

const DIRECTION_MARKS = /[‎‏؜‪-‮⁦-⁩​-‍﻿]/g;
const NAMED_ENTITIES = { nbsp: " ", lt: "<", gt: ">", quot: "\"", apos: "'", ndash: "–", mdash: "—",
  zwnj: "", zwj: "", lrm: "", rlm: "", rsquo: "’", lsquo: "‘" };

function decodeEntities(s) {
  // One pass, so "&amp;nbsp;" becomes the text "&nbsp;" and isn't decoded twice.
  return s.replace(/&(#[0-9]{1,7}|#x[0-9a-fA-F]{1,6}|[a-zA-Z]{2,8});/g, (whole, name) => {
    const n = name.toLowerCase();
    if (n === "amp") return "&";
    if (n in NAMED_ENTITIES) return NAMED_ENTITIES[n];
    const cp = n.startsWith("#x") ? parseInt(n.slice(2), 16) : n.startsWith("#") ? parseInt(n.slice(1), 10) : NaN;
    return Number.isFinite(cp) && cp <= 0x10FFFF ? String.fromCodePoint(cp) : whole;
  });
}

// Drops HTML tags, comments and <style>/<script>/<head> blocks, decodes entities, collapses whitespace.
export function stripHtml(raw) {
  let s = raw
    .replace(/<!--[\s\S]*?-->/g, " ")
    .replace(/<(style|script|head)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, " ")
    .replace(/<br\s*\/?>/gi, " ")
    .replace(/<\/?(?:p|div|tr|td|th|li|ul|ol|table|tbody|h[1-6])\b[^>]*>/gi, " ")
    .replace(/<\/?[a-z][a-z0-9]*\b[^<>]*>/gi, "");
  s = decodeEntities(s).replace(DIRECTION_MARKS, "");
  return s.replace(/\s+/g, " ").trim();
}

const FOOTER_MARKERS = ["never share", "do not share", "don't share", "don\u2019t share", "for your security", "for security reasons",
  "disclaimer", "this is a system generated", "this is an automated", "this is an auto-generated",
  "please do not reply", "do not reply to this", "unsubscribe", "regards",
  "لا تشارك", "يرجى عدم الرد", "إخلاء المسؤولية", "مع تحيات", "مع أطيب التحيات"];
// Promo blocks that banks put under the alert ("Explore our latest offers… Win a car…").
const PROMO_MARKERS = ["offer", "offers", "win", "reminder", "explore", "terms and conditions", "download",
  "اربح", "عرض", "عروض", "تذكير"];

// A marker as a whole word: English on ASCII word edges ("win" is not inside "WINGSTOP");
// Arabic not inside another word ("عرض" is not inside "معرض"), allowing و / ال / ب / ل in front.
const markerRe = m => ASCII.test(m) ? new RegExp(`(?<![a-z0-9])${esc(m)}(?![a-z0-9])`, "i")
  : new RegExp(`(?<![\\p{L}\\p{N}])(?:و?ال|و|ب|ل)?${esc(m)}`, "iu");

// Plain text of an email body without the bank's banners, footer and promos (mirrors MessageText.emailBody):
// - after the transaction amount (the first one that isn't a balance), cut at the earliest footer or promo marker;
// - before it, drop whole sentences that hold a marker ("For your security, never share your OTP."),
//   but never the sentence the amount is in, so a banner can't hide the transaction.
export function emailBody(raw) {
  const text = normalize(stripHtml(raw));
  const amounts = allAmounts(text);
  const anchor = amounts.find(a => !precededByBalance(a, text)) || amounts[0];
  if (!anchor) return text;
  const markers = [...FOOTER_MARKERS, ...PROMO_MARKERS].map(markerRe);
  const hasMarker = s => markers.some(re => re.test(s));
  const rest = text.slice(anchor.end);
  let cut = rest.length;
  for (const re of markers) {
    const i = rest.search(re);
    if (i >= 0 && i < cut) cut = i;
  }
  // The last piece is the start of the amount's own sentence; it is always kept.
  const before = sentences(text.slice(0, anchor.start));
  const own = before.pop();
  const kept = [...before.filter(s => !hasMarker(s)), own + text.slice(anchor.start, anchor.end + cut)];
  return kept.join(" ").replace(/ +/g, " ").replace(/^[ \-|]+|[ \-|]+$/g, "");
}

// Splits after ".", "!" or "?" followed by a space ("AED 10.00" is not a sentence end).
// The last element is whatever follows the last sentence end, possibly empty.
const sentences = s => s.replace(/([.!?])\s+/g, "$1\u0001").split("\u0001");

// An email arrives with a subject, an address as sender, or HTML in the body.
export function looksLikeEmail(body, sender, subject) {
  if (subject && subject.trim()) return true;
  if (sender && sender.includes("@")) return true;
  return /<\/?(?:html|body|div|p|br|table|td|span)\b/i.test(body);
}

// Mirrors MessageReader.read in Swift: what "Paste a message" previews is exactly what Save logs.
export function readMessage(message, sender = null, subject = null) {
  const isEmail = looksLikeEmail(message, sender, subject);
  const text = isEmail ? emailBody(message) : stripHtml(message);
  const subj = (subject || "").trim();
  if (subj && isIgnorable(subj)) return { parsed: null, text, isEmail };
  let parsed = parse(text, sender);
  if (!parsed && subj) parsed = parse(subj + ". " + text, sender);
  return { parsed, text, isEmail };
}
