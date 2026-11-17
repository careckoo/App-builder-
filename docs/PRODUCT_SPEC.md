# Masroofi v1 Product Spec · مواصفات المنتج

Status: draft for the Lead and the user · 2026-11-17 · Working name "Masroofi" (rename pending, UNFORGET S8).
Body in English; Arabic UI copy is Gulf Arabic, in quotes. Amounts show as `AED 120` and stay left-to-right in both languages.

---

## 1. Principle · المبدأ

**One honest number a day, kept up to date for you.** Masroofi tells you how much you can spend today and still reach payday comfortably, and keeps that number right without you typing. Everything else (lists, charts, plans) exists to make that number trustworthy. If a feature makes the home screen busier or asks the user to do work the phone could do, it doesn't ship.

What makes us better than OutCap:

| | OutCap (seen) | Masroofi |
|---|---|---|
| Automatic sources | Bank SMS only ("waiting for a message") | **Three**: Apple Pay (Wallet "Transaction" automation), bank SMS, bank alert email, merged so one purchase shows once. Keeps working as UAE banks move alerts into their apps. |
| Setup | Manual salary, payday, obligations | Salary amount and payday **detected from the first salary message**; bills, subscriptions and own accounts **suggested** from what the bank already tells us |
| Unreadable message | "Teach us" (sends to them) | **Teach Masroofi on the phone**: tap the amount and merchant once, a local template is saved. Nothing leaves the device. |
| UAE fit | Saudi-first | UAE banks and sender IDs, UAE merchants and billers (DEWA, TAQA/ADDC, SEWA, Salik, Etisalat/e&, du, Tabby, Tamara), Sat–Sun weekend salary shift, Hijri seasons, school-fee months |
| Free tier | Widget and carry-over are Pro | Automation, the daily number, widget, Siri, bills and alerts that protect money are **always free** |
| Privacy | On-device | On-device, no server, no analytics SDK, optional Face ID lock, one tap to delete stored message text |

### Glossary (use these words everywhere, so we don't sound like the competitor)

| English | Gulf Arabic | Notes |
|---|---|---|
| Safe to spend today | "تقدر تصرف اليوم" | Home headline |
| Today's amount | "مصروف اليوم" | Short form. Avoid "حد اليوم" (competitor's term) |
| Pay cycle | "دورة الراتب" | |
| Left until payday | "المتبقي حتى الراتب" | |
| Fixed bills | "الفواتير الثابتة" | Rent, school, utilities, installments |
| Outside today's amount | "برّا مصروف اليوم" | Comes from the cycle, not today |
| Between your accounts | "بين حساباتك" | Own transfers, card bill payments |
| Money in | "فلوس داخلة" | Transfers, bonuses, refunds |
| Savings goal | "هدف ادخار" | |
| Leftover | "اللي تبقّى" | |

---

## 2. Features by tab · الميزات حسب التبويب

Five tabs (HIG maximum on iPhone): **Today "اليوم"** · **Activity "الحركات"** · **Insights "نظرة"** · **Plan "الخطة"** · **Settings "الإعدادات"**. Plan replaces today's "Budgets" tab.

Legend: **Auto** = what happens without the user. **Ver** = 1.0 (TestFlight) or 1.1. OutCap equivalent in brackets where one exists.

### 2.1 Today · اليوم (deliberately small)

