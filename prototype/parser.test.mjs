// Run with: node prototype/parser.test.mjs
// Same cases as MasroofiCore/Tests/MasroofiCoreTests/BankMessageParserTests.swift.
import assert from "node:assert/strict";
import { parse, categorize, stripHtml, emailBody } from "./parser.js";

const cases = [
  ["FAB English purchase",
    "Card ending 1234 was used for AED 45.50 at CARREFOUR,ABU DHABI AE on 17/11/2026 10:22. Available balance AED 5,230.10", "FAB",
    { amount: 45.5, currency: "AED", kind: "purchase", merchant: "CARREFOUR", cardLast4: "1234", balanceAfter: 5230.1 }, "groceries"],
  ["Credit card, no space",
    "Your Cr.Card XXX5678 was used for AED125.00 on 17/11/2026 at TALABAT,DUBAI. Avl Cr. limit is AED 12,000.00", null,
    { amount: 125, kind: "purchase", merchant: "TALABAT", cardLast4: "5678" }, "delivery"],
  ["Arabic purchase, Arabic digits",
    "تم خصم مبلغ ٤٥٫٥٠ درهم من بطاقتك المنتهية ب ١٢٣٤ لدى كارفور بتاريخ ١٧/١١/٢٠٢٦. الرصيد المتاح ٥٬٢٣٠٫١٠ درهم", null,
    { amount: 45.5, kind: "purchase", merchant: "كارفور", cardLast4: "1234", balanceAfter: 5230.1 }, "groceries"],
  ["Salary credit", "AED 18,500.00 has been credited to your account XXX9012 (Salary). Avl Bal AED 20,100.00", null,
    { amount: 18500, kind: "income", merchant: "Salary" }, "income"],
  ["Arabic salary", "تم إيداع راتب بمبلغ 18,500.00 درهم في حسابك رقم ***9012", null, { amount: 18500, kind: "income" }, "income"],
  ["ATM", "AED 500.00 withdrawn from your account XXX9012 at ATM ADCB MUSAFFAH on 17-11-2026. Avl Bal AED 3,600.00", null,
    { kind: "withdrawal", amount: 500 }, "cash"],
  ["Foreign currency", "Purchase of USD 15.49 with Debit Card ending 4321 at NETFLIX.COM. Avl Balance is AED 4,100.00.", null,
    { currency: "USD", amount: 15.49, merchant: "NETFLIX.COM", cardLast4: "4321" }, "subscriptions"],
  ["Refund", "Refund of AED 89.00 from NOON.COM has been credited to your card ending 1234.", null,
    { kind: "refund", amount: 89, merchant: "NOON.COM" }, "income"],
  ["Transfer out", "AED 1,000.00 transferred to AHMED ALI from your account XXX9012 on 17/11/2026.", null,
    { kind: "transferOut", merchant: "AHMED ALI" }, "transfer"],
  ["Merchant containing 'bal'", "Card ending 1234 was used for AED 60.00 at GLOBAL VILLAGE on 17/11/2026. Avl Bal AED 900.00", null,
    { merchant: "GLOBAL VILLAGE", balanceAfter: 900 }, "other"],
  ["Arabic fuel", "عملية شراء بقيمة 120.00 د.إ بالبطاقة رقم 4455 عند أدنوك 512. رصيدك 2,000.00 د.إ", null,
    { amount: 120, kind: "purchase", cardLast4: "4455" }, "fuel"],
  // Short English keywords must match whole words only.
  // Cash put into a CDM was already counted when it was withdrawn: between your own accounts, not income.
  ["Cash deposit ('pos' inside 'deposit') is ownTransfer", "Cash deposit of AED 500.00 via CDM at ADCB MUSAFFAH", null,
    { amount: 500, kind: "ownTransfer", merchant: null }, "transfer"],
  ["Dental treatment ('atm' inside 'treatment')", "Card ending 1234 was used for AED 350.00 at DENTAL TREATMENT CLINIC on 17/11/2026", null,
    { amount: 350, kind: "purchase", merchant: "DENTAL TREATMENT CLINIC" }, "health"],
  ["Merchant starting with a number", "Card ending 1234 was used for AED 12.00 at 7 ELEVEN", null,
    { amount: 12, kind: "purchase", merchant: "7 ELEVEN" }, "other"],
  ["'liv' inside a word is not Liv bank", "Card ending 1234 was used for AED 25.00 at DELIVEROO on 17/11/2026. Order delivered.", null,
    { kind: "purchase", merchant: "DELIVEROO", bank: null }, "delivery"],
  ["Mobile recharge ('paid' inside 'prepaid' no longer counts)",
    "Your du prepaid number was recharged with AED 50.00 using card ending 1234 at DU ONLINE on 17/11/2026", null,
    { amount: 50, kind: "purchase", merchant: "DU ONLINE", cardLast4: "1234" }, "telecom"],
  ["Card payment at a merchant is a purchase", "Your card payment of AED 30.00 at STARBUCKS was successful", null,
    { amount: 30, kind: "purchase", merchant: "STARBUCKS" }, "dining"],
  // Real messages (one UAE bank, Nov 2026), verbatim.
  ["Real: credit-card bill payment",
    "Dear Customer, your payment of AED2000.00 on 13/11/2026 for card ending with *197 has been credited. Thank you", null,
    { amount: 2000, currency: "AED", kind: "cardPayment", merchant: null, cardLast4: "197" }, "transfer"],
  ["Real: Trx etisalat",
    "Trx. of AED50.00 on your card ending *822 at etisalat Digital App, UAE is Approved. Avl. card bal is 4852.54. Trx Date: 16/11/26 15:38", null,
    { amount: 50, currency: "AED", kind: "purchase", merchant: "etisalat Digital App", cardLast4: "822", balanceAfter: 4852.54 }, "telecom"],
  ["Real: Trx Carrefour",
    "Trx. of AED10.79 on your card ending *822 at CARREFOUR HYPERMARKET, UAE is Approved. Avl. card bal is 4902.54. Trx Date: 16/11/26 13:12", null,
    { amount: 10.79, kind: "purchase", merchant: "CARREFOUR HYPERMARKET", cardLast4: "822", balanceAfter: 4902.54 }, "groceries"],
  ["Real: Trx Cravia",
    "Trx. of AED34.00 on your card ending *822 at CRAVIA INC LLC, UAE is Approved. Avl. card bal is 4913.33. Trx Date: 16/11/26 13:09", null,
    { amount: 34, kind: "purchase", merchant: "CRAVIA INC LLC", cardLast4: "822", balanceAfter: 4913.33 }, "other"],
  // B1: "at" before a date, a phone number or "us" doesn't turn a card bill payment into a purchase.
  ["B1 card payment 'credited at <date>'", "Your payment of AED 2,000.00 has been credited at 16/11/26 15:38 for card ending 5678.", null,
    { kind: "cardPayment", amount: 2000, merchant: null }, "transfer"],
  ["B1 card payment 'call us at <phone>'", "Dear Customer, your payment of AED2000.00 for card ending with *197 has been credited. For queries call us at 600 50 3335", null,
    { kind: "cardPayment", cardLast4: "197" }, "transfer"],
  ["B1 card payment 'banking with us at ADCB'", "Your payment of AED 2,000.00 for your credit card ending 5678 has been received. Thank you for banking with us at ADCB.", null,
    { kind: "cardPayment" }, "transfer"],
  // B2: card-bill wordings.
  ["B2 debited towards credit card payment", "AED 2,000.00 has been debited from your account XXX9012 towards your credit card payment.", null, { kind: "cardPayment", amount: 2000 }, "transfer"],
  ["B2 payment received towards credit card", "Payment of AED 2,000.00 received towards your credit card ending 5678", null, { kind: "cardPayment", cardLast4: "5678" }, "transfer"],
  ["B2 thank you for your payment to your credit card", "Thank you for your payment of AED 2,000.00 to your credit card", null, { kind: "cardPayment" }, "transfer"],
  ["B2 paid to your credit card", "AED 2,000 paid to your credit card ending 5678", null, { kind: "cardPayment" }, "transfer"],
  ["B2 credit card payment has been received", "Your Credit card XXX5678 payment of AED 2000 has been received", null, { kind: "cardPayment" }, "transfer"],
  ["B2 credited to your credit card", "AED 2,000.00 credited to your credit card ending 5678", null, { kind: "cardPayment" }, "transfer"],
  ["B2 payment towards card credited", "Payment of AED 2000 towards card ending 5678 credited.", null, { kind: "cardPayment" }, "transfer"],
  ["B2 Arabic تم سداد لبطاقتك", "تم سداد مبلغ 2000 درهم لبطاقتك", null, { kind: "cardPayment", amount: 2000 }, "transfer"],
  // B3/B4: between your own accounts.
  ["B3 from your account to your account", "AED 5,000.00 transferred from your account XXX9012 to your account XXX3456 on 17/11/2026.", null, { kind: "ownTransfer", merchant: null }, "transfer"],
  ["B3 own account", "AED 1,000.00 transferred to own account XXX3456", null, { kind: "ownTransfer" }, "transfer"],
  ["B3 Arabic من حسابك إلى حسابك", "تم تحويل مبلغ 1,000 درهم من حسابك 9012 إلى حسابك 3456", null, { kind: "ownTransfer", amount: 1000 }, "transfer"],
  ["B4 fixed deposit matured", "Your Fixed Deposit of AED 10,000.00 has matured and been credited to your account XXX9012.", null, { kind: "ownTransfer" }, "transfer"],
  ["B4 new fixed deposit", "AED 10,000.00 debited from your account XXX9012 for a new Fixed Deposit.", null, { kind: "ownTransfer", merchant: null }, "transfer"],
  ["B4/W1 Saving Space", "AED 500.00 moved to your Saving Space Holiday.", null, { kind: "ownTransfer" }, "transfer"],
  ["B4/W1 transfer to savings account", "AED 2,000.00 transferred to your savings account XXX7777.", null, { kind: "ownTransfer" }, "transfer"],
  ["Salary into a savings account stays income", "AED 18,500.00 salary credited to your savings account XXX7777.", null, { kind: "income" }, "income"],
  // B7: balance markers are whole words.
  ["B7 BALI RESTAURANT", "Purchase at BALI RESTAURANT AED 120.00", null, { kind: "purchase", amount: 120, merchant: "BALI RESTAURANT" }, "dining"],
  ["B7 GLOBAL VILLAGE before amount", "Trx at GLOBAL VILLAGE AED 50.00 approved", null, { amount: 50, merchant: "GLOBAL VILLAGE" }, "other"],
  ["B7 UNLIMITED BURGERS", "Purchase at UNLIMITED BURGERS for AED 50.00", null, { amount: 50, merchant: "UNLIMITED BURGERS" }, "other"],
  ["B7 FONDUE HOUSE", "Purchase at FONDUE HOUSE for AED 50.00", null, { amount: 50, merchant: "FONDUE HOUSE" }, "other"],
  // B8: categoriser keywords are whole words (with a plural/possessive "s").
  ["B8 NOVOTEL is not novo cinema", "Card ending 1234 was used for AED 50.00 at NOVOTEL ABU DHABI", null, { merchant: "NOVOTEL" }, "other"],
  ["B8 AFTERNOON TEA is not noon", "Card ending 1234 was used for AED 50.00 at AFTERNOON TEA LOUNGE", null, {}, "other"],
  ["B8 MASTER BAKERS is not aster", "Card ending 1234 was used for AED 50.00 at MASTER BAKERS", null, {}, "other"],
  ["B8 PALACE DOWNTOWN is not ace", "Card ending 1234 was used for AED 50.00 at PALACE DOWNTOWN", null, {}, "other"],
  ["B8 MCDONALD'S", "Card ending 1234 was used for AED 50.00 at MCDONALD'S", null, {}, "dining"],
  ["B8 apple.com still works", "Card ending 1234 was used for AED 50.00 at APPLE.COM/BILL", null, {}, "subscriptions"],
  ["B8 h&m still works", "Card ending 1234 was used for AED 50.00 at H&M", null, {}, "shopping"],
  ["B8 itc without trailing space", "Card ending 1234 was used for AED 50.00 at ITC", null, {}, "transport"],
];

