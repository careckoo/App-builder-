import Foundation

// MARK: - Accounts

public enum AccountType: String, Codable, CaseIterable, Sendable {
    case current, savings, creditCard, prepaid, bnpl
    public var symbol: String {
        switch self {
        case .current: "building.columns"
        case .savings: "banknote"
        case .creditCard: "creditcard"
        case .prepaid: "wallet.pass"
        case .bnpl: "calendar.badge.clock"
        }
    }
}

/// An account as the matcher sees it.
public struct AccountRef: Sendable, Equatable {
    public let id: String
    public let bankName: String?
    public let type: AccountType
    public let endings: [String]
    public let isSalary: Bool
    public init(id: String, bankName: String?, type: AccountType, endings: [String], isSalary: Bool) {
        self.id = id; self.bankName = bankName; self.type = type; self.endings = endings; self.isSalary = isSalary
    }
}

/// Which of the person's accounts a message or statement row belongs to: by card ending, then by bank.
public enum AccountMatcher {
    /// Digits only, the last 4. Nil with fewer than 3 digits.
    public static func normalizeEnding(_ s: String?) -> String? {
        guard let s else { return nil }
        let digits = BankMessageParser.normalize(s).filter(\.isNumber)
        return digits.count >= 3 ? String(digits.suffix(4)) : nil
    }

    /// ADIB sends 3 digits: "123" matches "0123"; "1234" doesn't match "1235".
    public static func endingsMatch(_ a: String, _ b: String) -> Bool {
        guard let a = normalizeEnding(a), let b = normalizeEnding(b) else { return false }
        let n = min(a.count, b.count)
        return a.suffix(n) == b.suffix(n)
    }

    public static func match(bankName: String?, ending: String?, kind: TransactionKind, among accounts: [AccountRef]) -> String? {
        let sameBank: (AccountRef) -> Bool = { a in
            guard let b = bankName, let ab = a.bankName else { return true }
            return b.caseInsensitiveCompare(ab) == .orderedSame
        }
        if let e = normalizeEnding(ending) {
            let hits = accounts.filter { a in a.endings.contains { endingsMatch($0, e) } }
            let banked = hits.filter(sameBank)
            if banked.count == 1 { return banked[0].id }
            if hits.count == 1 { return hits[0].id }
            if !hits.isEmpty { return nil }
            // An ending no account has: don't guess, unless the bank has only one account without endings.
            let blank = accounts.filter { $0.endings.isEmpty && bankName != nil && sameBank($0) }
            return blank.count == 1 ? blank[0].id : nil
        }
        guard let bankName else { return accounts.count == 1 ? accounts[0].id : nil }
        let atBank = accounts.filter { $0.bankName?.caseInsensitiveCompare(bankName) == .orderedSame }
        if atBank.count == 1 { return atBank[0].id }
        if atBank.isEmpty { return nil }
        if kind == .income, let s = atBank.first(where: \.isSalary) { return s.id }
        let current = atBank.filter { $0.type == .current }
        return current.count == 1 ? current[0].id : nil
    }
}

// MARK: - Commitments

public enum Frequency: Equatable, Sendable, Hashable {
    case monthly, everyMonths(Int), months([Int]), once

    /// "m", "e3", "M9,1,4", "o".
    public init(raw: String) {
        switch raw.first {
        case "e": self = .everyMonths(max(1, Int(raw.dropFirst()) ?? 1))
        case "M": self = .months(raw.dropFirst().split(separator: ",").compactMap { Int($0) }.filter { (1...12).contains($0) })
        case "o": self = .once
        default: self = .monthly
        }
    }
    public var raw: String {
        switch self {
        case .monthly: "m"
        case .everyMonths(let n): "e\(n)"
        case .months(let m): "M" + m.map(String.init).joined(separator: ",")
        case .once: "o"
        }
    }
    /// Payments in a year (0 for a one-off).
    public var perYear: Decimal {
        switch self {
        case .monthly: 12
        case .everyMonths(let n): Decimal(12) / Decimal(max(n, 1))
        case .months(let m): Decimal(m.count)
        case .once: 0
        }
    }
}

