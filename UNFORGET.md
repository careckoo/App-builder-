<!-- unforget-format: v2 -->
# Masroofi · مصروفي — UNFORGET.md

The single source of truth for deferred work on Masroofi. Every deferred item, release blocker and follow-up lives here, one row each. Do not start a second backlog file.

**Last promoted:** never (ledger created 2026-11-17)
**Currently shipping toward:** v1.0 (first App Store release)

**Target key:** 🔴 THIS = v1.0, blocks release · 🔵 NEXT = v1.1, first update after launch · 🟡 LATER = two cycles out · ⚪ SOMEDAY = idea, no commitment.

---

## 1. Paused plans

| # | Target | Finding | Urgency | Risk: Fix | Risk: No Fix | ROI | Blast Radius | Fix Effort | Status |
|---|---|---|---|---|---|---|---|---|---|

### Detail - Paused plans

(none yet)

---

## 2. Session spillover

| # | Target | Finding | Urgency | Risk: Fix | Risk: No Fix | ROI | Blast Radius | Fix Effort | Status |
|---|---|---|---|---|---|---|---|---|---|
| S1 | 🔴 THIS | Collect 20–30 real, anonymised SMS per UAE bank (incl. salary and ATM) and add them to the parser tests (Swift + JS); confirm which bank the current real samples are from (looks like ADIB) | 🟡 HIGH | ⚪ Low | 🟡 High | 🟠 Excellent | 🟢 2-5 files | Large | `@status:open` Waiting on real bank messages |
| S2 | 🔴 THIS | Confirm each bank's SMS sender ID on real phones, starting with the bank of the current real samples (likely ADIB) | 🟡 HIGH | ⚪ Low | 🟡 High | 🟠 Excellent | 🟢 2-5 files | Small | `@status:open` Needs real phones |
| S3 | 🔴 THIS | App icon, Arabic + English screenshots, App Store listing in both languages | 🟡 HIGH | ⚪ Low | 🟡 High | 🟠 Excellent | 🟢 2-5 files | Medium | `@status:open` Not started |
| S4 | 🔵 NEXT | Optional Pro tier (StoreKit 2): forecasts, AI monthly summary, shared family budget via CloudKit | ⚪ LOW | 🟡 High | ⚪ Low | 🟢 Good | 🔴 >15 files | Large | `@status:open` Product decision pending |
| S5 | 🔴 THIS | Swift code has never been compiled; first Xcode build (XcodeGen + build + tests) on a Mac | 🔴 CRITICAL | ⚪ Low | 🔴 Critical | 🟠 Excellent | 🟡 6-15 files | Medium | `@status:open` Blocked: no Mac in the cloud container |
| S6 | 🔴 THIS | Replace placeholder bundle ID (now one `APP_BUNDLE_ID` setting) and App Group `group.ae.masroofi.shared` (still in several files) with IDs the user owns | 🟡 HIGH | 🟢 Medium | 🔴 Critical | 🟠 Excellent | 🟢 2-5 files | Small | `@status:open` Needs the user's Apple Developer IDs |
| S7 | ⚪ SOMEDAY | Watch UAE Open Finance and Apple FinanceKit availability in the UAE as a no-SMS import option | ⚪ LOW | 🟡 High | ⚪ Low | 🟢 Good | 🔴 >15 files | Large | `@status:open` Watching; nothing to build yet |
| S8 | 🔴 THIS | App name "Masroofi / مصروفي" is already used by two App Store apps; pick a new name and rename everywhere | 🟡 HIGH | 🟢 Medium | 🟡 High | 🟠 Excellent | 🟡 6-15 files | Medium | `@status:blocked` Waiting on the user's name choice |
| S9 | 🔴 THIS | Enrol in the Apple Developer Program (needed for real IDs, signing and TestFlight) | 🟡 HIGH | ⚪ Low | 🔴 Critical | 🟠 Excellent | ⚪ 1 file | Small | `@status:blocked` User action |
| S10 | 🔴 THIS | Connect the user's Mac (Remote Control) or work on the Mac directly, so Xcode can build the app | 🔴 CRITICAL | ⚪ Low | 🔴 Critical | 🟠 Excellent | ⚪ 1 file | Small | `@status:blocked` User action; unblocks S5 |

### Detail - Session spillover