let pass = 0;
for (const [name, msg, sender, expected, cat] of cases) {
  const t = parse(msg, sender);
  try {
    assert.ok(t, "parsed");
    for (const [k, v] of Object.entries(expected)) assert.equal(t[k], v, `${k}`);
    assert.equal(categorize(t), cat, "category");
    pass++; console.log("✓", name);
  } catch (e) { console.log("✗", name, "—", e.message, JSON.stringify(t)); }
}

const ignored = [
  "Your OTP for AED 45.50 at AMAZON is 482913. Do not share it with anyone.",
  "رمز التحقق الخاص بك هو 482913 لعملية بقيمة 45.50 درهم",
  "Transaction of AED 300.00 at ZARA declined due to insufficient balance.",
  "Dear customer, your card has been delivered.",
  // A6/W2: reminders and statements, no money moved.
  "Minimum payment due AED 250.00 on your card ending 5678. Please pay by 05/12/2026.",
  "Reminder: your Tabby payment of AED 200.00 is due on 20/11/2026.",
  "Your credit card statement is ready. Statement balance AED 5,000.00, minimum due AED 250.00, due date 05/12/2026.",
  "Your credit card payment of AED 2,000.00 is due on 25/11/2026.",
  "تذكير: يرجى سداد الحد الأدنى 250 درهم لبطاقتك",
  "Your credit limit has been increased to AED 20,000.00",
  // W3: prize draws.
  "اربح جوائز قيمة! استخدم بطاقتك بقيمة 100 درهم وادخل السحب",
  "ادخل السحب على جوائز بقيمة 50,000 درهم عند استخدام بطاقتك",
];
for (const msg of ignored) {
  if (parse(msg) === null) { pass++; console.log("✓ ignored:", msg.slice(0, 40)); }
  else console.log("✗ should ignore:", msg, JSON.stringify(parse(msg)));
}

