import Foundation

/// One transaction read from a bank or card statement, before the person reviews it.
public struct StatementRow: Sendable, Equatable, Identifiable {
    public var id: Int
    public var date: Date
    public var details: String
    public var merchant: String?
    public var amount: Decimal
    public var currency: String
    public var kind: TransactionKind
    public var balance: Decimal?
    public var cardLast4: String?

    public var isExpense: Bool { kind == .purchase || kind == .withdrawal || kind == .transferOut }

    public var parsed: ParsedTransaction {
        ParsedTransaction(amount: amount, currency: currency, kind: kind, merchant: merchant,
                          cardLast4: cardLast4, date: date, bankName: nil)
    }
}

/// What the reader understood about a statement file.
public struct StatementAnalysis: Sendable, Equatable {
    public enum Role: String, Sendable, CaseIterable { case date, details, debit, credit, amount, balance, direction, currency }

    public var rows: [StatementRow]
    /// Column index for each role it found (tables only; empty for PDF text).
    public var columns: [Role: Int]
    public var dateFormat: String
    /// Lines that looked like summary rows or had no date or amount.
    public var skipped: Int
    /// Bank named in the file (header text or file name), when there is one.
    public var bankName: String?
    /// Last 4 digits of the account, IBAN or card printed in the header.
    public var accountLast4: String?
    /// The file is a credit card statement (purchases are on a card, payments are card payments).
    public var looksLikeCard: Bool

    public var moneyIn: Decimal { rows.filter { $0.kind == .income || $0.kind == .refund }.reduce(0) { $0 + $1.amount } }
    public var moneyOut: Decimal { rows.filter(\.isExpense).reduce(0) { $0 + $1.amount } }
    public var dateRange: ClosedRange<Date>? {
        guard let lo = rows.map(\.date).min(), let hi = rows.map(\.date).max() else { return nil }
        return lo...hi
    }
}

/// Reads any bank's statement layout on the phone: finds the date, details and money columns (by
/// their headings in English or Arabic, or by what the cells look like), works out the date format,
/// which way the money went, cleans the shop name, and skips opening / closing balance lines.
public enum StatementImporter {

    // MARK: Tables (CSV, Excel)

