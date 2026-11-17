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
| S1 | 🔴 THIS | Collect 20–30 real, anonymised SMS per UAE bank and add them to the parser tests (Swift + JS) | 🟡 HIGH | ⚪ Low | 🟡 High | 🟠 Excellent | 🟢 2-5 files | Large | `@status:open` Waiting on real bank messages |
| S2 | 🔴 THIS | Confirm each bank's SMS sender ID on real phones | 🟡 HIGH | ⚪ Low | 🟡 High | 🟠 Excellent | 🟢 2-5 files | Small | `@status:open` Needs real phones |
| S3 | 🔴 THIS | App icon, Arabic + English screenshots, App Store listing in both languages | 🟡 HIGH | ⚪ Low | 🟡 High | 🟠 Excellent | 🟢 2-5 files | Medium | `@status:open` Not started |
| S4 | 🔵 NEXT | Optional Pro tier (StoreKit 2): forecasts, AI monthly summary, shared family budget via CloudKit | ⚪ LOW | 🟡 High | ⚪ Low | 🟢 Good | 🔴 >15 files | Large | `@status:open` Product decision pending |
| S5 | 🔴 THIS | Swift code has never been compiled; first Xcode build (XcodeGen + build + tests) on a Mac | 🔴 CRITICAL | ⚪ Low | 🔴 Critical | 🟠 Excellent | 🟡 6-15 files | Medium | `@status:open` Blocked: no Mac in the cloud container |
| S6 | 🔴 THIS | Replace placeholder bundle ID prefix `ae.masroofi` and App Group `group.ae.masroofi.shared` with IDs the user owns | 🟡 HIGH | 🟢 Medium | 🔴 Critical | 🟠 Excellent | 🟢 2-5 files | Small | `@status:open` Needs the user's Apple Developer IDs |
| S7 | ⚪ SOMEDAY | Watch UAE Open Finance and Apple FinanceKit availability in the UAE as a no-SMS import option | ⚪ LOW | 🟡 High | ⚪ Low | 🟢 Good | 🔴 >15 files | Large | `@status:open` Watching; nothing to build yet |

### Detail - Session spillover

- **S1** - From README.md "Before release". The parser samples in `MasroofiCore` tests and `prototype/parser.test.mjs` follow typical UAE formats but are not real messages; each bank's exact wording (English and Arabic, Arabic-Indic digits) needs checking. Anonymise card numbers, balances and names before committing. Any parser change goes in both `MasroofiCore` (Swift) and `prototype/parser.js` with tests in both. Logged 2026-11-17. Deferred because: external-block (needs real SMS from real accounts).
  **Verify-still-open:** `grep -n "20–30" README.md` — expect: the unchecked "Collect 20–30 real, anonymised SMS" box under "Before release".
- **S2** - From README.md "Before release". Sender IDs (e.g. `ADCB`, `FAB`, `EmiratesNBD`) differ between banks and sometimes change; the Shortcuts automation only fires on an exact sender match, so a wrong ID means no transactions are logged. Source of truth in code: `MasroofiCore` `BankDirectory`. Logged 2026-11-17. Deferred because: external-block (needs real phones with UAE bank accounts).
  **Verify-still-open:** `grep -n "sender IDs on real phones" README.md` — expect: the unchecked box under "Before release".
- **S3** - From README.md "Before release". Needs an app icon, App Store screenshots in Arabic (RTL) and English, and listing text in Gulf Arabic and English. Submission is not possible without the icon and listing. Logged 2026-11-17. Deferred because: user-decision (branding, copy and store listing are the user's call).
  **Verify-still-open:** `grep -n "App icon, screenshots" README.md` — expect: the unchecked box under "Before release".
- **S4** - From README.md "Before release", marked optional there; targeted at v1.1 so it does not block launch. StoreKit 2 subscription for forecasts, an AI monthly summary and a shared family budget over CloudKit (`Store` in `Masroofi/Models/Models.swift` already notes CloudKit can be switched on later). An AI summary must keep the "Data Not Collected" privacy label in mind. Logged 2026-11-17. Deferred because: user-decision (pricing and scope of a paid tier).
- **S5** - The cloud container has no Mac or Xcode, so none of the Swift (16 `.swift` files across `MasroofiCore/`, `Masroofi/`, `MasroofiWidget/`) has been compiled, and `swift test` in `MasroofiCore` has not run. Only the JS copy of the parser is tested (`node prototype/parser.test.mjs`). First step on a Mac: `brew install xcodegen && xcodegen`, build both targets, run `cd MasroofiCore && swift test`, then run on a real iPhone (the Shortcuts automation needs a device). Expect compile fixes. Logged 2026-11-17. Deferred because: external-block (no Mac available).
- **S6** - Placeholders appear in `project.yml` (`bundleIdPrefix: ae.masroofi`, two `application-groups` entries), `Masroofi/Resources/Masroofi.entitlements`, `MasroofiWidget/MasroofiWidget.entitlements` and `Masroofi/Models/Models.swift` (`appGroup`). All App Group strings must match or the app, widget and Shortcut intent stop sharing the SwiftData store. Logged 2026-11-17. Deferred because: user-decision (only the user can register IDs under their Apple Developer team).
  **Verify-still-open:** `grep -rn "ae.masroofi" project.yml Masroofi/Resources/Masroofi.entitlements MasroofiWidget/MasroofiWidget.entitlements Masroofi/Models/Models.swift` — expect: the placeholder IDs still present in all four files.
- **S7** - From README.md "How no typing works". UAE Open Finance (Central Bank framework) would give direct account access through a licensed provider; Apple FinanceKit is limited to certain countries and institutions. Either would remove the one-time Shortcuts setup. Revisit when either is available in the UAE. Logged 2026-11-17. Deferred because: external-block (not available in the UAE yet).

---

## 3. Audit findings

Pending: a quality review of the Swift code is in progress (2026-11-17). Its findings will be logged here as A-rows when it reports.

| # | Target | Finding | Urgency | Risk: Fix | Risk: No Fix | ROI | Blast Radius | Fix Effort | Status |
|---|---|---|---|---|---|---|---|---|---|

### Detail - Audit findings

(none yet)

---

## 4. User-reported / observed

| # | Target | Finding | Urgency | Risk: Fix | Risk: No Fix | ROI | Blast Radius | Fix Effort | Status |
|---|---|---|---|---|---|---|---|---|---|
| U1 | 🔵 NEXT | FX rates in `AppSettings.fxToAED` are hard-coded estimates; refresh them or use the bank-posted AED amount | 🟢 MEDIUM | ⚪ Low | 🟢 Medium | 🟢 Good | 🟢 2-5 files | Small | `@status:open` Not started |

### Detail - User-reported / observed

- **U1** - `Masroofi/Models/Models.swift` `AppSettings.fxToAED` holds fixed rates ("Rough rates for showing foreign purchases in AED"). Only USD is exact (pegged at 3.6725); EUR, GBP, INR, PKR, EGP and others drift, so AED totals for foreign spending will be off. Options: prefer the AED amount the bank posts in the SMS when present, or refresh rates periodically (no server today, so this needs thought to keep the privacy promise). Logged 2026-11-17. Deferred because: scope (not needed for a v1.0 that is mostly AED spending).
  **Verify-still-open:** `grep -n "fxToAED" Masroofi/Models/Models.swift` — expect: a `static let fxToAED` dictionary of literal rates.
