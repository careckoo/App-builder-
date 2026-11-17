import Foundation

/// The salary cycle: from one payday to the next. Most UAE salaries land between the 25th and
/// the 1st, so the app works in pay cycles rather than calendar months.
public struct PayCycle: Sendable, Equatable {
    public let start: Date
    public let end: Date   // exclusive: the next payday

    public static func current(payday: Int, today: Date = .now, calendar: Calendar = .dubai) -> PayCycle {
        let day = min(max(payday, 1), 28)
        var comps = calendar.dateComponents([.year, .month], from: today)
        comps.day = day
        let thisMonthPayday = calendar.date(from: comps)!
        let start = today >= calendar.startOfDay(for: thisMonthPayday)
            ? thisMonthPayday
            : calendar.date(byAdding: .month, value: -1, to: thisMonthPayday)!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        return PayCycle(start: calendar.startOfDay(for: start), end: calendar.startOfDay(for: end))
    }

    public func daysLeft(from today: Date = .now, calendar: Calendar = .dubai) -> Int {
        max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: end).day ?? 1)
    }
}

/// The single number on the home screen: how much you can spend today and still reach payday
/// with your bills paid and your savings goal met.
public struct SafeToSpend: Sendable, Equatable {
    public let today: Decimal          // what's left for today
    public let dailyAllowance: Decimal // the even split at the start of today
    public let leftForCycle: Decimal   // what's left until payday
    public let daysLeft: Int
    public let status: Status

    public enum Status: String, Sendable { case relaxed, onTrack, careful, over }

    /// - Parameters:
    ///   - income: income received (or expected) this cycle.
    ///   - fixedObligations: rent, bills, installments still to be paid this cycle.
    ///   - savingsGoal: amount to set aside this cycle.
    ///   - spentBeforeToday: flexible spending in this cycle, before today.
    ///   - spentToday: flexible spending today.
    public static func compute(income: Decimal, fixedObligations: Decimal, savingsGoal: Decimal,
                               spentBeforeToday: Decimal, spentToday: Decimal, daysLeft: Int) -> SafeToSpend {
        let availableAtStartOfToday = income - fixedObligations - savingsGoal - spentBeforeToday
        let days = Decimal(max(daysLeft, 1))
        let allowance = max(0, availableAtStartOfToday / days).rounded(2)
        let left = allowance - spentToday
        let ratio: Double = allowance == 0 ? 1 : NSDecimalNumber(decimal: spentToday / allowance).doubleValue
        let status: Status = left < 0 ? .over : ratio > 0.8 ? .careful : ratio > 0.4 ? .onTrack : .relaxed
        return SafeToSpend(today: left.rounded(2), dailyAllowance: allowance,
                           leftForCycle: (availableAtStartOfToday - spentToday).rounded(2),
                           daysLeft: daysLeft, status: status)
    }
}

/// Bank SMS sometimes arrive twice (network retry, two SIMs, a card and an account alert for the
/// same purchase). Two messages with the same amount, card and merchant within 3 minutes are one purchase.
public enum DuplicateDetector {
    public static func fingerprint(_ t: ParsedTransaction) -> String {
        let merchant = (t.merchant ?? "").lowercased().filter { $0.isLetter || $0.isNumber }
        return "\(t.kind.rawValue)|\(t.amount)|\(t.currency)|\(t.cardLast4 ?? "")|\(merchant)"
    }

    public static func isDuplicate(_ t: ParsedTransaction, at date: Date,
                                   recent: [(fingerprint: String, date: Date)], window: TimeInterval = 180) -> Bool {
        let fp = fingerprint(t)
        return recent.contains { $0.fingerprint == fp && abs($0.date.timeIntervalSince(date)) <= window }
    }
}

public extension Calendar {
    static var dubai: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Dubai")!
        return c
    }
}

extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var value = self, result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
