#if DEBUG
import Foundation
import SwiftData
import KhurdaCore

/// Debug builds only: launch with `-demo` to skip setup and fill the store with a believable month,
/// and `-tab N` to open a tab. Used for simulator screenshots; never compiled into a release build.
enum DemoData {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }
    static var tab: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count else { return 0 }
        return Int(args[i + 1]) ?? 0
    }

    static var showTeach: Bool { ProcessInfo.processInfo.arguments.contains("-teach") }
    static let teachSample = "Dear customer, you spent 45.50 dirhams with your debit card x4821 at LULU HYPERMARKET on 24-11-2026. Avl bal 5,230.10"

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        guard isOn else { return }
        AppSettings.defaults.set(true, forKey: "didFinishSetup")
        guard ((try? context.fetchCount(FetchDescriptor<Transaction>())) ?? 0) == 0 else { return }
        AppSettings.monthlyIncome = 18500
        AppSettings.payday = 27
        AppSettings.savingsGoal = 0

        let cal = Calendar.dubai
        let cycle = PayCycle.current(payday: 27)
        let today = cal.startOfDay(for: .now)
        func add(_ merchant: String, _ amount: Decimal, _ cat: CategoryID, daysAgo: Int, hour: Int = 13,
                 kind: TransactionKind = .purchase, via: TransactionSource = .wallet) {
            let date = cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: -daysAgo, to: today)!)!
            guard date >= cycle.start else { return }
            let p = ParsedTransaction(amount: amount, kind: kind, merchant: merchant, cardLast4: "4821", date: date)
            context.insert(Transaction(parsed: p, category: cat, amountAED: amount, source: nil, via: via))
        }
        let days = cal.dateComponents([.day], from: cycle.start, to: today).day ?? 0
        add("Salary", 18500, .income, daysAgo: days, hour: 9, kind: .income, via: .sms)
        for d in 0...days {
            if d % 2 == 0 { add("Starbucks", 24, .dining, daysAgo: d, hour: 8) }
            if d % 3 == 0 { add("Talabat", Decimal(45 + d % 4 * 12), .delivery, daysAgo: d, hour: 20) }
            if d % 5 == 1 { add("Carrefour", Decimal(180 + d * 7), .groceries, daysAgo: d, hour: 18, via: .sms) }
            if d % 7 == 3 { add("ADNOC", 120, .fuel, daysAgo: d, hour: 7) }
        }
        add("Noon", 349, .shopping, daysAgo: 4, hour: 22, via: .email)
        add("VOX Cinemas", 110, .entertainment, daysAgo: 2, hour: 21)
        add("Zara", 260, .shopping, daysAgo: 0, hour: 17)

        context.insert(Obligation(title: "Rent", amount: 6000, dueDay: 1, category: .family))
        context.insert(Obligation(title: "DEWA", amount: 420, dueDay: 12, category: .bills))
        context.insert(Obligation(title: "e&", amount: 299, dueDay: 20, category: .bills))
        let firstMonth = cal.date(byAdding: .month, value: -2, to: today)!
        context.insert(Jameya(name: String(localized: "Work jameya"), share: 1000, members: 10, myTurn: 5,
                              firstMonth: firstMonth, dueDay: 27, organiser: "Umm Khalid"))
        let ramadan = SavingsGoal(name: String(localized: "Ramadan & Eid"), target: 6000, monthly: 750, symbol: "moon.stars.fill")
        ramadan.saved = 2250
        ramadan.lastCredit = 750; ramadan.lastCreditCycleStart = cycle.start
        context.insert(ramadan)
        let travel = SavingsGoal(name: String(localized: "Travel"), target: 12000, monthly: 1000, symbol: "airplane")
        travel.saved = 3000
        travel.lastCredit = 1000; travel.lastCreditCycleStart = cycle.start
        context.insert(travel)
        context.insert(UnreadMessage(text: "عزيزي العميل، تم خصم 85.00 درهم من بطاقتك المنتهية بـ 4821 لدى مقهى الريف بتاريخ 24/11", sender: "NEWBANK"))
        context.insert(Budget(category: .delivery, limit: 600))
        context.insert(Budget(category: .dining, limit: 300))
        try? context.save()
    }
}
#endif
