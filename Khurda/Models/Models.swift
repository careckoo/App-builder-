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
        try? context.save()
        AppSettings.defaults.set(start, forKey: key)
    }
}

/// One SwiftData store in the App Group, so the Shortcut, the widget and the app all see the same data.
/// CloudKit sync can be switched on later with `cloudKitDatabase: .private(...)`.
enum Store {
    static let schema = Schema([Transaction.self, Budget.self, Obligation.self, MerchantRule.self])

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