- **S1** - From README.md "Before release". The parser samples in `MasroofiCore` tests and `prototype/parser.test.mjs` follow typical UAE formats but are not real messages; each bank's exact wording (English and Arabic, Arabic-Indic digits) needs checking. Anonymise card numbers, balances and names before committing. Any parser change goes in both `MasroofiCore` (Swift) and `prototype/parser.js` with tests in both. Logged 2026-11-17. Deferred because: external-block (needs real SMS from real accounts).
  2026-11-17: commit 773b646 added support for the user's real ADIB-style SMS (Trx/approved format, 3-digit card endings, balance without currency, SMS timestamps). Still owed: confirm which bank these real samples come from (the logo looks like ADIB, not confirmed), and collect more real samples, especially salary credits and ATM withdrawals, which have no real sample yet.
  **Verify-still-open:** `grep -n "20–30" README.md` — expect: the unchecked "Collect 20–30 real, anonymised SMS" box under "Before release".
- **S2** - From README.md "Before release". Sender IDs (e.g. `ADCB`, `FAB`, `EmiratesNBD`) differ between banks and sometimes change; the Shortcuts automation only fires on an exact sender match, so a wrong ID means no transactions are logged. Source of truth in code: `MasroofiCore` `BankDirectory`. Logged 2026-11-17. Deferred because: external-block (needs real phones with UAE bank accounts).
  2026-11-17: start with the bank of the user's real samples (likely ADIB). `BankDirectory` currently assumes sender ID `ADIB` (`MasroofiCore/Sources/MasroofiCore/BankDirectory.swift`, `prototype/parser.js`); confirm the exact sender name shown on the user's phone.
  **Verify-still-open:** `grep -n "sender IDs on real phones" README.md` — expect: the unchecked box under "Before release".