/// Rent, a loan, school fees, DEWA, a Tabby plan… A jameya is a commitment too, with its own model.
public enum CommitmentType: String, CaseIterable, Sendable {
    case rent, loan, carLoan, cardInstalment, schoolFees, telecom, utilities, insurance, bnpl,
         familySupport, subscription, domesticWorker, charity, other

    public var symbol: String {
        switch self {
        case .rent: "house.fill"
        case .loan: "banknote.fill"
        case .carLoan: "car.fill"
        case .cardInstalment: "creditcard.fill"
        case .schoolFees: "graduationcap.fill"
        case .telecom: "antenna.radiowaves.left.and.right"
        case .utilities: "bolt.fill"
        case .insurance: "cross.case.fill"
        case .bnpl: "calendar.badge.clock"
        case .familySupport: "figure.2.and.child.holdinghands"
        case .subscription: "play.rectangle.fill"
        case .domesticWorker: "person.fill"
        case .charity: "heart.fill"
        case .other: "pin.fill"
        }
    }
    public var category: CategoryID {
        switch self {
        case .rent, .familySupport, .domesticWorker: .family
        case .loan, .carLoan, .cardInstalment, .bnpl: .installments
        case .schoolFees: .education
        case .telecom: .telecom
        case .utilities: .bills
        case .subscription: .subscriptions
        case .charity: .charity
        case .insurance, .other: .other
        }
    }
    public var defaultFrequency: Frequency {
        switch self {
        case .rent: .everyMonths(3)
        case .schoolFees: .months([9, 1, 4])
        case .insurance: .everyMonths(12)
        default: .monthly
        }
    }
    public var keywords: [String] {
        switch self {
        case .loan: ["loan", "قرض"]
        case .carLoan: ["auto loan", "car loan"]
        case .cardInstalment: ["epp", "ipp", "instalment", "installment"]
        case .schoolFees: ["school", "مدرسة", "academy"]
        case .telecom: ["etisalat", "e&", "du", "virgin mobile", "اتصالات"]
        case .utilities: ["dewa", "addc", "aadc", "taqa", "sewa", "fewa", "empower", "tabreed", "ديوا"]
        case .insurance: ["insurance", "takaful", "تأمين"]
        case .bnpl: ["tabby", "tamara", "postpay", "تابي", "تمارا"]
        case .charity: ["red crescent", "dar al ber"]
        default: []
        }
    }
    public var amountVaries: Bool { self == .telecom || self == .utilities }
    public var asksInstalments: Bool { [.loan, .carLoan, .cardInstalment, .bnpl].contains(self) }
}

/// When a commitment falls due: its first (next) date, how often, and how many payments.
public struct CommitmentSchedule: Sendable, Equatable {
    public let amount: Decimal
    public let frequency: Frequency
    public let firstDue: Date
    /// 0 = open-ended.
    public let instalments: Int

    public init(amount: Decimal, frequency: Frequency, firstDue: Date, instalments: Int) {
        self.amount = amount; self.frequency = frequency; self.firstDue = firstDue; self.instalments = instalments
    }

    /// The `index`-th payment (1-based), on the first date's day, clamped to the month's length.
    public func dueDate(index: Int, calendar: Calendar = .dubai) -> Date? {
        guard index >= 1, instalments == 0 || index <= instalments else { return nil }
        let day = calendar.component(.day, from: firstDue)
        func on(monthsAfter n: Int) -> Date? {
            guard let m = calendar.date(byAdding: .month, value: n, to: Self.monthStart(firstDue, calendar)) else { return nil }
            let len = calendar.range(of: .day, in: .month, for: m)?.count ?? 28
            return calendar.date(byAdding: .day, value: min(day, len) - 1, to: m)
        }
        switch frequency {
        case .monthly: return on(monthsAfter: index - 1)
        case .everyMonths(let n): return on(monthsAfter: (index - 1) * max(n, 1))
        case .once: return index == 1 ? calendar.startOfDay(for: firstDue) : nil
        case .months(let list):
            guard !list.isEmpty else { return nil }
            var found = 0
            for k in 0..<(index * 12 + 12) {
                guard let d = on(monthsAfter: k) else { return nil }
                if list.contains(calendar.component(.month, from: d)) {
                    found += 1
                    if found == index { return d }
                }
            }
            return nil
        }
    }