    public static func analyze(table raw: [[String]], hint: String = "") -> StatementAnalysis? {
        let table = raw.map { $0.map { BankMessageParser.normalize($0) } }
        guard !table.isEmpty else { return nil }
        let width = table.map(\.count).max() ?? 0
        let (headerRow, columns) = findHeader(table) ?? (nil, inferColumns(table, width: width))
        guard let dateCol = columns[.date],
              columns[.amount] != nil || columns[.debit] != nil || columns[.credit] != nil else { return nil }

        let body = Array(table.dropFirst((headerRow ?? -1) + 1))
        let headerText = table.prefix((headerRow ?? 0) + 1).flatMap { $0 }.joined(separator: " ") + " " + hint
        let format = dateFormat(for: body.compactMap { $0[safe: dateCol] })

        struct Raw { var index: Int; var date: Date; var details: String; var signed: Decimal?; var amount: Decimal; var balance: Decimal? }
        var raws: [Raw] = []
        var skipped = 0
        for (i, r) in body.enumerated() {
            let details = columns[.details].flatMap { r[safe: $0] } ?? r.enumerated()
                .filter { $0.offset != dateCol && Money.parse($0.element) == nil }.map(\.element).joined(separator: " ")
            guard let cell = r[safe: dateCol], let date = parseDate(cell, format: format), !isSummary(details) else {
                skipped += 1; continue
            }
            var signed: Decimal?
            var magnitude: Decimal = 0
            if let d = columns[.debit].flatMap({ r[safe: $0] }).flatMap(Money.parse), d.value != 0 {
                signed = -abs(d.value); magnitude = abs(d.value)
            } else if let c = columns[.credit].flatMap({ r[safe: $0] }).flatMap(Money.parse), c.value != 0 {
                signed = abs(c.value); magnitude = abs(c.value)
            } else if let a = columns[.amount].flatMap({ r[safe: $0] }).flatMap(Money.parse), a.value != 0 {
                magnitude = abs(a.value)
                if let dir = columns[.direction].flatMap({ r[safe: $0] }) {
                    signed = isCreditMarker(dir) ? magnitude : -magnitude
                } else if a.marker != nil || a.value < 0 {
                    signed = a.value < 0 || a.marker == .debit ? -magnitude : magnitude
                } else {
                    signed = a.value   // sign decided below, once we know if the file uses signs at all
                }
            }
            guard magnitude > 0 else { skipped += 1; continue }
            let balance = columns[.balance].flatMap { r[safe: $0] }.flatMap(Money.parse)?.value
            raws.append(Raw(index: i, date: date, details: details, signed: signed, amount: magnitude, balance: balance))
        }
        guard !raws.isEmpty else { return nil }

        // Some rows say CR (or DR) and the rest say nothing: the unmarked ones go the other way.
        if columns[.debit] == nil, columns[.credit] == nil, columns[.direction] == nil, let ac = columns[.amount] {
            let markers = Set(body.compactMap { r in r[safe: ac].flatMap(Money.parse)?.marker })
            if markers.count == 1, let only = markers.first {
                for i in raws.indices {
                    let m = body[raws[i].index][safe: ac].flatMap(Money.parse)
                    if m?.marker == nil, (m?.value ?? 0) > 0 { raws[i].signed = only == .credit ? -raws[i].amount : raws[i].amount }
                }
            }
        }

        // One amount column, every value positive, no Dr/Cr: the running balance tells the direction,
        // or the words do (salary, refund, deposit).
        let singleUnsigned = columns[.debit] == nil && columns[.credit] == nil && columns[.direction] == nil
            && !raws.contains { ($0.signed ?? 0) < 0 }
            && !body.contains { r in columns[.amount].flatMap { r[safe: $0] }.flatMap(Money.parse)?.marker != nil }
        if singleUnsigned {
            let signs = balanceSigns(raws.map { ($0.amount, $0.balance) })
            for i in raws.indices {
                if let s = signs[i] { raws[i].signed = s ? raws[i].amount : -raws[i].amount }
                else { raws[i].signed = wordsSayMoneyIn(raws[i].details) ? raws[i].amount : -raws[i].amount }
            }
        }

        let card = looksLikeCardStatement(headerText)
        let currency = columns[.currency] == nil ? (detectCurrency(headerText) ?? "AED") : "AED"
        let rows = raws.map { r -> StatementRow in
            let cur = columns[.currency].flatMap { body[r.index][safe: $0] }.flatMap(currencyCode) ?? currency
            return makeRow(id: r.index, date: r.date, details: r.details, amount: r.amount,
                           moneyIn: (r.signed ?? -1) > 0, balance: r.balance, currency: cur, card: card)
        }
        return StatementAnalysis(rows: rows, columns: columns, dateFormat: format, skipped: skipped,
                                 bankName: bankName(in: headerText),
                                 accountLast4: accountDigits(headerText), looksLikeCard: card)
    }

    // MARK: PDF text

    /// A PDF statement, as the lines of text it shows. A line that starts with (or holds) a date and
    /// ends in amounts is a transaction; a line with words only continues the one above it.
    public static func analyze(lines rawLines: [String], hint: String = "") -> StatementAnalysis? {
        let lines = rawLines.map { BankMessageParser.normalize($0) }.filter { !$0.isEmpty }
        let tokens = lines.compactMap { dateToken(in: $0)?.text }
        guard tokens.count >= 1 else { return nil }
        let format = dateFormat(for: tokens)
        let headerText = lines.prefix(25).joined(separator: " ") + " " + hint

        struct Raw { var date: Date; var details: String; var amounts: [Money]; var line: Int }
        var raws: [Raw] = []
        var skipped = 0
        var opening: Decimal?
        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            if opening == nil, isOpeningBalance(lower), let m = moneyTokens(in: line).last { opening = m.value }
            guard let tok = dateToken(in: line), let date = parseDate(tok.text, format: format) else {
                // Words only, right under a transaction: the rest of its details.
                if let last = raws.indices.last, raws[last].line == i - 1 || raws[last].line == i - 2,
                   moneyTokens(in: line).isEmpty, !isSummary(line), line.count < 80 {
                    raws[last].details += " " + line; raws[last].line = i
                }
                continue
            }
            var rest = line
            rest.removeSubrange(tok.range)
            // A second date on the line (value date) isn't part of the details.
            if let t2 = dateToken(in: rest) { rest.removeSubrange(t2.range) }
            let amounts = moneyTokens(in: rest)
            guard !amounts.isEmpty, !isSummary(rest) else { skipped += 1; continue }
            var details = rest
            for m in amounts.reversed() { details.removeSubrange(m.range) }
            details = details.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            raws.append(Raw(date: date, details: details, amounts: amounts.map(\.money), line: i))
        }
        guard !raws.isEmpty else { return nil }

