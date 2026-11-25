import Foundation
import SwiftData
import KhurdaCore

/// One money movement. Created automatically from a bank SMS or email or an Apple Pay purchase,
/// or by hand when someone pays cash.
@Model
final class Transaction {
    var amount: Decimal = 0
    var currency: String = "AED"
    /// Amount in AED. For foreign-currency purchases this is an estimate until the bank posts it.
    var amountAED: Decimal = 0
    var kindRaw: String = TransactionKind.purchase.rawValue
    var merchant: String = ""
    var categoryRaw: String = CategoryID.other.rawValue
    var cardLast4: String?
    /// The card's name in Apple Wallet ("FAB Cashback"), when the purchase came from Apple Pay.
    var cardName: String?
    var bankName: String?
    var balanceAfter: Decimal?
    var date: Date = Date.now
    var note: String = ""
    /// The original SMS, kept on the device only, so the person can see where a number came from.
    var sourceMessage: String?
    var fingerprint: String = ""
    var isFixedObligation: Bool = false
    /// `TransactionSource` raw value. Records saved before this field existed came from SMS.
    var sourceRaw: String = TransactionSource.sms.rawValue

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .purchase }
        set { kindRaw = newValue.rawValue }
    }
    var category: CategoryID {
        get { CategoryID(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    var source: TransactionSource {
        get { TransactionSource(rawValue: sourceRaw) ?? .sms }
        set { sourceRaw = newValue.rawValue }
    }
    var isExpense: Bool { kind == .purchase || kind == .withdrawal || kind == .transferOut }

    /// - Parameters:
    ///   - source: the original message text, kept on the device (nil for Apple Pay and manual entries).
    ///   - via: where the transaction came from.
    init(parsed: ParsedTransaction, category: CategoryID, amountAED: Decimal, source: String?,
         via: TransactionSource = .sms, cardName: String? = nil) {
        amount = parsed.amount
        currency = parsed.currency
        self.amountAED = amountAED
        kindRaw = parsed.kind.rawValue
        merchant = parsed.merchant ?? ""
        categoryRaw = category.rawValue
        cardLast4 = parsed.cardLast4
        bankName = parsed.bankName
        balanceAfter = parsed.balanceAfter
        date = parsed.date ?? .now
        sourceMessage = source
        fingerprint = DuplicateDetector.fingerprint(parsed)
        sourceRaw = via.rawValue
        self.cardName = cardName
    }
}

/// A monthly limit for one category, e.g. "Food delivery: 600 AED".
@Model
final class Budget {
    var categoryRaw: String = CategoryID.other.rawValue
    var limit: Decimal = 0
    init(category: CategoryID, limit: Decimal) { categoryRaw = category.rawValue; self.limit = limit }
    var category: CategoryID { CategoryID(rawValue: categoryRaw) ?? .other }
}

/// Rent, school fees, a Tabby installment: money already promised this cycle.
@Model
final class Obligation {
    var title: String = ""
    var amount: Decimal = 0
    var dueDay: Int = 1
    var categoryRaw: String = CategoryID.bills.rawValue
    var isPaidThisCycle: Bool = false
    init(title: String, amount: Decimal, dueDay: Int, category: CategoryID) {
        self.title = title; self.amount = amount; self.dueDay = dueDay; categoryRaw = category.rawValue
    }
}

/// A jameya (جمعية): a rotating savings group. The share is a fixed bill each month; in your turn the
/// whole pot comes to you. Schedule maths lives in `JameyaSchedule` (KhurdaCore).
@Model
final class Jameya {
    var name: String = ""
    var share: Decimal = 0
    var members: Int = 10
    var myTurn: Int = 1
    /// Any day in the first round's month.
    var firstMonth: Date = Date.now
    var dueDay: Int = 27
    /// The organiser, for the reminder ("Pay Umm Khalid"). Optional.
    var organiser: String = ""
    /// Start of the pay cycle in which this cycle's share was paid (matched from the bank or ticked by hand).
    var paidCycleStart: Date?
    var receivedPot: Bool = false
    var createdAt: Date = Date.now

    init(name: String, share: Decimal, members: Int, myTurn: Int, firstMonth: Date, dueDay: Int, organiser: String = "") {
        self.name = name; self.share = share; self.members = members; self.myTurn = myTurn
        self.firstMonth = firstMonth; self.dueDay = dueDay; self.organiser = organiser
    }

    var schedule: JameyaSchedule {
        JameyaSchedule(share: share, members: members, myTurn: myTurn, firstMonth: firstMonth, dueDay: dueDay)
    }

    /// The share is due in this pay cycle (one of its rounds falls between the two paydays).
    func isDue(in cycle: PayCycle) -> Bool { !schedule.rounds(dueFrom: cycle.start, to: cycle.end).isEmpty }
    func isPaid(in cycle: PayCycle) -> Bool { paidCycleStart == cycle.start }
}

/// Something to save for: a car, Umrah, a wedding, Ramadan and Eid. The monthly amount is set aside
/// on payday, before today's amount is worked out.
@Model
final class SavingsGoal {
    var name: String = ""
    var target: Decimal = 0
    var saved: Decimal = 0
    var monthly: Decimal = 0
    var symbol: String = "star.fill"
    var targetDate: Date?
    var createdAt: Date = Date.now

    init(name: String, target: Decimal, monthly: Decimal, symbol: String = "star.fill", targetDate: Date? = nil) {
        self.name = name; self.target = target; self.monthly = monthly; self.symbol = symbol; self.targetDate = targetDate
    }

    var progress: Double {
        target <= 0 ? 0 : min(1, NSDecimalNumber(decimal: saved / target).doubleValue)
    }
    var isReached: Bool { target > 0 && saved >= target }
}

/// When someone moves a merchant to another category, remember it.
@Model
final class MerchantRule {
    var keyword: String = ""
    var categoryRaw: String = CategoryID.other.rawValue
    init(keyword: String, category: CategoryID) { self.keyword = keyword.lowercased(); categoryRaw = category.rawValue }
}

/// Settings shared by the app, the widget and the App Intent (stored in the App Group).
enum AppSettings {
    static let appGroup = "group.ae.khurda.shared"
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static var payday: Int {
        get { defaults.object(forKey: "payday") as? Int ?? 27 }
        set { defaults.set(newValue, forKey: "payday") }
    }
    static var monthlyIncome: Decimal {
        get { Decimal(string: defaults.string(forKey: "income") ?? "") ?? 0 }
        set { defaults.set("\(newValue)", forKey: "income") }
    }
    static var savingsGoal: Decimal {
        get { Decimal(string: defaults.string(forKey: "savings") ?? "") ?? 0 }
        set { defaults.set("\(newValue)", forKey: "savings") }
    }
    /// Rough rates for showing foreign purchases in AED. AED is pegged to USD at 3.6725.
    /// Built from strings: a Decimal from a float literal goes through Double and picks up binary noise.
    static let fxToAED: [String: Decimal] = [
        "AED": "1", "USD": "3.6725", "EUR": "4.0", "GBP": "4.7", "SAR": "0.979", "QAR": "1.009",
        "OMR": "9.54", "KWD": "11.95", "BHD": "9.74", "INR": "0.043", "PKR": "0.013", "EGP": "0.075"
    ].mapValues { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))! }
}

