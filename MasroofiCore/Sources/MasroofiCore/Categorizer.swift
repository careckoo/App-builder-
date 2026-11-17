import Foundation

/// Built-in spending categories. People can add their own in the app; these are the defaults.
public enum CategoryID: String, Codable, Sendable, CaseIterable {
    case groceries, dining, delivery, transport, fuel, shopping, bills, telecom
    case health, entertainment, subscriptions, travel, education, family, cash
    case transfer, income, installments, charity, other

    public var nameEN: String {
        switch self {
        case .groceries: "Groceries"
        case .dining: "Restaurants & cafés"
        case .delivery: "Food delivery"
        case .transport: "Taxi & transport"
        case .fuel: "Fuel"
        case .shopping: "Shopping"
        case .bills: "Utilities"
        case .telecom: "Mobile & internet"
        case .health: "Health"
        case .entertainment: "Entertainment"
        case .subscriptions: "Subscriptions"
        case .travel: "Travel"
        case .education: "Education"
        case .family: "Family & home"
        case .cash: "Cash"
        case .transfer: "Transfers"
        case .income: "Income"
        case .installments: "Buy now, pay later"
        case .charity: "Charity"
        case .other: "Other"
        }
    }

    public var nameAR: String {
        switch self {
        case .groceries: "بقالة"
        case .dining: "مطاعم ومقاهي"
        case .delivery: "توصيل طعام"
        case .transport: "تاكسي ومواصلات"
        case .fuel: "وقود"
        case .shopping: "تسوق"
        case .bills: "كهرباء وماء"
        case .telecom: "جوال وإنترنت"
        case .health: "صحة"
        case .entertainment: "ترفيه"
        case .subscriptions: "اشتراكات"
        case .travel: "سفر"
        case .education: "تعليم"
        case .family: "الأسرة والمنزل"
        case .cash: "نقد"
        case .transfer: "تحويلات"
        case .income: "دخل"
        case .installments: "تقسيط"
        case .charity: "صدقة وتبرعات"
        case .other: "أخرى"
        }
    }