    static func monthStart(_ d: Date, _ cal: Calendar) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: d))!
    }

    /// Payments due in [from, to).
    public func dues(from: Date, to: Date, calendar: Calendar = .dubai) -> [(index: Int, date: Date)] {
        var out: [(Int, Date)] = []
        var i = 1
        while let d = dueDate(index: i, calendar: calendar), i < 1200 {
            if d >= to { break }
            if d >= from { out.append((i, d)) }
            i += 1
        }
        return out
    }

    /// The first payment on or after `date`.
    public func next(onOrAfter date: Date, calendar: Calendar = .dubai) -> (index: Int, date: Date)? {
        let day = calendar.startOfDay(for: date)
        var i = 1
        while let d = dueDate(index: i, calendar: calendar), i < 1200 {
            if d >= day { return (i, d) }
            i += 1
        }
        return nil
    }

    public var lastDue: Date? { instalments > 0 ? dueDate(index: instalments) : nil }

    /// Smoothed cost per month, for plans and goals ("rent AED 15,000 every 3 months" = 5,000 a month).
    public func monthlyEquivalent(on date: Date, paidCount: Int) -> Decimal {
        if instalments > 0, paidCount >= instalments { return 0 }
        if let last = lastDue, last < Calendar.dubai.startOfDay(for: date) { return 0 }
        switch frequency {
        case .monthly: return amount
        case .everyMonths(let n): return amount / Decimal(max(n, 1))
        case .months(let m): return amount * Decimal(m.count) / 12
        case .once:
            guard paidCount == 0 else { return 0 }
            let months = max(1, Calendar.dubai.dateComponents([.month], from: date, to: firstDue).month ?? 1)
            return amount / Decimal(months)
        }
    }

    /// Payments and money left on a fixed plan; nil when open-ended.
    public func remaining(paidCount: Int) -> (payments: Int, amount: Decimal)? {
        guard instalments > 0 else { return nil }
        let left = max(0, instalments - paidCount)
        return (left, amount * Decimal(left))
    }
}

/// Does a payment look like this commitment? Amount close (or within range when it varies), a keyword
/// or the name in the shop, or the same category, and within 10 days of an unpaid due date.
public enum CommitmentMatcher {
    public struct Candidate: Sendable {
        public let id: Int
        public let title: String
        public let amount: Decimal
        public let amountVaries: Bool
        public let category: CategoryID
        public let keywords: [String]
        public let dueDates: [Date]
        public init(id: Int, title: String, amount: Decimal, amountVaries: Bool, category: CategoryID, keywords: [String], dueDates: [Date]) {
            self.id = id; self.title = title; self.amount = amount; self.amountVaries = amountVaries
            self.category = category; self.keywords = keywords; self.dueDates = dueDates
        }
    }

    public static func match(amountAED: Decimal, merchant: String, category: CategoryID, date: Date,
                             among candidates: [Candidate]) -> Int? {
        let window: TimeInterval = 10 * 86_400
        var best: (id: Int, keyword: Bool, diff: Decimal)?
        for c in candidates {
            let words = (c.keywords + [c.title]).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count >= 2 }
            let named = words.contains { TextMatch.containsWord(merchant, $0) }
            let diff = abs(amountAED - c.amount)
            let amountOK: Bool
            if c.amountVaries {
                amountOK = named && amountAED >= c.amount * Decimal(string: "0.5")! && amountAED <= c.amount * Decimal(string: "1.6")!
            } else {
                amountOK = diff <= max(5, c.amount * Decimal(string: "0.02")!)
            }
            guard amountOK, named || c.category == category,
                  c.dueDates.contains(where: { abs($0.timeIntervalSince(date)) <= window }) else { continue }
            if best == nil || (named && !best!.keyword) || (named == best!.keyword && diff < best!.diff) {
                best = (c.id, named, diff)
            }
        }
        return best?.id
    }
}