| # | Feature | What it does | Auto | Tier | Ver |
|---|---|---|---|---|---|
| T1 | Today's number + ring | Big "AED 120" with "تقدر تصرف اليوم" and a ring that empties as you spend [big ring] | Recomputes on every logged payment, at midnight, and when salary lands | Free | 1.0 |
| T2 | Context line | "مساء الخير يا سالم · 6 أيام حتى الراتب · المتبقي AED 2,450" [greeting, days to payday, remaining from salary] | Greeting follows time of day; name optional | Free | 1.0 |
| T3 | Cycle chip | "اليوم 24 من 31 · 38 عملية". Tap opens the cycle summary [profile ring header] | | Free | 1.0 |
| T4 | Status word | Relaxed / On track / Careful / Over, colour on the ring | | Free | 1.0 |
| T5 | Last 3 payments | With source badge (Apple Pay, SMS, email, hand) | | Free | 1.0 |
| T6 | Add (+) | Amount keypad, merchant optional, category guessed. Cash, or anything the automations missed [add manually] | Category from merchant | Free | 1.0 |
| T7 | Paste a message | Paste an old bank SMS or email | | Free | 1.0 |
| T8 | Live empty state | Instead of "waiting for first bank message": a checklist of connected sources, each turning on when its first payment arrives ("Apple Pay: شغّال · ADIB: ننتظر أول رسالة") [empty state] | Updates itself | Free | 1.0 |
| T9 | Source health banner | If a source that normally logs goes quiet for 4 days, one calm banner with a "Fix it" link to the setup steps | Yes | Free | 1.0 |