        // Two or more amounts: the last is the balance. Its change says which way the money went.
        let hasBalance = raws.filter { $0.amounts.count >= 2 }.count * 2 > raws.count
        let pairs: [(Decimal, Decimal?)] = raws.map { r in
            let amount = hasBalance && r.amounts.count >= 2 ? r.amounts[r.amounts.count - 2] : r.amounts[0]
            return (abs(amount.value), hasBalance ? r.amounts.last?.value : nil)
        }
        let signs = balanceSigns(pairs, opening: opening)
        let card = looksLikeCardStatement(headerText)
        let currency = detectCurrency(headerText) ?? "AED"
        let rows = raws.enumerated().compactMap { i, r -> StatementRow? in
            let amount = hasBalance && r.amounts.count >= 2 ? r.amounts[r.amounts.count - 2] : r.amounts[0]
            guard amount.value != 0 else { return nil }
            let moneyIn: Bool
            if amount.marker != nil || amount.value < 0 { moneyIn = amount.marker == .credit || (amount.marker == nil && amount.value > 0) }
            else if let s = signs[i] { moneyIn = s }
            else { moneyIn = wordsSayMoneyIn(r.details) }
            return makeRow(id: i, date: r.date, details: r.details, amount: abs(amount.value), moneyIn: moneyIn,
                           balance: hasBalance ? r.amounts.last?.value : nil, currency: currency, card: card)
        }
        return StatementAnalysis(rows: rows, columns: [:], dateFormat: format, skipped: skipped,
                                 bankName: bankName(in: headerText),
                                 accountLast4: accountDigits(headerText), looksLikeCard: card)
    }

    // MARK: Duplicates

    /// The same transaction already logged from an SMS, email or an earlier import: same AED amount,
    /// same direction, within a day (statements show the posting date), and a similar name if both have one.
    public static func isDuplicate(_ row: StatementRow, amountAED: Decimal, of existing: [CrossSourceDuplicate.Record]) -> Bool {
        existing.contains { e in
            let sameDirection = (e.kind == .income || e.kind == .refund) == (row.kind == .income || row.kind == .refund)
            let close = abs(e.date.timeIntervalSince(row.date)) <= 36 * 3600
            let sameMoney = e.amountAED == amountAED || (e.currency == row.currency && e.amount == row.amount)
            let names = row.merchant.map { e.merchant.isEmpty || CrossSourceDuplicate.merchantsSimilar(e.merchant, $0) } ?? true
            return sameDirection && close && sameMoney && names && CrossSourceDuplicate.sameCard(e.cardLast4, row.cardLast4)
        }
    }

    // MARK: Row

    static func makeRow(id: Int, date: Date, details: String, amount: Decimal, moneyIn: Bool,
                        balance: Decimal?, currency: String, card: Bool) -> StatementRow {
        let lower = details.lowercased()
        let kind: TransactionKind
        if moneyIn {
            if BankMessageParser.containsAny(lower, BankMessageParser.refundKeywords) { kind = .refund }
            else if card || BankMessageParser.isCardPayment(lower) { kind = .cardPayment }
            else if BankMessageParser.isOwnTransfer(lower) { kind = .ownTransfer }
            else { kind = .income }
        } else {
            if BankMessageParser.isCardPayment(lower) || lower.contains("card payment") || lower.contains("cc payment") { kind = .cardPayment }
            else if BankMessageParser.isOwnTransfer(lower) { kind = .ownTransfer }
            else if BankMessageParser.containsAny(lower, ["atm", "cash withdrawal", "سحب نقدي", "صراف"]) { kind = .withdrawal }
            else if BankMessageParser.containsAny(lower, ["transfer", "tfr", "trf", "remittance", "ipi", "aani", "تحويل", "حوالة"])
                        && !BankMessageParser.containsAny(lower, ["pos", "purchase", "شراء"]) { kind = .transferOut }
            else { kind = .purchase }
        }
        return StatementRow(id: id, date: date, details: details, merchant: merchantName(details, kind: kind),
                            amount: amount, currency: currency, kind: kind, balance: balance,
                            cardLast4: BankMessageParser.cardLast4(in: details))
    }

    /// "POS PURCHASE CARD NO.XXXX1234 CARREFOUR MOE,DUBAI AE 12/11/2026" → "CARREFOUR MOE".
    public static func merchantName(_ details: String, kind: TransactionKind) -> String? {
        var s = " " + details + " "
        let noise = [
            #"(?i)\b(?:pos|ecom|e-com|online|debit card|credit card|card|apple pay|google pay|samsung pay|contactless)\s+(?:purchase|transaction|txn|trx|payment)s?\b"#,
            #"(?i)\b(?:purchase|pos|ecom|txn|trx|transaction|payment to|paid to|bill payment|online banking|mobile banking)\b[:\-]?"#,
            #"(?i)\b(?:card|crd)\s*(?:no\.?|number|ending(?:\s+with)?)?\s*[x*•]*[0-9x*•]{0,12}[0-9]{4}\b"#,
            #"(?i)\b[0-9]{4,6}[x*•]{4,}[0-9]{4}\b|[x*•]{2,}[0-9]{3,4}\b"#,
            #"(?i)\b(?:ref|reference|auth|rrn|txn id|trn)\b\.?\s*(?:no\.?|#)?\s*[:#]?\s*[A-Z0-9-]+"#,
            #"\b[0-9]{1,2}[/.-][0-9]{1,2}[/.-][0-9]{2,4}\b|\b[0-9]{4}-[0-9]{2}-[0-9]{2}\b|\b[0-9]{1,2}-[A-Za-z]{3}-[0-9]{2,4}\b"#,
            #"\b[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?\b"#,
            #"\b[0-9]{6,}\b"#,
            #"(?:عملية\s+)?شراء|بطاقة\s*(?:رقم)?\s*[0-9x*]*"#,
            #"(?i)\b(?:aed|usd|eur|gbp|sar)\s*[0-9.,]+"#
        ]
        for p in noise { s = s.replacingOccurrences(of: p, with: " ", options: .regularExpression) }
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        var name = BankMessageParser.cleanMerchant(s.trimmingCharacters(in: CharacterSet(charactersIn: " ,.-:/|")))
        if name.lowercased().hasPrefix("to ") || name.lowercased().hasPrefix("at ") { name = String(name.dropFirst(3)) }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ,.-:/|"))
        guard name.count >= 2, name.contains(where: \.isLetter) else { return nil }
        return String(name.prefix(48))
    }

    // MARK: Columns

    static let headings: [(StatementAnalysis.Role, [String])] = [
        (.balance, ["balance", "running bal", "الرصيد", "رصيد"]),
        (.date, ["transaction date", "txn date", "trans date", "trans. date", "date", "تاريخ العملية", "التاريخ", "تاريخ"]),
        (.debit, ["debit", "withdrawal", "withdrawals", "paid out", "money out", "dr amount", "مدين", "المدين", "سحب", "مسحوبات", "خصم"]),
        (.credit, ["credit", "deposit", "deposits", "paid in", "money in", "cr amount", "دائن", "الدائن", "إيداع", "ايداع", "إيداعات"]),
        (.direction, ["dr/cr", "cr/dr", "debit/credit", "type", "نوع"]),
        (.currency, ["currency", "ccy", "العملة"]),
        (.amount, ["amount", "transaction amount", "value", "المبلغ", "مبلغ", "القيمة"]),
        (.details, ["description", "details", "narration", "narrative", "particulars", "remarks", "merchant",
                    "transaction", "البيان", "التفاصيل", "الوصف", "الشرح", "التاجر"])
    ]

    /// A heading row near the top: a date column and a money column, named in English or Arabic.
    static func findHeader(_ table: [[String]]) -> (Int?, [StatementAnalysis.Role: Int])? {
        for (i, row) in table.prefix(40).enumerated() {
            var found: [StatementAnalysis.Role: Int] = [:]
            for (c, cell) in row.enumerated() {
                let l = cell.lowercased()
                guard !l.isEmpty, l.count < 40 else { continue }
                // "Value date" / "posting date" only when there's no transaction date.
                if l.contains("value date") || l.contains("posting date") || l.contains("تاريخ القيد") {
                    if found[.date] == nil { found[.date] = c }
                    continue
                }
                if let role = headings.first(where: { _, words in words.contains { headingMatches(l, $0) } })?.0 {
                    if role == .date, let old = found[.date], !(row[old].lowercased().contains("value") || row[old].lowercased().contains("posting")) { continue }
                    if found[role] == nil || role == .date { found[role] = c }
                }
            }
            if found[.date] != nil, found[.amount] != nil || found[.debit] != nil || found[.credit] != nil {
                return (i, found)
            }
        }
        return nil
    }

    static func headingMatches(_ cell: String, _ word: String) -> Bool {
        if word.unicodeScalars.allSatisfy(\.isASCII) { return BankMessageParser.containsWord(cell, word) }
        return cell.contains(word)
    }

    /// No heading row: the date column is the one whose cells read as dates, money columns are the
    /// numeric ones, the details column is the one with the most words.
    static func inferColumns(_ table: [[String]], width: Int) -> [StatementAnalysis.Role: Int] {
        let sample = Array(table.prefix(60))
        func share(_ c: Int, _ test: (String) -> Bool) -> Double {
            let cells = sample.compactMap { $0[safe: c] }.filter { !$0.isEmpty }
            return cells.isEmpty ? 0 : Double(cells.filter(test).count) / Double(sample.count)
        }
        var out: [StatementAnalysis.Role: Int] = [:]
        let dates = (0..<width).filter { share($0) { dateToken(in: $0) != nil || isExcelSerial($0) } >= 0.5 }
        guard let date = dates.first else { return [:] }
        out[.date] = date
        let numeric = (0..<width).filter { c in !dates.contains(c) && share(c) { Money.parse($0) != nil } >= 0.4 }
        let letters = (0..<width).filter { !dates.contains($0) && !numeric.contains($0) }
            .max { a, b in
                func avg(_ c: Int) -> Int { sample.compactMap { $0[safe: c] }.reduce(0) { $0 + $1.filter(\.isLetter).count } }
                return avg(a) < avg(b)
            }
        out[.details] = letters
        switch numeric.count {
        case 0: break
        case 1: out[.amount] = numeric[0]
        case 2: out[.amount] = numeric[0]; out[.balance] = numeric[1]
        default: out[.debit] = numeric[numeric.count - 3]; out[.credit] = numeric[numeric.count - 2]; out[.balance] = numeric.last
        }
        return out
    }

    // MARK: Direction

    /// For each row, whether money came in, worked out from the running balance. Tries the rows in
    /// file order and in reverse (newest-first statements) and keeps whichever explains more rows.
    static func balanceSigns(_ rows: [(amount: Decimal, balance: Decimal?)], opening: Decimal? = nil) -> [Bool?] {
        func signs(_ order: [Int]) -> ([Int: Bool], Int) {
            var out: [Int: Bool] = [:], hits = 0
            var prev: Decimal? = opening
            for i in order {
                guard let b = rows[i].balance else { prev = nil; continue }
                if let p = prev {
                    let delta = b - p
                    if abs(abs(delta) - rows[i].amount) < Decimal(string: "0.011")! { out[i] = delta > 0; hits += 1 }
                }
                prev = b
            }
            return (out, hits)
        }
        let forward = signs(Array(rows.indices))
        let backward = signs(Array(rows.indices.reversed()))
        let best = forward.1 >= backward.1 ? forward.0 : backward.0
        return rows.indices.map { best[$0] }
    }

    static func wordsSayMoneyIn(_ details: String) -> Bool {
        let l = details.lowercased()
        return BankMessageParser.containsAny(l, ["salary", "credit", "deposit", "refund", "reversal", "cashback", "inward",
                                                 "transfer from", "received", "راتب", "إيداع", "ايداع", "استرداد", "حوالة واردة", "دائن"])
    }

    static func isCreditMarker(_ s: String) -> Bool {
        let l = s.lowercased().trimmingCharacters(in: .whitespaces)
        return l == "cr" || l == "c" || l.hasPrefix("credit") || l == "+" || l.contains("دائن") || l.contains("إيداع")
    }

    // MARK: Summary lines

    static let summaryWords = ["opening balance", "closing balance", "balance brought forward", "brought forward",
                               "carried forward", "balance b/f", "balance c/f", "b/f", "c/f", "total", "subtotal",
                               "statement balance", "available balance", "minimum payment", "minimum due",
                               "الرصيد الافتتاحي", "الرصيد الختامي", "رصيد افتتاحي", "رصيد ختامي", "المجموع", "الإجمالي", "رصيد مرحل"]

    static func isSummary(_ text: String) -> Bool {
        BankMessageParser.containsAny(text.lowercased(), summaryWords)
    }
    static func isOpeningBalance(_ lower: String) -> Bool {
        BankMessageParser.containsAny(lower, ["opening balance", "balance brought forward", "brought forward", "balance b/f",
                                              "previous balance", "الرصيد الافتتاحي", "رصيد افتتاحي"])
    }

    // MARK: Header facts

    /// The bank named in a statement's header: its full name ("Abu Dhabi Commercial Bank"), its short
    /// name ("ADCB") or its SMS sender ID, as whole words.
    static func bankName(in text: String) -> String? {
        let l = text.lowercased()
        let aliases: [String: [String]] = [
            "ADCB": ["abu dhabi commercial bank"], "ADIB": ["abu dhabi islamic bank"], "First Abu Dhabi Bank": ["fab"],
            "Emirates NBD": ["emirates nbd", "emiratesnbd"], "Dubai Islamic Bank": ["dib"], "RAKBANK": ["rak bank", "national bank of ras al khaimah"],
            "NBF": ["national bank of fujairah"], "Commercial Bank of Dubai": ["cbd"]
        ]
        for b in BankDirectory.all {
            let names = [b.nameEN.lowercased(), b.nameAR] + (aliases[b.nameEN] ?? [])
            if names.contains(where: { headingMatches(l, $0) }) { return b.nameEN }
        }
        return BankDirectory.bankName(sender: nil, body: l)
    }

    static func looksLikeCardStatement(_ text: String) -> Bool {
        let l = text.lowercased()
        return BankMessageParser.containsAny(l, ["credit card statement", "card statement", "card number", "minimum payment",
                                                 "credit limit", "كشف حساب البطاقة", "بطاقة الائتمان", "الحد الائتماني"])
    }

    static func accountDigits(_ text: String) -> String? {
        if let iban = text.range(of: #"\bAE[0-9]{2}\s?(?:[0-9]{4}\s?){4}[0-9]{3}\b"#, options: .regularExpression) {
            return String(text[iban].filter(\.isNumber).suffix(4))
        }
        let patterns = [#"(?i)(?:account|a/c|acct|card)\s*(?:no\.?|number|#)?\s*[:.]?\s*[x*•0-9 -]*([0-9]{4})\b"#,
                        #"(?:رقم الحساب|رقم البطاقة|حساب رقم)\s*[:.]?\s*[x*0-9 -]*([0-9]{4})\b"#]
        for p in patterns { if let d = BankMessageParser.firstCapture(p, in: text) { return d } }
        return nil
    }

    static func detectCurrency(_ text: String) -> String? {
        let l = " " + text.lowercased() + " "
        for (token, iso) in [("aed", "AED"), ("درهم", "AED"), ("usd", "USD"), ("sar", "SAR"), ("eur", "EUR"), ("gbp", "GBP")]
            where BankMessageParser.containsWord(l, token) { return iso }
        return nil
    }

    static func currencyCode(_ cell: String) -> String? {
        let t = cell.trimmingCharacters(in: .whitespaces).uppercased()
        if t.count == 3, t.allSatisfy(\.isLetter) { return t }
        return detectCurrency(cell)
    }

    // MARK: Dates

    static let formats = [
        "dd/MM/yyyy", "MM/dd/yyyy", "yyyy-MM-dd", "dd-MM-yyyy", "MM-dd-yyyy", "dd.MM.yyyy", "yyyy/MM/dd",
        "dd/MM/yy", "MM/dd/yy", "dd-MM-yy", "dd-MMM-yyyy", "dd-MMM-yy", "dd MMM yyyy", "dd MMM yy", "MMM dd, yyyy",
        "dd MMMM yyyy", "yyyyMMdd"
    ]

    static let dateTokenPattern = #"\b(?:[0-9]{1,2}[/.-][0-9]{1,2}[/.-](?:[0-9]{4}|[0-9]{2})|[0-9]{4}[-/][0-9]{1,2}[-/][0-9]{1,2}|[0-9]{1,2}[ -](?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*[ ,-]*(?:[0-9]{4}|[0-9]{2})|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]* [0-9]{1,2}, [0-9]{4})\b"#

    static func dateToken(in s: String) -> (text: String, range: Range<String.Index>)? {
        guard let r = s.range(of: dateTokenPattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return (String(s[r]), r)
    }

    /// The format that reads the most of these cells. Day-first wins a tie (the UAE way); a first
    /// number above 12 anywhere rules out month-first.
    static func dateFormat(for cells: [String]) -> String {
        let tokens = cells.prefix(200).compactMap { dateToken(in: $0)?.text }
        guard !tokens.isEmpty else { return "excel" }
        var best = ("dd/MM/yyyy", -1)
        for f in formats {
            let n = tokens.filter { date($0, format: f) != nil }.count
            if n > best.1 { best = (f, n) }
        }
        return best.0
    }

    static func parseDate(_ cell: String, format: String) -> Date? {
        if isExcelSerial(cell), let n = Double(cell.trimmingCharacters(in: .whitespaces)) {
            // Excel day numbers count from 30 Dec 1899.
            // The number is a wall-clock day and time, not an instant: read it in UTC, rebuild it in Dubai.
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            let base = DateComponents(calendar: utc, year: 1899, month: 12, day: 30).date!
            var c = utc.dateComponents([.year, .month, .day, .hour, .minute], from: base.addingTimeInterval((n * 86400).rounded()))
            c.timeZone = .dubaiZone
            return Calendar.dubai.date(from: c)
        }
        guard let tok = dateToken(in: cell) else {
            return date(cell.trimmingCharacters(in: .whitespaces), format: format)
        }
        return date(tok.text, format: format) ?? formats.lazy.compactMap { date(tok.text, format: $0) }.first
    }

    static func isExcelSerial(_ cell: String) -> Bool {
        guard let n = Double(cell.trimmingCharacters(in: .whitespaces)) else { return false }
        return n > 30_000 && n < 80_000
    }

    static func date(_ s: String, format: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .dubaiZone
        f.dateFormat = format
        f.isLenient = false
        let cleaned = s.replacingOccurrences(of: "sept", with: "sep", options: .caseInsensitive)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard let d = f.date(from: cleaned) else { return nil }
        let y = Calendar.dubai.component(.year, from: d)
        return (2000...2100).contains(y) ? d : nil
    }

    // MARK: Money in a cell

    struct MoneyToken { var money: Money; var range: Range<String.Index> }

    /// Amounts on a PDF line: numbers with two decimals ("1,250.00", "45.50 CR", "(12.00)", "-30.00").
    static func moneyTokens(in s: String) -> [(value: Decimal, marker: Money.Marker?, range: Range<String.Index>, money: Money)] {
        let pattern = #"\(?-?(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)\.[0-9]{2}\)?(?:\s?(?:cr|dr)\b|-)?"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
            guard let r = Range(m.range, in: s), let money = Money.parse(String(s[r])) else { return nil }
            return (money.value, money.marker, r, money)
        }
    }
}

