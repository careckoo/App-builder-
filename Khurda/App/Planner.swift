import Foundation
import SwiftData
import KhurdaCore

/// The month in one place: usual spending, the daily target, ways to save, and how much room a goal has.
/// Built from the stored data each time a screen asks; nothing here is stored.
@MainActor
struct Planner {
    let context: ModelContext

    struct Month {
        let numbers: SafeToSpendCalculator.Numbers
        let baseline: Baseline
        let plan: MonthPlan
        let opportunities: [Opportunity]
        /// Monthly equivalents, for goals: regular income, commitments, goals.
        let incomeMonthly: Decimal
        let commitmentsMonthly: Decimal
        let goalsMonthly: Decimal
        let commitmentsThisCycle: Decimal
        let goalsThisCycle: Decimal
        var cycleDays: Int {
            Calendar.dubai.dateComponents([.day], from: numbers.cycle.start, to: numbers.cycle.end).day ?? 30
        }
        /// What to set aside so today's amount, from now to payday, is the daily target: the flexible
        /// money left after what's already spent, minus the target for each day left.
        var extraForTarget: Decimal {
            let flexibleLeft = numbers.income - numbers.fixed - goalsThisCycle - numbers.spentBeforeToday
            return max(0, flexibleLeft - plan.dailyTarget * Decimal(numbers.cycle.daysLeft())).roundedDown(to: 10)
        }
        /// Room for one more goal each month, at usual spending.
        func room(excludingGoal monthly: Decimal = 0) -> Decimal {
            GoalPlanner.room(income: incomeMonthly, commitments: commitmentsMonthly, usual: baseline.monthlyTotal,
                             otherGoals: goalsMonthly - monthly)
        }
    }

    func month(now: Date = .now) throws -> Month {
        let n = try SafeToSpendCalculator(context: context).numbers(now: now)
        let cal = Calendar.dubai
        let payday = AppSettings.payday
        var completed: [PayCycle] = []
        var c = n.cycle
        for _ in 0..<3 {
            let prev = PayCycle.current(payday: payday, today: cal.date(byAdding: .day, value: -1, to: c.start)!)
            completed.append(prev); c = prev
        }
        let oldest = completed.last!.start
        let txs = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.date >= oldest }))
        var firstQuery = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)])
        firstQuery.fetchLimit = 1
        let first = try context.fetch(firstQuery).first?.date
        let spends = txs.filter { $0.isExpense && !$0.isFixedObligation }
            .map { CategorySpend(category: $0.category, merchant: $0.merchant, amountAED: $0.amountAED, date: $0.date) }

        let obligations = try context.fetch(FetchDescriptor<Obligation>())
        let jameyas = try context.fetch(FetchDescriptor<Jameya>())
        let goals = try context.fetch(FetchDescriptor<SavingsGoal>())
        let covered = Set(obligations.filter { !$0.isFinished }.map(\.category))

        let income = max(n.income, AppSettings.monthlyIncome)
        let baseline = BaselineCalculator.compute(spends: spends, completed: completed, current: n.cycle, today: now,
                                                  trackedSince: first, income: income, household: AppSettings.household,
                                                  ownsCar: AppSettings.ownsCar, covered: covered)
        let elapsed = (cal.dateComponents([.day], from: n.cycle.start, to: cal.startOfDay(for: now)).day ?? 0) + 1
        let last30 = spends.filter { $0.date >= cal.date(byAdding: .day, value: -30, to: now)! }
        let thisCycle = spends.filter { $0.date >= n.cycle.start }
        let found = SavingsFinder.find(thisCycle: thisCycle, last30Days: last30, elapsedDays: elapsed, baseline: baseline,
                                       income: income, household: AppSettings.household, ownsCar: AppSettings.ownsCar)

        let goalsThisCycle = goals.reduce(Decimal(0)) { $0 + $1.reserve(in: n.cycle) }
        let days = cal.dateComponents([.day], from: n.cycle.start, to: n.cycle.end).day ?? 30
        let plan = MonthPlan.compute(income: n.income, commitments: n.fixed, goals: goalsThisCycle,
                                     usualMonthly: baseline.monthlyTotal, potentialMonthly: SavingsFinder.total(found),
                                     cycleDays: days)
        let commitmentsMonthly = obligations.reduce(Decimal(0)) { $0 + $1.schedule.monthlyEquivalent(on: now, paidCount: $1.paidCount) }
            + jameyas.filter { $0.schedule.lastDueDate >= now }.reduce(Decimal(0)) { $0 + $1.share }
        let goalsMonthly = goals.filter { !$0.isReached }.reduce(Decimal(0)) { $0 + $1.monthly }
        return Month(numbers: n, baseline: baseline, plan: plan, opportunities: Array(found.prefix(3)),
                     incomeMonthly: AppSettings.monthlyIncome, commitmentsMonthly: commitmentsMonthly,
                     goalsMonthly: goalsMonthly, commitmentsThisCycle: n.fixed, goalsThisCycle: goalsThisCycle)
    }
}

/// Keeps the widget's and Shortcut's cached income and payday in step with the income list.
@MainActor
enum Incomes {
    static func sync(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<IncomeSource>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        guard !all.isEmpty else { return }
        AppSettings.monthlyIncome = all.filter(\.isRegular).reduce(Decimal(0)) { $0 + $1.amount }
        if let salary = all.first(where: { $0.kindRaw == "salary" }), salary.dayOfMonth != AppSettings.payday {
            AppSettings.payday = salary.dayOfMonth
        }
    }

    /// First launch after the update: the salary typed at setup becomes an income, the banks picked at
    /// setup (and ones seen in messages) become accounts.
    static func migrateIfNeeded(context: ModelContext) {
        let key = "didMigrateAccounts"
        guard !AppSettings.defaults.bool(forKey: key) else { return }
        defer { AppSettings.defaults.set(true, forKey: key) }
        let incomes = (try? context.fetchCount(FetchDescriptor<IncomeSource>())) ?? 0
        if incomes == 0, AppSettings.monthlyIncome > 0 {
            context.insert(IncomeSource(name: String(localized: "Salary"), amount: AppSettings.monthlyIncome, day: AppSettings.payday))
        }
        let accounts = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        if accounts == 0 {
            var made = Set<String>()
            let txs = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
            let groups = Dictionary(grouping: txs.filter { $0.bankName != nil }) { "\($0.bankName!)|\($0.cardLast4 ?? "")" }
            for (key, list) in groups where list.count >= 2 {
                let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                guard let bank = BankDirectory.all.first(where: { $0.nameEN == parts[0] }) else { continue }
                // A card payment seen on this ending makes it a card, unless salary or transfers land
                // there too (that's the account the card is paid from): on a card, income becomes a card payment.
                let isCard = list.contains { $0.kind == .cardPayment }
                    && !list.contains { $0.kind == .income || $0.kind == .transferOut }
                let a = Account(bankID: bank.id, type: isCard ? .creditCard : .current, last4: parts[1])
                context.insert(a)
                list.forEach { $0.accountID = a.id }
                made.insert(bank.id)
            }
            for id in AppSettings.selectedBanks where !made.contains(id) {
                context.insert(Account(bankID: id, type: .current))
            }
        }
        try? context.save()
    }
}

extension AppSettings {
    /// Banks picked at setup or in Settings (BankDirectory ids).
    static var selectedBanks: [String] {
        get { defaults.stringArray(forKey: "selectedBanks") ?? [] }
        set { defaults.set(newValue, forKey: "selectedBanks") }
    }
}
