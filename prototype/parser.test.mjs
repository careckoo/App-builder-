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