/// An amount as a statement cell writes it: "1,250.00", "-45.50", "(45.50)", "45.50 CR", "AED 45.50", "45.50-".
public struct Money: Sendable, Equatable {
    public enum Marker: Sendable { case credit, debit }
    public var value: Decimal
    public var marker: Marker?

    public static func parse(_ raw: String) -> Money? {
        var s = BankMessageParser.normalize(raw).trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.count <= 30 else { return nil }
        var marker: Marker?
        let lower = s.lowercased()
        if lower.hasSuffix("cr") || lower.hasSuffix("دائن") { marker = .credit }
        if lower.hasSuffix("dr") || lower.hasSuffix("مدين") { marker = .debit }
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") { negative = true }
        if s.hasPrefix("-") || s.hasSuffix("-") || s.hasPrefix("−") { negative = true }
        s = s.replacingOccurrences(of: #"(?i)\b(aed|dhs?|usd|sar|eur|gbp|cr|dr)\b|درهم|د\.إ|دائن|مدين"#, with: "", options: .regularExpression)
        s = s.filter { $0.isNumber || $0 == "." || $0 == "," }
        // A whole cell must be a number: "Card 1234" or a phone number isn't money.
        let leftover = BankMessageParser.normalize(raw).replacingOccurrences(of: #"(?i)\b(aed|dhs?|usd|sar|eur|gbp|cr|dr)\b|درهم|د\.إ|دائن|مدين|[0-9.,()+\-−\s]"#, with: "", options: .regularExpression)
        guard !s.isEmpty, leftover.isEmpty, s.contains(where: \.isNumber), let v = AmountText.number(s) else { return nil }
        return Money(value: negative ? -v : v, marker: marker)
    }
}

extension Collection {
    subscript(safe i: Index) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension TimeZone {
    static let dubaiZone = TimeZone(identifier: "Asia/Dubai")!
}
