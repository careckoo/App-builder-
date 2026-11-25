import Foundation

/// One flexible payment, as the insights need it (no SwiftData, so it can be unit-tested).
public struct Spend: Sendable, Equatable {
    public let merchant: String
    public let amountAED: Decimal
    public let date: Date
    public init(merchant: String, amountAED: Decimal, date: Date) {
        self.merchant = merchant; self.amountAED = amountAED; self.date = date
    }
}

public enum Insights {

    // MARK: Will my salary last?

    public struct Forecast: Sendable, Equatable {
        /// Average flexible spending per day so far this cycle.
        public let dailyPace: Decimal
        /// What's left on payday at this pace. Negative means it runs out first.
        public let leftAtPayday: Decimal
        /// When it runs out before payday: how many days early.
        public let shortByDays: Int?
        /// Nothing is left for flexible spending already (bills and savings take it all, or it's spent).
        public let alreadyOver: Bool
    }

    /// - Parameters:
    ///   - available: income − fixed bills − savings for the cycle (what flexible spending can use).
    ///   - spent: flexible spending so far this cycle, today included.
    ///   - daysElapsed: days of the cycle so far, today included (at least 1).
    ///   - daysLeft: days left until payday, today included (at least 1).
    public static func forecast(available: Decimal, spent: Decimal, daysElapsed: Int, daysLeft: Int) -> Forecast {
        let elapsed = Decimal(max(daysElapsed, 1))
        let pace = (spent / elapsed).rounded(2)
        // Today is already in `spent`, so project the days after today.
        let remainingDays = Decimal(max(daysLeft - 1, 0))
        let left = (available - spent - pace * remainingDays).rounded(2)
        let money = available - spent
        if money <= 0 {
            return Forecast(dailyPace: pace, leftAtPayday: left, shortByDays: nil, alreadyOver: true)
        }
        var short: Int?
        if left < 0, pace > 0 {
            let lastsDays = NSDecimalNumber(decimal: money / pace).intValue
            short = max(1, max(daysLeft - 1, 0) - lastsDays)
        }
        return Forecast(dailyPace: pace, leftAtPayday: left, shortByDays: short, alreadyOver: false)
    }

    // MARK: Money leaks

    public struct Leak: Sendable, Equatable {
        public let merchant: String
        public let count: Int
        public let total: Decimal
    }

    /// Small, frequent purchases at the same place: "17 coffees · AED 340 this cycle".
    /// A leak is 4+ purchases of up to `smallUpTo` each at one merchant. Biggest total first.
    public static func leaks(_ spends: [Spend], smallUpTo: Decimal = 60, minimumCount: Int = 4) -> [Leak] {
        let small = spends.filter { $0.amountAED > 0 && $0.amountAED <= smallUpTo && !$0.merchant.isEmpty }
        let groups = Dictionary(grouping: small) { merchantKey($0.merchant) }
        return groups.compactMap { _, items -> Leak? in
            guard items.count >= minimumCount else { return nil }
            // Show the name as the bank wrote it most often.
            let name = Dictionary(grouping: items, by: \.merchant).max { $0.value.count < $1.value.count }!.key
            return Leak(merchant: name, count: items.count, total: items.reduce(0) { $0 + $1.amountAED })
        }
        .sorted { $0.total > $1.total }
    }

    /// "STARBUCKS #123", "Starbucks 456" and "starbucks" are one place: letters only, lowercased.
    static func merchantKey(_ name: String) -> String {
        let letters = name.lowercased().map { $0.isLetter ? $0 : " " }
        return String(letters).split(separator: " ").joined(separator: " ")
    }

    // MARK: Days

    /// Flexible spending per calendar day (Dubai time), for the chart and the calendar.
    public static func dailyTotals(_ spends: [Spend], calendar: Calendar = .dubai) -> [Date: Decimal] {
        Dictionary(grouping: spends) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.amountAED } }
    }

    /// The last `count` days ending today, oldest first, with zero for days without spending.
    public static func lastDays(_ count: Int, totals: [Date: Decimal], today: Date = .now,
                                calendar: Calendar = .dubai) -> [(day: Date, total: Decimal)] {
        let start = calendar.startOfDay(for: today)
        return (0..<count).reversed().map { back in
            let day = calendar.date(byAdding: .day, value: -back, to: start)!
            return (day, totals[day] ?? 0)
        }
    }

    /// Days in the cycle so far (today included) where spending stayed within `allowance`.
    public static func daysWithin(allowance: Decimal, totals: [Date: Decimal], from start: Date, today: Date = .now,
                                  calendar: Calendar = .dubai) -> (within: Int, of: Int) {
        var day = calendar.startOfDay(for: start)
        let end = calendar.startOfDay(for: today)
        var within = 0, all = 0
        while day <= end {
            all += 1
            if (totals[day] ?? 0) <= allowance { within += 1 }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return (within, all)
    }
}
