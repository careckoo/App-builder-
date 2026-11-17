# Sarfi · صرفي

An iPhone budget app for the UAE that tracks spending **automatically from your bank's SMS alerts**, in Arabic and English. You never type an amount.

It combines the best parts of two App Store apps:

| From **OutCap** (id6798327313) | From **Budget app** (id1525179720) |
|---|---|
| Reads bank SMS through Apple Shortcuts | Category budgets with progress bars |
| One daily "safe to spend" number | Recurring bills and subscriptions |
| Payday-based cycle, BNPL installments | Charts, widgets, CSV export |
| Data stays on the phone | Full Arabic interface |

…and adds UAE-specific pieces: UAE bank sender IDs, Arabic and English message parsing (including Arabic-Indic digits), UAE merchants (Carrefour, Lulu, Talabat, Careem, ADNOC, TAQA, DEWA, Salik, Tabby, Tamara…), and automatic bill matching.

**Clickable prototype:** `prototype/index.html` (open it through a local web server: `cd prototype && python3 -m http.server`).

---

## How "no typing" works on iPhone

iOS does **not** let any App Store app read the SMS inbox. Apple's supported route is a **Shortcuts personal automation**, which the user creates once:

1. Shortcuts → Automation → **New Automation** → **Message**
2. **Sender**: `ADCB`, `FAB`, `EmiratesNBD`… (exactly as shown in Messages)
3. **Run Immediately** (no confirmation prompt)
4. Action: **Sarfi → Log bank message**, Message = *Shortcut Input → Message*

From then on every bank alert runs `LogBankMessageIntent` in the background. It parses the SMS, saves the transaction, updates the widget, and shows a small banner like "AED 45.50 · CARREFOUR. Left today: AED 375". The app ships an `AppShortcutsProvider`, so the action shows up in Shortcuts right after install. The in-app setup screen walks through these taps and confirms when the first message arrives.

Apps can't create automations themselves, so this one-time setup (about a minute per bank) is unavoidable today. Later options to look at:
- **UAE Open Finance** (Central Bank framework): direct bank-account access through a licensed provider, with no SMS needed.
- **Apple FinanceKit**: currently limited to certain countries and institutions; watch for UAE availability.

## Project layout

```
SarfiCore/               Swift package: pure logic, unit-tested, no UI
  BankMessageParser      SMS → amount, currency, type, merchant, card, balance, date
  Categorizer            merchant → category (UAE merchants, Arabic + English), learns user overrides
  SafeToSpend, PayCycle  daily allowance from salary, bills, savings goal, days to payday
  DuplicateDetector      ignores the same purchase arriving twice
  BankDirectory          UAE banks, Arabic names, SMS sender IDs
Sarfi/                   iOS app (SwiftUI + SwiftData + App Intents, iOS 17+)
  Intents/               LogBankMessageIntent (the Shortcut action), SafeToSpendToday (Siri)
  Views/                 Today, Activity, Plan (budgets), Setup/Settings
  Resources/             Localizable.xcstrings (English + Arabic), entitlements
SarfiWidget/             Home Screen + Lock Screen widget
prototype/               Browser prototype + JS copy of the parser + tests
project.yml              XcodeGen spec
```

## Build on a Mac

```bash
brew install xcodegen
xcodegen                         # creates Sarfi.xcodeproj
open Sarfi.xcodeproj
```
Set your Apple Developer Team under Signing for both targets. Change the bundle ID prefix (`ae.sarfi`) and the App Group (`group.ae.sarfi.shared`) to ones you own, then run on an iPhone. The Shortcuts automation needs a real device to receive SMS.

Tests:
```bash
cd SarfiCore && swift test        # Swift parser tests (Mac or Linux with Swift)
node prototype/parser.test.mjs    # same cases against the JS copy
```

## Privacy

- Messages are parsed on the device. There is no server, and the app never asks for bank credentials.
- OTPs, promotional messages and declined payments are recognised and skipped.
- The original SMS is stored with its transaction, on the device only, so the user can see where each number came from.
- App Store privacy label: "Data Not Collected" (as long as no analytics SDK is added).

## Before release

- [ ] Collect 20–30 **real, anonymised** SMS per bank and add them to the tests. The current samples follow typical UAE formats, but each bank's exact wording needs checking.
- [ ] Confirm the SMS sender IDs on real phones (they differ between banks and sometimes change).
- [ ] App icon, screenshots in Arabic and English, App Store listing in both languages.
- [ ] TestFlight: Pro features are unlocked for every tester; there is no paywall yet. Add StoreKit before the App Store release.
- [ ] Optional: Pro tier (StoreKit 2) for forecasts, AI monthly summary, shared family budget (CloudKit).