// MARK: - Usual spending

public struct CategorySpend: Sendable, Equatable {
    public let category: CategoryID
    public let merchant: String
    public let amountAED: Decimal
    public let date: Date
    public init(category: CategoryID, merchant: String, amountAED: Decimal, date: Date) {
        self.category = category; self.merchant = merchant; self.amountAED = amountAED; self.date = date
    }
}

public enum Household: String, CaseIterable, Sendable { case single, couple, family }

/// What the person usually spends a month, per category: the middle of their last 3 pay cycles,
/// blended with typical UAE spending while there's little history.
public struct Baseline: Sendable, Equatable {
    public enum Source: Sendable, Equatable { case history, blended, typical }
    public let monthly: [CategoryID: Decimal]
    public let source: Source
    public let cyclesUsed: Double
    public let oneOffs: [CategorySpend]
    public var monthlyTotal: Decimal { monthly.values.reduce(0, +) }
    public var daily: Decimal { (monthlyTotal / BaselineCalculator.monthDays).roundedDown(to: 1) }
}

public enum BaselineCalculator {
    public static let monthDays: Decimal = Decimal(string: "30.44")!

    /// Everyday categories. Travel, school, charity and transfers are lumpy and left out.
    public static let everyday: [CategoryID] = [.groceries, .dining, .delivery, .transport, .fuel, .shopping, .health,
                                                .entertainment, .family, .cash, .other, .telecom, .bills, .subscriptions]

    /// - Parameters:
    ///   - completed: up to 3 finished pay cycles, newest first.
    ///   - trackedSince: the first day Khurda has data for (first transaction or imported statement).
    ///   - covered: categories already covered by commitments (left out, they're in commitments).
    public static func compute(spends: [CategorySpend], completed: [PayCycle], current: PayCycle, today: Date,
                               trackedSince: Date?, income: Decimal, household: Household, ownsCar: Bool?,
                               covered: Set<CategoryID>) -> Baseline {
        let cats = everyday.filter { !covered.contains($0) }
        let cal = Calendar.dubai
        let counted = completed.prefix(3).filter { c in
            guard let since = trackedSince else { return false }
            return since <= cal.date(byAdding: .day, value: 3, to: c.start)!
        }
        // Big one-offs: more than AED 750 and 4× the category's usual purchase.
        let window = spends.filter { s in counted.contains { $0.start <= s.date && s.date < $0.end } }
        var oneOffs: [CategorySpend] = []
        for c in [CategoryID.shopping, .family, .health, .cash, .other] {
            let inCat = window.filter { $0.category == c }
            for (i, s) in inCat.enumerated() where s.amountAED > 750 {
                // Compared with the category's other purchases, so one big buy doesn't set its own bar.
                let others = inCat.enumerated().filter { $0.offset != i }.map(\.element.amountAED).sorted()
                let median = others.isEmpty ? 0 : others[others.count / 2]
                if s.amountAED > 4 * median { oneOffs.append(s) }
            }
        }
        let usable = spends.filter { s in !oneOffs.contains(s) }

        var observed: [CategoryID: Decimal] = [:]
        var n: Double = Double(counted.count)
        if counted.isEmpty {
            let elapsed = (cal.dateComponents([.day], from: current.start, to: cal.startOfDay(for: today)).day ?? 0) + 1
            if elapsed >= 7, let since = trackedSince, since <= cal.date(byAdding: .day, value: 3, to: current.start)! {
                n = 0.5
                for c in cats {
                    let spent = usable.filter { $0.category == c && $0.date >= current.start }.reduce(0) { $0 + $1.amountAED }
                    observed[c] = spent * monthDays / Decimal(elapsed)
                }
            }
        } else {
            for c in cats {
                let perCycle = counted.map { cycle -> Decimal in
                    let days = max(1, cal.dateComponents([.day], from: cycle.start, to: cycle.end).day ?? 30)
                    let s = usable.filter { $0.category == c && cycle.start <= $0.date && $0.date < cycle.end }.reduce(0) { $0 + $1.amountAED }
                    return s * monthDays / Decimal(days)
                }.sorted()
                switch perCycle.count {
                case 3: observed[c] = perCycle[1]
                case 2: observed[c] = (perCycle[0] + perCycle[1]) / 2
                default: observed[c] = perCycle.first ?? 0
                }
            }
        }
        let w: Decimal = n >= 3 ? 1 : n >= 2 ? Decimal(string: "0.9")! : n >= 1 ? Decimal(string: "0.7")! : n > 0 ? Decimal(string: "0.4")! : 0
        var monthly: [CategoryID: Decimal] = [:]
        for c in cats {
            let typical = UAETypical.monthly(c, income: income, household: household, ownsCar: ownsCar)
            let v = w * (observed[c] ?? 0) + (1 - w) * typical
            if v > 0 { monthly[c] = v.rounded(to: 10) }
        }
        return Baseline(monthly: monthly, source: n == 0 ? .typical : n < 3 ? .blended : .history,
                        cyclesUsed: n, oneOffs: oneOffs)
    }
}

