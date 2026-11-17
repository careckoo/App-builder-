import Foundation

/// What kind of money movement a bank message describes.
public enum TransactionKind: String, Codable, Sendable, CaseIterable {
    case purchase      // card / POS / online spend
    case withdrawal    // ATM cash
    case transferOut   // money you sent
    case income        // salary, transfer in, deposit
    case refund        // reversal / refund
}

/// The result of reading one bank SMS. Every field except `amount` and `kind` is optional,
/// because banks leave things out.
public struct ParsedTransaction: Equatable, Sendable {
    public var amount: Decimal
    public var currency: String          // ISO code, e.g. "AED"
    public var kind: TransactionKind
    public var merchant: String?
    public var cardLast4: String?
    public var balanceAfter: Decimal?
    public var date: Date?
    public var bankName: String?

    public var isExpense: Bool { kind == .purchase || kind == .withdrawal || kind == .transferOut }
}

/// Reads UAE bank SMS messages in English or Arabic and turns them into transactions.
///
/// It does not rely on one rigid template per bank. It looks for the same clues a person would:
/// a currency next to a number, a verb that says money left or arrived, a merchant after
/// "at" / "لدى", and the last four digits of a card. That keeps it working when a bank
/// changes its wording slightly.
public struct BankMessageParser: Sendable {

    public init() {}

    // MARK: - Public API

    public func parse(_ raw: String, sender: String? = nil, receivedAt: Date = .now) -> ParsedTransaction? {
        let text = Self.normalize(raw)
        let lower = text.lowercased()

        // 1. Never log one-time passwords, promos or failed transactions.
        if Self.containsAny(lower, Self.ignoreKeywords) { return nil }

        // 2. Find the transaction amount (not the balance or credit limit).
        guard let (amount, currency) = Self.transactionAmount(in: text), amount > 0 else { return nil }

        // 3. Decide direction.
        guard let kind = Self.kind(for: lower) else { return nil }

        return ParsedTransaction(
            amount: amount,
            currency: currency,
            kind: kind,
            merchant: kind == .income ? Self.incomeSource(in: text) : Self.merchant(in: text),
            cardLast4: Self.cardLast4(in: text),
            balanceAfter: Self.balance(in: text),
            date: Self.date(in: text) ?? receivedAt,
            bankName: BankDirectory.bankName(sender: sender, body: lower)
        )
    }

    // MARK: - Normalisation

