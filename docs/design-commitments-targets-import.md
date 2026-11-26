# Khurda · خردة — Design spec: accounts, commitments, daily targets, goals, statement import

Status: design spec for the ios-engineer · 2026-11-26 · owner: ux-designer
Scope: iOS 17, SwiftUI + SwiftData, Xcode 15.4. Everything runs on the device: no network, no cloud AI,
no Apple Foundation Models. No third-party packages (the project has none today; keep it that way).
Amounts are AED, shown `AED 1,250`, always left-to-right in both languages (wrap in LTR isolates in Arabic).

Glossary additions (extends `docs/PRODUCT_SPEC.md` §1):

| English | Gulf Arabic | Notes |
|---|---|---|
| Accounts & cards | «حساباتك وبطاقاتك» | Settings row |
| Commitments | «الالتزامات» | Replaces "Fixed bills" «الفواتير الثابتة» as the section name |
| What you usually spend | «مصروفك المعتاد» | The baseline. Never say "baseline" in the UI |
| Daily target | «هدفك اليومي» | Planned per-day amount. "Safe to spend today" stays the live number |
| Expected to save | «المتوقع تحوّشه» | |
| Ways to save | «طرق توفّر فيها» | Potential savings |
| Import a statement | «استورد كشف حساب» | |

---

## 0. Where things live (the 5 tabs stay)

| Tab | Change |
|---|---|
| **Today** «اليوم» | No new UI. The ring keeps showing Safe to spend. If the person accepted a daily target, the ring's allowance equals it at the start of the cycle (see §3.5). |
| **Activity** «الحركات» | Toolbar button **Import** (`square.and.arrow.down`) opens the import flow (§5). Account filter chips above the list ("All · ADCB ••1234 · FAB card ••9876"). Transaction detail gets an **Account** row (picker). |
| **Insights** «نظرة» | Two new cards after "Will your salary last?": **What you usually spend** (per-category baseline, §3.1) and **Ways to save** (§3.4). |
| **Plan** «الخطة» | New top card **Your month** (§3.3). Sections become: Your month · **Commitments** (merges Fixed bills + Jameya, §2) · Savings goals (deadline maths, §4) · Budgets. |
| **Settings** «الإعدادات» | New top section **Your money**: Income, Payday, Accounts & cards (§1). New section **Data**: Import a statement, Past imports (undo), Export to CSV (moved). |

Existing `SettingsView` salary fields (income, payday, savings) move into the new screens; "Save each month" becomes **Extra to save each month** «توفير إضافي كل شهر» (it is what "Use this target" writes, §3.5).

---

## 1. Settings: income, payday, accounts & cards

### 1.1 Data model (all in `Khurda/Models/Models.swift`, which the widget also compiles)

```swift
/// A bank account or card the person owns. Messages and statement rows are attributed to one.
@Model final class Account {
    var id: UUID = UUID()
    var bankID: String = ""            // BankDirectory id ("adcb"), or "other"
    var customBankName: String = ""    // when bankID == "other"
    var nickname: String = ""          // "Salary", "Cashback card"; empty → "<Bank> ••1234"
    var typeRaw: String = AccountType.current.rawValue   // KhurdaCore.AccountType
    var last4: String = ""             // digits only, 3–4 (ADIB sends 3); empty = unknown
    var otherEndingsRaw: String = ""   // "4567,890": a debit card ending + the account ending, supplementary cards
    var isSalaryAccount: Bool = false
    var isArchived: Bool = false       // closed card: kept so old transactions keep their label
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    @Relationship(deleteRule: .nullify, inverse: \Transaction.account) var transactions: [Transaction]? = []
}

/// Salary, housing allowance, rent from a flat, pension, side income.
@Model final class IncomeSource {
    var name: String = ""
    var amount: Decimal = 0            // monthly (or per occurrence for non-monthly)
    var kindRaw: String = "salary"     // salary, allowance, rental, pension, business, support, other
    var dayOfMonth: Int = 27           // 1–31; the salary's day IS the payday
    var isRegular: Bool = true         // false = "sometimes": not counted in the plan, only when it arrives
    var accountID: UUID?               // where it lands (helps salary detection)
    var createdAt: Date = Date.now
}
```

