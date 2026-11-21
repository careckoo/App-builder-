import XCTest
@testable import KhurdaCore

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

    /// A banner sentence above the amount is dropped; the amount's own sentence is always kept.
    func testSecurityBannerBeforeAmountDoesNotHideIt() throws {
        let text = MessageText.emailBody("For your security, check alerts. AED 10.00 debited at X")
        XCTAssertEqual(text, "AED 10.00 debited at X")
        XCTAssertEqual(try XCTUnwrap(BankMessageParser().parse(text)).amount, 10)
    }

    // M1: purchase-approval codes sent by email.
    func testAuthorisationCodeEmailsAreSkipped() {
        XCTAssertNil(BankMessageParser().parse(MessageText.emailBody(
            "<p>Use 482913 to authorise your purchase of AED 500.00 at AMAZON.AE. Do not share this code with anyone.</p>")))
        XCTAssertNil(BankMessageParser().parse(MessageText.emailBody(
            "482913 is your code for purchase of AED 500.00 at AMAZON.AE. Never share this code.")))
    }

    func testOTPSubjectSkipsTheEmail() {
        XCTAssertTrue(BankMessageParser.isIgnorable("Your one-time password"))
        XCTAssertFalse(BankMessageParser.isIgnorable("Debit card purchase"))
        XCTAssertNil(MessageReader.read("<p>Card ending 1234 was used for AED 500.00 at AMAZON.AE</p>",
                                        sender: "alerts@bank.ae", subject: "Your OTP").parsed)
    }

    func testSubjectWithTheVerbStillHelps() throws {
        let r = MessageReader.read("<p>Amount: AED 42.00</p><p>Merchant: at NOON.COM</p>",
                                   sender: "alerts@bank.ae", subject: "Debit card purchase")
        XCTAssertTrue(r.isEmail)
        let t = try XCTUnwrap(r.parsed)
        XCTAssertEqual(t.amount, 42)
        XCTAssertEqual(t.kind, .purchase)
    }

    // M2: real bank emails with a security banner above the alert and promos below it.
    func testSecurityBannerAboveAmountAndInFooter() throws {
        let body = "<p>For your security, never share your OTP or PIN with anyone.</p>"
            + "<p>Dear Customer, your Debit Card ending 4321 was used for AED 89.00 at LULU HYPERMARKET on 17/11/2026 18:05.</p>"
            + "<p>Available balance AED 3,200.00</p><p>Never share your OTP, PIN or password. Regards, Your Bank</p>"
        let t = try XCTUnwrap(BankMessageParser().parse(MessageText.emailBody(body), sender: "alerts@bank.ae"))
        XCTAssertEqual(t.kind, .purchase)
        XCTAssertEqual(t.amount, 89)
        XCTAssertEqual(t.merchant, "LULU HYPERMARKET")
        XCTAssertEqual(t.cardLast4, "4321")
        XCTAssertEqual(t.balanceAfter, 3200)
    }

    func testPromoBlockAfterAmount() throws {
        let body = "<p>Dear Customer, your Credit Card ending 5678 was used for AED 230.00 at IKEA on 17/11/2026 12:40.</p>"
            + "<p>Explore our latest offers in the app. Win a car when you spend AED 500 or more! Terms and conditions apply.</p>"
        let t = try XCTUnwrap(BankMessageParser().parse(MessageText.emailBody(body), sender: "alerts@bank.ae"))
        XCTAssertEqual(t.kind, .purchase)
        XCTAssertEqual(t.amount, 230)
        XCTAssertEqual(t.merchant, "IKEA")
    }

    func testPromoMarkersAreWholeWords() {
        XCTAssertEqual(MessageText.emailBody("Card ending 1234 was used for AED 25.00 at WINGSTOP. Win AED 100!"),
                       "Card ending 1234 was used for AED 25.00 at WINGSTOP.")
        XCTAssertEqual(MessageText.emailBody("تم خصم 900 درهم لدى معرض السيارات. عروض حصرية لك"),
                       "تم خصم 900 درهم لدى معرض السيارات.")
    }

    // m3: curly apostrophe.
    func testCurlyApostropheFooter() {
        XCTAssertEqual(MessageText.emailBody("Card ending 1234 was used for AED 20.00 at X. Don\u{2019}t share your OTP."),
                       "Card ending 1234 was used for AED 20.00 at X.")
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
                kind: TransactionKind = .purchase, currency: String = "AED", card: String? = nil) -> CrossSourceDuplicate.Record {
        CrossSourceDuplicate.Record(source: source, kind: kind, amount: amount, currency: currency,
                                    amountAED: currency == "AED" ? amount : amount * Decimal(string: "3.6725")!,
                                    date: now.addingTimeInterval(seconds), merchant: merchant, cardLast4: card)
    }

    // m1: merge safety.
    func testDifferentCardEndingsAreNotMerged() {
        let wallet = record(.wallet, 45.5, "Carrefour", card: "1234")
        XCTAssertNil(CrossSourceDuplicate.match(for: record(.sms, 45.5, "CARREFOUR", after: 30, card: "9876"), among: [wallet]))
        XCTAssertEqual(CrossSourceDuplicate.match(for: record(.sms, 45.5, "CARREFOUR", after: 30, card: "1234"), among: [wallet]), 0)
        // A 3-digit ending ("*234") agrees with the 4-digit one; an unknown ending never blocks.
        XCTAssertEqual(CrossSourceDuplicate.match(for: record(.sms, 45.5, "CARREFOUR", after: 30, card: "234"), among: [wallet]), 0)
        XCTAssertEqual(CrossSourceDuplicate.match(for: record(.sms, 45.5, "CARREFOUR", after: 30), among: [wallet]), 0)
    }

    func testEmptyMerchantMergesOnlyWithOneCandidate() {
        let two = [record(.wallet, 20, "Starbucks", after: -60), record(.wallet, 20, "Costa", after: -30)]
        XCTAssertNil(CrossSourceDuplicate.match(for: record(.email, 20, ""), among: two))
        XCTAssertEqual(CrossSourceDuplicate.match(for: record(.email, 20, ""), among: [two[0]]), 0)
        // A named match wins over a record with no merchant.
        let mixed = [record(.sms, 20, "", after: -10), record(.sms, 20, "STARBUCKS", after: -60)]
        XCTAssertEqual(CrossSourceDuplicate.match(for: record(.wallet, 20, "Starbucks"), among: mixed), 1)
        // Two records without a merchant: don't guess.
        XCTAssertNil(CrossSourceDuplicate.match(for: record(.wallet, 20, "Starbucks"),
                                                among: [record(.sms, 20, "", after: -10), record(.sms, 20, "", after: -20)]))
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
