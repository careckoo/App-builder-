import XCTest
@testable import MasroofiCore

/// Apple Pay amounts, bank alert emails, and the same purchase reported by two sources.
final class TransactionSourcesTests: XCTestCase {

    // MARK: - Amount text from the Wallet automation

    func testAmountText() throws {
        let cases: [(String, String, String)] = [
            ("AED 45.50", "45.50", "AED"),
            ("45.50 د.إ", "45.50", "AED"),
            ("د.إ.\u{200F} ٤٥٫٥٠", "45.50", "AED"),   // Arabic locale: Arabic digits and a right-to-left mark
            ("\u{200F}٤٥٫٥٠ د.إ.\u{200F}", "45.50", "AED"),
            ("$12.00", "12.00", "USD"),
            ("US$ 12.00", "12.00", "USD"),
            ("1,250.00", "1250.00", "AED"),
            ("١٬٢٥٠٫٠٠ د.إ.", "1250.00", "AED"),
            ("45,50", "45.50", "AED"),
            ("1.250,75 €", "1250.75", "EUR"),
            ("45", "45", "AED"),
            ("AED45.50.", "45.50", "AED")
        ]
        for (text, amount, currency) in cases {
            let r = try XCTUnwrap(AmountText.parse(text), text)
            XCTAssertEqual(r.amount, Decimal(string: amount), text)
            XCTAssertEqual(r.currency, currency, text)
        }
    }

    func testAmountTextRejectsEmptyAndZero() {
        XCTAssertNil(AmountText.parse(""))
        XCTAssertNil(AmountText.parse("AED"))
        XCTAssertNil(AmountText.parse("0.00"))
    }

    // MARK: - Email

    static let alertEmail = """
    <html><head><style>p { color: #333; }</style></head><body>
    <div>Transaction alert</div>
    <p>Dear&nbsp;Customer,<br>Your Credit Card ending 5678 was used for <b>AED&nbsp;125.00</b> at TALABAT,DUBAI on 17/11/2026 10:22.<br/>
    Available limit AED 12,000.00</p>
    <p>For your security, never share your OTP or PIN with anyone.</p>
    <p>Regards,<br>Your Bank</p></body></html>
    """

    func testStripHTML() {
        XCTAssertEqual(
            MessageText.stripHTML("<p>Dear&nbsp;Customer,</p><br/>Card ending 1234 was used for <b>AED&nbsp;45.50</b> at H&amp;M<br>on 17/11/2026."),
            "Dear Customer, Card ending 1234 was used for AED 45.50 at H&M on 17/11/2026.")
        XCTAssertEqual(MessageText.stripHTML("Caf&#233; &#x41;ED &lt;50&gt; and AED < 50"), "Café AED <50> and AED < 50")
        XCTAssertEqual(MessageText.stripHTML("A&amp;nbsp;B"), "A&nbsp;B")
        XCTAssertEqual(MessageText.stripHTML("<style>x{}</style><!-- hidden -->Plain  SMS\ntext"), "Plain SMS text")
    }

    func testAlertEmailParsesAndFooterIsDropped() throws {
        let text = MessageText.emailBody(Self.alertEmail)
        XCTAssertFalse(text.lowercased().contains("otp"), text)
        let t = try XCTUnwrap(BankMessageParser().parse(text, sender: "alerts@adcb.com"))
        XCTAssertEqual(t.kind, .purchase)
        XCTAssertEqual(t.amount, 125)
        XCTAssertEqual(t.merchant, "TALABAT")
        XCTAssertEqual(t.cardLast4, "5678")
        XCTAssertEqual(t.bankName, "ADCB")
    }

    func testOTPEmailIsStillSkipped() {
        XCTAssertNil(BankMessageParser().parse(MessageText.emailBody("<p>Your OTP for AED 45.50 at AMAZON is 482913. Do not share it.</p>")))
    }

    func testSecurityBannerBeforeAmountIsKept() {
        let s = "For your security, check alerts. AED 10.00 debited at X"
        XCTAssertEqual(MessageText.emailBody(s), s)
    }