`Transaction` gains: `var account: Account?` (relationship), `var commitment: Obligation?` (relationship, see §2),
`var importBatchID: UUID?`, `var postedAmountAED: Decimal?` (statement's real AED amount for an FX purchase).

`AppSettings` gains `household` ("single" | "couple" | "family"; default "single") and `ownsCar` (Bool?, nil = unknown).
`AppSettings.monthlyIncome` stays as a **cache** = Σ regular `IncomeSource.amount` (the widget and intent read it), rewritten whenever incomes change. `AppSettings.payday` = the `dayOfMonth` of the income marked salary (first salary if several).

Schema: add `Account`, `IncomeSource`, `ImportBatch` (§5.1) to `Store.schema`. All changes are additive with defaults, so SwiftData lightweight migration handles them (check on device, UNFORGET S13).

**One-time migration** (in `KhurdaApp.task`, guarded by `defaults["didMigrateAccounts"]`):
1. If no `IncomeSource` and `monthlyIncome > 0` → insert `IncomeSource(name: "Salary", amount: monthlyIncome, dayOfMonth: payday, kind: salary)`.
2. If no `Account`: group existing transactions by (bankName, cardLast4); for each group with ≥ 2 transactions insert an `Account` (type `.current`, or `.creditCard` if any `cardPayment` was seen *to* that ending) and set `tx.account`. Bank-only groups (no ending) → one account per bank with empty last4.

### 1.2 KhurdaCore: `Accounts.swift`

```swift
public enum AccountType: String, Codable, CaseIterable, Sendable { case current, savings, creditCard, prepaid, bnpl }

public struct AccountRef: Sendable, Equatable {
    public let id: String; public let bankID: String?; public let type: AccountType
    public let endings: [String]; public let isSalary: Bool
}

public enum AccountMatch: Equatable, Sendable {
    case matched(id: String, sure: Bool)
    case ambiguous([String])
    case unknown(bankID: String?, ending: String?)   // feeds the "Is this yours?" prompt
}

public enum AccountMatcher {
    /// Digits only (Arabic-Indic converted), keep the last 4. nil when fewer than 3 digits.
    public static func normalizeEnding(_ s: String?) -> String?
    /// Suffix compare on the shorter length (≥ 3): "123" matches "0123"; "1234" ≠ "1235".
    public static func endingsMatch(_ a: String, _ b: String) -> Bool
    public static func match(bankID: String?, ending: String?, kind: TransactionKind,
                             among accounts: [AccountRef]) -> AccountMatch
}
```

Add to `BankDirectory`: `bank(sender:body:) -> Bank?` (the existing `bankName` becomes `bank(...)?.nameEN`), `bank(id:)`, `bank(named:)` (matches nameEN, nameAR, senderIDs as whole words; used by import).

**Attribution rules** (`match`), first hit wins:
1. `ending` present and exactly one account (not archived) has a matching ending **and** the same bank (or account bank unknown) → `.matched(sure: true)`.
2. `ending` present, bank unknown, exactly one account anywhere with that ending → `.matched(sure: true)`.
3. `ending` present but no account has it → `.unknown(bankID, ending)`.
4. No ending, bank known, exactly one account at that bank → `.matched(sure: false)`.
5. No ending, several at that bank: `kind == .income` → the salary account if one; `kind == .cardPayment` → the bank's current account (money left it); otherwise prefer `.current` if exactly one → `.matched(sure: false)`; else `.ambiguous(ids)`.
6. Nothing → `.unknown(bankID, nil)`.

Wired in `TransactionLogger.save` after the transaction is built (SMS, email, Wallet — Wallet passes the card name: match `cardName` text against nickname/bank too). `.ambiguous`/`.unknown` leave `account = nil`.

**Account type effects**
- Credit-card account: a credit *to* it is never income. Parser `income` on a credit-card account → `cardPayment` (neutral) unless the text says refund/reversal (→ `refund`).
- A transfer out whose text contains an ending of another own account → `ownTransfer` (neutral). This delivers PRODUCT_SPEC P9.

**"Is this yours?"** For transactions with `account == nil` and a card ending, group by (bank, ending). When a group reaches 2 transactions, show one banner on Activity:
EN "We've seen card ••1234 from ADCB in 3 messages. Is it yours?" · AR «شفنا بطاقة ••1234 من بنك أبوظبي التجاري في 3 رسايل. هي لك؟» · buttons "Yes, add it" «إيه، ضيفها» / "Not mine" «مو لي» (stores the ending in `defaults["ignoredEndings"]`, never asks again). "Yes" opens the account editor prefilled, then back-fills `account` on those transactions.

### 1.3 Screens

**Settings › Your money** «فلوسك»
```
Income                      AED 21,500 / month  ›
Payday                      27th                ›
Accounts & cards            3                   ›
Who's at home               Just me             ›     (household; feeds §3.1 defaults)
```

**Income** «الدخل» — list of IncomeSources: name, amount, "on the 27th". Footer: "Only regular income counts in your plan. Bonuses and gifts count when they arrive." «الدخل الثابت بس يدخل في خطتك. المكافآت والهدايا تنحسب لما توصل.»
Editor fields: Name · Type (Salary / Housing allowance / Rent you receive / Pension / Business / Family support / Other) «راتب / بدل سكن / إيجار يوصلك / تقاعد / تجارة / دعم من الأهل / غيره» · Amount · Day it arrives · "It's regular" toggle «ثابت كل شهر» · Lands in (account picker).
Rule: exactly one income is the salary that sets payday; changing its day updates `AppSettings.payday` (which already protects the cycle from resetting).

**Accounts & cards** «حساباتك وبطاقاتك» — grouped by bank, each row: symbol by type (`building.columns` current, `banknote` savings, `creditcard` credit, `wallet.pass` prepaid, `calendar.badge.clock` BNPL), display name, `••1234` (LTR), "Salary" badge.
Buttons: "Add an account or card" «ضيف حساب أو بطاقة». Swipe: Archive «أرشفة» (not delete, if it has transactions; delete only when empty).
Editor: Bank (searchable list from `BankDirectory`, "Other bank" «بنك ثاني») · Type segmented: Account «حساب» / Savings «توفير» / Credit card «بطاقة ائتمان» / Prepaid «مسبقة الدفع» · Nickname (optional) · Last 4 digits «آخر 4 أرقام» (number pad, 3–4 digits, optional) · More endings (optional, "Debit card number ending, if different" «آخر أرقام بطاقة الخصم لو تختلف») · Salary goes here «الراتب ينزل هنا».
Footer: "Only the last digits, never the full number. They help Khurda tell your cards apart." «بس آخر الأرقام، مو الرقم كامل. تساعد خردة يفرّق بين بطاقاتك.»

**Setup flow** (`SetupFlowView`, step "banks"): keep multi-select banks, then for each selected bank a row of two toggles "Account" / "Credit card" (default Account on) → creates `Account`s with empty last4. The guide (`ShortcutGuideView`) now gets its bank list from `Account` bank IDs. Selected banks are finally persisted (today they live only in `@State`).

---

## 2. Commitments «الالتزامات»

### 2.1 Approach
Keep the `Obligation` class (renaming a `@Model` class is a migration); extend it into a general **commitment**. Keep `Jameya` as its own model (its turn/pot behaviour stays untouched). The UI shows **one list** built from both via a view-level enum:

```swift
enum CommitmentItem: Identifiable { case bill(Obligation), jameya(Jameya) }
```

### 2.2 Data model: fields added to `Obligation`

```swift
var typeRaw: String = CommitmentType.other.rawValue
var frequencyRaw: String = "m"          // "m" monthly · "e3"/"e6"/"e12" every N months · "M9,1,4" given months · "o" once
var firstDue: Date = Date.now           // first (or next) due date; dueDay stays = its day
var instalments: Int = 0                // 0 = open-ended; else total number of payments
var paidCount: Int = 0                  // payments made so far (ticked or matched)
var amountVaries: Bool = false          // DEWA, phone bills: amount is an estimate
var matchKeyword: String = ""           // "dewa", "tabby", landlord name; prefilled from the type
var accountID: UUID?                    // pays from / charged to (optional)
var spreadCost: Bool = false            // non-monthly: set aside a share every month (P1, §2.5)
var setAside: Decimal = 0               // P1: money already put aside for the next payment
var lastSetAsideCycle: Date?            // P1
var createdAt: Date = Date.now
var isFinished: Bool { instalments > 0 && paidCount >= instalments }
```
`isPaidThisCycle`, `title`, `amount`, `dueDay`, `categoryRaw` keep their meaning. Old rows default to monthly, open-ended, type `.other` → behaviour unchanged.

### 2.3 KhurdaCore: `Commitments.swift`

```swift
public enum CommitmentType: String, CaseIterable, Sendable {
    case rent, loan, carLoan, creditCard, schoolFees, telecom, utilities, insurance, bnpl,
         familySupport, subscription, domesticWorker, jameya, charity, other
    public var nameEN: String; public var nameAR: String; public var symbol: String
    public var category: CategoryID          // for matching + charts
    public var defaultFrequency: Frequency
    public var keywords: [String]            // match hints
    public var amountVaries: Bool
    public var asksInstalments: Bool         // loan, carLoan, bnpl, creditCard(EPP)
}

public enum Frequency: Equatable, Sendable {
    case monthly, everyMonths(Int), months([Int]), once
    public init?(raw: String); public var raw: String
    public var paymentsPerYear: Decimal      // 12, 12/N, months.count, 0
}

public struct CommitmentSchedule: Sendable {
    public init(amount: Decimal, frequency: Frequency, firstDue: Date, instalments: Int /*0 = open*/)
    /// 1-based. nil when beyond `instalments`.
    public func dueDate(index: Int, calendar: Calendar = .dubai) -> Date?
    /// (index, date) pairs with date in [from, to).
    public func dues(from: Date, to: Date, calendar: Calendar = .dubai) -> [(index: Int, date: Date)]
    public var lastDue: Date?                // nil when open-ended
    public func next(after: Date) -> (index: Int, date: Date)?
    /// Smoothed monthly cost, for plans and goal affordability.
    public func monthlyEquivalent(on date: Date, paidCount: Int) -> Decimal
    public func remaining(paidCount: Int) -> (payments: Int, amount: Decimal)?   // nil when open-ended
}
```

Type table (defaults the editor prefills):

| Type | EN | AR | Category | Frequency | Keywords | Varies | Instalments |
|---|---|---|---|---|---|---|---|
| rent | Rent | «إيجار» | family | every 3 months* | — (asks landlord name) | no | no |
| loan | Loan instalment | «قسط قرض» | installments | monthly | "loan", "قرض", "pl " | no | yes |
| carLoan | Car loan | «قسط السيارة» | installments | monthly | "auto loan", "car loan" | no | yes |
| creditCard | Card instalment plan | «أقساط البطاقة» | installments | monthly | "epp", "ipp", "instalment" | no | yes |
| schoolFees | School fees | «رسوم المدرسة» | education | months [9,1,4] | "school", "مدرسة", "academy" | no | no |
| telecom | Phone & internet | «جوال وإنترنت» | telecom | monthly | "etisalat", "e&", "du", "virgin mobile" | yes | no |
| utilities | Electricity & water | «كهرباء وماء» | bills | monthly | "dewa", "addc", "aadc", "taqa", "sewa", "fewa", "empower", "tabreed" | yes | no |
| insurance | Insurance | «تأمين» | other | yearly | "insurance", "تأمين", "takaful" | no | no |
| bnpl | Tabby / Tamara | «تابي وتمارا» | installments | monthly | "tabby", "tamara", "postpay", "تابي", "تمارا" | no | yes (default 4) |
| familySupport | Family support | «مصروف الأهل» | family | monthly | — | no | no |
| subscription | Subscription | «اشتراك» | subscriptions | monthly | merchant name | no | no |
| domesticWorker | Domestic worker salary | «راتب العاملة» | family | monthly | — | no | no |
| jameya | Jameya | «جمعية» | transfer | → opens `JameyaEditor` | — | — | — |
| charity | Charity / sadaqah | «صدقة» | charity | monthly | "red crescent", "dar al ber" | no | no |
| other | Something else | «غيره» | other | monthly | — | no | no |

*UAE rent is usually 1–4 cheques a year; the editor asks "How many cheques a year?" «كم شيك بالسنة؟» (1/2/4/6/12) → `everyMonths(12/n)`.

"Credit card minimum" is deliberately offered as **Card instalment plan** (EPP/IPP). Card purchases already count as spending when made, and paying the card bill is neutral (`cardPayment`); adding the card's whole bill as a commitment would count the money twice. Editor footer for this type: "Only for an instalment plan or an old balance you're paying off. Everyday card spending is already counted." «بس لخطة تقسيط أو رصيد قديم تسدده. مصروف البطاقة اليومي محسوب أصلًا.»

**Due-date maths** (`dueDate(index:)`), with `calendar = .dubai`, day clamped to month length like `JameyaSchedule`:
- monthly: `firstDue + (i−1) months`
- everyMonths(N): `firstDue + (i−1)·N months`
- months(list): the i-th date ≥ firstDue whose month ∈ list, day = firstDue's day
- once: i == 1 only
- If `instalments > 0` and `i > instalments` → nil. `lastDue = dueDate(index: instalments)`.

**Monthly equivalent** (used by §3.3 and §4, never for "what to set aside this cycle"):
```
finished or lastDue < date      → 0
monthly                         → A
everyMonths(N)                  → A / N
months(list)                    → A · list.count / 12
once                            → A / max(1, paydays from today to the due date)  (0 if already paid)
```

**Reserve this cycle** (replaces the `fixedUnpaid` term in `SafeToSpendCalculator.numbers`):
```
dueNow  = schedule.dues(from: cycle.start, to: cycle.end).filter { $0.index > paidCount_atCycleStart }
reserve = isFinished || isPaidThisCycle ? 0 : amountEstimate × dueNow.count
amountEstimate = amountVaries ? median(last 3 matched payments) ?? amount : amount
```
Monthly commitments reserve every cycle exactly as today. Non-monthly reserve only in the cycle they fall due (until P1 spread). Add a heads-up one cycle earlier in Insights "Coming up": "Insurance AED 2,400 is due next cycle" «التأمين 2,400 درهم موعده الدورة الجاية».

**Matching a payment** (generalises `matchingObligation`; pure part in KhurdaCore):
```swift
public enum CommitmentMatcher {
    public struct Candidate: Sendable { public let id: String; title: String; amount: Decimal; amountVaries: Bool
        category: CategoryID; keywords: [String]; accountID: String?; dueDates: [Date] }
    public static func match(amountAED: Decimal, merchant: String, category: CategoryID,
                             accountID: String?, date: Date, among: [Candidate]) -> String?
}
```
A candidate matches when **all** hold:
1. Amount: fixed → `|Δ| ≤ max(5, 2% of amount)`; varies → `0.5·est ≤ amount ≤ 1.6·est` **and** a keyword/title hit is required.
2. Identity: a keyword or the title appears as a whole word in the merchant (`TextMatch.containsWord`), **or** same category.
3. Account: if both sides have an account and they differ → no match.
4. Date: within ±10 days of a due date that is not yet paid (same window as jameya).
Several candidates → prefer keyword hit, then smallest |Δ amount|.
On match: `isPaidThisCycle = true`, `paidCount += 1`, `tx.isFixedObligation = true`, `tx.commitment = bill`. Ticking by hand does the same; unticking decrements `paidCount` (min 0) and clears the link.
CycleReset already unticks on payday; it must not touch `paidCount`.

When `paidCount` reaches `instalments`: local notification + Plan banner
EN "Your car loan is done! AED 1,850 a month is free from next payday." · AR «خلص قسط السيارة! من الراتب الجاي عندك 1,850 درهم زيادة كل شهر.»
Finished commitments move to a collapsed "Finished" «خلصت» group; keep them for history.

Reminders: `Reminders.upcoming` uses `schedule.next(after:)` instead of `dueDay` so quarterly and yearly items remind correctly.

### 2.4 Screens

**Plan › Commitments** (replaces "Jameya" and "Fixed bills" sections)
```
COMMITMENTS                                  AED 7,450 this cycle
[house]  Rent · 4 cheques           AED 15,000   Due 1 Jan      ○
[car]    Car loan                   AED 1,850    18 of 48 · ends Mar 2029   ✓
[bolt]   DEWA · about               AED 620      Due 12th       ○
[3 ppl]  Office jameya              AED 1,000    Your turn in 3 months  ✓   (existing JameyaRow)
[cal]    Tabby · Noon               AED 112      2 of 4 · ends Jan 2027  ○
+ Add a commitment
Finished (2) ›
```
Row anatomy: symbol, title, sub-line (frequency or "n of N · ends Month Year" or jameya phase), amount (prefix "about" «تقريبًا» when `amountVaries`), paid state (○ / ✓ tappable to tick by hand). Rows not due this cycle are dimmed with "Next: 1 Jan" «الجاي: 1 يناير». Sort: due this cycle & unpaid first, by date; then paid; then not due.
Footer: "Set aside before your daily amount is worked out, and ticked off when the bank message arrives." «تنحسب قبل مصروفك اليومي، وتتأشّر لحالها لما توصل رسالة البنك.»

**Add a commitment** — step 1, a grid of type tiles (symbol + name, the table above). Jameya → existing `JameyaEditor`. Others → step 2 form:
- Name «الاسم» (prefilled with the type name)
- Amount «المبلغ» · toggle "Amount changes each time" «المبلغ يتغيّر كل مرة» (on by default for utilities/telecom)
- How often «كل قدّيش؟»: Monthly «كل شهر» / Every 3 months «كل 3 شهور» / Every 6 months «كل 6 شهور» / Yearly «كل سنة» / Choose months «أشهر معيّنة» (month chips) / One payment «دفعة وحدة»
- Next payment «الدفعة الجاية» (date picker; sets `firstDue`, `dueDay`)
- If `asksInstalments`: "Fixed number of payments" «عدد دفعات محدّد» toggle → Payments left «الدفعات الباقية» stepper, showing "Last payment: March 2029" «آخر دفعة: مارس 2029». (Entered as "left" because that is what people know; store `instalments = left + paidCount(0)`, `firstDue = next payment`.)
- Paid from «تندفع من» (account picker, optional)
- Recognise it by «نعرفه من» (keyword, prefilled; footer "A word from the bank message, e.g. DEWA" «كلمة من رسالة البنك، مثل DEWA»)
- (P1) Spread the cost «وزّعها على الشهور» for non-monthly

Detail screen: header amount + schedule, list of past payments (linked transactions), "Mark this cycle as paid" «دفعتها هالدورة», Edit, Delete «حذف» (confirm: "Delete this commitment? Past payments stay in Activity." «تبي تحذف الالتزام؟ الدفعات السابقة تبقى في الحركات.»).

**Suggestions** (P2): recurring debits found in history (same cleaned merchant, 2+ times, 26–35 days apart, amount ±10%) → card "Looks like a monthly payment: du AED 349. Add it to commitments?" «شكله دفعة شهرية: du بـ 349 درهم. نضيفه للالتزامات؟»

### 2.5 Spread cost (P1)
For non-monthly commitments with `spreadCost`:
```
m        = paydays from this cycle's start up to the next due date (≥ 1, this cycle included)
reserve  = max(0, ceil((A − setAside) / m))       // per cycle
```
CycleReset: `setAside += reserve(of the cycle that just ended)`; record `lastSetAsideCycle`.
On the payment: the transaction is linked as usual but counts in `fixedPaid` only for `max(0, A − setAside)`; then `setAside = max(0, setAside − A)`.
Row sub-line: "AED 1,200 of 2,400 put aside" «انحاش 1,200 من 2,400 درهم».

---

## 3. Daily life: baseline, daily target, expected savings, ways to save

### 3.1 Baseline («مصروفك المعتاد»)

Input: flexible spending = `isExpense && !isFixedObligation`, kinds purchase/withdrawal/transferOut, from SMS, email, Wallet, manual **and imported statements**. Refunds: subtract a refund from the category of the most recent purchase at the same merchant key within 30 days; otherwise ignore.

Daily-life categories: groceries, dining, delivery, transport, fuel, shopping, health, entertainment, family, cash, other, plus telecom, bills, subscriptions **only when no commitment of that type exists** (otherwise they're already in commitments). Lumpy categories travel, education, charity, transfer are excluded from the baseline and shown separately as "Not counted: travel, school" «ما انحسب: سفر، مدرسة».

```swift
public struct CategorySpend: Sendable { public let category: CategoryID; let merchant: String; let amountAED: Decimal; let date: Date }
public enum Household: String, Sendable { case single, couple, family }

public struct Baseline: Sendable, Equatable {
    public enum Source: Sendable { case history, blended, typical }
    public let monthly: [CategoryID: Decimal]     // per 30.44 days
    public let source: [CategoryID: Source]
    public let cyclesUsed: Double                 // 0, 0.5, 1, 2, 3
    public let oneOffs: [CategorySpend]           // excluded big purchases, listed in the UI
    public var monthlyTotal: Decimal
    public var daily: Decimal                     // monthlyTotal / 30.44
}

public enum BaselineCalculator {
    public static let monthDays: Decimal = 30.44
    public static func compute(spends: [CategorySpend], completedCycles: [PayCycle] /* newest first, ≤ 3 */,
                               current: PayCycle, today: Date, trackedSince: Date,
                               income: Decimal, household: Household, ownsCar: Bool?,
                               excluded: Set<CategoryID>) -> Baseline
}
public enum UAETypical {
    public static func monthly(_ c: CategoryID, income: Decimal, household: Household, ownsCar: Bool?) -> Decimal
}
```

**Method**
1. **Which cycles count.** The last 3 completed pay cycles (built with `PayCycle.current(payday:today:)` stepping back). A cycle counts only if `trackedSince ≤ cycle.start + 3 days` (`trackedSince` = min(first transaction date, earliest `ImportBatch.periodStart` for any account)). So a cycle half-covered by data never drags the baseline down.
2. **One-offs.** Within each category over the window, a transaction is a one-off when `amount > max(750, 4 × median transaction amount of that category)` and the category is shopping, family, health, cash or other. Excluded; listed as "Big one-offs (not in your usual)" «مشتريات كبيرة (ما تنحسب في المعتاد)».
3. **Per cycle, per category**: `S(c,k) = Σ amounts × 30.44 / cycleDays(k)` (normalise cycle length).
4. **Observed**: n = counted cycles. n = 3 → median of the three; n = 2 → mean; n = 1 → the value. If n = 0 and the current cycle has `elapsed ≥ 7` days → `obs = spentSoFar × 30.44 / elapsed`, and n = 0.5.
5. **Blend with UAE typical**: `w(n) = [0: 0, 0.5: 0.4, 1: 0.7, 2: 0.9, 3: 1.0]`
   `baseline(c) = w · obs(c) + (1 − w) · typical(c)` (a category with zero observed spend shrinks toward 0 as n grows, which is right: no car → no fuel).
   `source = n == 0 ? .typical : n < 3 ? .blended : .history`.
6. Round each category to AED 10.

**UAE typical defaults** (`UAETypical`, starting assumptions to tune with real data; single person):
`typical(c) = clamp(pct(c) × income, min(c), max(c)) × householdFactor(c)`

| Category | % of income | min AED | max AED | couple | family |
|---|---|---|---|---|---|
| groceries | 8% | 700 | 2,500 | ×1.6 | ×2.3 |
| dining | 4% | 250 | 1,500 | ×1.5 | ×1.8 |
| delivery | 3% | 150 | 1,000 | ×1.4 | ×1.7 |
| transport (taxi, Salik, parking) | 3% | 150 | 1,000 | ×1.3 | ×1.5 |
| fuel | 3.5% | 200 | 900 | ×1.3 | ×1.6 |
| shopping | 5% | 300 | 2,000 | ×1.4 | ×1.8 |
| health | 1.5% | 100 | 600 | ×1.6 | ×2.2 |
| entertainment | 2% | 100 | 800 | ×1.5 | ×1.8 |
| family & home | 3% | 200 | 1,500 | ×1.5 | ×2.0 |
| cash | 2% | 100 | 800 | ×1.2 | ×1.5 |
| other | 2% | 100 | 800 | ×1.2 | ×1.5 |
| telecom (if no commitment) | — | 300 | 300 | ×1.8 | ×2.5 |
| utilities (if no commitment) | 3% | 300 | 1,500 | ×1.4 | ×2.0 |
| subscriptions (if no commitment) | — | 100 | 100 | ×1.2 | ×1.5 |

`ownsCar == false` → fuel = 0; `ownsCar == true` → transport ×0.6. Unknown → as table.

**Insights card "What you usually spend"** «مصروفك المعتاد»: total "AED 5,180 a month · about AED 170 a day" «5,180 درهم بالشهر · تقريبًا 170 درهم باليوم», then a list of categories with horizontal bars (baseline) and a tick mark for this cycle's pace. Footer depends on `source`:
- typical: "Based on typical UAE spending until we see a full month of yours. Import a statement to make it yours now." «مبني على مصروف معتاد في الإمارات لين نشوف شهر كامل من مصروفك. استورد كشف حساب عشان يصير على مقاسك من الحين.» + button "Import a statement".
- blended: "Based on your last 1 month and typical UAE spending." «مبني على آخر شهر من مصروفك ومصروف معتاد في الإمارات.»
- history: "The middle of your last 3 months, big one-offs left out." «الوسط من آخر 3 شهور، بدون المشتريات الكبيرة.»

### 3.2 Inputs for the month (one place, `SafeToSpendCalculator`)

| Symbol | Meaning | Source |
|---|---|---|
| `I` | income this cycle | `max(received, Σ regular IncomeSource)` (today's rule, extended to several incomes) |
| `C` | commitments to set aside this cycle | Σ `Obligation` reserve (§2.3) + fixed already paid + Σ `Jameya.reserve` |
| `G` | goals this cycle | Σ `SavingsGoal.reserve(in:)` |
| `X` | extra to save | `AppSettings.savingsGoal` |
| `D` | days in this cycle | `cycle.end − cycle.start` in days |
| `B` | usual spending for this cycle | `baseline.monthlyTotal × D / 30.44` |
| `P` | potential savings per month | §3.4 |
| `Iₘ, Cₘ` | monthly equivalents | Σ regular income; Σ `monthlyEquivalent` + jameya share (if running) |

### 3.3 KhurdaCore: `MonthPlan`

```swift
public struct MonthPlan: Sendable, Equatable {
    public enum Status: Sendable { case comfortable, tight, short }
    public let flexible: Decimal          // F = I − C − G
    public let usual: Decimal             // B
    public let dailyTarget: Decimal
    public let expectedSavings: Decimal   // at your usual spending
    public let savingsWithTarget: Decimal // if you keep to the daily target
    public let shortBy: Decimal           // > 0 when commitments + usual spending exceed income
    public let extraToSave: Decimal       // what "Use this target" writes to AppSettings.savingsGoal
    public let status: Status

    public static func compute(income I: Decimal, commitments C: Decimal, goals G: Decimal,
                               usualMonthly: Decimal, potentialMonthly P: Decimal, cycleDays D: Int) -> MonthPlan
}
```
Formulas (all Decimal; `k = D / 30.44`):
```
F        = I − C − G
B        = usualMonthly × k
shortBy  = max(0, B − F)
if F ≤ 0:   dailyTarget = 0, status = .short
else:
  flexTarget  = min(F, max(B − 0.5 × P × k, 0.7 × B))   // aim for half the found savings, never cut more than 30% at once
  if F < B:  flexTarget = F                              // habits don't fit: the target is what fits
  dailyTarget = flexTarget / D, rounded DOWN to AED 5 (to AED 1 when below AED 50)
expectedSavings   = G + (F − B)            // may be negative → show as "short by"
savingsWithTarget = G + F − dailyTarget × D
extraToSave       = max(0, F − dailyTarget × D)
status = F − B ≥ 0.10 × I ? .comfortable : F ≥ B ? .tight : .short
```
Note X is deliberately not in F: the target replaces it.

### 3.4 KhurdaCore: `SavingsFinder` (ways to save)

```swift
public struct Opportunity: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case aboveUsual(CategoryID, percent: Int)       // this cycle is running hot
        case aboveTypical(CategoryID)                   // habit well above UAE typical
        case smallRepeats(merchant: String, count: Int) // coffees, cafeteria
        case overlappingSubscriptions([String])         // Netflix + OSN+ + Shahid
        case fees                                       // bank charges, late fees
    }
    public let kind: Kind; public let category: CategoryID?; public let monthly: Decimal
}
public enum SavingsFinder {
    public static func find(thisCycle: [CategorySpend], last30Days: [CategorySpend], elapsedDays: Int,
                            baseline: Baseline, typical: [CategoryID: Decimal]) -> [Opportunity]
    public static func total(_ o: [Opportunity]) -> Decimal
}
```
Rules (monthly AED):
1. **Above usual** — needs `elapsed ≥ 7` and `source(c) != .typical`. `pace = spent(c) × 30.44 / elapsed`. If `pace ≥ 1.2 × base(c)` and `pace − base(c) ≥ 100` → `monthly = pace − base(c)`, `percent = round((pace / base − 1) × 100)`.
2. **Above typical** — `source(c) != .typical`, c ∉ {health, bills, telecom, education}. If `base(c) > 1.3 × typical(c)` and `base(c) − typical(c) ≥ 150` → `monthly = 0.25 × (base(c) − typical(c))`.
3. **Small repeats** — `Insights.leaks(last30Days, smallUpTo: 60, minimumCount: 4)`, top 2 → `monthly = 0.5 × total`.
4. **Overlapping subscriptions** — in the last 35 days, ≥ 2 merchants from the same group charged. Groups: video {netflix, osn, shahid, disney, prime video, starzplay, apple tv}, music {spotify, anghami, apple music, youtube premium}. `monthly = cheapest charge in the group`.
5. **Fees** — last 30 days, merchant/description has a whole-word fee keyword: "fee", "charge", "late payment", "overlimit", "interest", "finance charge", «رسوم», «غرامة», «فائدة». `monthly = Σ` when ≥ 10.

De-duplication: per category keep only the largest of rules 1–2; subtract any rule-3 amount in the same category from it (floor 0). `P = Σ` of what's left. Each `monthly` rounds down to AED 10; drop those under AED 30. Show the top 3, biggest first.

Copy (EN · AR), `{x}` = value:
- aboveUsual: "Dining is {40}% above your usual this month · save AED {320} a month" · «المطاعم أعلى من عادتك بـ {40}% هالشهر · توفّر {320} درهم بالشهر»
- aboveTypical: "You spend AED {1,400} a month on delivery; around AED {700} is typical. Trimming a quarter of the gap saves AED {175}." · «تصرف {1,400} درهم بالشهر على التوصيل، والمعتاد تقريبًا {700}. لو خففت ربع الفرق توفّر {175} درهم.»
- smallRepeats: "{17} times at Starbucks in a month · halve it to save AED {170}" · «{17} مرة في ستاربكس خلال شهر · لو نصّصتها توفّر {170} درهم»
- subscriptions: "You pay for Netflix and OSN+ · keep one, save AED {35}" · «مشترك في Netflix و OSN+ · خلّ واحد ووفّر {35} درهم»
- fees: "AED {45} went on bank fees this month" · «راح {45} درهم رسوم بنك هالشهر»
Card title "Ways to save" «طرق توفّر فيها», total line "Up to AED {530} a month" «لين {530} درهم بالشهر». Tone: suggestions, never scolding. No card when the list is empty.

### 3.5 Plan › "Your month" card «شهرك»

```
YOUR MONTH                                   Pay cycle 27 Nov – 26 Dec
Income                                 AED 21,500
Commitments                          − AED 7,450
Goals                                − AED 1,500
Usually spend                        − AED 5,180   (i)
─────────────────────────────────────────────────
Expected to save                         AED 7,370   (incl. goals)

Daily target          AED 150 a day
If you keep to it you'll save          AED 8,450
[ Use this target ]
```
- "Use this target" «اعتمد هذا الهدف» → `AppSettings.savingsGoal = extraToSave`. SafeToSpend then reserves it like today's savings, so the ring's allowance at the start of the cycle equals the daily target. Re-computed and offered again each payday ("New cycle, new target: AED 155 a day" «دورة جديدة، هدفك اليومي: 155 درهم»); never applied silently.
- Status line under the total: comfortable "You've got room" «عندك مجال»; tight "It fits, just" «تمشي، بس على الحافة»; short (red-free wording, `Theme.over` icon only): "Commitments and usual spending are AED {900} more than your income" «التزاماتك ومصروفك المعتاد أكثر من دخلك بـ {900} درهم» + link "See ways to save".
- (i) opens the baseline card's text explaining the source.
- Daily target and `Safe to spend today` are different words on purpose: the first is the plan, the second is live.

---

## 4. Goals with deadlines

`SavingsGoal` already has `targetDate` (unused) and `monthly`. Add `var planByDate: Bool = true`.

### 4.1 KhurdaCore: `GoalPlanner`
```swift
public enum GoalPlanner {
    /// Paydays strictly after `today` up to and including `through`.
    public static func paydays(after today: Date, through: Date, payday: Int, calendar: Calendar = .dubai) -> [Date]
    public enum Need: Equatable, Sendable { case reached, tooSoon(neededNow: Decimal), monthly(Decimal, paydays: Int, perDay: Decimal) }
    public static func need(target: Decimal, saved: Decimal, deadline: Date, payday: Int, today: Date) -> Need
    public static func finishDate(target: Decimal, saved: Decimal, monthly: Decimal, payday: Int, today: Date) -> Date?
    public static func room(incomeMonthly: Decimal, commitmentsMonthly: Decimal, usualMonthly: Decimal,
                            otherGoalsMonthly: Decimal) -> Decimal
    public enum Fit: Equatable, Sendable { case comfortable, tight, notAffordable(shortBy: Decimal, earliest: Date?) }
    public static func fit(monthly: Decimal, room: Decimal, target: Decimal, saved: Decimal, payday: Int, today: Date) -> Fit
}
```
Formulas:
```
R = target − saved;  R ≤ 0 → .reached
N = paydays(after: today, through: deadline).count
N == 0 → .tooSoon(neededNow: R)
monthly = R / N rounded UP to AED 10;  perDay = monthly / 30.44 rounded to AED 1
finishDate: M ≤ 0 → nil;  N = ceil(R / M);  date = paydays(after: today, through: today + 20 years)[N − 1]
room = Iₘ − Cₘ − baseline.monthlyTotal − Σ other goals' monthly
fit:  monthly ≤ 0.8 × room → .comfortable
      monthly ≤ room       → .tight
      else → .notAffordable(shortBy: monthly − max(room, 0),
                            earliest: room > 0 ? finishDate(M: floor10(0.8 × room)) : nil)
```
(Payday credit stays in `CycleReset` exactly as today; the planner only proposes `monthly`.)

### 4.2 Goal editor (extends `GoalEditor`)
Segmented "Plan by" «خطّط حسب»: **Date** «التاريخ» / **Monthly amount** «المبلغ الشهري».
- By date: Target · Already saved · "Reach it by" «توصله قبل» (month-year picker) → computed line: "Set aside AED {1,250} a month (about AED {41} a day) from {12} paydays" «حوّش {1,250} درهم بالشهر (تقريبًا {41} درهم باليوم) من {12} راتب». `monthly` is written from it.
- By amount: Target · Already saved · Monthly → "You'll reach it in {August 2027}" «بتوصله في {أغسطس 2027}». `targetDate` is written from it.
Fit banner under the result:
- comfortable: none (or a small ✓ "Fits your month" «يناسب شهرك»).
- tight: "This fits, but leaves little spare each month." «يمشي، بس ما يخلّي لك مجال كثير كل شهر.»
- notAffordable: "That's AED {400} a month more than you have spare. {September 2027} would fit, or see ways to save." «هذا أكثر من اللي يتبقى لك بـ {400} درهم بالشهر. {سبتمبر 2027} يناسبك، أو شوف طرق توفّر فيها.» with buttons "Use {September 2027}" «خلّه {سبتمبر 2027}» and "Ways to save".
- tooSoon: "Too close for payday savings. You'd need AED {3,000} now." «قريب وايد عشان نحوّش من الراتب. تحتاج {3,000} درهم الحين.»
`GoalRow` sub-line uses `finishDate`; overdue goals (deadline passed, not reached): "Date passed · {AED 2,000} to go" «فات الموعد · باقي {2,000} درهم» with "Pick a new date".

---

## 5. Import statements (.xlsx, .csv, .pdf)

### 5.1 Model
```swift
@Model final class ImportBatch {
    var id: UUID = UUID()
    var fileName: String = ""
    var formatRaw: String = "csv"          // csv, xlsx, pdf
    var importedAt: Date = Date.now
    var accountID: UUID?
    var periodStart: Date = Date.now
    var periodEnd: Date = Date.now
    var added: Int = 0
    var skippedDuplicates: Int = 0
}
```
Imported rows are normal `Transaction`s with `source = .statement` (already reserved in `TransactionSource`), `importBatchID`, `account`, `sourceMessage = original row text` (device-only, like SMS). Fingerprint for statements: `"stmt|\(accountID)|\(yyyy-MM-dd)|\(amount)|\(isOut)|\(normalizedDescription)|\(balance ?? "")|\(occurrence)"` — `occurrence` numbers identical rows within one file, so re-importing the same or an overlapping file skips them exactly, while two real identical coffees in one file both import.

**Settings › Past imports** «الاستيرادات السابقة»: list of batches; swipe "Undo import" «تراجع عن الاستيراد» deletes that batch's transactions (confirm: "Remove the {142} transactions from this file?" «نشيل الـ {142} حركة اللي من هالملف؟»). Undo is what makes a bad auto-detection safe.

### 5.2 Readers → one `RawTable`
```swift
public struct RawTable: Sendable { public var rows: [[String]]; public var preamble: [String] }  // preamble = text above the table / PDF page header lines
```
- **CSV / TSV** (`CSVReader`, KhurdaCore): encoding by BOM (UTF-8, UTF-16 LE/BE); else try UTF-8; else Windows-1256 (Arabic Excel exports: `CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingWindowsArabic)`); else ISO-8859-1. Delimiter = the one of `, ; \t |` with the most consistent non-zero count per line over the first 20 lines. RFC 4180 quotes, `""` escapes, CRLF/LF, newlines inside quotes.
- **XLSX** (`XLSXReader`, KhurdaCore, no package): an .xlsx is a ZIP. Read the ZIP central directory, inflate entries with Apple's `Compression` framework (`COMPRESSION_ZLIB` = raw DEFLATE; stored entries copied). Parse with `XMLParser`: `xl/workbook.xml` (sheet names, `date1904`), `xl/_rels/workbook.xml.rels`, `xl/sharedStrings.xml`, `xl/styles.xml` (`cellXfs` → numFmtId; ids 14–22 and 45–47 and custom codes containing d/m/y are dates), then the sheet. Cell types: `s` shared string, `inlineStr`, `str`, `b`, `n` (date when its style is a date → serial → `1899-12-30 + serial days`, or `1904-01-01` base). Expand `r="C7"` refs so empty cells keep column positions. Several sheets → the sheet with the most rows that have a date and a number; picker "Sheet" in the column step. `.xls` (old binary) → error copy "Save it as .xlsx or CSV" (below). ~250 lines; covered by a fixture test.
- **PDF** (`PDFTableReader`, app target, PDFKit): `PDFDocument(url:)`. `isLocked` → password prompt (the person types it; `unlock(withPassword:)`; never stored or logged — UAE e-statements are often locked with a date of birth or card digits). Per page: `page.selection(for: page.bounds)?.selectionsByLine()`; for each line, characters' x positions via `page.characterBounds(at:)`; split a line into cells where the gap between characters > 2 × the median character width; group lines into rows by y (± 2 pt). Column positions: cluster cell left/right edges across all rows (1-D clustering, 8 pt tolerance) so cells line up into the same column index; right-aligned numbers cluster by their right edge. Lines without a date that follow a dated row are appended to that row's description (multi-line narrations). Drop repeated header lines and page footers ("Page 2 of 5", «صفحة»). A PDF with no text layer (scanned) → "This PDF is a scan…" (OCR with Vision is deferred, see UNFORGET U2 which plans the same OCR).
  Arabic PDFs: text may come out in visual order; reverse runs of Arabic letters when `NLLanguageRecognizer` / letter scan says the line is RTL and the extracted string starts with the last word (detect by checking the known header synonyms both ways).

Limits: 10 MB, 5,000 rows (more → "We'll import the latest 5,000 rows" «بنستورد آخر 5,000 حركة»). Parsing runs off the main actor (`Task.detached`); inserting runs on the main context in chunks of 200 with one save per chunk.

### 5.3 KhurdaCore: `StatementAnalyzer`
```swift
public enum ColumnRole: String, CaseIterable, Sendable {
    case date, valueDate, description, debit, credit, amount, balance, currency, drCr, reference, ignore
}
public enum SignRule: Sendable { case debitCreditColumns, drCrColumn, negativeIsOut, positiveIsOut, balanceDelta }
public struct DateFormat: Sendable, Equatable { public let pattern: String; public let dayFirst: Bool; public let ambiguous: Bool }
public struct ColumnMapping: Sendable, Equatable {
    public var headerRow: Int?; public var roles: [Int: ColumnRole]
    public var dateFormat: DateFormat; public var sign: SignRule; public var confidence: Double  // 0…1
}
public struct StatementRow: Sendable, Identifiable {
    public let id: Int                      // row index in the table
    public var date: Date; public var description: String; public var merchant: String
    public var amount: Decimal; public var isOut: Bool; public var kind: TransactionKind
    public var category: CategoryID; public var balance: Decimal?; public var cardLast4: String?
    public var foreign: (amount: Decimal, currency: String)?
    public var issues: [Issue]              // .dateUnsure, .amountUnreadable, .possibleDuplicate, .summaryRow
    public enum Issue: Sendable { case dateUnsure, amountUnreadable, possibleDuplicate, summaryRow }
}
public enum StatementAnalyzer {
    public static func detectMapping(_ t: RawTable, accountType: AccountType?) -> ColumnMapping
    public static func rows(_ t: RawTable, mapping: ColumnMapping, categorizer: Categorizer,
                            ownEndings: [String], accountType: AccountType?) -> [StatementRow]
    public static func detectAccount(_ t: RawTable, rows: [StatementRow], accounts: [AccountRef]) -> AccountMatch
}
public enum DateGuesser {
    public static func guess(_ samples: [String]) -> DateFormat?
    public static func parse(_ s: String, _ f: DateFormat) -> Date?
}
public enum MerchantCleaner { public static func clean(_ description: String) -> (merchant: String, cardLast4: String?, date: Date?) }
public enum StatementDuplicates {
    public struct Existing: Sendable { public let id: String; date: Date; amountAED: Decimal; currency: String
        isOut: Bool; merchant: String; accountID: String?; cardLast4: String?; bankID: String? }
    public enum Match: Sendable { case sure(String), likely(String) }
    public static func match(_ rows: [StatementRow], fileAccountID: String?, fileEnding: String?,
                             fileBankID: String?, existing: [Existing]) -> [Int: Match]
}
```
`BankMessageParser.normalize` (digits), `kind(for:)` and `AmountText.number` become `public` so the importer reuses them.

**Heuristics**

1. **Normalise every cell**: Arabic-Indic/Persian digits → ASCII, `٫`→`.`, `٬ ،`→`,`, strip direction marks, trim, NBSP → space.
2. **Header row**: scan the first 30 rows; score = number of cells matching the synonym table (case-insensitive, whole phrase). Best score ≥ 2 → header row. Repeated copies of that row later (PDF page breaks) are dropped. No header → roles from content only.

   | Role | English synonyms | Arabic synonyms |
   |---|---|---|
   | date | date, transaction date, txn date, trans date, posting date, post date, booking date | التاريخ، تاريخ العملية، تاريخ المعاملة، تاريخ الحركة، تاريخ القيد |
   | valueDate | value date, effective date | تاريخ القيمة، تاريخ الاستحقاق |
   | description | description, details, transaction details, narration, narrative, particulars, remarks, merchant, beneficiary | البيان، الوصف، التفاصيل، تفاصيل العملية، الشرح |
   | debit | debit, debits, withdrawal, withdrawals, dr, paid out, money out, debit amount | مدين، المدين، سحب، السحوبات، خصم |
   | credit | credit, credits, deposit, deposits, cr, paid in, money in, credit amount | دائن، الدائن، إيداع، الإيداعات |
   | amount | amount, transaction amount, amount (aed), aed amount, billing amount | المبلغ، القيمة، مبلغ العملية |
   | balance | balance, running balance, available balance, ledger balance | الرصيد، الرصيد المتاح، الرصيد الجاري |
   | currency | currency, ccy, original currency | العملة |
   | drCr | dr/cr, cr/dr, type, debit/credit | نوع العملية |
   | reference | reference, ref, ref no, cheque no, transaction id | المرجع، رقم المرجع، رقم الشيك |

3. **Column scoring** over up to 200 data rows; per column j: `dateRate`, `numRate` (non-empty cells parsing as amounts), `emptyRate`, `letterRate`, `avgLen`, `hasNegatives`. `H(j, role)` = 3 if the header matches the role else 0.
   - date = H + 2·dateRate (leftmost wins; a second date column → valueDate)
   - description = H + letterRate + min(avgLen/20, 1), only if numRate < 0.5
   - amount = H + numRate + (hasNegatives ? 0.5 : 0)
   - debit/credit pair (a, b) = H + numRate + 2·complementarity, where complementarity = share of rows with exactly one of a, b filled (≥ 0.9 expected)
   - balance = H + numRate + 3·consistency, consistency = share of consecutive rows where `|bal(i) − bal(i−1)| == |amount(i)| ± 0.01` (also tells sort order: ascending if `bal(i) = bal(i−1) ± amount(i)`, descending if reversed)
   Assign greedily, highest score first, one role per column. `confidence = min(normalised score of date, description, and amount-or-debit/credit)`. confidence < 0.6 or no date/amount column → open the **Check columns** step automatically.
4. **Date format** (`DateGuesser`): candidates `dd/MM/yyyy, MM/dd/yyyy, yyyy-MM-dd, dd-MM-yyyy, dd.MM.yyyy, dd/MM/yy, dd MMM yyyy, dd-MMM-yy, dd-MMM-yyyy, d MMM, yyyy/MM/dd`, each optionally followed by ` HH:mm(:ss)`; English month names and Arabic «يناير فبراير مارس أبريل مايو يونيو يوليو أغسطس سبتمبر أكتوبر نوفمبر ديسمبر» (and Levantine «كانون الثاني…» as aliases); Excel serial numbers 30000–60000 from CSV. Pick the format with the highest parse rate over samples (≥ 0.9). Day-first vs month-first: any first field > 12 → day-first; any second field > 12 → month-first; neither → day-first (UAE) with `ambiguous = true`, and also check plausibility: dates must fall within the last 3 years, not in the future, and be mostly monotonic in file order; pick the reading that passes. Missing year (`d MMM`) → the year that keeps the date ≤ the statement end and ≤ today. When ambiguous, the review shows a toggle "Dates read as day/month" «التواريخ: يوم/شهر».
   If a description contains its own date within 7 days before the posting date ("POS 12/11/26 CARREFOUR"), use it as the transaction date (matches the SMS date better).
5. **Amounts**: `AmountText.number` plus: `(123.45)` and `123.45-` → negative; suffix/prefix `DR`/`CR`/«مدين»/«دائن» → direction; `AED 1,234.50`; `1.234,50` when the column consistently uses `,` as decimals; `-`, empty, `0.00` → empty.
6. **Direction** (`SignRule`), in order: separate debit/credit columns → that; a drCr column → that; amounts with mixed signs → negative is out (or positive is out if balance consistency says so); all positive with a balance → `balanceDelta` (balance goes down = out); all positive, no balance → credit-card account: positive is out; otherwise ask in the column step: "Positive amounts are…" «الأرقام الموجبة…» Money out «فلوس طالعة» / Money in «فلوس داخلة».
7. **Skip rows**: no date or no amount; summary rows matching opening/closing balance, brought/carried forward, total, «الرصيد الافتتاحي»، «الرصيد الختامي»، «المجموع»، «الإجمالي»، «رصيد سابق» (flagged `.summaryRow`, hidden).
8. **Kind** from the description, reusing `BankMessageParser.kind(for:)` keyword logic, with statement additions: "salary", "sal ", "payroll", «راتب» → income; "atm", "cash wdl", «سحب نقدي» → withdrawal; "refund", "reversal", «استرجاع» → refund; card account credit "payment received", "thank you", «سداد» → cardPayment; current account debit "cc payment", "card payment", "credit card" → cardPayment; contains an own account ending or "own account" → ownTransfer; "trf", "transfer", "ipi", "aani", «تحويل» → transferOut (debit) / income (credit); everything else debit → purchase, credit → income.
9. **Merchant cleaning** (`MerchantCleaner`): uppercase working copy; capture card ending from masked numbers first (`\d{4,6}[X*•]{4,}\d{3,4}`, `[X*]{2,}\d{3,4}`, "card ending 1234"); then remove: leading transaction codes ("POS", "PUR", "PURCHASE", "DEBIT CARD PURCHASE", "SPOS", "ECOM", "APPLE PAY", "IPP", "VISA", "MASTERCARD", "MC"), masked numbers, dates, times, `AUTH\s*\S+`, `REF[:\s]*\S+`, runs of ≥ 6 digits, amounts with currency, trailing locations (`AE`, `ARE`, `UAE`, DUBAI, ABU DHABI, SHARJAH, AJMAN, AL AIN, RAS AL KHAIMAH, FUJAIRAH, UMM AL QUWAIN, and Arabic forms دبي، أبوظبي، الشارقة), trailing store numbers (`#123`, `-0045`, ` 0045`), extra punctuation; collapse spaces; Title Case for Latin text, Arabic left as is. If nothing remains, keep the original trimmed text. Foreign amount in the narration ("USD 25.00") → `foreign`.
10. **Category**: `Categorizer(learned:)` on the cleaned merchant via a `ParsedTransaction` built from the row (so learned rules and A5 whole-word matching apply).
11. **Account detection**: in the preamble/first 30 rows look for bank names (`BankDirectory.bank(named:)`, EN/AR) and masked account/card numbers or an IBAN (`AE\d{21}` → last 4 digits). Feed (bankID, ending) to `AccountMatcher.match`. Fallback: the card endings most common in the rows. Result is only a pre-selection; the person confirms.
12. **Duplicates vs SMS/Wallet/email** (`StatementDuplicates.match`): candidates `e` with `e.isOut == r.isOut` (cardPayment/ownTransfer compare as neutral), not from this same batch, `−1 ≤ (r.date − e.date) ≤ 3` days (statements post later), amount `|e.amountAED − r.amount| ≤ 0.01` for AED, or within 4% when `e.currency != AED`, and account compatible (`e.accountID == fileAccount`, or `e.accountID == nil` and (`e.cardLast4 == nil` or `endingsMatch(e.cardLast4, r.cardLast4 ?? fileEnding)`) and bank not contradicting). Score `= 10 − 2·|dayDiff| + (merchantsSimilar ? 5 : 0) + (cards match ? 3 : 0)`. Greedy: highest score first; each existing transaction used once. Score ≥ 10 → `.sure` (skipped; enrich the existing tx with `account`, and `postedAmountAED`/`amountAED` when it was an FX estimate — fixes UNFORGET U1 for those). 4 ≤ score < 10 → `.likely` ("Needs a look", unchecked by default). Also skip exact statement-fingerprint repeats (re-import) silently and count them as "already imported".
13. **Side effects** on import: rows before the current cycle never tick commitments or jameya rounds. Rows inside the current cycle run the same commitment and jameya matching as SMS. Salary detection: ≥ 2 income rows of similar size (±5%) on similar days → offer "Your salary looks like AED {18,250} on the {25th}. Use it?" «شكل راتبك {18,250} درهم يوم {25}. نعتمده؟» (never changes the plan silently, PRODUCT_SPEC P3).

### 5.4 Import screens (sheet from Activity › Import, or Settings › Data › Import a statement)

**1. Choose a file** «اختر ملف»
Explainer: "Download a statement from your bank's app or website as Excel, CSV or PDF, then pick it here. Nothing leaves your iPhone." «نزّل كشف حساب من تطبيق البنك أو موقعه (إكسل أو CSV أو PDF) واختاره هنا. ولا شي يطلع من جوالك.»
Button "Choose file" «اختر الملف» → `.fileImporter` with `[.commaSeparatedText, .tabSeparatedText, .plainText, .pdf, UTType("org.openxmlformats.spreadsheetml.sheet")!]`. (P2: register document types so "Open in Khurda" works from Files/Mail.)
Locked PDF → alert with secure field: "This PDF is locked. Type its password; it stays on your phone and isn't saved." «هذا الملف مقفول. اكتب كلمة السر؛ تبقى في جوالك وما نحفظها.»

**2. Check columns** «تأكد من الأعمدة» (shown only when confidence < 0.6, a sheet choice exists, dates are ambiguous with no plausibility winner, or the sign is unknown; always reachable from step 3 via "Columns")
```
Sheet: [Transactions ▾]
┌ Date ▾ ┬ Description ▾        ┬ Debit ▾ ┬ Credit ▾ ┬ Balance ▾ ┐   ← role menu per column
│ 03/11  │ POS CARREFOUR MOE…   │ 245.50  │          │ 12,300.10 │
│ 03/11  │ SALARY NOV           │         │ 18,250   │ 30,550.10 │
└───────────────────────────────────────────────────────────────┘   (first 6 rows, horizontal scroll)
Dates read as: (•) day/month  ( ) month/day      e.g. 03/11 = 3 November
Positive amounts are: (•) Money out ( ) Money in   (only if needed)
[Continue]
```
Role names: Date «التاريخ», Description «البيان», Money out «طالع», Money in «داخل», Amount «المبلغ», Balance «الرصيد», Ignore «تجاهل». The table keeps the file's column order (LTR in both languages, since bank files are LTR tables; headers may be Arabic text).

**3. Review** «راجع قبل الاستيراد»
```
This file is for   [ADCB ••1234 · Salary account ▾]      ← required; "Add a new account" at the bottom of the menu
1 Sep – 30 Nov 2026 · 214 rows
[ To add 168 ] [ Already logged 39 ] [ Needs a look 7 ]   ← segmented filter
──────────────────────────────────────────
☑ 28 Nov   Carrefour                 [cart Groceries]   AED 245.50
           POS CARREFOUR MOE DUBAI AE 4521XXXXXXXX1234   ← original, caption
☑ 25 Nov   Salary                    [Income]          +AED 18,250
☐ 24 Nov   Talabat                   [Food delivery]    AED 64.00
           ⚠ Looks like one you already have: AED 64.00 · Talabat · 23 Nov (SMS)
…
──────────────────────────────────────────
[ Import 168 ]                                            ← sticky bottom button
```
- Tap the category chip → category menu; then a one-time prompt "Use {Groceries} for all {Carrefour}?" «نخلي كل {Carrefour} {بقالة}؟» → creates a `MerchantRule` and re-categorises matching rows.
- Tap a row → edit date, merchant, amount direction, kind (Purchase / Income / Between your accounts «بين حساباتك» / Cash withdrawal).
- "Already logged" rows show the matched transaction and can be force-included.
- "Needs a look": possible duplicates (unchecked), unsure dates, unreadable amounts (cannot be checked until edited).
- If rows fall in the current cycle: footer note "{12} of these are from this pay cycle and will change today's amount." «{12} منها من دورة الراتب الحالية وبتغيّر مصروف اليوم.»
- "Columns" toolbar button → step 2.

**4. Done** «تم»
"Added 168 transactions from ADCB ••1234. Skipped 39 you already had." «انضافت 168 حركة من بنك أبوظبي التجاري ••1234. تخطّينا 39 مسجّلة من قبل.»
If the baseline source moved from typical to history: "Your usual spending is now based on your own 3 months." «مصروفك المعتاد صار مبني على آخر 3 شهور من مصروفك.» + button "See your month" «شوف شهرك» (→ Plan). Salary/commitment suggestions appear here (§5.3 #13, §2.4).

Error copy:
- Old Excel: "This is an old Excel file (.xls). Open it in Numbers or Excel and save it as .xlsx or CSV." «هذا ملف إكسل قديم (.xls). افتحه في Numbers أو Excel واحفظه .xlsx أو CSV.»
- No table: "We couldn't find a table of transactions in this file. Try the Excel or CSV version from your bank." «ما لقينا جدول حركات في الملف. جرّب نسخة الإكسل أو CSV من البنك.»
- Scanned PDF: "This PDF is a scan, so there's no text to read yet. Try the Excel or CSV version." «هذا الـ PDF صورة ممسوحة، ما فيه نص نقدر نقراه للحين. جرّب نسخة الإكسل أو CSV.»
- Wrong password: "That password didn't open it." «كلمة السر ما فتحته.»
- Nothing new: "Everything in this file is already in Khurda." «كل اللي في الملف موجود في خردة من قبل.»

---

## 6. Edge cases

**Accounts**
- Two cards with the same last 4 at different banks → resolved by bank; same bank too → `.ambiguous`, ask on the transaction detail.
- ADIB-style 3-digit endings vs 4 stored: suffix match (§1.2). Never match on fewer than 3 digits.
- Supplementary / replaced card (new number, same account): "More endings" field; archive the old card.
- Deleting an account with transactions: archive instead; hard delete only when empty (`.nullify` keeps the transactions).
- Joint account shared with a spouse: out of scope (Family budget, P18).

**Income & payday**
- Several incomes on different days: payday = the salary's day; other incomes count in the cycle where they're expected (income window already shifted 5 days early).
- Irregular income (`isRegular = false`) is never in the plan; it only adds when received.
- No income entered (freelancer): `I = received so far`; Your month shows "Add your income to see a target" «ضيف دخلك عشان نطلع لك هدف».

**Commitments**
- Quarterly/yearly commitment due twice in one cycle (short Feb cycle): `dues` returns both → reserve ×2 (same as jameya).
- Instalment commitment created mid-way ("8 payments left"): `instalments = 8`, `paidCount = 0`, `firstDue = next payment`.
- Utilities amount differs every month: `amountVaries` with keyword required; the estimate learns from the median of the last 3 matched payments.
- Tabby purchase SMS (first instalment) and the Tabby commitment: the purchase matches the commitment if within 10 days of its first due date; otherwise it stays flexible spending. Keep the existing "is due on" ignore rule (UNFORGET S12) in mind.
- Card instalment plan vs everyday card spending: see §2.3 note; never offer "pay full card bill" as a commitment.
- Rent paid by post-dated cheque: no SMS may arrive until clearing → ticking by hand is normal; the cheque-clearing debit matches later by amount ± 10 days.
- Jameya stays exactly as today; it just renders inside the Commitments list.

**Baseline & targets**
- New user, no history: typical defaults (source .typical), labelled clearly; "Ways to save" rules 1–2 are off until real data.
- Ramadan/Eid or travel month inflates a cycle: median of 3 resists one outlier month; travel is excluded entirely.
- Imported history from only one of several accounts: baseline undercounts → footer shows "Based on ADCB ••1234 only. Import your other cards too." «مبني على بطاقة ••1234 بس. استورد بطاقاتك الثانية بعد.» when other accounts exist with no data in the window.
- `F ≤ 0` (commitments eat the salary): daily target 0, status short, "Ways to save" is the only call to action; never show a negative daily target.
- Daily target accepted, then income changes mid-cycle: re-offer, don't auto-apply.

**Goals**
- Deadline before next payday → `tooSoon`. Deadline in the past → overdue copy.
- `monthly = 0` in "by amount" → no finish date, "Add a monthly amount" «حدد مبلغ شهري».
- Several goals: each goal's fit uses `room` minus the *other* goals, so adding goals shows the squeeze honestly.

**Import**
- Same file imported twice / overlapping periods: statement fingerprint skips exact repeats; overlaps with SMS are caught by the duplicate match.
- Statement in descending order: detected via balance consistency; sorting doesn't matter for import.
- Credit-card statement where "PAYMENT – THANK YOU" is a credit: `cardPayment`, never income.
- Pending / authorisation-hold rows (some card statements): rows with "pending"/«معلّقة» are flagged "Needs a look".
- FX rows: statement amount is the posted AED; the foreign amount is kept in `note`/`foreign`.
- Huge PDFs with images: page limit 60; beyond that "Split the statement by month" «قسّم الكشف شهر شهر».
- Arabic-only statements with Arabic-Indic digits and Arabic month names: handled by normalisation + month table.
- Rows older than 3 years: imported but excluded from the baseline window anyway.

---

## 7. Build order (one engineer)

A full build of everything here is about 3–4 days. **Day 1** is the first block; it gives the owner every feature in a basic, working form. Each step ends with KhurdaCore tests.

**Day 1 (P0)**
1. KhurdaCore pure logic + tests (≈ 2.5 h): `AccountMatcher`, `CommitmentSchedule` + `CommitmentType`/`Frequency`, `CommitmentMatcher`, `BaselineCalculator` + `UAETypical`, `MonthPlan`, `GoalPlanner`. These are small, testable, and everything else calls them.
2. Models (≈ 45 min): `Account`, `IncomeSource`, `ImportBatch`, new `Obligation`/`Transaction`/`SavingsGoal` fields, schema update, one-time migration. Keep them in `Models.swift` (the widget compiles it).
3. Settings › Your money (≈ 1.5 h): Income list/editor, payday, Accounts & cards list/editor; attribution in `TransactionLogger.save`.
4. Commitments (≈ 1.5 h): unified list in Plan, type grid + form, `SafeToSpendCalculator` uses the new reserve, generalised matcher, `Reminders` via `next(after:)`.
5. Your month card + Use this target (≈ 1 h).
6. Goal editor by date / by amount + fit banner (≈ 45 min).
7. Import, CSV only (≈ 2 h): `CSVReader`, `StatementAnalyzer` (headers, scoring, `DateGuesser`, amounts, direction, `MerchantCleaner`), `StatementDuplicates`, Review screen (steps 1, 3, 4; columns step can be a simple role list), `ImportBatch` + undo.

**Day 2 (P1)**
8. XLSX reader (ZIP + Compression + XMLParser) with fixture tests.
9. PDF reader (PDFKit lines → cells → columns), password unlock.
10. Insights: "What you usually spend" and "Ways to save" (`SavingsFinder`).
11. "Is this yours?" ending prompt; credit-card-account credit → cardPayment rule; own-ending → ownTransfer.
12. Spread cost for non-monthly commitments (§2.5).
13. Columns step with per-column role menus; MerchantRule from the review screen.

**Later (P2)**
14. Recurring-payment and salary suggestions from imported history.
15. Setup flow: account types per bank and an optional commitments step.
16. "Open in Khurda" document types; OCR for scanned PDFs (with U2).
17. Mirror any parser-level changes (made-public `kind(for:)` additions) in `prototype/parser.js` with tests, per CLAUDE.md.

Tests to add (KhurdaCore): ending suffix match (3 vs 4 digits); match rules 1–6; quarterly/yearly/school-term due dates incl. 31st and February; instalments finishing; monthly equivalent; baseline with 0/0.5/1/2/3 cycles and a one-off; MonthPlan comfortable/tight/short and rounding to AED 5; GoalPlanner tooSoon, reached, reverse date, notAffordable earliest date; CSV with `;` and quotes; Windows-1256 Arabic headers; dd/MM vs MM/dd ambiguity; `(123.45)` and `DR/CR`; balance-delta direction; merchant cleaning samples (POS…MOE DUBAI AE, masked card); duplicate sure/likely and re-import fingerprint.