- **S3** - From README.md "Before release". Needs an app icon, App Store screenshots in Arabic (RTL) and English, and listing text in Gulf Arabic and English. Submission is not possible without the icon and listing. Logged 2026-11-17. Deferred because: user-decision (branding, copy and store listing are the user's call).
  **Verify-still-open:** `grep -n "App icon, screenshots" README.md` — expect: the unchecked box under "Before release".
- **S4** - From README.md "Before release", marked optional there; targeted at v1.1 so it does not block launch. StoreKit 2 subscription for forecasts, an AI monthly summary and a shared family budget over CloudKit (`Store` in `Masroofi/Models/Models.swift` already notes CloudKit can be switched on later). An AI summary must keep the "Data Not Collected" privacy label in mind. Logged 2026-11-17. Deferred because: user-decision (pricing and scope of a paid tier).
- **S5** - The cloud container has no Mac or Xcode, so none of the Swift (16 `.swift` files across `MasroofiCore/`, `Masroofi/`, `MasroofiWidget/`) has been compiled, and `swift test` in `MasroofiCore` has not run. Only the JS copy of the parser is tested (`node prototype/parser.test.mjs`). First step on a Mac: `brew install xcodegen && xcodegen`, build both targets, run `cd MasroofiCore && swift test`, then run on a real iPhone (the Shortcuts automation needs a device). Expect compile fixes. Logged 2026-11-17. Deferred because: external-block (no Mac available).
  2026-11-17: the code review fixes in commit 773b646 (17 files) are also not compiled. S10 (connect the user's Mac, or work on it directly) is what unblocks this row.
- **S6** - Placeholders appear in `project.yml` (`bundleIdPrefix: ae.masroofi`, two `application-groups` entries), `Masroofi/Resources/Masroofi.entitlements`, `MasroofiWidget/MasroofiWidget.entitlements` and `Masroofi/Models/Models.swift` (`appGroup`). All App Group strings must match or the app, widget and Shortcut intent stop sharing the SwiftData store. Logged 2026-11-17. Deferred because: user-decision (only the user can register IDs under their Apple Developer team).
  2026-11-17: since commit 773b646 the bundle ID is set in one place, `APP_BUNDLE_ID: ae.masroofi.app` under `settings.base` in `project.yml` (the widget uses `$(APP_BUNDLE_ID).widget`; `bundleIdPrefix` is gone). The App Group `group.ae.masroofi.shared` still appears in five places: `Masroofi/Models/Models.swift` (`appGroup`), both `.entitlements` files, and the two `application-groups` entries in `project.yml`. Needs S9 (Apple Developer enrolment) first; if the app is renamed (S8), choose IDs after the name is settled.
  **Verify-still-open:** `grep -rn "ae.masroofi" project.yml Masroofi/Resources/Masroofi.entitlements MasroofiWidget/MasroofiWidget.entitlements Masroofi/Models/Models.swift` — expect: `APP_BUNDLE_ID: ae.masroofi.app` in project.yml and `group.ae.masroofi.shared` in all four files (twice in project.yml).
- **S7** - From README.md "How no typing works". UAE Open Finance (Central Bank framework) would give direct account access through a licensed provider; Apple FinanceKit is limited to certain countries and institutions. Either would remove the one-time Shortcuts setup. Revisit when either is available in the UAE. Logged 2026-11-17. Deferred because: external-block (not available in the UAE yet).
- **S8** - "Masroofi" / "مصروفي" is already the name of two apps on the App Store, so the listing name needs to change. Candidates the user is choosing between: صرفي (Sarfi), خردة, بيزاتي (close to the UAE company Bayzat, a possible confusion or trademark issue), بهانس. Once chosen, rename the user-facing name everywhere: `CFBundleDisplayName` for the app and widget in `project.yml`, `Localizable.xcstrings`, App Shortcut phrases (they use `.applicationName`), widget text, `prototype/index.html`, `README.md`, this ledger's title, and the S3 store listing. Internal target and module names (`Masroofi`, `MasroofiCore`) can stay. Settle the name before S6 so bundle ID and App Group can match it. Logged 2026-11-17. Deferred because: user-decision (naming is the user's call).
  **Verify-still-open:** `grep -rln "Masroofi\|مصروفي" README.md project.yml prototype/index.html Masroofi/Resources/Localizable.xcstrings` — expect: the current name still present in these files.
- **S9** - Enrolment (paid yearly, approval can take a few days) gives the Team ID for `DEVELOPMENT_TEAM` in `project.yml`, lets the user register the bundle ID and App Group (S6), and is required for TestFlight and App Store submission. A free Apple ID can run the app on the user's own iPhone for testing, but not TestFlight. Logged 2026-11-17. Deferred because: external-block (user action; only the user can enrol).
- **S10** - The cloud container has no Mac or Xcode (see S5). Two ways forward: the user connects their Mac to the session (Remote Control) so builds run there, or the user works on the Mac directly. Either one lets S5 (first build and `swift test`) start. Logged 2026-11-17. Deferred because: scaffolding (needs a Mac this session cannot provide).

---

## 3. Audit findings

The Swift quality review finished on 2026-11-17. Its blockers and majors were fixed in commit 773b646 (not compiled yet, see S5). The leftover minors are logged below.

| # | Target | Finding | Urgency | Risk: Fix | Risk: No Fix | ROI | Blast Radius | Fix Effort | Status |
|---|---|---|---|---|---|---|---|---|---|
| A1 | 🔴 THIS | Widget and App Shortcut phrases have no Arabic translations (the app is bilingual) | 🟡 HIGH | ⚪ Low | 🟢 Medium | 🟠 Excellent | 🟢 2-5 files | Small | `@status:open` Not started |
| A2 | 🔵 NEXT | Payday 29–31 can't be set: `PayCycle` and the payday pickers clamp to 28 | 🟢 MEDIUM | 🟢 Medium | 🟢 Medium | 🟢 Good | 🟢 2-5 files | Small | `@status:open` Not started |
| A3 | 🔵 NEXT | Arabic ignore-keywords still match as substrings (e.g. "رفض" inside longer words) | 🟢 MEDIUM | 🟢 Medium | 🟢 Medium | 🟢 Good | 🟢 2-5 files | Small | `@status:open` Not started |
| A4 | 🔵 NEXT | `isPrecededByBalanceMarker` uses substring markers ("bal", "due"), so a nearby word can hide the real amount | 🟢 MEDIUM | 🟢 Medium | 🟢 Medium | 🟢 Good | 🟢 2-5 files | Small | `@status:open` Not started |
| A5 | 🔵 NEXT | Categorizer rules are substring matches ("rta", "nol", "osn", "yas" inside other merchant names) | ⚪ LOW | ⚪ Low | ⚪ Low | 🟢 Good | 🟢 2-5 files | Small | `@status:open` Not started |
| A6 | 🔴 THIS | "Minimum payment due" credit-card reminder SMS are likely logged as a purchase or card payment; they must be ignored | 🟡 HIGH | ⚪ Low | 🟡 High | 🟠 Excellent | 🟢 2-5 files | Small | `@status:open` Not started |
| A7 | ⚪ SOMEDAY | Two identical date-only SMS texts are treated as one transaction (accepted trade-off) | ⚪ LOW | 🟢 Medium | ⚪ Low | 🟡 Marginal | 🟢 2-5 files | Medium | `@status:open` Accepted trade-off |
| A8 | 🔵 NEXT | JS prototype notification shows card bill payments as "+AED" (like income) | ⚪ LOW | ⚪ Low | ⚪ Low | 🟢 Good | ⚪ 1 file | Trivial | `@status:open` Gate says do now; handed to developer |
| A9 | 🔴 THIS | Delete in `TransactionDetailView` waits 400 ms after dismiss; confirm on a device that it is safe and smooth | 🟢 MEDIUM | ⚪ Low | 🟢 Medium | 🟢 Good | ⚪ 1 file | Small | `@status:open` Verify on device |

### Detail - Audit findings

- **A1** - From the Swift quality review (2026-11-17). App Shortcut phrases in `Masroofi/Intents/LogBankMessageIntent.swift` (`MasroofiShortcuts`) and the widget's display name/description in `MasroofiWidget/SafeToSpendWidget.swift` are English only. App Shortcut phrases are localized through an `AppShortcuts.xcstrings` catalog; widget strings through `Localizable.xcstrings` (the widget target got the catalog in 773b646). Use natural Gulf Arabic. Logged 2026-11-17. Deferred because: scope (the review fixed blockers and majors only).
  **Verify-still-open:** `ls Masroofi/Resources/AppShortcuts.xcstrings; grep -n "phrases:" Masroofi/Intents/LogBankMessageIntent.swift` — expect: no AppShortcuts.xcstrings file and English-only phrases.
- **A2** - From the Swift quality review (2026-11-17). `MasroofiCore/Sources/MasroofiCore/SafeToSpend.swift` clamps payday with `min(max(payday, 1), 28)` and both pickers in `Masroofi/Views/SetupFlowView.swift` offer `1...28`. Users paid on the 29th–31st (or "last day of the month") can't set it. Fix needs month-length handling (February, 30-day months) and tests. Logged 2026-11-17. Deferred because: scope.
  **Verify-still-open:** `grep -n "28" MasroofiCore/Sources/MasroofiCore/SafeToSpend.swift Masroofi/Views/SetupFlowView.swift` — expect: the `min(..., 28)` clamp and two `1...28` pickers.
- **A3** - From the Swift quality review (2026-11-17). English keywords became whole-word in 773b646, but Arabic ones still use plain substring matching (`containsWord` falls back to `contains` for non-ASCII; JS `has()` does `s.includes(w)`). Example: "رفض" in the ignore list (`BankMessageParser.swift` around line 94, `prototype/parser.js` line 7) can match inside longer words and drop a real transaction. Arabic attaches prefixes (و، ال، ب), so a strict word boundary could miss real matches; needs care and tests in both Swift and JS. Logged 2026-11-17. Deferred because: scope.
  **Verify-still-open:** `grep -n "if (!ASCII.test(w)) return s.includes(w)" prototype/parser.js` — expect: the substring fallback still present.
- **A4** - From the Swift quality review (2026-11-17). `balanceMarkers` (`MasroofiCore/Sources/MasroofiCore/BankMessageParser.swift`) and `BALANCE_MARKERS` (`prototype/parser.js`) are checked with `before.contains(marker)` over the 28 characters before an amount, so short markers like "bal" and "due" match inside other words and the real amount can be skipped as a balance. Fix in both copies with tests. Logged 2026-11-17. Deferred because: scope.
  **Verify-still-open:** `grep -n "balanceMarkers.contains { before.contains" MasroofiCore/Sources/MasroofiCore/BankMessageParser.swift` — expect: one match.
- **A5** - From the Swift quality review (2026-11-17). `MasroofiCore/Sources/MasroofiCore/Categorizer.swift` and `prototype/parser.js` (`RULES`, `categorize`) match rules with `contains`/`includes`, so "rta", "nol", "osn" and "yas" fire inside unrelated merchant names. Learned rules (user corrections) also match by substring. Impact is a wrong category the user can correct. Logged 2026-11-17. Deferred because: scope.
  **Verify-still-open:** `grep -n "padded.contains" MasroofiCore/Sources/MasroofiCore/Categorizer.swift` — expect: substring rule lookup still present.
- **A6** - From the Swift quality review (2026-11-17). Credit-card statement reminders ("Minimum payment due AED X by DD/MM") contain an amount and card wording, so the parser likely logs them as a purchase or as the new `cardPayment` kind. Nothing in `BankMessageParser.swift` or `prototype/parser.js` mentions "minimum" today. The user has a credit card, so this will show up as phantom spending or a phantom payment. Add ignore keywords (English and Arabic, e.g. "minimum payment", "min. due", "الحد الأدنى") in both Swift and JS with tests; a real reminder SMS from the user's bank (S1) would make the test exact. Logged 2026-11-17. Deferred because: scope (parser change in two copies, for the parser developer).
  **Verify-still-open:** `grep -rni "minimum" MasroofiCore/Sources prototype/parser.js` — expect: no matches.
- **A7** - From the Swift quality review (2026-11-17). `DuplicateDetector` (`MasroofiCore/Sources/MasroofiCore/SafeToSpend.swift`) fingerprints the parsed message; when an SMS carries only a date (no time), two genuinely separate but identical purchases on the same day get the same fingerprint and the second is dropped. Accepted as a trade-off against double-logging forwarded or repeated SMS. Revisit only if users report missing transactions. Logged 2026-11-17. Deferred because: scope (accepted trade-off).
- **A8** - From the Swift quality review (2026-11-17). `prototype/index.html`: `isExp` (around line 336) covers only purchase, withdrawal and transferOut, so a `cardPayment` falls into the income branch of the notification (around line 506) and shows `+AED`. Prototype only, not the iOS app. The deferral gate (Trivial + 1 file) routes this to do-now; logged at the Lead's request and handed to the developer. Logged 2026-11-17. Deferred because: scope.
  **Verify-still-open:** `grep -n 'const isExp = t => \["purchase", "withdrawal", "transferOut"\]' prototype/index.html` — expect: one match without `cardPayment`.
- **A9** - From the Swift quality review (2026-11-17). `Masroofi/Views/ActivityView.swift` (`TransactionDetailView`, around line 103) dismisses, then `Task.sleep(for: .milliseconds(400))` before deleting, so the list does not touch a deleted SwiftData object. Timing-based; confirm on a real iPhone that delete never crashes and the list updates cleanly. Needs S5/S10 (a build) first. Logged 2026-11-17. Deferred because: scaffolding (needs a device build).
  **Verify-still-open:** `grep -n "milliseconds(400)" Masroofi/Views/ActivityView.swift` — expect: one match.

---

## 4. User-reported / observed

| # | Target | Finding | Urgency | Risk: Fix | Risk: No Fix | ROI | Blast Radius | Fix Effort | Status |
|---|---|---|---|---|---|---|---|---|---|
| U1 | 🔵 NEXT | FX rates in `AppSettings.fxToAED` are hard-coded estimates; refresh them or use the bank-posted AED amount | 🟢 MEDIUM | ⚪ Low | 🟢 Medium | 🟢 Good | 🟢 2-5 files | Small | `@status:open` Not started |

### Detail - User-reported / observed

- **U1** - `Masroofi/Models/Models.swift` `AppSettings.fxToAED` holds fixed rates ("Rough rates for showing foreign purchases in AED"). Only USD is exact (pegged at 3.6725); EUR, GBP, INR, PKR, EGP and others drift, so AED totals for foreign spending will be off. Options: prefer the AED amount the bank posts in the SMS when present, or refresh rates periodically (no server today, so this needs thought to keep the privacy promise). Logged 2026-11-17. Deferred because: scope (not needed for a v1.0 that is mostly AED spending).
  **Verify-still-open:** `grep -n "fxToAED" Masroofi/Models/Models.swift` — expect: a `static let fxToAED` dictionary of literal rates.
