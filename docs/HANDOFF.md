# Khurda · خردة — handoff to Claude Code on the Mac

Everything needed to continue this project in a local Claude Code session on the user's Mac.
All code, decisions and the backlog are in this repository on branch `claude/gallant-franklin-ru6lh1`.

---

## 0. First message to paste into local Claude Code

> You are the Lead of the Khurda (خردة) iPhone app project in this folder. Read `docs/HANDOFF.md`, `CLAUDE.md`,
> `UNFORGET.md` and `docs/PRODUCT_SPEC.md`, then follow the "Next steps on the Mac" in HANDOFF.md, starting with
> step 1 (first build). Only you talk to me; use the agents in `.claude/agents/` for the work. Answer me in
> Gulf Arabic. Commit and push to the same branch after every working step.

---

## 1. Get the code onto the Mac

```bash
# Claude Code (if not installed)
curl -fsSL https://claude.ai/install.sh | bash

# The project (the repo may be private: sign in when git asks, or run `gh auth login` first)
cd ~/Documents/Khurda          # the empty folder the user created
git clone https://github.com/careckoo/App-builder-.git .
git checkout claude/gallant-franklin-ru6lh1
claude                         # then paste the message from section 0
```

Before building, the user must open Xcode once, accept the licence and let it install its components
(needs the Mac password). If needed: `sudo xcode-select -s /Applications/Xcode.app`.

---

## 2. What the app is

An iPhone budget app for the UAE that tracks spending **automatically**, so the user never types an amount.
It shows one number: **«مصروف اليوم» / "Left to spend today"**. That is (income − fixed bills − savings goal −
spending so far) ÷ days left until payday.

It started from two App Store apps the user liked:
- **OutCap** (id6798327313): Saudi, reads bank SMS through Shortcuts, one daily number.
- **Budget app** (id1525179720): budgets, recurring bills, Arabic UI, but manual entry.

Khurda keeps the best of both. It is built for UAE banks and is more automatic. Use our own design and wording:
never copy OutCap's look, which is dark green and gold.

### How "automatic" works on iPhone (important constraints)
- iOS does **not** let an app read the SMS inbox or other apps' **push notifications**.
- So all automatic sources go through **Shortcuts personal automations**. The user sets each one up once, with
  "Run Immediately".
  1. **Apple Pay (recommended):** the "Transaction" (Wallet) trigger → our `LogWalletTransactionIntent`
     (amount, merchant, card).
  2. **Bank SMS:** the "Message" trigger, sender = bank → `LogBankMessageIntent`.
  3. **Bank email alerts:** the "Email" trigger, sender = bank alert address → `LogBankMessageIntent` (subject +
     body; HTML is stripped).
  4. **Manual:** a "+" quick add for cash.
- If the same purchase arrives from two sources (for example Apple Pay and then SMS), it is merged into one
  record and the bank's details are added to it.
- **Bank transfers** can't be caught automatically when the bank only sends push notifications. The plan is a
  share extension: share the transfer receipt → read it with on-device OCR (Vision). Recurring recipients are
  remembered. See UNFORGET U2.

---

## 3. User decisions (final)

| Topic | Decision |
|---|---|
| Name | **خردة / Khurda** (final; earlier names Masroofi, Sarfi were dropped) |
| Bundle ID (placeholder) | `ae.khurda.app`, widget `ae.khurda.app.widget`, App Group `group.ae.khurda.shared`. Replace with real ones after Apple Developer enrolment |
| Look | **"Gulf morning"**: light, uplifting. Opens in Light; Settings has Light / Dark / Match iPhone |
| Palette (light / dark) | bg `#FFFCF6`/`#12161C` · surface `#FFFFFF`/`#1B2129` · sand `#F6EFE3`/`#232A33` · accent sea blue `#2E8BEF`/`#5AA9FF` (small text `#1B6FCC`) · sunny `#FFC53D`/`#FFD36B` · green `#22B573`/`#3DD68C` · amber `#F5A524`/`#FFB84D` · coral `#F2545B`/`#FF7A80` · text `#1E2A36`/`#EEF2F6` · secondary `#6B7785`/`#9AA6B2` |
| Tabs | Today · Activity · Insights · Plan («الخطة») · Settings |
| Pro pricing | AED 59.99/yr (7-day trial), AED 9.99/mo, AED 179.99 lifetime launch offer |
| TestFlight | Pro unlocked for every tester; paywall goes live only at App Store launch |
| Language | Arabic (Gulf dialect, natural, not machine-translated) + English; amounts in Western digits; Arabic plurals for "days to payday" |
| User's payments | Mostly Apple Pay or bank transfers; the bank sends push notifications for everything |

---

## 4. Project layout

