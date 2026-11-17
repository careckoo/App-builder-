import Foundation
import SwiftData
import WidgetKit
import SarfiCore

/// Turns a bank SMS or email, an Apple Pay purchase, or a manual entry into a saved transaction.
/// Used by the Shortcuts actions (App Intents), by "Paste a message" and by quick-add in the app.
@MainActor
struct TransactionLogger {
    enum Outcome {
        case saved(Transaction, SafeToSpend)
        /// Another source already logged this purchase; the existing record was filled in instead.
        case merged(Transaction)
        case duplicate
        case notATransaction
    }

    let context: ModelContext

    init(context: ModelContext = Store.container.mainContext) { self.context = context }

    /// A bank SMS or alert email. Email is recognised by a subject, an address as sender, or HTML.
    func log(message: String, sender: String?, subject: String? = nil) throws -> Outcome {
        // Same reading as the "Paste a message" preview: HTML and footer removed, an OTP subject skips
        // the email, and a subject like "Debit card purchase" helps when the body has no verb.
        let read = MessageReader.read(message, sender: sender, subject: subject)
        guard let parsed = read.parsed else { return .notATransaction }
        return try save(parsed, via: read.isEmail ? .email : .sms, original: read.text)
    }

    /// An Apple Pay purchase from the Wallet "Transaction" automation. `amountText` is whatever
    /// Shortcuts passes ("AED 45.50", "د.إ.‏ ٤٥٫٥٠"…).
    func logWallet(amountText: String, merchant: String?, card: String?) throws -> Outcome {
        guard let money = AmountText.parse(amountText) else { return .notATransaction }
        let (amount, currency) = money
        let name = merchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cardName = card?.trimmingCharacters(in: .whitespacesAndNewlines)
        // A Wallet card name sometimes ends in the last digits ("Visa 1234").
        var last4: String?
        if let c = cardName, let r = c.range(of: #"[0-9]{4}$"#, options: .regularExpression) { last4 = String(c[r]) }
        let parsed = ParsedTransaction(amount: amount, currency: currency, kind: .purchase,
                                       merchant: name.isEmpty ? nil : name, cardLast4: last4, date: .now,
                                       bankName: cardName.flatMap { BankDirectory.bankName(sender: nil, body: $0.lowercased()) })
        return try save(parsed, via: .wallet, original: nil,
                        cardName: (cardName?.isEmpty ?? true) ? nil : cardName)
    }

    /// Cash, or a card payment none of the automatic sources caught. The person chose the category.
    func logManual(amount: Decimal, currency: String = "AED", merchant: String, category: CategoryID,
                   date: Date = .now) throws -> Transaction {
        CycleReset.runIfNeeded(context: context)
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = ParsedTransaction(amount: amount, currency: currency, kind: .purchase,
                                       merchant: name.isEmpty ? nil : name, date: date)
        let rate = AppSettings.fxToAED[currency] ?? 1
        let tx = Transaction(parsed: parsed, category: category, amountAED: amount * rate, source: nil, via: .manual)
        // Same as the automatic sources: paying a bill by hand ticks it off instead of counting twice.
        if tx.isExpense, let bill = try matchingObligation(for: tx) {
            bill.isPaidThisCycle = true
            tx.isFixedObligation = true
        }
        context.insert(tx)
        try context.save()
        WidgetCenter.shared.reloadAllTimelines()
        return tx
    }

    private func save(_ parsed: ParsedTransaction, via source: TransactionSource, original: String?,
                      cardName: String? = nil) throws -> Outcome {
        CycleReset.runIfNeeded(context: context)

        // Ignore the same purchase arriving twice. Look up by fingerprint, not by "logged in the last
        // few minutes": the transaction date can be the bank's own timestamp or, for a pasted old
        // message, a day in the past, so a recency window on `date` would miss those repeats.
        let fp = DuplicateDetector.fingerprint(parsed)
        let same = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.fingerprint == fp }))
        let date = parsed.date ?? .now
        // Wallet runs once per real tap, so a repeat Apple Pay fingerprint (same amount and shop, two
        // coffees) is real spending. Wallet vs bank message is handled by the cross-source merge below.
        if source != .wallet,
           DuplicateDetector.isDuplicate(parsed, at: date, recent: same.map { ($0.fingerprint, $0.date) }) {
            return .duplicate
        }
        // The exact same text again is a repeat only when the text pins down one moment (its own
        // time, or a balance). "AED 15 at ADNOC" can honestly happen twice in a day.
        if let original, DuplicateDetector.canMatchByText(original, parsed: parsed) {
            let key = DuplicateDetector.normalizedText(original)
            if same.contains(where: { $0.sourceMessage.map(DuplicateDetector.normalizedText) == key }) { return .duplicate }
        }

        let rate = AppSettings.fxToAED[parsed.currency] ?? 1
        let amountAED = parsed.amount * rate

        // The same Apple Pay purchase can also arrive as the bank's SMS or email, a few seconds apart.
        let lo = date.addingTimeInterval(-CrossSourceDuplicate.window)
        let hi = date.addingTimeInterval(CrossSourceDuplicate.window)
        let nearby = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.date >= lo && $0.date <= hi }))
        let incoming = CrossSourceDuplicate.Record(source: source, kind: parsed.kind, amount: parsed.amount,
                                                   currency: parsed.currency, amountAED: amountAED, date: date,
                                                   merchant: parsed.merchant ?? "", cardLast4: parsed.cardLast4)
        if let i = CrossSourceDuplicate.match(for: incoming, among: nearby.map(\.record)) {
            let existing = nearby[i]
            try enrich(existing, with: parsed, fingerprint: fp, from: source, original: original, cardName: cardName)
            try context.save()
            WidgetCenter.shared.reloadAllTimelines()
            return .merged(existing)
        }

        let category = try categorizer().category(for: parsed)
        let tx = Transaction(parsed: parsed, category: category, amountAED: amountAED, source: original,
                             via: source, cardName: cardName)

        // A payment that matches a bill (e.g. DEWA, school, Tabby) marks that bill paid instead of counting twice.
        if tx.isExpense, let bill = try matchingObligation(for: tx) {
            bill.isPaidThisCycle = true
            tx.isFixedObligation = true
        }

        context.insert(tx)
        try context.save()
        WidgetCenter.shared.reloadAllTimelines()
        return .saved(tx, try SafeToSpendCalculator(context: context).current())
    }

    private func categorizer() throws -> Categorizer {
        let rules = try context.fetch(FetchDescriptor<MerchantRule>())
        let learned = Dictionary(rules.map { ($0.keyword, CategoryID(rawValue: $0.categoryRaw) ?? .other) },
                                 uniquingKeysWith: { a, _ in a })
        return Categorizer(learned: learned)
    }

    /// Keep one record and give it the best of both: Apple Pay has the clean merchant name and the
    /// real moment; the bank message has the card digits, the bank and the balance.
    private func enrich(_ tx: Transaction, with parsed: ParsedTransaction, fingerprint: String,
                        from source: TransactionSource, original: String?, cardName: String?) throws {
        if tx.cardLast4 == nil { tx.cardLast4 = parsed.cardLast4 }
        if tx.bankName == nil { tx.bankName = parsed.bankName }
        if tx.balanceAfter == nil { tx.balanceAfter = parsed.balanceAfter }
        if tx.cardName == nil { tx.cardName = cardName }
        if tx.sourceMessage == nil { tx.sourceMessage = original }
        if tx.merchant.isEmpty, let m = parsed.merchant, !m.isEmpty {
            tx.merchant = m
            if tx.category == .other { tx.category = try categorizer().category(for: parsed) }
        }
        // A repeat of the bank message should now be caught by the fingerprint check.
        if tx.source == .wallet && source != .wallet { tx.fingerprint = fingerprint }
    }

    private func matchingObligation(for tx: Transaction) throws -> Obligation? {
        // A pasted message from last cycle must not tick off this cycle's bill.
        guard tx.date >= PayCycle.current(payday: AppSettings.payday).start else { return nil }
        let unpaid = try context.fetch(FetchDescriptor<Obligation>(predicate: #Predicate { !$0.isPaidThisCycle }))
        return unpaid.first { bill in
            let close = abs(NSDecimalNumber(decimal: bill.amount - tx.amountAED).doubleValue) <= max(5, NSDecimalNumber(decimal: bill.amount).doubleValue * 0.02)
            let title = bill.title.trimmingCharacters(in: .whitespaces)
            let named = !title.isEmpty && TextMatch.containsWord(tx.merchant, title)
            return close && (bill.categoryRaw == tx.categoryRaw || named)
        }
    }
}

extension Transaction {
    var record: CrossSourceDuplicate.Record {
        CrossSourceDuplicate.Record(source: source, kind: kind, amount: amount, currency: currency,
                                    amountAED: amountAED, date: date, merchant: merchant, cardLast4: cardLast4)
    }
}

/// Works out today's safe-to-spend number from the stored data.
@MainActor
struct SafeToSpendCalculator {
    let context: ModelContext

    /// Salary often lands a few days before payday (e.g. when payday falls on a weekend).
    static let earlyIncomeDays = 5

    func current(now: Date = .now) throws -> SafeToSpend {
        CycleReset.runIfNeeded(context: context, now: now)
        let cal = Calendar.dubai
        let cycle = PayCycle.current(payday: AppSettings.payday, today: now)
        let start = cycle.start
        // Income counts in a window shifted earlier by a few days: [start - 5d, end - 5d).
        // Shifting the end too means an early salary counts in the new cycle only, not in both.
        let incomeStart = cal.date(byAdding: .day, value: -Self.earlyIncomeDays, to: start)!
        let incomeEnd = cal.date(byAdding: .day, value: -Self.earlyIncomeDays, to: cycle.end)!
        let fetched = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.date >= incomeStart }))
        let txs = fetched.filter { $0.date >= start }
        let startOfToday = cal.startOfDay(for: now)

        let flexible = txs.filter { $0.isExpense && !$0.isFixedObligation }
        let refunds = txs.filter { $0.kind == .refund }.reduce(Decimal(0)) { $0 + $1.amountAED }
        let spentBefore = flexible.filter { $0.date < startOfToday }.reduce(Decimal(0)) { $0 + $1.amountAED } - refunds
        let spentToday = flexible.filter { $0.date >= startOfToday }.reduce(Decimal(0)) { $0 + $1.amountAED }

        // Use the salary that actually arrived; fall back to what the person told us during setup.
        // `kind` is computed, so it can't go in the #Predicate; filter here instead.
        let received = fetched
            .filter { $0.kind == .income && $0.date >= incomeStart && $0.date < incomeEnd }
            .reduce(Decimal(0)) { $0 + $1.amountAED }
        let income = max(received, AppSettings.monthlyIncome)

        let obligations = try context.fetch(FetchDescriptor<Obligation>())
        let fixedPaid = txs.filter { $0.isFixedObligation }.reduce(Decimal(0)) { $0 + $1.amountAED }
        let fixedUnpaid = obligations.filter { !$0.isPaidThisCycle }.reduce(Decimal(0)) { $0 + $1.amount }

        return SafeToSpend.compute(income: income, fixedObligations: fixedPaid + fixedUnpaid,
                                   savingsGoal: AppSettings.savingsGoal,
                                   spentBeforeToday: spentBefore, spentToday: spentToday,
                                   daysLeft: cycle.daysLeft(from: now))
    }
}