/// Fixed bills are ticked off when their payment arrives; on payday they start again unticked.
/// Lives here (compiled into both the app and the widget) because the Shortcut, the widget and the
/// app can each be the first thing to run after payday.
enum CycleReset {
    @MainActor
    static func runIfNeeded(context: ModelContext, now: Date = .now) {
        let start = PayCycle.current(payday: AppSettings.payday, today: now).start
        let key = "lastCycleStart"
        let last = AppSettings.defaults.object(forKey: key) as? Date
        guard last != start else { return }
        (try? context.fetch(FetchDescriptor<Obligation>()))?.forEach { $0.isPaidThisCycle = false }
        // The monthly amount for each goal was set aside from this salary: count it as saved.
        // Only when a cycle was seen before, so the first launch doesn't credit a month nobody saved.
        if last != nil {
            (try? context.fetch(FetchDescriptor<SavingsGoal>()))?.forEach { g in
                if !g.isReached { g.saved = min(g.target, g.saved + g.monthly) }
            }
        }
        try? context.save()
        AppSettings.defaults.set(start, forKey: key)
    }
}

/// One SwiftData store in the App Group, so the Shortcut, the widget and the app all see the same data.
/// CloudKit sync can be switched on later with `cloudKitDatabase: .private(...)`.
enum Store {
    static let schema = Schema([Transaction.self, Budget.self, Obligation.self, MerchantRule.self,
                                Jameya.self, SavingsGoal.self])

    static let container: ModelContainer = {
        // Without the App Group entitlement (a free Apple ID, or an unsigned build) SwiftData traps
        // instead of throwing, so check first and fall back to the app's own store. The widget then
        // can't read the data, but the app and the Shortcuts actions still work.
        let hasGroup = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppSettings.appGroup) != nil
        let config = hasGroup
            ? ModelConfiguration(schema: schema, groupContainer: .identifier(AppSettings.appGroup))
            : ModelConfiguration(schema: schema, groupContainer: .none)
        do { return try ModelContainer(for: schema, configurations: config) }
        catch { fatalError("Could not open the data store: \(error)") }
    }()
}
