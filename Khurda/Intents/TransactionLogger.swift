import Foundation
import SwiftData
import WidgetKit
import KhurdaCore

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
        /// Not understood but kept in "Messages we couldn't read", for the person to teach Khurda.
        case keptToTeach
    }

    let context: ModelContext

    // A default argument is evaluated outside the main actor (Swift 5.10), so the shared
    // context is read here, inside the @MainActor initialiser.
    init(context: ModelContext? = nil) { self.context = context ?? Store.container.mainContext }

    /// A bank SMS or alert email. Email is recognised by a subject, an address as sender, or HTML.
    func log(message: String, sender: String?, subject: String? = nil) throws -> Outcome {
        // Same reading as the "Paste a message" preview: HTML and footer removed, an OTP subject skips
        // the email, and a subject like "Debit card purchase" helps when the body has no verb.
        let read = MessageReader.read(message, sender: sender, subject: subject)
        if let parsed = read.parsed ?? learned(read.text, sender: sender) {
            return try save(parsed, via: read.isEmail ? .email : .sms, original: read.text)
        }
        if read.isWorthTeaching {
            try keepUnread(read.text, sender: sender)
            return .keptToTeach
        }
        return .notATransaction
    }

    /// Reads with a shape the person taught Khurda, newest first.
    func learned(_ text: String, sender: String?) -> ParsedTransaction? {
        let all = (try? context.fetch(FetchDescriptor<LearnedTemplate>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        for t in all {
            if let parsed = t.template?.read(text, sender: sender) { t.timesUsed += 1; return parsed }
        }
        return nil
    }

    private func keepUnread(_ text: String, sender: String?) throws {
        let existing = try context.fetch(FetchDescriptor<UnreadMessage>(predicate: #Predicate { $0.text == text }))
        guard existing.isEmpty else { return }
        context.insert(UnreadMessage(text: text, sender: sender))
        try context.save()
    }

    /// The person tapped the amount (and shop) in a message: learn its shape, then log it.
    func teach(_ template: MessageTemplate, message: String, sender: String?) throws -> Outcome {
        context.insert(LearnedTemplate(template: template, example: message))
        // Every waiting message of the same shape is read now too.
        let waiting = try context.fetch(FetchDescriptor<UnreadMessage>())
        var outcome: Outcome = .notATransaction
        for w in waiting {
            guard let parsed = template.read(w.text, sender: w.sender, date: w.receivedAt) else { continue }
            let result = try save(parsed, via: .sms, original: w.text)
            if w.text == message { outcome = result }
            context.delete(w)
        }
        if case .notATransaction = outcome, let parsed = template.read(message, sender: sender) {
            outcome = try save(parsed, via: .sms, original: message)
        }
        try context.save()
        return outcome
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
        } else {
            try matchJameya(tx)
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
        } else {
            try matchJameya(tx)
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

    /// A transfer out of exactly the share, within 10 days of an unpaid round's due date, pays that
    /// round. The pot is never matched automatically (a salary can be the same size): the person
    /// confirms it on the jameya screen.
    private func matchJameya(_ tx: Transaction) throws {
        guard tx.isExpense, tx.kind != .purchase || tx.merchant.isEmpty else { return }
        for j in try context.fetch(FetchDescriptor<Jameya>()) where j.schedule.isShare(tx.amountAED) {
            let unpaid = (1...j.schedule.members).filter { !j.paidRounds.contains($0) }
            guard let round = j.schedule.roundPaid(on: tx.date, candidates: unpaid) else { continue }
            j.paidRounds.insert(round)
            j.bankPaidRounds.insert(round)
            tx.isFixedObligation = true
            tx.category = .transfer
            if tx.note.isEmpty { tx.note = j.name }
            return
        }
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

    /// The pieces behind today's number, for the Today screen and Insights.
    struct Numbers {
        let cycle: PayCycle
        let income: Decimal
        let fixed: Decimal
        let savings: Decimal
        let spentBeforeToday: Decimal
        let spentToday: Decimal
        /// What flexible spending can use this cycle.
        var available: Decimal { income - fixed - savings }
    }

    func current(now: Date = .now) throws -> SafeToSpend {
        let n = try numbers(now: now)
        return SafeToSpend.compute(income: n.income, fixedObligations: n.fixed, savingsGoal: n.savings,
                                   spentBeforeToday: n.spentBeforeToday, spentToday: n.spentToday,
                                   daysLeft: n.cycle.daysLeft(from: now))
    }

    func numbers(now: Date = .now) throws -> Numbers {
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
        // Jameya shares due this cycle are set aside like bills, except rounds paid by a matched
        // transfer, which are already in `fixedPaid`.
        let jameyaUnpaid = try context.fetch(FetchDescriptor<Jameya>())
            .reduce(Decimal(0)) { $0 + $1.reserve(in: cycle) }
        let goals = try context.fetch(FetchDescriptor<SavingsGoal>())
            .reduce(Decimal(0)) { $0 + $1.reserve(in: cycle) }

        return Numbers(cycle: cycle, income: income, fixed: fixedPaid + fixedUnpaid + jameyaUnpaid,
                       savings: AppSettings.savingsGoal + goals,
                       spentBeforeToday: spentBefore, spentToday: spentToday)
    }
}