    func testLooksLikeEmail() {
        XCTAssertTrue(MessageText.looksLikeEmail("AED 1", sender: nil, subject: "Transaction alert"))
        XCTAssertTrue(MessageText.looksLikeEmail("AED 1", sender: "alerts@bank.ae", subject: nil))
        XCTAssertTrue(MessageText.looksLikeEmail("<p>AED 1</p>", sender: nil, subject: nil))
        XCTAssertFalse(MessageText.looksLikeEmail("AED 1 at X", sender: "ADCB", subject: ""))
    }

    // MARK: - Same purchase from Apple Pay and the bank's SMS/email

    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func record(_ source: TransactionSource, _ amount: Decimal, _ merchant: String, after seconds: TimeInterval = 0,
                kind: TransactionKind = .purchase, currency: String = "AED") -> CrossSourceDuplicate.Record {
        CrossSourceDuplicate.Record(source: source, kind: kind, amount: amount, currency: currency,
                                    amountAED: currency == "AED" ? amount : amount * Decimal(string: "3.6725")!,
                                    date: now.addingTimeInterval(seconds), merchant: merchant)
    }

    func testWalletThenSMSIsOnePurchase() {
        let wallet = record(.wallet, 45.5, "Carrefour")
        let sms = record(.sms, 45.5, "CARREFOUR HYPERMARKET", after: 40)
        XCTAssertEqual(CrossSourceDuplicate.match(for: sms, among: [wallet]), 0)
        XCTAssertEqual(CrossSourceDuplicate.match(for: wallet, among: [sms]), 0)
    }

    func testEmptyMerchantMatches() {
        XCTAssertEqual(CrossSourceDuplicate.match(for: record(.email, 20, "", after: 120), among: [record(.wallet, 20, "Starbucks")]), 0)
    }

    func testNotSameWhenAmountTimeMerchantOrSourceDiffer() {
        let wallet = record(.wallet, 45.5, "Carrefour")
        XCTAssertNil(CrossSourceDuplicate.match(for: record(.sms, 45.0, "CARREFOUR", after: 30), among: [wallet]))
        XCTAssertNil(CrossSourceDuplicate.match(for: record(.sms, 45.5, "CARREFOUR", after: 301), among: [wallet]))
        XCTAssertNil(CrossSourceDuplicate.match(for: record(.sms, 45.5, "STARBUCKS", after: 30), among: [wallet]))
        // Two Apple Pay purchases are not merged here; `DuplicateDetector` handles same-source repeats.
        XCTAssertNil(CrossSourceDuplicate.match(for: record(.wallet, 45.5, "Carrefour", after: 30), among: [wallet]))
        // Manual entries are the person's own choice and are never merged.
        XCTAssertNil(CrossSourceDuplicate.match(for: record(.sms, 45.5, "Carrefour", after: 30), among: [record(.manual, 45.5, "Carrefour")]))
        // Only purchases.
        XCTAssertNil(CrossSourceDuplicate.match(for: record(.sms, 45.5, "", after: 30, kind: .refund), among: [wallet]))
    }

    func testClosestInTimeWins() {
        let existing = [record(.wallet, 30, "Costa", after: -200), record(.wallet, 30, "Costa", after: -20)]
        XCTAssertEqual(CrossSourceDuplicate.match(for: record(.sms, 30, "COSTA COFFEE"), among: existing), 1)
    }

    func testForeignAmountMatchesByCurrency() {
        let wallet = record(.wallet, 15.49, "Netflix", currency: "USD")
        XCTAssertEqual(CrossSourceDuplicate.match(for: record(.sms, 15.49, "NETFLIX.COM", after: 10, currency: "USD"), among: [wallet]), 0)
    }

    func testMerchantSimilarity() {
        XCTAssertTrue(CrossSourceDuplicate.merchantsSimilar("McDonald's", "MCDONALDS DXB MALL"))
        XCTAssertTrue(CrossSourceDuplicate.merchantsSimilar("7-Eleven", "7 ELEVEN"))
        XCTAssertTrue(CrossSourceDuplicate.merchantsSimilar("Talabat", "TALABAT,DUBAI"))
        XCTAssertTrue(CrossSourceDuplicate.merchantsSimilar("", "ANYTHING"))
        XCTAssertFalse(CrossSourceDuplicate.merchantsSimilar("Al Maya", "Carrefour Mall"))
        XCTAssertFalse(CrossSourceDuplicate.merchantsSimilar("Starbucks", "Costa Coffee"))
    }
}
