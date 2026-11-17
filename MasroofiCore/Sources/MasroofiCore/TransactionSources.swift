import Foundation

/// Where a transaction came from. Stored as `Transaction.sourceRaw`.
public enum TransactionSource: String, Codable, Sendable, CaseIterable {
    case sms        // bank SMS via the Message automation, or pasted
    case email      // bank alert email via the Email automation
    case wallet     // Apple Pay, via the Wallet "Transaction" automation
    case manual     // typed in by hand (cash, a card swipe nothing else caught)
    case statement  // imported from a bank statement (reserved; no importer yet)

    /// Automatic sources that can report the same purchase as each other.
    public var isAutomatic: Bool { self == .sms || self == .email || self == .wallet }
}

public extension ParsedTransaction {
    /// For sources that aren't a bank message (Apple Pay, manual entry), so they share the same
    /// fingerprint, categoriser and saving code as parsed messages. (No `balanceAfter` parameter, so the
    /// signature differs from the memberwise initializer the parser uses.)
    init(amount: Decimal, currency: String = "AED", kind: TransactionKind = .purchase, merchant: String?,
         cardLast4: String? = nil, date: Date? = nil, bankName: String? = nil) {
        self.amount = amount
        self.currency = currency
        self.kind = kind
        self.merchant = merchant
        self.cardLast4 = cardLast4
        self.balanceAfter = nil
        self.date = date
        self.bankName = bankName
    }
}

// MARK: - Amount text (Apple Pay)

/// Reads an amount that Shortcuts hands over as text: "AED 45.50", "45.50 د.إ", "د.إ.‏ ٤٥٫٥٠",
/// "$12.00", "1,250.00", "45,50". The Wallet automation formats the amount in the phone's language,
/// so it can carry a currency symbol, Arabic digits and invisible direction marks.
public enum AmountText {
    static let symbols: [(String, String)] = [("$", "USD"), ("€", "EUR"), ("£", "GBP"), ("₹", "INR")]