/// Starting assumptions for a person in the UAE, until Khurda sees their own month. To tune with real data.
public enum UAETypical {
    static let table: [CategoryID: (pct: Decimal, min: Decimal, max: Decimal, couple: Decimal, family: Decimal)] = [
        .groceries: (8, 700, 2500, 1.6, 2.3), .dining: (4, 250, 1500, 1.5, 1.8), .delivery: (3, 150, 1000, 1.4, 1.7),
        .transport: (3, 150, 1000, 1.3, 1.5), .fuel: (3.5, 200, 900, 1.3, 1.6), .shopping: (5, 300, 2000, 1.4, 1.8),
        .health: (1.5, 100, 600, 1.6, 2.2), .entertainment: (2, 100, 800, 1.5, 1.8), .family: (3, 200, 1500, 1.5, 2.0),
        .cash: (2, 100, 800, 1.2, 1.5), .other: (2, 100, 800, 1.2, 1.5), .telecom: (0, 300, 300, 1.8, 2.5),
        .bills: (3, 300, 1500, 1.4, 2.0), .subscriptions: (0, 100, 100, 1.2, 1.5)
    ]

    public static func monthly(_ c: CategoryID, income: Decimal, household: Household, ownsCar: Bool?) -> Decimal {
        guard let t = table[c] else { return 0 }
        if c == .fuel, ownsCar == false { return 0 }
        var v = min(max(income * t.pct / 100, t.min), t.max)
        switch household {
        case .single: break
        case .couple: v *= t.couple
        case .family: v *= t.family
        }
        if c == .transport, ownsCar == true { v *= Decimal(string: "0.6")! }
        return v
    }
}

// MARK: - The month

/// Income − commitments − goals = flexible money; against usual spending that gives a daily target,
/// what you'll save, and whether it fits.
public struct MonthPlan: Sendable, Equatable {
    public enum Status: Sendable, Equatable { case comfortable, tight, short }
    public let flexible: Decimal
    public let usual: Decimal
    public let dailyTarget: Decimal
    public let expectedSavings: Decimal
    public let savingsWithTarget: Decimal
    public let shortBy: Decimal
    public let extraToSave: Decimal
    public let status: Status

    public static func compute(income: Decimal, commitments: Decimal, goals: Decimal, usualMonthly: Decimal,
                               potentialMonthly: Decimal, cycleDays: Int) -> MonthPlan {
        let d = Decimal(max(cycleDays, 1))
        let k = d / BaselineCalculator.monthDays
        let f = income - commitments - goals
        let b = usualMonthly * k
        let target: Decimal
        if f <= 0 {
            target = 0
        } else {
            var flex = min(f, max(b - potentialMonthly * k / 2, b * Decimal(string: "0.7")!))
            if f < b { flex = f }
            let perDay = flex / d
            target = perDay < 50 ? perDay.roundedDown(to: 1) : perDay.roundedDown(to: 5)
        }
        let status: Status = f - b >= income / 10 ? .comfortable : f >= b ? .tight : .short
        return MonthPlan(flexible: f, usual: b, dailyTarget: target, expectedSavings: goals + f - b,
                         savingsWithTarget: goals + f - target * d, shortBy: max(0, b - f),
                         extraToSave: max(0, f - target * d), status: f <= 0 ? .short : status)
    }
}

