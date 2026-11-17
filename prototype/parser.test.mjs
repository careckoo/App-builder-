// Run with: node prototype/parser.test.mjs
// Same cases as MasroofiCore/Tests/MasroofiCoreTests/BankMessageParserTests.swift.
import assert from "node:assert/strict";
import { parse, categorize } from "./parser.js";

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
  ["Cash deposit ('pos' inside 'deposit')", "Cash deposit of AED 500.00 via CDM at ADCB MUSAFFAH", null,
    { amount: 500, kind: "income" }, "income"],
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
];
for (const msg of ignored) {
  if (parse(msg) === null) { pass++; console.log("✓ ignored:", msg.slice(0, 40)); }
  else console.log("✗ should ignore:", msg, JSON.stringify(parse(msg)));
}
const total = cases.length + ignored.length;
console.log(`\n${pass}/${total} passed`);
process.exit(pass === total ? 0 : 1);
