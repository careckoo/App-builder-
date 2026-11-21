import Foundation

/// What kind of money movement a bank message describes.
public enum TransactionKind: String, Codable, Sendable, CaseIterable {
    case purchase      // card / POS / online spend
    case withdrawal    // ATM cash
    case transferOut   // money you sent
    case income        // salary, transfer in, deposit
    case refund        // reversal / refund
    case cardPayment   // credit-card bill paid from your own account: not income, not spending
    case ownTransfer   // between your own accounts, a fixed deposit, savings, or cash into a CDM: neutral
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
            merchant: kind == .income ? Self.incomeSource(in: text)
                    : (kind == .cardPayment || kind == .ownTransfer) ? nil : Self.merchant(in: text),
            cardLast4: Self.cardLast4(in: text),
            balanceAfter: Self.balance(in: text),
            date: Self.resolvedDate(in: text, receivedAt: receivedAt),
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
            // "\r\n" is one Character in Swift, so it needs its own case.
            case "\u{00A0}", "\n", "\t", "\r", "\r\n": out.append(" ")
            default: out.append(ch)
            }
        }
        return out.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Keywords

    static let ignoreKeywords = [
        "otp", "one time password", "one-time password", "verification code", "do not share",
        "activation code", "declined", "insufficient", "failed", "unsuccessful", "offer", "offers", "win",
        "رمز التحقق", "كلمة المرور لمرة واحدة", "رمز التفعيل", "لا تشارك", "مرفوضة", "رفض", "غير كاف", "عرض خاص",
        // Payment reminders and prize draws: no money moved.
        // Not a bare "reminder": "Set a reminder in our app" sits under real purchase alerts.
        "minimum payment due", "minimum amount due", "minimum due", "min. due", "min due", "is due on",
        "payment reminder", "friendly reminder", "this is a reminder", "please pay",
        "الحد الأدنى", "تذكير", "مستحق الدفع", "مستحقة الدفع", "تاريخ الاستحقاق", "اربح", "السحب على", "جوائز", "جائزة",
        // Purchase-approval codes ("Use 482913 to authorise your purchase of AED 500 at AMAZON.AE").
        "to authorise", "to authorize", "is your code", "your code is", "passcode", "secure code"
    ]

    /// True for an OTP, promo, reminder or failed payment. Also used on an email's subject, so an
    /// "Your one-time password" email is skipped even when its body looks like a purchase.
    public static func isIgnorable(_ text: String) -> Bool {
        containsAny(normalize(text).lowercased(), ignoreKeywords)
    }

    static let refundKeywords = ["refund", "refunded", "reversal", "reversed", "cashback", "مسترد", "استرداد", "استرجاع", "عكس"]
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
        "debited", "used for", "purchase", "purchased", "spent", "paid", "payment", "pos", "charged", "transaction of",
        "trx", "txn", "approved", "recharge", "recharged",
        "تم خصم", "خصم", "شراء", "عملية شراء", "مشتريات", "دفع", "تم استخدام", "تم الدفع"
    ]

    /// "your payment of AED2000.00 ... for card ending with *197 has been credited": the person paid
    /// their own credit-card bill. Counting it as income (or as spending) would distort safe-to-spend.
    static let cardPaymentPatterns = [
        #"\b(?:payment|paid)\b.{0,80}?\b(?:for|to|towards) (?:your )?(?:credit )?card\b"#,
        #"\bcredit card (?:bill )?payment\b"#,
        #"\bcredit card\b.{0,30}?\bpayment\b.{0,80}?\b(?:received|credited)\b"#,
        #"\bcard (?:bill )?payment\b.{0,60}?\b(?:received|credited)\b"#,
        #"\bpayment received for your (?:credit )?card\b"#,
        #"\bcredited to (?:your )?credit card\b"#,
        #"سداد (?:ال)?بطاق"#,
        #"سداد.{0,60}?(?:لبطاقت|(?:إلى|الى) بطاقت)"#,
        #"تم استلام دفعة.{0,80}?بطاق"#
    ]

    /// A merchant named after "at" / لدى / عند ("card payment of AED 30 at STARBUCKS" is a purchase).
    /// Not a date or phone number ("credited at 16/11/26", "call us at 600…") and not "with us at ADCB".
    static let merchantAt = #"(?<!\bus )\bat\s+(?!us\b|your\b|the\b|any\b)[^\s0-9+(]|(?:لدى|عند)\s+[^\s0-9+(]"#

    static func isCardPayment(_ lower: String) -> Bool {
        if matches(merchantAt, lower) { return false }
        return cardPaymentPatterns.contains { matches($0, lower) }
    }

    /// Money moved between the person's own accounts, into or out of a fixed deposit or savings, or
    /// cash put into a CDM (already counted when it was withdrawn). Not income, not spending.
    static let ownTransferPatterns = [
        #"\bfrom your (?:a/c|account|acct)\b.*\bto your (?:a/c|account|acct)\b"#,
        #"\bto your (?:a/c|account|acct)\b.*\bfrom your (?:a/c|account|acct)\b"#,
        #"\bown (?:a/c|account|accounts|acct)\b"#,
        #"\bbetween (?:your|own) accounts\b"#,
        #"\b(?:fixed|term) deposit\b"#,
        #"\bsavings? spaces?\b"#,
        #"\b(?:transfer(?:red)?|moved|sent|tfr)\b.{0,40}?\b(?:to|into|from)\b.{0,15}?\bsavings? (?:account|a/c|pot)\b"#,
        #"\bcdm\b"#,
        #"\bcash deposit\b"#,
        #"من حسابك.*(?:إلى|الى) حسابك"#,
        #"بين حساباتك"#,
        #"وديعة"#,
        #"(?:إيداع|ايداع) نقدي"#,
        #"(?:تحويل|حول).{0,40}?حساب (?:ال)?(?:توفير|ادخار)"#
    ]

    static func isOwnTransfer(_ lower: String) -> Bool { ownTransferPatterns.contains { matches($0, lower) } }

    static func matches(_ pattern: String, _ s: String) -> Bool {
        s.range(of: pattern, options: .regularExpression) != nil
    }

    static func kind(for lower: String) -> TransactionKind? {
        if containsAny(lower, refundKeywords) { return .refund }
        if isOwnTransfer(lower) { return .ownTransfer }
        if containsAny(lower, withdrawalKeywords) { return .withdrawal }
        if isCardPayment(lower) { return .cardPayment }
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
        "balance", "bal", "avl", "avlbal", "avail", "available", "limit", "outstanding", "due",
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
        // Whole words for English markers: "BALI RESTAURANT" and "UNLIMITED BURGERS" are merchants.
        return containsAny(before, balanceMarkers)
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
        if let b = allAmounts(in: text).last(where: { isPrecededByBalanceMarker($0, in: text) }) { return b.value }
        // "Avl. card bal is 4852.54": a balance with no currency next to it.
        guard let s = firstCapture(#"(?:\bbal(?:ance)?|الرصيد|رصيد)\.?\s*(?:is\s*|:\s*)?"# + number, in: text) else { return nil }
        return Decimal(string: s.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX"))
    }

    // MARK: - Merchant, card, date

    static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    static func merchant(in text: String) -> String? {
        let stops = #"(?=\s+on\s|\s+from\s|\s+with\s+card|\s+has\s|\s+(?:was|is)\s|\s+من\s+(?:حساب|بطاق)|\s+بتاريخ|\s+في\s+[0-9]|\s+بقيمة|\s+[0-9]{1,2}[/-]|\.\s|\.$|(?:,\s*|\s+)(?:avl|avail|available|bal\b|balance|الرصيد|رصيد)|\s+(?:for\s+)?(?:"# + currencyAlternation + #")\s?[0-9]|$)"#
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
                // Reject bare numbers only. `Decimal(string:)` would also reject "7 ELEVEN", because it reads the leading 7.
                if name.count >= 2, !matches(#"^[0-9.,]+$"#, name),
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
        // "at the DUBAI MALL" -> "DUBAI MALL".
        if name.lowercased().hasPrefix("the ") { name = String(name.dropFirst(4)).trimmingCharacters(in: .whitespaces) }
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
        // Some banks show only the last 3 digits ("card ending *822").
        firstCapture(#"(?:ending(?:\s+with)?|x{2,}|\*+|\bno\.?|رقم|المنتهية ب|المنتهي ب)\s*[x*]*\s*([0-9]{3,4})\b"#, in: text)
    }

    /// A date written in the message, and whether it also had a time ("16/11/26 15:38").
    static func date(in text: String) -> (date: Date, hasTime: Bool)? {
        let posix = Locale(identifier: "en_US_POSIX")
        let time = #"\s+[0-9]{1,2}:[0-9]{2}"#
        let candidates: [(String, String, Bool)] = [
            (#"\b([0-9]{1,2}/[0-9]{1,2}/[0-9]{4}"# + time + #")\b"#, "d/M/yyyy H:mm", true),
            (#"\b([0-9]{1,2}-[0-9]{1,2}-[0-9]{4}"# + time + #")\b"#, "d-M-yyyy H:mm", true),
            (#"\b([0-9]{1,2}/[0-9]{1,2}/[0-9]{2}"# + time + #")\b"#, "d/M/yy H:mm", true),
            (#"\b([0-9]{1,2}/[0-9]{1,2}/[0-9]{4})\b"#, "d/M/yyyy", false),
            (#"\b([0-9]{1,2}-[0-9]{1,2}-[0-9]{4})\b"#, "d-M-yyyy", false),
            (#"\b([0-9]{1,2}/[0-9]{1,2}/[0-9]{2})\b"#, "d/M/yy", false),
            (#"\b([0-9]{1,2}-[A-Za-z]{3}-[0-9]{2,4})\b"#, "d-MMM-yy", false),
            (#"\b([0-9]{4}-[0-9]{2}-[0-9]{2})\b"#, "yyyy-MM-dd", false)
        ]
        for (pattern, format, hasTime) in candidates {
            guard let raw = firstCapture(pattern, in: text) else { continue }
            let s = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let f = DateFormatter()
            f.locale = posix
            f.timeZone = TimeZone(identifier: "Asia/Dubai")
            f.dateFormat = (format == "d-MMM-yy" && s.count > 9) ? "d-MMM-yyyy" : format
            if let d = f.date(from: s) { return (d, hasTime) }
        }
        return nil
    }

    /// When the transaction happened.
    /// - The message has a date and a time: use them.
    /// - Only a date, and it is the day the message arrived (or later): use the arrival time, so the
    ///   purchase doesn't show at 00:00 and the duplicate check sees the real moment.
    /// - Only a date, earlier than arrival (an old message pasted later): keep the message's own day.
    static func resolvedDate(in text: String, receivedAt: Date, calendar: Calendar = .dubai) -> Date {
        guard let found = date(in: text) else { return receivedAt }
        if found.hasTime { return found.date }
        if calendar.startOfDay(for: found.date) >= calendar.startOfDay(for: receivedAt) { return receivedAt }
        return found.date
    }

    /// English keywords match on word edges, so "pos" doesn't hit "deposit", "atm" doesn't hit
    /// "treatment" and "paid" doesn't hit "prepaid". Same as `(?<![a-z0-9])word(?![a-z0-9])` in parser.js.
    /// Arabic keywords stay plain substrings, because Arabic attaches prefixes such as و / ب / ال.
    static func containsWord(_ s: String, _ word: String) -> Bool {
        guard word.unicodeScalars.allSatisfy(\.isASCII) else { return s.contains(word) }
        var from = s.startIndex
        while from < s.endIndex, let r = s.range(of: word, range: from..<s.endIndex) {
            let startOK = r.lowerBound == s.startIndex || !isASCIIAlphanumeric(s[s.index(before: r.lowerBound)])
            let endOK = r.upperBound == s.endIndex || !isASCIIAlphanumeric(s[r.upperBound])
            if startOK && endOK { return true }
            from = s.index(after: r.lowerBound)
        }
        return false
    }

    static func isASCIIAlphanumeric(_ c: Character) -> Bool {
        guard let a = c.asciiValue else { return false }
        return (a >= 48 && a <= 57) || (a >= 97 && a <= 122) || (a >= 65 && a <= 90)
    }

    static func containsAny(_ s: String, _ words: [String]) -> Bool { words.contains { containsWord(s, $0) } }
}