```
project.yml              XcodeGen spec (targets Khurda + KhurdaWidget, package KhurdaCore)
KhurdaCore/              Swift package, pure logic, unit tests (no UI)
  Sources/KhurdaCore/
    BankMessageParser    SMS/email text → amount, currency, kind, merchant, card, balance, date
    TransactionSources   AmountText, MessageText (HTML/email cleaning), MessageReader,
                         CrossSourceDuplicate (merge Wallet + SMS/email), TextMatch
    Categorizer          merchant → category (UAE merchants, AR+EN, whole-word), learned rules
    SafeToSpend          PayCycle, daily number, DuplicateDetector
    BankDirectory        UAE banks, Arabic names, SMS sender IDs
  Tests/KhurdaCoreTests/ XCTest suites
Khurda/                  iOS app (SwiftUI + SwiftData + App Intents, iOS 17+)
  App/                   KhurdaApp, Theme ("Gulf morning", Appearance setting)
  Intents/               LogBankMessageIntent, LogWalletTransactionIntent, SafeToSpendToday,
                         TransactionLogger (save / merge / bills), SafeToSpendCalculator
  Models/                Transaction (sourceRaw, cardName…), Budget, Obligation, MerchantRule, CycleReset
  Views/                 Home (+ QuickAdd, Paste), Activity, Budgets (shown as "Plan"), Setup/Settings
  Resources/             Localizable.xcstrings (EN+AR), InfoPlist.xcstrings, entitlements
KhurdaWidget/            Home + Lock Screen widget
prototype/               Browser prototype + parser.js (JS copy of the parser) + parser.test.mjs
docs/PRODUCT_SPEC.md     Full v1 spec: features per tab, Free/Pro, onboarding, 19 notifications, visuals, milestones
UNFORGET.md              The ONE backlog (unforget skill format)
.claude/agents/          Team: ios-engineer, bug-hunter, backlog-keeper, quality-reviewer, ux-designer
.claude/skills/          unforget, bug-echo, prompter, skill-reviewer (Apache-2.0, from github.com/Terryc21)
.claude/TEAM.md          Rules every agent follows (only the Lead talks to the user)
```

Transaction kinds: `purchase`, `withdrawal`, `transferOut` (expenses); `income`, `refund`; neutral, which never
touches the daily number: `cardPayment` (credit-card bill payment) and `ownTransfer` (between your own
accounts, savings, fixed deposits, CDM cash deposits).

---

## 5. Current state (honest)

- **The Swift code has NEVER been compiled.** It was written in a Linux cloud container with no Xcode.
  Expect a round of compile fixes on the first build.
- The parser logic is tested through its JS mirror: `node prototype/parser.test.mjs` → **89/89 pass**. That
  includes the user's 4 real bank SMS (likely ADIB: "Trx. of AED… is Approved", and a card payment).
- Two code reviews and two bug-echo passes are done and their fixes applied. The findings that remain are in
  UNFORGET.md.
- Things to watch on the first build (flagged by the reviewer):
  - the `UIColor` dynamic provider in Theme.swift (the widget needs UIKit);
  - `@AppStorage` with the `Appearance` enum;
  - switch expressions;
  - `IntentDialog` built from interpolated strings;
  - the ICU regex lookbehind `(?<!\bus )`;
  - `#Predicate { $0.fingerprint == fp }`;
  - `onChange(of: scenePhase)`;
  - `PasteButton`;
  - the `"\r\n"` Character case.
- Clickable prototype (browser): https://claude.ai/artifact/BFcHF3MW7vDdStEBwrEsgC

---

## 6. Next steps on the Mac (in order)

1. **First build (UNFORGET S5).**
   ```bash
   brew install xcodegen            # install Homebrew first if missing: https://brew.sh
   xcodegen
   cd KhurdaCore && swift test && cd ..
   xcodebuild -project Khurda.xcodeproj -scheme Khurda \
     -destination 'platform=iOS Simulator,name=iPhone 16' build
   ```
   Fix every compile error. Keep `KhurdaCore` and `prototype/parser.js` in step: any parser change goes in both,
   with tests in both. Run the app in the Simulator and take screenshots in English and Arabic.
2. **Run on the user's iPhone** with a free Apple ID (personal team) to check the Shortcuts automations for real:
   Apple Pay "Transaction", Message and Email. Confirm the variable names shown in Arabic and English. A free
   personal team may not support App Groups; if signing fails, temporarily disable the widget/App Group.
3. **Milestones from docs/PRODUCT_SPEC.md §7:**
   - M1: the honest number (payday 29–31, onboarding with Apple Pay first, text colour tokens on all screens)
   - M2: a plan that fills itself (salary/payday detection, recurring-bill finder, own-account detection,
     transfer-receipt share extension with OCR)
   - M3: notifications and Insights tab
   - M4: StoreKit 2 Pro and App Store assets
4. **Apple Developer enrolment (S9)** by the user, then real bundle ID / App Group (S6). Reserve the name
   «خردة» in App Store Connect; if it is taken, ask the user for an alternative (S8).
5. **TestFlight:** archive in Xcode and upload, or use `xcodebuild -exportArchive` with an App Store Connect API
   key. Add testers.

---

## 7. Still needed from the user

1. Does the bank app offer **email alerts** (and for which transaction types)? (S11)
2. A **transfer receipt** screenshot from the bank app, with names and account numbers hidden (for OCR). (U2)
3. A **Tabby/Tamara purchase SMS**, to check the "next payment is due on…" ignore rule. (S12)
4. The **bank's SMS sender name** as shown in Messages (the samples look like ADIB). (S2)
5. **Apple Developer Program** enrolment (USD 99/yr). (S9)

---

## 8. How the team works (from CLAUDE.md)

- Only the Lead talks to the user. Agents report to the Lead in the format in `.claude/TEAM.md`.
- Loop:
  1. If the request is unclear, use the prompter skill.
  2. Brief the agents; independent work runs in parallel.
  3. Chain the work: ios-engineer fix → bug-hunter (bug-echo) → quality-reviewer → backlog-keeper (unforget)
     logs anything deferred.
  4. Ask the user only what is theirs to decide, in one message.
  5. Commit and push, then report in plain language.
- Never claim something builds or passes unless it was run.