Not on Today, on purpose: obligations total, link status tiles, history (OutCap's quick tiles). They live in Plan, Settings and Activity. The home screen stays one number.

### 2.2 Activity · الحركات

| # | Feature | What it does | Auto | Tier | Ver |
|---|---|---|---|---|---|
| A1 | Transaction list | By day, searchable, source badge, foreign amounts with AED estimate [history] | | Free | 1.0 |
| A2 | Cross-source merge | Apple Pay tap + bank SMS for the same purchase show once, with both sources in detail | Yes | Free | 1.0 |
| A3 | Detail and fix | Original message (on device), change category ("دايماً لهذا المتجر"), mark as: outside today's amount, between my accounts, fixed bill, refund | Category learns from the correction | Free | 1.0 |
| A4 | Categories view | Segmented "القائمة / الفئات": per-cycle breakdown with bars [categories tab] | | Free | 1.0 |
| A5 | Edit categories | Rename, icon, add custom; merge two categories in 1.1 [edit categories] | | Free | 1.0 |
| A6 | Unread messages | A "ما قدرنا نقراها" section for bank messages that came in but didn't parse, never silently dropped | Yes | Free | 1.0 |
| A7 | Teach Masroofi | On an unread message the user taps the amount, then the merchant, in the message text. A local template is saved for that sender and used before the generic parser next time. No server ["teach us"] | Learns per sender | Free | 1.1 |
| A8 | Refund matching | A credit from the same merchant within 30 days offsets the purchase and gives today's amount back | Yes | Free | 1.1 |
| A9 | CSV export | Cycle or all time, share sheet | | Free | 1.0 |

Automation features are never paywalled: a user who can't teach a message stops trusting the number.

### 2.3 Insights · نظرة

| # | Feature | What it does | Auto | Tier | Ver |
|---|---|---|---|---|---|
| I1 | Weekly pulse | Days within today's amount, total kept under it this week [weekly pulse, days within limit, total under limit] | | Free | 1.0 |
| I2 | 7-day chart | Daily bars with a line at each day's amount; bars calm / amber / coral [daily bar chart] | | Free | 1.0 |
| I3 | Cycle report | Totals, top categories, days within amount, biggest day. Unlocks after 3 days of data [cycle report] | Ready the morning after the cycle ends | Free (compare with last cycle: Pro) | 1.0 |
| I4 | Will my salary last? | Projects the cycle to payday from your pace plus bills still due: "على هالمعدّل يتبقى لك AED 300 يوم الراتب" or "بتخلص قبل الراتب بـ 4 أيام" | Recomputed daily | Pro | 1.0 |
| I5 | Money-leak finder | Small, frequent purchases grouped by merchant: "17 مرة قهوة · AED 340 هالدورة" [paywall leak screen] | After 10 days of data | Pro (top 1 shown free as a teaser) | 1.0 |
| I6 | Duplicate charge check | Same merchant, same amount, same source within 10 minutes (not a cross-source echo) → alert | Yes | Free | 1.0 |
| I7 | Unusual spend | Payment over 3× your median for that category or merchant → alert | After 3 weeks | Pro | 1.1 |
| I8 | Your patterns | Weekday vs weekend, the week after payday, busiest merchants and hours. After 21 days [your patterns] | | Pro | 1.1 |
| I9 | Cycle story | Swipeable end-of-cycle recap, shareable as an image with amounts hidden by default [weekly story] | | Pro | 1.1 |

### 2.4 Plan · الخطة (budgets, bills, savings, income)

| # | Feature | What it does | Auto | Tier | Ver |
|---|---|---|---|---|---|
| P1 | Income | Fixed salary or variable; monthly amount; extra fixed income (housing allowance, pension, social support "دعم"); opening balance with start date for a mid-cycle start [income & salary] | | Free | 1.0 |
| P2 | Payday | Day 1–31 or "last working day" (fixes UNFORGET A2). Weekend rule: if payday falls on Sat/Sun, "قبلها / بعدها / نفس اليوم" (user's choice; government and many private payrolls differ) [salary moves on weekend] | Shift computed each month | Free | 1.0 |
| P3 | Salary detection | First salary credit ("salary", "راتب", "SAL", or the largest credit near payday) → "راتبك نزل AED 18,250 يوم 25. نعتمده؟" Never changes the plan silently | Suggests amount and day; the cycle starts on the day salary actually lands, so an early Eid salary starts the new cycle early | Free | 1.0 |
| P4 | Variable income | Plan from the average of the last 3 incomes, or "only what's come in" mode | | Free | 1.1 |
| P5 | Money in | Transfers, bonuses: ask once per large credit "نضيفها لمصروف الدورة / للادخار / مو لي (استرجاع)" [received amounts] | Remembers the answer per sender | Free | 1.0 |
| P6 | Fixed bills | Rent, school fees, DEWA/TAQA/ADDC/SEWA, e&/du, Tabby/Tamara/postpay installments. Taken off the cycle up front [obligations] | Ticked paid when the bank message matches | Free | 1.0 |
| P7 | Subscription & recurring finder | 1.0: known subscriptions (Netflix, OSN+, Spotify, Shahid, iCloud, Anghami…) suggested on first charge. 1.1: any merchant charged ~monthly (26–35 days apart, amount ±10%, 2+ times) | Suggests "نضيفه للفواتير الثابتة؟" | Free | 1.0 / 1.1 |
| P8 | Outside today's amount | Rules: outgoing transfers outside automatically (toggle, default off); bills & installments outside automatically (toggle, default on); mark any one payment as exceptional [outside today's limit] | Applies on log | Free | 1.0 |
| P9 | My accounts & cards | Card and account endings seen in messages are collected; "تحوّلت فلوس لحساب ••456. هذا حسابك؟" Yes → transfers between own accounts and card bill payments never touch today's amount [transfers to my accounts, my cards] | Detects endings; asks once | Free | 1.0 |
| P10 | Per-card cap | A monthly cap on one card (e.g. the credit card) | Tracked automatically | Pro | 1.1 |
| P11 | Leftover | "اللي تبقّى اليوم يروح: لبكرة / للادخار" (OutCap's carry-over is Pro; ours is free and adds the savings sweep) | Midnight | Free | 1.0 |
| P12 | When I go over | "نوزّعها على باقي الأيام" (default) / "من الادخار" / "نبدأ من جديد الدورة الجاية" [recovery plan] | | Free | 1.0 |
| P13 | Category budgets | Monthly limit per category with progress bars | Updated on log | Free: 3 · Pro: unlimited | 1.0 |
| P14 | Savings goals | Goal with target and date (car, Umrah, wedding, travel, "رمضان والعيد"); monthly amount reserved from salary before today's amount is worked out. The Ramadan & Eid preset fills its date from the Umm al-Qura calendar on device (Ramadan 1448 starts around 8 Feb 2027) [savings] | Reserve taken on payday | Free: 1 · Pro: unlimited | 1.0 |
| P15 | Giving | Monthly sadaqah as an amount or % of salary, reserved like a bill [charity setting] | On payday | Free | 1.0 |
| P16 | Season planner | Ramadan, Eid al-Fitr, Eid al-Adha, school terms (Sep, Jan, Apr), summer travel as planned spikes: suggests reserving across the months before | Suggests 6 weeks ahead | Pro | 1.1 |
| P17 | Zakat helper | Savings and assets the user enters, nisab value the user enters (no network), 2.5% above it, reminder on a chosen Hijri date. Labelled as a calculator, not a ruling | | Pro | 1.1 |
| P18 | Family budget | Shared cycle or shared goal with a spouse via CloudKit sharing; each phone's automations log into it. Data stays in the users' iCloud, so "Data Not Collected" still holds | | Pro | 1.1 |

### 2.5 Settings · الإعدادات

| # | Feature | What it does | Tier | Ver |
|---|---|---|---|---|
| S1 | Automatic tracking | Apple Pay, bank SMS (per bank), email alerts: status and "last received" per source; setup steps [link status] | Free | 1.0 |
| S2 | Notifications | Grouped toggles, see section 5 | Free | 1.0 |
| S3 | Appearance | System / Light / Dark | Free | 1.0 |
| S4 | Digits | Western "123" (default, matches bank messages, shows `AED 120`) or Arabic "١٢٣" (shows "١٢٠ درهم") | Free | 1.0 |
| S5 | Language | Opens iOS per-app language | Free | 1.0 |
| S6 | Keep message text | On by default, device only; "امسح نصوص الرسائل كلها" button | Free | 1.0 |
| S7 | Face ID lock | Lock the app; widget can hide the amount | Free | 1.0 |
| S8 | Widgets & Siri | Home and Lock Screen widget, "How much can I spend today?" (OutCap: widget is Pro) | Free | 1.0 |
| S9 | Control Center "Add cash" | iOS 18 control and interactive widget button | Free | 1.1 |
| S10 | Setup guide | Step screens with a short screen recording per step [setup video] | Free | 1.0 steps / 1.1 recordings |
| S11 | Unread messages | Link to Activity A6/A7 ["bank message we couldn't read?"] | Free | 1.0 |
| S12 | Pro | Plans, offer code redemption (StoreKit sheet), restore purchases [promo code, restore] | | 1.0 |
| S13 | About | What's new, send feedback (mail, no SDK), privacy policy, about | Free | 1.0 |
| S14 | Backup | Export/import an encrypted file | Free | 1.1 |

### 2.6 "Smarter" ideas evaluated

| Idea | Verdict | Where |
|---|---|---|
| Detect payday + salary from first salary message | Keep, suggest-only | P3, 1.0 |
| Detect recurring bills/subscriptions | Keep; known list 1.0, pattern 1.1 (needs two months of data anyway) | P7 |
| Detect own accounts/cards from endings | Keep, ask once per ending | P9, 1.0 |
| Teach Masroofi (local template) | Keep; inbox 1.0, tap-to-teach 1.1 (needs careful matching and tests in Swift and JS) | A6, A7 |
| Duplicate-charge alert | Keep, free (protects money) | I6, 1.0 |
| Unusual-spend alert | Keep, needs history | I7, 1.1 |
| "Will my salary last?" | Keep, Pro headline feature | I4, 1.0 |
| Money-leak finder | Keep, Pro with a free teaser | I5, 1.0 |
| End-of-day summary | Keep, default on at 21:00 | N5 |
| Weekend salary shift with choice | Keep | P2, 1.0 |
| Ramadan/Eid, school months | Goal preset 1.0, full planner 1.1 | P14, P16 |
| Zakat helper | Keep as calculator | P17, 1.1 |
| Family sharing | Keep | P18, 1.1 |
| Digits, light/dark | Keep | S3, S4 |
| Added by us: source health check, live empty state, cycle starts when salary lands, refund matching, Face ID lock, leftover-to-savings | Keep | T8, T9, P3, A8, S7, P11 |
| Dropped: tips/news notifications | Drop. Marketing pushes erode trust in the money alerts | |

---

## 3. Free vs Pro · المجاني والمدفوع

**Rule:** free = everything automatic, the daily number, and anything that protects money. Pro = the smart layer and "more of" things.

| Free (forever) | Pro "مصروفي برو" |
|---|---|
| All three automatic sources, merge, manual add, paste | Will my salary last? (I4) |
| Today's number, ring, widget, Siri | Money-leak finder, full list (I5) |
| Fixed bills with auto-tick, subscription suggestions | Unusual-spend alert, patterns, cycle story (1.1) |
| Salary and own-account detection | Cycle-vs-cycle comparison |
| Leftover and overspend rules, outside-amount rules | Unlimited budgets and savings goals |
| 3 budgets, 1 savings goal, giving | Season planner, Zakat helper (1.1) |
| Duplicate-charge alert, source health, unread inbox, teach | Per-card caps, family budget (1.1) |
| Insights basics, cycle report, CSV, Face ID | Alternate app icons |

**Suggested UAE pricing**

| Plan | Price | Why |
|---|---|---|
| Yearly | **AED 59.99** with 7-day free trial | Lower than OutCap's AED 79.99 to win switchers; about AED 5 a month, less than one coffee; no server costs to recover |
| Monthly | **AED 9.99** | Deliberately pricier per month so yearly is the obvious choice (50% saving) |
| Lifetime | **AED 179.99** (launch offer) | Fits a privacy-first, no-server app; attracts users wary of subscriptions |

Turn on Apple Family Sharing for all plans (one purchase covers the household; fits the family budget). Use App Store offer codes for promos. Paywall headline uses our own framing: "اعرف وين تروح فلوسك قبل لا تروح" / "See where your money goes before it's gone", with the free leak teaser underneath.

---

## 4. Onboarding (4 screens) · البداية

| # | Screen | Copy (EN / AR) | Notes |
|---|---|---|---|
| 1 | Promise | "One number a day. We keep it right." / "رقم واحد كل يوم، وإحنا نضبطه لك." Sub: "No typing. Your data never leaves this iPhone." / "بدون كتابة أرقام. بياناتك ما تطلع من هالآيفون." CTA "Let's start" / "يلا نبدأ" | |
| 2 | Your salary | "What should we call you?" / "شو نناديك؟" (optional) · salary · payday + weekend rule. Footer: "Skip this and we'll pick it up from your first salary message." / "تقدر تتخطى، ونعرفه من أول رسالة راتب." | The only typed numbers |
| 3 | Apple Pay first | "Track every Apple Pay tap" / "كل دفعة Apple Pay تنحسب لحالها". 3 steps with "Open Shortcuts" / "افتح الاختصارات", then a live check: "Tap your card anywhere, we're listening" / "ادفع بأي مكان، وإحنا ننتظر" | Works with any card in Wallet, even if the bank sends no SMS |
| 4 | More sources + alerts | Two optional cards: "Bank SMS" / "رسائل البنك" (pick banks) and "Email alerts" / "تنبيهات الإيميل". Then the notification ask in context: "Want a heads-up after each payment?" / "تبي نبلغك بعد كل دفعة؟" CTA "Done" / "تم" | "I'll finish this later" / "بكمّل بعدين" always visible |

---

## 5. Notifications · التنبيهات

Settings groups: Daily · Each payment · Today's amount · Salary & bills · Smart alerts · Reports. Amounts use LTR isolates in Arabic. `{name}` is omitted when not set.

| # | Trigger | English | Gulf Arabic | Default | Tier |
|---|---|---|---|---|---|
| N1 | Morning, 8:00 (adjustable) | "Good morning, {name}. You've got AED 120 for today." | "صباح الخير يا {name}، مصروفك اليوم AED 120." | On | Free |
| N2 | Each logged payment | "AED 45.50 at Carrefour. AED 74.50 left today." | "AED 45.50 في كارفور. باقي لك اليوم AED 74.50." | On | Free |
| N3 | 80% of today's amount used | "Only AED 20 left for today. Easy does it." | "باقي لك AED 20 بس لليوم. خفّف شوي." | On | Free |
| N4 | Over today's amount | "AED 35 over today. We'll spread it over the next 12 days, about AED 3 a day." | "تعدّيت مصروف اليوم بـ AED 35. بنوزّعها على الـ 12 يوم الجاية، تقريباً AED 3 باليوم." | On | Free |
| N5 | End of day, 21:00 | "Today: AED 85 of AED 120. Nice, AED 35 rolls into tomorrow." | "صرفت اليوم AED 85 من AED 120. كفو! الـ AED 35 الباقية تنضاف لبكرة." | On | Free |
| N6 | Payday (salary detected) | "Salary's in: AED 18,250. New cycle, AED 410 a day." | "نزل الراتب: AED 18,250. بدت دورة جديدة، ومصروفك اليومي AED 410." | On | Free |
| N7 | Salary differs from plan | "Your salary came in at AED 18,250, not AED 18,000. Update your plan?" | "راتبك نزل AED 18,250 مو AED 18,000. نحدّث الخطة؟" | On | Free |
| N8 | Bill due in 2 days, not yet paid | "Rent (AED 6,000) is due on the 1st." | "موعد الإيجار (AED 6,000) يوم 1." | On | Free |
| N9 | Bill auto-ticked | "DEWA paid: AED 412. Ticked off for you." | "انسدّت فاتورة ديوا: AED 412. علّمناها لك." | On | Free |
| N10 | Duplicate charge (time-sensitive) | "Charged twice? AED 120 at Noon, 2 minutes apart." | "انخصم منك مرتين؟ AED 120 من نون، بينهم دقيقتين." | On | Free |
| N11 | Own account question | "Money moved to account ••456. Is that yours?" (Yes / No) | "تحوّلت فلوس لحساب ••456. هذا حسابك؟" ("إي" / "لا") | On | Free |
| N12 | Subscription found | "Spotify looks monthly (AED 21.99). Add it to fixed bills?" | "شكل Spotify اشتراك شهري (AED 21.99). نضيفه للفواتير الثابتة؟" | On | Free |
| N13 | Unread message | "Got a message from ADIB we couldn't read. Show us once and we'll get it next time." | "وصلتنا رسالة من ADIB ما عرفنا نقراها. علّمنا مرة وحدة ونقراها بعدين." | On | Free |
| N14 | Source quiet 4 days | "Nothing from Apple Pay or ADIB for 4 days. Is the automation still on?" | "ما وصلنا شي من Apple Pay ولا ADIB من 4 أيام. الأتمتة للحين شغّالة؟" | On | Free |
| N15 | Cycle report ready | "Your cycle report is ready: within your amount 22 of 30 days." | "تقرير دورتك جاهز: التزمت بمصروفك 22 يوم من 30." | On | Free |
| N16 | Streak | "7 days in a row within your amount." | "7 أيام ورا بعض وأنت ضمن مصروفك. كفو عليك!" | On | Free |
| N17 | Forecast falls short (max weekly) | "At this pace, money runs out 4 days before payday. AED 25 less a day gets you there." | "على هالمعدّل، فلوسك بتخلص قبل الراتب بـ 4 أيام. لو خفّفت AED 25 باليوم توصل براحة." | On | Pro |
| N18 | Unusual spend (1.1) | "Bigger than usual: AED 950 at Sharaf DG, about 4× your normal for electronics." | "مبلغ أكبر من العادة: AED 950 في شرف دي جي، تقريباً 4 أضعاف معدّلك في الإلكترونيات." | On | Pro |
| N19 | Season ahead (1.1) | "Ramadan is 3 weeks away. Set aside AED 1,500 from this salary?" | "باقي على رمضان 3 أسابيع. نحجز AED 1,500 من هالراتب؟" | On | Pro |

Rules: at most one N3/N4 per day; N2 and N3/N4 merge into one banner when they coincide; quiet hours follow iOS Focus; no marketing notifications.

---

## 6. Visual direction · الهوية البصرية

Goal: unmistakably not OutCap (dark green + gold) and still native iOS.

**Palette "Gulf dusk"**: calm indigo-blue brand, warm sand surfaces, status colours that don't shame.

| Role | Light | Dark | Notes |
|---|---|---|---|
| Brand / accent | Indigo `#3A4FE0` | `#7C8CFF` | Replaces the current teal in `Theme.swift`, which reads close to the competitor's green |
| Surface tint (cards) | Sand `#F6EFE4` | `#1C1A24` | Over system grouped backgrounds; never full-screen colour |
| Relaxed | Mint `#2BB59A` | `#45D3B5` | |
| Careful | Amber `#F2A33A` | `#FFB95C` | |
| Over | Coral `#F0625A` | `#FF7B73` | Softer than red: "adjust", not "fail" |

Status colours are for the ring, bars and icons; text stays in system label colours (mint and amber on white are below AA contrast for text). Hex values are a starting point, to be contrast-checked on device. Status is never shown by colour alone (word + icon too).

**Type**: SF Pro for UI, **SF Pro Rounded** for the big number (`.monospacedDigit()` so it doesn't jump); **SF Arabic** for Arabic (the system face, so Dynamic Type and weights just work). No bundled fonts in 1.0. Arabic line height +15% to avoid clipped diacritics; test at the largest accessibility size.

**Home concept "The day ring and the payday moon"**: one thick ring holds today's amount and empties as you spend; the number in the centre. Under it a small crescent fills as payday approaches (the cycle as a moon phase): a quiet, local motif that replaces OutCap's second "day 24 of 31" ring. Nothing else above the fold.

**RTL**: the ring does not mirror (clock metaphor, like Activity rings); progress bars, chevrons, back buttons and the 7-day chart's time axis do mirror (today on the left in Arabic). Amounts and card endings are wrapped in LTR isolates. Merchant names stay as the bank wrote them.

**Motion**: the ring eases to its new value with a soft spring when a payment lands; the number uses `.contentTransition(.numericText())`; a light haptic on each logged payment, a success haptic on payday. Reduce Motion swaps all of this for cross-fades.

**Icon direction**: indigo crescent around a coin on sand; no green, no gold.

---

## 7. Build order for v1.0 (TestFlight) · ترتيب البناء

| Milestone | Scope | Done when |
|---|---|---|
| **M1 · The honest number** | Finish the in-progress sources (Apple Pay, SMS, email, manual, merge); outside-amount rules, own transfers and card payments in the calculation; payday 1–31 + weekend rule (A2); ignore "minimum payment due" (A6); new Today screen (T1–T8) with the new palette; 4-screen onboarding | First build on a Mac (S5) and the user lives on it for a week with correct numbers |
| **M2 · Plan that fills itself** | Salary detection and cycle-starts-on-salary (P3); money in (P5); bills auto-tick + known subscriptions (P6, P7); own-account prompts (P9); leftover and overspend choices (P11, P12); 1 savings goal with Ramadan & Eid preset (P14); giving (P15); Plan tab replaces Budgets | A fresh install with only Apple Pay + salary SMS needs no manual setup beyond screen 2 |
| **M3 · Tell me** | Notifications N1–N16; Insights free (I1–I3, I6); source health (T9); unread inbox (A6); Settings S1–S8, S10–S11, S13; widget restyle; full Arabic pass incl. App Shortcuts and widget (A1) and RTL review | Internal TestFlight to family; every screen checked in Arabic and English, light and dark, largest text size |
| **M4 · Pro + store** | StoreKit 2 plans, paywall, offer codes, restore; I4 forecast, I5 leak finder, unlimited budgets/goals, cycle comparison; App Store assets (S3) | External TestFlight |

v1.1 queue: A7 teach templates, A8 refunds, P4, P7 pattern detection, P10, P16–P18, I7–I9, S9, S14, merge categories.