// Other checks: [name, fn] where fn throws on failure.
const checks = [
  ["B9 learned: exact name wins", () => assert.equal(categorize({ kind: "purchase", merchant: "CAFE X" }, { "cafe x": "family", "cafe": "dining" }), "family")],
  ["B9 learned: longest whole-word name wins", () => assert.equal(categorize({ kind: "purchase", merchant: "AL MAYA SUPERMARKET MARINA" },
    { "al maya": "dining", "al maya supermarket": "family" }), "family")],
  ["B9 learned: not inside another word", () => assert.equal(categorize({ kind: "purchase", merchant: "NOVOTEL" }, { "novo": "entertainment" }), "other")],
  ["W7 sender as a whole word", () => assert.equal(parse("Card ending 1234 was used for AED 10.00 at X", "AD-ADCB").bank.en, "ADCB")],
  ["W7 sender exact", () => assert.equal(parse("Card ending 1234 was used for AED 10.00 at X", "ADCBAlert").bank.en, "ADCB")],
  ["W7 sender not inside another name", () => assert.equal(parse("Card ending 1234 was used for AED 10.00 at X", "FABULOUSCO").bank, null)],
  ["Email: stripHtml", () => assert.equal(
    stripHtml("<html><head><style>p{color:red}</style></head><body><p>Dear&nbsp;Customer,</p><br/>Your card ending 1234 was used for <b>AED&nbsp;45.50</b> at H&amp;M<br>on 17/11/2026 10:22.</body></html>"),
    "Dear Customer, Your card ending 1234 was used for AED 45.50 at H&M on 17/11/2026 10:22.")],
  ["Email: numeric entities and AED < 50 stay", () => assert.equal(stripHtml("Caf&#233; &#x41;ED &lt;50&gt; and AED < 50"), "Café AED <50> and AED < 50")],
  ["Email: &amp;nbsp; decoded once", () => assert.equal(stripHtml("A&amp;nbsp;B"), "A&nbsp;B")],
  ["Email: transaction alert parses, footer about OTP dropped", () => {
    const body = "<div>Transaction alert</div><p>Dear Customer,<br>Your Credit Card ending 5678 was used for AED&nbsp;125.00 at TALABAT,DUBAI on 17/11/2026 10:22.<br>Available limit AED 12,000.00</p>" +
      "<p>For your security, never share your OTP or PIN with anyone.</p><p>Regards,<br>Your Bank</p>";
    const text = emailBody(body);
    assert.ok(!/otp/i.test(text), text);
    const t = parse(text, "alerts@adcb.com");
    assert.equal(t.amount, 125); assert.equal(t.merchant, "TALABAT"); assert.equal(t.kind, "purchase"); assert.equal(t.bank.en, "ADCB");
  }],
  ["Email: OTP email is still skipped", () => assert.equal(parse(emailBody("<p>Your OTP for AED 45.50 at AMAZON is 482913. Do not share it.</p>")), null)],
  ["Email: security banner before the amount is kept", () => assert.equal(emailBody("For your security, check alerts. AED 10.00 debited at X"), "For your security, check alerts. AED 10.00 debited at X")],
];
for (const [name, fn] of checks) {
  try { fn(); pass++; console.log("✓", name); } catch (e) { console.log("✗", name, "—", e.message); }
}

const total = cases.length + ignored.length + checks.length;
console.log(`\n${pass}/${total} passed`);
process.exit(pass === total ? 0 : 1);
