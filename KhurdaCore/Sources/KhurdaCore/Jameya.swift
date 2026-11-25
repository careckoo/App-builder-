import Foundation

/// A jameya (جمعية): a rotating savings group. Every member pays the same share each month, and each
/// month one member takes the whole pot. With 10 members paying AED 1,000, the pot is AED 10,000 and
/// every member gets it once, in their turn, over 10 months.
///
/// Before your turn you're saving (you've paid in more than you've had back); after it you're paying
/// back an interest-free advance. Either way the monthly share is a fixed bill for the pay cycle.
public struct JameyaSchedule: Sendable, Equatable {
    /// What one member pays each round.
    public let share: Decimal
    /// How many turns there are: one per member (a member holding two shares takes two turns).
    public let members: Int
    /// Your turn, 1-based. Turn 1 takes the pot in the first month.
    public let myTurn: Int
    /// Any day in the first month (only the year and month are used).
    public let firstMonth: Date
    /// Day of the month the share is due and the pot is paid out (1–31; clamped to short months).
    public let dueDay: Int

    public init(share: Decimal, members: Int, myTurn: Int, firstMonth: Date, dueDay: Int) {
        self.share = share
        self.members = max(members, 1)
        self.myTurn = min(max(myTurn, 1), max(members, 1))
        self.firstMonth = firstMonth
        self.dueDay = min(max(dueDay, 1), 31)
    }

    /// What the person whose turn it is takes home.
    public var pot: Decimal { share * Decimal(members) }

    /// The due date of a round (1-based).
    public func dueDate(round: Int, calendar: Calendar = .dubai) -> Date {
        var comps = calendar.dateComponents([.year, .month], from: firstMonth)
        comps.day = 1
        let first = calendar.date(from: comps)!
        let month = calendar.date(byAdding: .month, value: round - 1, to: first)!
        let length = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
        var day = calendar.dateComponents([.year, .month], from: month)
        day.day = min(dueDay, length)
        return calendar.startOfDay(for: calendar.date(from: day)!)
    }

    public var myPayoutDate: Date { dueDate(round: myTurn) }
    public var lastDueDate: Date { dueDate(round: members) }

    /// The round whose month contains `date`: 1…members while running, nil before it starts or after it ends.
    public func round(on date: Date, calendar: Calendar = .dubai) -> Int? {
        let a = calendar.dateComponents([.year, .month], from: firstMonth)
        let b = calendar.dateComponents([.year, .month], from: date)
        let index = (b.year! - a.year!) * 12 + (b.month! - a.month!) + 1
        return (1...members).contains(index) ? index : nil
    }

    /// Rounds whose due date falls in [from, to). Used to put the share into the right pay cycle.
    public func rounds(dueFrom from: Date, to: Date, calendar: Calendar = .dubai) -> [Int] {
        (1...members).filter { r in
            let d = dueDate(round: r, calendar: calendar)
            return d >= from && d < to
        }
    }

    public enum Phase: Equatable, Sendable {
        case notStarted
        /// Before your turn: `roundsUntilTurn` 0 means it's your turn this month.
        case saving(roundsUntilTurn: Int)
        case yourTurn
        /// After your turn: rounds still to pay.
        case payingBack(roundsLeft: Int)
        case finished
    }

    public func phase(on date: Date, calendar: Calendar = .dubai) -> Phase {
        guard let r = round(on: date, calendar: calendar) else {
            return date < dueDate(round: 1, calendar: calendar) ? .notStarted : .finished
        }
        if r < myTurn { return .saving(roundsUntilTurn: myTurn - r) }
        if r == myTurn { return .yourTurn }
        return .payingBack(roundsLeft: members - r + 1)
    }

    /// Shares paid by the end of round `round` (every member pays every round, your own turn included).
    public func paidIn(throughRound round: Int) -> Decimal { share * Decimal(min(max(round, 0), members)) }

    /// Paid in minus taken out, after `round` rounds. Positive: the group holds your money.
    /// Negative: you've had the pot and still owe shares. Zero at the end.
    public func balance(afterRound round: Int) -> Decimal {
        let r = min(max(round, 0), members)
        return paidIn(throughRound: r) - (r >= myTurn ? pot : 0)
    }

    /// A bank payment is this jameya's share when it's within 1% (or AED 1) of it.
    public func isShare(_ amountAED: Decimal) -> Bool { Self.close(amountAED, share) }

    /// An incoming credit is the pot when it's within 1% of it (some organisers keep a small fee).
    /// Many groups simply skip your own share in your month, so the pot less one share also counts.
    public func isPot(_ amountAED: Decimal) -> Bool {
        Self.close(amountAED, pot) || (members > 1 && Self.close(amountAED, pot - share))
    }

    static func close(_ a: Decimal, _ b: Decimal) -> Bool {
        let diff = abs(NSDecimalNumber(decimal: a - b).doubleValue)
        return diff <= max(1, NSDecimalNumber(decimal: b).doubleValue * 0.01)
    }
}