// MARK: - Ways to save

public struct Opportunity: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case aboveUsual(percent: Int)
        case aboveTypical(typical: Decimal, usual: Decimal)
        case smallRepeats(merchant: String, count: Int)
        case overlappingSubscriptions([String])
        case fees(total: Decimal)
    }
    public let kind: Kind
    public let category: CategoryID?
    public let monthly: Decimal
    public var id: String { "\(kind)-\(category?.rawValue ?? "")" }
}

public enum SavingsFinder {
    static let video = ["netflix", "osn", "shahid", "disney", "prime video", "starzplay", "apple tv"]
    static let music = ["spotify", "anghami", "apple music", "youtube premium"]
    static let feeWords = ["fee", "fees", "charge", "charges", "late payment", "overlimit", "interest", "finance charge", "رسوم", "غرامة", "فائدة"]

    public static func find(thisCycle: [CategorySpend], last30Days: [CategorySpend], elapsedDays: Int,
                            baseline: Baseline, income: Decimal, household: Household, ownsCar: Bool?) -> [Opportunity] {
        var byCategory: [CategoryID: Opportunity] = [:]
        if baseline.source != .typical {
            for (c, base) in baseline.monthly where base > 0 {
                var best: Opportunity?
                if elapsedDays >= 7 {
                    let spent = thisCycle.filter { $0.category == c }.reduce(0) { $0 + $1.amountAED }
                    let pace = spent * BaselineCalculator.monthDays / Decimal(elapsedDays)
                    if pace >= base * Decimal(string: "1.2")!, pace - base >= 100 {
                        let pct = NSDecimalNumber(decimal: (pace / base - 1) * 100).intValue
                        best = Opportunity(kind: .aboveUsual(percent: pct), category: c, monthly: pace - base)
                    }
                }
                if ![.health, .bills, .telecom, .education].contains(c) {
                    let typical = UAETypical.monthly(c, income: income, household: household, ownsCar: ownsCar)
                    if typical > 0, base > typical * Decimal(string: "1.3")!, base - typical >= 150 {
                        let o = Opportunity(kind: .aboveTypical(typical: typical.rounded(to: 10), usual: base), category: c,
                                            monthly: (base - typical) / 4)
                        if best == nil || o.monthly > best!.monthly { best = o }
                    }
                }
                if let best { byCategory[c] = best }
            }
        }
        var out: [Opportunity] = []
        let spends = last30Days.map { Spend(merchant: $0.merchant, amountAED: $0.amountAED, date: $0.date) }
        for leak in Insights.leaks(spends).prefix(2) {
            let monthly = leak.total / 2
            let cat = last30Days.first { Insights.merchantKey($0.merchant) == Insights.merchantKey(leak.merchant) }?.category
            if let cat, let o = byCategory[cat] {
                byCategory[cat] = Opportunity(kind: o.kind, category: cat, monthly: max(0, o.monthly - monthly))
            }
            out.append(Opportunity(kind: .smallRepeats(merchant: leak.merchant, count: leak.count), category: cat, monthly: monthly))
        }
        out += byCategory.values
        for group in [video, music] {
            var charged: [String: Decimal] = [:]
            for s in last30Days {
                let l = s.merchant.lowercased()
                if let name = group.first(where: { BankMessageParser.containsWord(l, $0) }) {
                    charged[name] = min(charged[name] ?? s.amountAED, s.amountAED)
                }
            }
            if charged.count >= 2, let cheapest = charged.values.min() {
                out.append(Opportunity(kind: .overlappingSubscriptions(charged.keys.sorted().map { $0.capitalized }),
                                       category: .subscriptions, monthly: cheapest))
            }
        }
        let fees = last30Days.filter { s in BankMessageParser.containsAny(s.merchant.lowercased(), feeWords) }
            .reduce(0) { $0 + $1.amountAED }
        if fees >= 10 { out.append(Opportunity(kind: .fees(total: fees), category: nil, monthly: fees)) }

        return out.map { Opportunity(kind: $0.kind, category: $0.category, monthly: $0.monthly.roundedDown(to: 10)) }
            .filter { $0.monthly >= 30 }
            .sorted { $0.monthly > $1.monthly }
    }

