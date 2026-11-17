import Foundation
import SwiftData
import WidgetKit
import MasroofiCore

/// Turns a bank SMS into a saved transaction. Used by the Shortcut (App Intent),
/// by "Paste a message" in the app, and by the share sheet.
@MainActor
struct TransactionLogger {
    enum Outcome {
        case saved(Transaction, SafeToSpend)
        case duplicate
        case notATransaction
    }

    let context: ModelContext

    init(context: ModelContext = Store.container.mainContext) { self.context = context }

    func log(message: String, sender: String?) throws -> Outcome {
        CycleReset.runIfNeeded(context: context)
        guard let parsed = BankMessageParser().parse(message, sender: sender) else { return .notATransaction }

        // Ignore the same purchase arriving twice. Look up by fingerprint, not by "logged in the last
        // few minutes": the transaction date can be the bank's own timestamp or, for a pasted old
        // message, a day in the past, so a recency window on `date` would miss those repeats.
        let fp = DuplicateDetector.fingerprint(parsed)
        let same = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.fingerprint == fp }))
        let date = parsed.date ?? .now
        if DuplicateDetector.isDuplicate(parsed, at: date, recent: same.map { ($0.fingerprint, $0.date) })
            || same.contains(where: { $0.sourceMessage == message }) {
            return .duplicate
        }

        let rules = try context.fetch(FetchDescriptor<MerchantRule>())
        let learned = Dictionary(rules.map { ($0.keyword, CategoryID(rawValue: $0.categoryRaw) ?? .other) },
                                 uniquingKeysWith: { a, _ in a })
        let category = Categorizer(learned: learned).category(for: parsed)
        let rate = AppSettings.fxToAED[parsed.currency] ?? 1
        let tx = Transaction(parsed: parsed, category: category, amountAED: parsed.amount * rate, source: message)

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

    private func matchingObligation(for tx: Transaction) throws -> Obligation? {
        let unpaid = try context.fetch(FetchDescriptor<Obligation>(predicate: #Predicate { !$0.isPaidThisCycle }))
        let name = tx.merchant.lowercased()
        return unpaid.first { bill in
            let close = abs(NSDecimalNumber(decimal: bill.amount - tx.amountAED).doubleValue) <= max(5, NSDecimalNumber(decimal: bill.amount).doubleValue * 0.02)
            return close && (bill.categoryRaw == tx.categoryRaw || name.contains(bill.title.lowercased()))
        }
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