    /// SF Symbol for the category.
    public var symbol: String {
        switch self {
        case .groceries: "cart.fill"
        case .dining: "fork.knife"
        case .delivery: "takeoutbag.and.cup.and.straw.fill"
        case .transport: "car.fill"
        case .fuel: "fuelpump.fill"
        case .shopping: "bag.fill"
        case .bills: "bolt.fill"
        case .telecom: "antenna.radiowaves.left.and.right"
        case .health: "cross.case.fill"
        case .entertainment: "popcorn.fill"
        case .subscriptions: "repeat"
        case .travel: "airplane"
        case .education: "graduationcap.fill"
        case .family: "house.fill"
        case .cash: "banknote.fill"
        case .transfer: "arrow.left.arrow.right"
        case .income: "arrow.down.circle.fill"
        case .installments: "calendar.badge.clock"
        case .charity: "heart.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}

/// Guesses a category from the merchant name. When a person re-categorises a merchant once,
/// the app stores that as a rule and `learned` takes priority next time.
public struct Categorizer: Sendable {
    public var learned: [String: CategoryID]

    public init(learned: [String: CategoryID] = [:]) { self.learned = learned }

    /// Keyword → category. Lower-case. English keywords match whole words of the merchant name (with a
    /// plural or possessive "s"); Arabic ones match as substrings. Covers common UAE merchants.
    public static let rules: [(String, CategoryID)] = [
        // Delivery before dining, so "TALABAT" isn't treated as a restaurant.
        ("talabat", .delivery), ("deliveroo", .delivery), ("noon food", .delivery), ("careem food", .delivery),
        ("instashop", .groceries), ("kibsons", .groceries), ("noon minutes", .groceries),
        ("carrefour", .groceries), ("lulu", .groceries), ("spinneys", .groceries), ("waitrose", .groceries),
        ("union coop", .groceries), ("abu dhabi coop", .groceries), ("choithrams", .groceries), ("grandiose", .groceries),
        ("nesto", .groceries), ("al maya", .groceries), ("baqala", .groceries), ("supermarket", .groceries),
        ("hypermarket", .groceries), ("كارفور", .groceries), ("لولو", .groceries), ("تعاونية", .groceries), ("بقالة", .groceries),
        ("starbucks", .dining), ("tim hortons", .dining), ("costa", .dining), ("mcdonald", .dining), ("kfc", .dining),
        ("shake shack", .dining), ("restaurant", .dining), ("cafe", .dining), ("café", .dining), ("coffee", .dining),
        ("مطعم", .dining), ("مقهى", .dining), ("كافيه", .dining),
        ("careem", .transport), ("uber", .transport), ("rta", .transport), ("salik", .transport), ("darb", .transport),
        ("itc", .transport), ("parking", .transport), ("mawaqif", .transport), ("nol", .transport), ("taxi", .transport),
        ("كريم", .transport), ("سالك", .transport), ("مواقف", .transport),
        ("adnoc", .fuel), ("enoc", .fuel), ("eppco", .fuel), ("emarat", .fuel), ("petrol", .fuel), ("أدنوك", .fuel),
        ("taqa", .bills), ("addc", .bills), ("aadc", .bills), ("dewa", .bills), ("sewa", .bills), ("fewa", .bills), ("etihad wa", .bills),
        ("empower", .bills), ("tabreed", .bills), ("طاقة", .bills), ("ديوا", .bills),
        ("etisalat", .telecom), ("e&", .telecom), ("du", .telecom), ("virgin mobile", .telecom), ("اتصالات", .telecom),
        ("netflix", .subscriptions), ("spotify", .subscriptions), ("apple.com", .subscriptions), ("osn", .subscriptions),
        ("shahid", .subscriptions), ("youtube", .subscriptions), ("anghami", .subscriptions), ("icloud", .subscriptions),
        ("amazon prime", .subscriptions), ("disney", .subscriptions), ("chatgpt", .subscriptions), ("claude", .subscriptions),
        ("amazon", .shopping), ("noon", .shopping), ("namshi", .shopping), ("shein", .shopping), ("ikea", .family),
        ("centrepoint", .shopping), ("max fashion", .shopping), ("h&m", .shopping), ("zara", .shopping), ("mall", .shopping),
        ("sharaf dg", .shopping), ("jumbo", .shopping), ("virgin megastore", .shopping), ("ace", .family), ("home centre", .family),
        ("pharmacy", .health), ("aster", .health), ("life pharmacy", .health), ("boots", .health), ("hospital", .health),
        ("clinic", .health), ("seha", .health), ("mediclinic", .health), ("صيدلية", .health), ("مستشفى", .health),
        ("vox", .entertainment), ("reel cinema", .entertainment), ("novo", .entertainment), ("ferrari world", .entertainment),
        ("yas", .entertainment), ("louvre", .entertainment), ("playstation", .entertainment), ("steam", .entertainment),
        ("emirates", .travel), ("etihad", .travel), ("flydubai", .travel), ("air arabia", .travel), ("booking.com", .travel),
        ("hotel", .travel), ("airbnb", .travel), ("طيران", .travel), ("فندق", .travel),
        ("school", .education), ("university", .education), ("academy", .education), ("مدرسة", .education), ("جامعة", .education),
        ("tabby", .installments), ("tamara", .installments), ("postpay", .installments), ("تابي", .installments), ("تمارا", .installments),
        ("red crescent", .charity), ("dar al ber", .charity), ("الهلال الأحمر", .charity), ("صدقة", .charity), ("زكاة", .charity)
    ]

    public func category(for parsed: ParsedTransaction) -> CategoryID {
        switch parsed.kind {
        case .income, .refund: return .income
        case .withdrawal: return .cash
        case .cardPayment, .ownTransfer: return .transfer
        case .transferOut, .purchase: break
        }
        guard let merchant = parsed.merchant?.lowercased() else {
            return parsed.kind == .transferOut ? .transfer : .other
        }
        if let learnedHit = learnedCategory(for: merchant) { return learnedHit }
        if let hit = Self.rules.first(where: { Self.ruleMatches(merchant, $0.0) }) { return hit.1 }
        return parsed.kind == .transferOut ? .transfer : .other
    }

    /// The person's own corrections: the exact merchant name first, then the longest learned name
    /// found as whole words (so the result doesn't depend on dictionary order).
    func learnedCategory(for merchant: String) -> CategoryID? {
        let lowered = Dictionary(learned.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        if let exact = lowered[merchant] { return exact }
        return lowered
            .filter { !$0.key.isEmpty && BankMessageParser.containsWord(merchant, $0.key) }
            .max { $0.key.count != $1.key.count ? $0.key.count < $1.key.count : $0.key > $1.key }?
            .value
    }

    /// NOVOTEL is not "novo", AFTERNOON TEA is not "noon"; RESTAURANTS and MCDONALD'S still match.
    static func ruleMatches(_ merchant: String, _ key: String) -> Bool {
        if BankMessageParser.containsWord(merchant, key) { return true }
        guard key.unicodeScalars.allSatisfy(\.isASCII) else { return false }
        return BankMessageParser.containsWord(merchant, key + "s") || BankMessageParser.containsWord(merchant, key + "'s")
    }
}