    public static func total(_ o: [Opportunity]) -> Decimal { o.reduce(0) { $0 + $1.monthly } }
}

// MARK: - Goals

public enum GoalPlanner {
    /// Paydays strictly after `today`, up to and including `through`.
    public static func paydays(after today: Date, through: Date, payday: Int) -> [Date] {
        var out: [Date] = []
        var cycle = PayCycle.current(payday: payday, today: today)
        while cycle.end <= through, out.count < 600 {
            out.append(cycle.end)
            cycle = PayCycle.current(payday: payday, today: cycle.end)
        }
        return out
    }

    public enum Need: Equatable, Sendable {
        case reached
        case tooSoon(neededNow: Decimal)
        case monthly(Decimal, paydays: Int, perDay: Decimal)
    }

    public static func need(target: Decimal, saved: Decimal, deadline: Date, payday: Int, today: Date) -> Need {
        let left = target - saved
        guard left > 0 else { return .reached }
        let n = paydays(after: today, through: deadline, payday: payday).count
        guard n > 0 else { return .tooSoon(neededNow: left) }
        let monthly = (left / Decimal(n)).roundedUp(to: 10)
        return .monthly(monthly, paydays: n, perDay: (monthly / BaselineCalculator.monthDays).rounded(to: 1))
    }

    public static func finishDate(target: Decimal, saved: Decimal, monthly: Decimal, payday: Int, today: Date) -> Date? {
        let left = target - saved
        guard monthly > 0 else { return nil }
        guard left > 0 else { return today }
        let n = NSDecimalNumber(decimal: (left / monthly)).doubleValue.rounded(.up)
        guard n <= 600 else { return nil }
        let far = Calendar.dubai.date(byAdding: .month, value: Int(n) + 2, to: today)!
        let days = paydays(after: today, through: far, payday: payday)
        return days.indices.contains(Int(n) - 1) ? days[Int(n) - 1] : days.last
    }

    /// What's spare each month for this goal: income − commitments − usual spending − the other goals.
    public static func room(income: Decimal, commitments: Decimal, usual: Decimal, otherGoals: Decimal) -> Decimal {
        income - commitments - usual - otherGoals
    }

    public enum Fit: Equatable, Sendable { case comfortable, tight, notAffordable(shortBy: Decimal, earliest: Date?) }

    public static func fit(monthly: Decimal, room: Decimal, target: Decimal, saved: Decimal, payday: Int, today: Date) -> Fit {
        if monthly <= room * Decimal(string: "0.8")! { return .comfortable }
        if monthly <= room { return .tight }
        let possible = (room * Decimal(string: "0.8")!).roundedDown(to: 10)
        return .notAffordable(shortBy: monthly - max(room, 0),
                              earliest: possible > 0 ? finishDate(target: target, saved: saved, monthly: possible, payday: payday, today: today) : nil)
    }
}

// MARK: - Rounding

public extension Decimal {
    func rounded(to step: Decimal) -> Decimal { roundValue(self / step, .plain) * step }
    func roundedDown(to step: Decimal) -> Decimal { roundValue(self / step, .down) * step }
    func roundedUp(to step: Decimal) -> Decimal { roundValue(self / step, .up) * step }

    private func roundValue(_ v: Decimal, _ mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var input = v, out = Decimal()
        NSDecimalRound(&out, &input, 0, mode)
        return out
    }
}