    public static func parse(_ raw: String) -> (amount: Decimal, currency: String)? {
        let text = MessageText.removingDirectionMarks(BankMessageParser.normalize(raw))
        guard let r = text.range(of: #"[0-9](?:[0-9.,]*[0-9])?"#, options: .regularExpression) else { return nil }
        guard let value = number(String(text[r])), value > 0 else { return nil }
        return (value, currency(in: text.replacingCharacters(in: r, with: " ")))
    }

    /// "1,250.00" and "1.250,00" are both 1250; "45,50" is 45.5; "1,250" is 1250.
    static func number(_ s: String) -> Decimal? {
        var digits = s
        let lastComma = s.lastIndex(of: ","), lastDot = s.lastIndex(of: ".")
        switch (lastComma, lastDot) {
        case let (c?, d?):
            // Whichever separator comes last is the decimal point.
            if c > d { digits = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
            else { digits = s.replacingOccurrences(of: ",", with: "") }
        case let (c?, nil):
            let after = s.distance(from: c, to: s.endIndex) - 1
            let commas = s.filter { $0 == "," }.count
            digits = (commas == 1 && after <= 2) ? s.replacingOccurrences(of: ",", with: ".")
                                                 : s.replacingOccurrences(of: ",", with: "")
        case (nil, _?):
            if s.filter({ $0 == "." }).count > 1 { digits = s.replacingOccurrences(of: ".", with: "") }
        case (nil, nil): break
        }
        return Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func currency(in rest: String) -> String {
        let lower = rest.lowercased()
        if let t = BankMessageParser.currencyTokens.first(where: { lower.contains($0.token.lowercased()) }) { return t.iso }
        if let s = symbols.first(where: { rest.contains($0.0) }) { return s.1 }
        return "AED"
    }
}

// MARK: - Email text

/// Bank alert emails carry the same sentence as the SMS, wrapped in HTML and a long footer.
public enum MessageText {
    /// Left-to-right / right-to-left marks and isolates that Arabic formatting inserts.
    static let directionMarks: Set<Unicode.Scalar> = [
        "\u{200E}", "\u{200F}", "\u{061C}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
        "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}", "\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}"
    ]

    static func removingDirectionMarks(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { !directionMarks.contains($0) }))
    }

    /// Drops HTML tags, comments, <style>/<script>/<head> blocks and decodes common entities,
    /// then collapses whitespace. Plain SMS text passes through unchanged (apart from spacing).
    public static func stripHTML(_ raw: String) -> String {
        var s = raw
        func sub(_ pattern: String, _ with: String) {
            s = s.replacingOccurrences(of: pattern, with: with, options: [.regularExpression, .caseInsensitive])
        }
        sub(#"<!--[\s\S]*?-->"#, " ")
        sub(#"<(style|script|head)\b[^>]*>[\s\S]*?</\1\s*>"#, " ")
        sub(#"<br\s*/?>"#, " ")
        sub(#"</?(?:p|div|tr|td|th|li|ul|ol|table|tbody|h[1-6])\b[^>]*>"#, " ")
        // Only things that look like tags: "AED < 50" is left alone.
        sub(#"</?[a-z][a-z0-9]*\b[^<>]*>"#, "")
        s = decodeEntities(s)
        s = removingDirectionMarks(s)
        return s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static let namedEntities: [String: String] = [
        "nbsp": " ", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "#39": "'",
        "ndash": "–", "mdash": "—", "zwnj": "", "zwj": "", "lrm": "", "rlm": "", "rsquo": "’", "lsquo": "‘"
    ]

    static func decodeEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }
        guard let re = try? NSRegularExpression(pattern: #"&(#[0-9]{1,7}|#x[0-9a-fA-F]{1,6}|[a-zA-Z]{2,8});"#) else { return input }
        var out = input
        // Replace from the end so earlier ranges stay valid. "&amp;" goes last, in one pass, so
        // "&amp;nbsp;" becomes the text "&nbsp;" and is not decoded twice.
        for m in re.matches(in: input, range: NSRange(input.startIndex..., in: input)).reversed() {
            guard let whole = Range(m.range, in: out), let nameR = Range(m.range(at: 1), in: out) else { continue }
            let name = String(out[nameR])
            var replacement: String?
            if name.lowercased() == "amp" { replacement = "&" }
            else if let named = namedEntities[name.lowercased()] { replacement = named }
            else if name.hasPrefix("#x") || name.hasPrefix("#X"), let v = UInt32(name.dropFirst(2), radix: 16),
                    let u = Unicode.Scalar(v) { replacement = String(Character(u)) }
            else if name.hasPrefix("#"), let v = UInt32(name.dropFirst()), let u = Unicode.Scalar(v) {
                replacement = String(Character(u))
            }
            if let replacement { out.replaceSubrange(whole, with: replacement) }
        }
        return out
    }

    /// Footer phrases. Bank emails end with "never share your OTP", "offers", disclaimers…
    /// which would make the parser skip the whole email as an OTP or promo.
    static let footerMarkers = [
        "never share", "do not share", "don't share", "for your security", "for security reasons",
        "disclaimer", "this is a system generated", "this is an automated", "this is an auto-generated",
        "please do not reply", "do not reply to this", "unsubscribe", "regards",
        "لا تشارك", "يرجى عدم الرد", "إخلاء المسؤولية", "مع تحيات", "مع أطيب التحيات"
    ]

    /// Plain text of an email body, cut before the footer. The cut only happens after the
    /// transaction amount, so a security banner at the top can't hide the transaction.
    public static func emailBody(_ raw: String) -> String {
        let text = BankMessageParser.normalize(stripHTML(raw))
        var cut: String.Index?
        for marker in footerMarkers {
            guard let r = text.range(of: marker, options: .caseInsensitive) else { continue }
            if let c = cut, c <= r.lowerBound { continue }
            if !BankMessageParser.allAmounts(in: String(text[..<r.lowerBound])).isEmpty { cut = r.lowerBound }
        }
        guard let cut else { return text }
        return String(text[..<cut]).trimmingCharacters(in: CharacterSet(charactersIn: " -|"))
    }

    /// An email arrives with a subject, an address as sender, or HTML in the body.
    public static func looksLikeEmail(_ body: String, sender: String?, subject: String?) -> Bool {
        if let subject, !subject.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        if let sender, sender.contains("@") { return true }
        return body.range(of: #"</?(?:html|body|div|p|br|table|td|span)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

// MARK: - Same purchase from two sources

/// The same Apple Pay purchase can arrive from Wallet and, seconds later, from the bank's SMS or
/// email. Same AED amount, within 5 minutes, similar merchant name = one purchase.
public enum CrossSourceDuplicate {
    public static let window: TimeInterval = 5 * 60

    public struct Record: Sendable, Equatable {
        public var source: TransactionSource
        public var kind: TransactionKind
        public var amount: Decimal
        public var currency: String
        public var amountAED: Decimal
        public var date: Date
        public var merchant: String

        public init(source: TransactionSource, kind: TransactionKind, amount: Decimal, currency: String,
                    amountAED: Decimal, date: Date, merchant: String) {
            self.source = source; self.kind = kind; self.amount = amount; self.currency = currency
            self.amountAED = amountAED; self.date = date; self.merchant = merchant
        }
    }

    /// Index of the existing record that is the same purchase as `incoming`, if any.
    /// Only different automatic sources are compared: two SMS are handled by `DuplicateDetector`,
    /// and manual entries are the person's own choice.
    public static func match(for incoming: Record, among existing: [Record], window: TimeInterval = window) -> Int? {
        guard incoming.source.isAutomatic, incoming.kind == .purchase else { return nil }
        return existing.indices
            .filter { i in
                let e = existing[i]
                return e.source.isAutomatic && e.source != incoming.source && e.kind == .purchase
                    && sameAmount(e, incoming)
                    && abs(e.date.timeIntervalSince(incoming.date)) <= window
                    && merchantsSimilar(e.merchant, incoming.merchant)
            }
            .min { abs(existing[$0].date.timeIntervalSince(incoming.date)) < abs(existing[$1].date.timeIntervalSince(incoming.date)) }
    }

    static func sameAmount(_ a: Record, _ b: Record) -> Bool {
        a.amountAED == b.amountAED || (a.currency == b.currency && a.amount == b.amount)
    }

    /// Case-insensitive; similar when either is empty, one contains the other, or one contains the
    /// other's first real word ("Carrefour" ~ "CARREFOUR HYPERMARKET", "McDonald's" ~ "MCDONALDS DXB").
    public static func merchantsSimilar(_ a: String, _ b: String) -> Bool {
        let wa = words(a), wb = words(b)
        if wa.isEmpty || wb.isEmpty { return true }
        let ca = wa.joined(), cb = wb.joined()
        if ca.contains(cb) || cb.contains(ca) { return true }
        return ca.contains(firstWord(wb)) || cb.contains(firstWord(wa))
    }

    static func words(_ s: String) -> [String] {
        s.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : ($0 == "'" || $0 == "’" ? "\u{0}" : " ") }
            .filter { $0 != "\u{0}" }
            .split(separator: " ").map { String($0) }
    }

    /// First word of three letters or more ("al", "the", "7" are too short to mean anything alone).
    static func firstWord(_ words: [String]) -> String {
        words.first { $0.count >= 3 && $0 != "the" } ?? words[0]
    }
}

// MARK: - Text helpers for the app

public extension DuplicateDetector {
    /// Two messages with the same text are the same alert only when the text pins down one moment:
    /// its own date and time, or a balance after the transaction. Without those, "AED 15.00 at ADNOC"
    /// twice in one day is two real purchases.
    static func canMatchByText(_ message: String, parsed: ParsedTransaction) -> Bool {
        parsed.balanceAfter != nil || BankMessageParser.date(in: BankMessageParser.normalize(message))?.hasTime == true
    }

    /// Text used to compare two messages: no HTML, unified digits and spacing, lower-case.
    static func normalizedText(_ message: String) -> String {
        BankMessageParser.normalize(MessageText.stripHTML(message)).lowercased()
    }
}

public enum TextMatch {
    /// Case-insensitive. English words match on word edges ("ADDC" is not inside "ADDCO");
    /// Arabic stays a substring, because Arabic attaches prefixes such as و / ب / ال.
    public static func containsWord(_ text: String, _ word: String) -> Bool {
        BankMessageParser.containsWord(text.lowercased(), word.lowercased())
    }
}
