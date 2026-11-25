import Foundation

/// "Teach Khurda": when a bank message isn't understood, the person taps the amount (and, if there is
/// one, the shop name) in the message once. Khurda turns that message into a pattern: the words around
/// the amount and the shop stay as they are, and other numbers (dates, card digits, balances) may change.
/// The next message of the same shape is read with it, on the phone, before the general parser.
public struct MessageTemplate: Codable, Sendable, Equatable {
    /// A regular expression with a named group `amount` and, optionally, `merchant`.
    public let pattern: String
    public let kind: TransactionKind
    public let currency: String
    /// Sender the template was learned from, when known. Nil means "any sender".
    public let sender: String?

    public init(pattern: String, kind: TransactionKind, currency: String, sender: String?) {
        self.pattern = pattern; self.kind = kind; self.currency = currency; self.sender = sender
    }

    /// How many words to keep on each side of the tapped parts. Banks change the start (a promo line)
    /// and the ending (balance wording, a reference), so only the nearby words have to match next time.
    static let wordsBefore = 4
    static let wordsAfter = 1

    /// - Parameters:
    ///   - message: the message as received.
    ///   - amount: the range of the amount the person tapped (digits only, or with separators).
    ///   - merchant: the range of the shop name, if they tapped one. Must not overlap the amount.
    public static func learn(message: String, amount: Range<String.Index>, merchant: Range<String.Index>?,
                             kind: TransactionKind, sender: String?) -> MessageTemplate? {
        guard AmountText.parse(String(message[amount])) != nil else { return nil }
        if let m = merchant, m.overlaps(amount) { return nil }

        var parts: [(range: Range<String.Index>, group: String)] = [(amount, "amount")]
        if let m = merchant { parts.append((m, "merchant")) }
        parts.sort { $0.range.lowerBound < $1.range.lowerBound }

        var pattern = ""
        // Before the first tapped part: only the last few words.
        let first = parts[0].range.lowerBound
        let before = String(message[message.startIndex..<first])
        pattern += literal(lastWords(before, wordsBefore))
        for (i, part) in parts.enumerated() {
            pattern += part.group == "amount"
                ? "(?<amount>[0-9٠-٩][0-9٠-٩,٬.٫]*)"
                : "(?<merchant>.+?)"
            let nextStart = i + 1 < parts.count ? parts[i + 1].range.lowerBound : message.endIndex
            let between = String(message[part.range.upperBound..<nextStart])
            if i + 1 < parts.count {
                pattern += literal(between)
            } else {
                // After the last part: a few words, so the shop name knows where it ends.
                pattern += literal(firstWords(between, wordsAfter))
            }
        }
        // A merchant at the very end must still stop somewhere: the end of the line.
        if parts.last?.group == "merchant", pattern.hasSuffix("(?<merchant>.+?)") { pattern += "(?:$|\\n)" }

        let currency = detectCurrency(around: amount, in: message) ?? "AED"
        let template = MessageTemplate(pattern: pattern, kind: kind, currency: currency, sender: sender)
        // It must at least read back the message it came from.
        return template.read(message, sender: sender) != nil ? template : nil
    }

    /// Reads a message with this template, or nil if it doesn't have the same shape.
    public func read(_ message: String, sender: String?, date: Date = .now) -> ParsedTransaction? {
        if let mine = self.sender, let theirs = sender,
           mine.caseInsensitiveCompare(theirs) != .orderedSame { return nil }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = message as NSString
        guard let m = regex.firstMatch(in: message, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let amountRange = m.range(withName: "amount")
        guard amountRange.location != NSNotFound,
              let money = AmountText.parse(ns.substring(with: amountRange)) else { return nil }
        var merchant: String?
        let mr = m.range(withName: "merchant")
        if mr.location != NSNotFound {
            let name = ns.substring(with: mr).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            merchant = name.isEmpty ? nil : name
        }
        return ParsedTransaction(amount: money.amount, currency: currency, kind: kind, merchant: merchant,
                                 cardLast4: Self.cardDigits(in: message), date: date,
                                 bankName: BankDirectory.bankName(sender: sender, body: message.lowercased()))
    }

    /// The last `n` words of `text`, with the spacing after them (what sits right before the amount).
    static func lastWords(_ text: String, _ n: Int) -> String {
        var count = 0, inWord = false
        var i = text.endIndex
        while i > text.startIndex {
            let prev = text.index(before: i)
            if text[prev].isWhitespace {
                if inWord { count += 1; inWord = false; if count == n { return String(text[i...]) } }
            } else { inWord = true }
            i = prev
        }
        return text
    }

    /// The first `n` words of `text`, with the spacing and punctuation before them.
    static func firstWords(_ text: String, _ n: Int) -> String {
        var count = 0, inWord = false
        for i in text.indices {
            if text[i].isWhitespace {
                if inWord { count += 1; inWord = false; if count == n { return String(text[..<i]) } }
            } else { inWord = true }
        }
        return text
    }

    /// Escapes regex characters, lets every run of digits be any digits, and every run of spaces be any spaces.
    static func literal(_ text: String) -> String {
        let t = text
        var out = ""
        var inDigits = false, inSpace = false
        for ch in t {
            if ch.isNumber {
                if !inDigits { out += "[0-9٠-٩]+" }
                inDigits = true; inSpace = false
                continue
            }
            if ch.isWhitespace {
                if !inSpace { out += "\\s+" }
                inSpace = true; inDigits = false
                continue
            }
            inDigits = false; inSpace = false
            out += NSRegularExpression.escapedPattern(for: String(ch))
        }
        return out
    }

    static func detectCurrency(around range: Range<String.Index>, in text: String) -> String? {
        let lo = text.index(range.lowerBound, offsetBy: -6, limitedBy: text.startIndex) ?? text.startIndex
        let hi = text.index(range.upperBound, offsetBy: 6, limitedBy: text.endIndex) ?? text.endIndex
        let near = String(text[lo..<hi])
        return AmountText.parse(near)?.currency
    }

    static func cardDigits(in text: String) -> String? {
        guard let r = text.range(of: #"(?:x|\*|•|ending|card|بطاقة|رقم)\s*[x*•]*\s*([0-9]{4})\b"#,
                                 options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(text[r].suffix(4))
    }
}