    /// Converts Arabic-Indic and Persian digits to ASCII, unifies separators and spaces.
    static func normalize(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "٠"..."٩":
                out.append(Character(String(ch.unicodeScalars.first!.value - 0x0660)))
            case "۰"..."۹":
                out.append(Character(String(ch.unicodeScalars.first!.value - 0x06F0)))
            case "٫": out.append(".")
            case "٬", "،": out.append(",")
            case "\u{00A0}", "\n", "\t", "\r": out.append(" ")
            default: out.append(ch)
            }
        }
        return out.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Keywords

    static let ignoreKeywords = [
        "otp", "one time password", "one-time password", "verification code", "do not share",
        "activation code", "declined", "insufficient", "failed", "unsuccessful", "offer", "win ",
        "رمز التحقق", "كلمة المرور لمرة واحدة", "رمز التفعيل", "لا تشارك", "مرفوضة", "رفض", "غير كاف", "عرض خاص"
    ]

    static let refundKeywords = ["refund", "reversal", "reversed", "cashback", "مسترد", "استرداد", "استرجاع", "عكس"]
    static let withdrawalKeywords = ["atm", "cash withdrawal", "withdrawn", "withdrawal", "سحب نقدي", "سحب", "صراف"]
    static let incomeKeywords = [
        "credited", "has been deposited", "deposit", "received", "salary", "transfer from", "inward",
        "تم إيداع", "تم ايداع", "إيداع", "ايداع", "راتب", "استلام", "تم استلام", "حوالة واردة", "أضيف", "اضيف"
    ]
    static let transferOutKeywords = [
        "transferred to", "transfer to", "sent to", "remittance", "outward", "tfr to",
        "تحويل إلى", "تحويل الى", "حوالة صادرة", "تم تحويل"
    ]
    static let purchaseKeywords = [
        "debited", "used for", "purchase", "spent", "paid", "payment", "pos", "charged", "transaction of",
        "تم خصم", "خصم", "شراء", "عملية شراء", "مشتريات", "دفع", "تم استخدام", "تم الدفع"
    ]

    static func kind(for lower: String) -> TransactionKind? {
        if containsAny(lower, refundKeywords) { return .refund }
        if containsAny(lower, withdrawalKeywords) { return .withdrawal }
        // "transfer to" must win over "debited" ("AED 500 debited ... transferred to Ahmed").
        if containsAny(lower, transferOutKeywords) && !lower.contains("إلى حسابك") && !lower.contains("to your account") {
            return .transferOut
        }
        // Strong income words ("Salary payment credited") beat weak purchase words like "payment",
        // unless the message also clearly says money was taken.
        let strongIncome = ["credited", "deposited", "salary", "تم إيداع", "تم ايداع", "راتب", "حوالة واردة", "إلى حسابك", "to your account"]
        let strongDebit = ["debited", "تم خصم", "used for", "purchase", "شراء"]
        if containsAny(lower, strongIncome) && !containsAny(lower, strongDebit) { return .income }
        // "debited" must win over "received" ("debited ... received by merchant").
        if containsAny(lower, purchaseKeywords) { return .purchase }
        if containsAny(lower, incomeKeywords) { return .income }
        return nil
    }

    // MARK: - Amounts

    /// Currency tokens as they appear in UAE bank SMS, mapped to ISO codes.
    static let currencyTokens: [(token: String, iso: String)] = [
        ("AED", "AED"), ("Dhs.", "AED"), ("Dhs", "AED"), ("DHS", "AED"), ("Dh", "AED"),
        ("درهم", "AED"), ("د.إ", "AED"), ("د.ا", "AED"),
        ("USD", "USD"), ("US$", "USD"), ("دولار", "USD"),
        ("EUR", "EUR"), ("GBP", "GBP"), ("SAR", "SAR"), ("ريال", "SAR"),
        ("INR", "INR"), ("PKR", "PKR"), ("EGP", "EGP"), ("QAR", "QAR"), ("OMR", "OMR"), ("KWD", "KWD"), ("BHD", "BHD")
    ]

    static let number = #"([0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]{1,3})?|[0-9]+(?:\.[0-9]{1,3})?)"#

    static var currencyAlternation: String {
        currencyTokens.map { NSRegularExpression.escapedPattern(for: $0.token) }.joined(separator: "|")
    }

    /// Words that, right before an amount, mean "this is not the transaction amount".
    static let balanceMarkers = [
        "balance", "bal", "avl", "avail", "available", "limit", "outstanding", "due",
        "الرصيد", "رصيد", "المتاح", "الحد", "المستحق"
    ]

    struct AmountMatch { let value: Decimal; let iso: String; let range: Range<String.Index> }

    static func allAmounts(in text: String) -> [AmountMatch] {
        let cur = currencyAlternation
        // Currency before number ("AED 45.50") or number before currency ("45.50 درهم").
        let patterns = [
            #"(?:"# + cur + #")\s?"# + number,
            number + #"\s?(?:"# + cur + #")"#
        ]
        var found: [AmountMatch] = []
        for (i, p) in patterns.enumerated() {
            guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard let full = Range(m.range, in: text), let numR = Range(m.range(at: 1), in: text) else { continue }
                let fullStr = String(text[full])
                let numStr = String(text[numR]).replacingOccurrences(of: ",", with: "")
                guard let value = Decimal(string: numStr, locale: Locale(identifier: "en_US_POSIX")) else { continue }
                let curStr = i == 0 ? String(fullStr[..<fullStr.range(of: String(text[numR]))!.lowerBound])
                                    : String(fullStr[fullStr.range(of: String(text[numR]))!.upperBound...])
                let isoCode = iso(for: curStr.trimmingCharacters(in: .whitespaces))
                if !found.contains(where: { $0.range.overlaps(full) }) {
                    found.append(AmountMatch(value: value, iso: isoCode, range: full))
                }
            }
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    static func iso(for token: String) -> String {
        let t = token.lowercased()
        return currencyTokens.first { $0.token.lowercased() == t }?.iso ?? "AED"
    }

    static func isPrecededByBalanceMarker(_ m: AmountMatch, in text: String) -> Bool {
        let start = text.index(m.range.lowerBound, offsetBy: -min(28, text.distance(from: text.startIndex, to: m.range.lowerBound)))
        let before = text[start..<m.range.lowerBound].lowercased()
        return balanceMarkers.contains { before.contains($0) }
    }

    static func transactionAmount(in text: String) -> (Decimal, String)? {
        let all = allAmounts(in: text)
        if let m = all.first(where: { !isPrecededByBalanceMarker($0, in: text) }) { return (m.value, m.iso) }
        // Some Arabic messages say "مبلغ 45.50" with the currency only on the balance; fall back.
        if let re = try? NSRegularExpression(pattern: #"(?:مبلغ|amount of|amt)\s?:?\s?"# + number, options: .caseInsensitive),
           let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(m.range(at: 1), in: text),
           let v = Decimal(string: text[r].replacingOccurrences(of: ",", with: "")) {
            return (v, all.first?.iso ?? "AED")
        }
        return nil
    }

    static func balance(in text: String) -> Decimal? {
        allAmounts(in: text).last(where: { isPrecededByBalanceMarker($0, in: text) })?.value
    }

    // MARK: - Merchant, card, date

    static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    static func merchant(in text: String) -> String? {
        let stops = #"(?=\s+on\s|\s+from\s|\s+has\s|\s+من\s+(?:حساب|بطاق)|\s+بتاريخ|\s+في\s+[0-9]|\s+بقيمة|\s+[0-9]{1,2}[/-]|\.\s|\.$|(?:,\s*|\s+)(?:avl|avail|available|bal\b|balance|الرصيد|رصيد)|$)"#
        let patterns = [
            #"\bat\s+(.+?)"# + stops,
            #"لدى\s+(.+?)"# + stops,
            #"عند\s+(.+?)"# + stops,
            #"\bto\s+(.+?)"# + stops,       // "paid to DEWA", "transferred to AHMED"
            #"إلى\s+(.+?)"# + stops,
            #"\bfrom\s+(.+?)"# + stops,     // "Refund of AED 89 from NOON.COM"
            #"\bfor\s+([A-Z][A-Za-z0-9 &*'.-]{2,})"# + stops
        ]
        for p in patterns {
            if var name = firstCapture(p, in: text) {
                name = cleanMerchant(name)
                if name.count >= 2, !name.allSatisfy(\.isNumber), Decimal(string: name) == nil,
                   !Self.isAccountReference(name) { return name }
            }
        }
        return nil
    }

    /// "your account XXX1234", "حسابك" — the message is talking about you, not a merchant.
    static func isAccountReference(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.hasPrefix("your ") || l.contains("account") || l.contains("card ending")
            || l.contains("حساب") || l.contains("بطاق")
    }

    static func cleanMerchant(_ s: String) -> String {
        var name = s.trimmingCharacters(in: CharacterSet(charactersIn: " ,.-:"))
        // "CARREFOUR,ABU DHABI AE" -> "CARREFOUR"  ; "Talabat Dubai" stays readable.
        if let comma = name.firstIndex(of: ",") { name = String(name[..<comma]) }
        for tail in [" AE", " UAE", " ARE", " ABU DHABI", " DUBAI", " SHARJAH", " AL AIN"] where name.uppercased().hasSuffix(tail) {
            name = String(name.dropLast(tail.count))
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    static func incomeSource(in text: String) -> String? {
        if let p = firstCapture(#"\(([^)]{2,30})\)"#, in: text) { return p }
        if let f = firstCapture(#"\bfrom\s+(.+?)(?=\s+on\s|\.\s|\.$|,|$)"#, in: text) { return cleanMerchant(f) }
        if let f = firstCapture(#"من\s+(.+?)(?=\s+بتاريخ|\.\s|\.$|،|,|$)"#, in: text), !f.contains("حساب") { return cleanMerchant(f) }
        let lower = text.lowercased()
        if lower.contains("salary") || text.contains("راتب") { return "Salary" }
        return nil
    }

    static func cardLast4(in text: String) -> String? {
        firstCapture(#"(?:ending(?:\s+with)?|x{2,}|\*{2,}|no\.?|رقم|المنتهية ب|المنتهي ب)\s*[x*]*\s*([0-9]{4})\b"#, in: text)
    }

    static func date(in text: String) -> Date? {
        let posix = Locale(identifier: "en_US_POSIX")
        let candidates: [(String, String)] = [
            (#"\b([0-9]{1,2}/[0-9]{1,2}/[0-9]{4})\b"#, "d/M/yyyy"),
            (#"\b([0-9]{1,2}-[0-9]{1,2}-[0-9]{4})\b"#, "d-M-yyyy"),
            (#"\b([0-9]{1,2}/[0-9]{1,2}/[0-9]{2})\b"#, "d/M/yy"),
            (#"\b([0-9]{1,2}-[A-Za-z]{3}-[0-9]{2,4})\b"#, "d-MMM-yy"),
            (#"\b([0-9]{4}-[0-9]{2}-[0-9]{2})\b"#, "yyyy-MM-dd")
        ]
        for (pattern, format) in candidates {
            guard let s = firstCapture(pattern, in: text) else { continue }
            let f = DateFormatter()
            f.locale = posix
            f.timeZone = TimeZone(identifier: "Asia/Dubai")
            f.dateFormat = (format == "d-MMM-yy" && s.count > 9) ? "d-MMM-yyyy" : format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    static func containsAny(_ s: String, _ words: [String]) -> Bool { words.contains { s.contains($0) } }
}
