import XCTest
@testable import KhurdaCore

/// Teach Khurda: learn a message shape from one tapped example, then read the next one like it.
final class MessageTemplateTests: XCTestCase {

    /// The person taps `amount` (and `merchant`) in `message`; returns the learned template.
    func teach(_ message: String, amount: String, merchant: String? = nil, kind: TransactionKind = .purchase,
               sender: String? = "NEWBANK") -> MessageTemplate? {
        let a = message.range(of: amount)!
        let m = merchant.flatMap { name in message.range(of: name, range: a.upperBound..<message.endIndex) ?? message.range(of: name) }
        return MessageTemplate.learn(message: message, amount: a, merchant: m, kind: kind, sender: sender)
    }

    func testLearnsAnUnknownEnglishShape() throws {
        let first = "Dear customer, you spent 45.50 dirhams with your debit card x1234 at LULU HYPERMARKET on 17-11-2026. Avl bal 5,230.10"
        let t = try XCTUnwrap(teach(first, amount: "45.50", merchant: "LULU HYPERMARKET"))
        let next = "Dear customer, you spent 1,250.00 dirhams with your debit card x1234 at IKEA YAS on 18-11-2026. Avl bal 3,980.10"
        let p = try XCTUnwrap(t.read(next, sender: "NEWBANK"))
        XCTAssertEqual(p.amount, 1250)
        XCTAssertEqual(p.merchant, "IKEA YAS")
        XCTAssertEqual(p.kind, .purchase)
        XCTAssertEqual(p.cardLast4, "1234")
    }

    func testLearnsArabicShapeWithArabicDigits() throws {
        let first = "تم خصم مبلغ ٤٥٫٥٠ درهم من حسابك لدى مطعم الفنر بتاريخ ١٧/١١"
        let t = try XCTUnwrap(teach(first, amount: "٤٥٫٥٠", merchant: "مطعم الفنر"))
        let p = try XCTUnwrap(t.read("تم خصم مبلغ ١٢٠٫٠٠ درهم من حسابك لدى كافيه بيت القهوة بتاريخ ١٨/١١", sender: "NEWBANK"))
        XCTAssertEqual(p.amount, 120)
        XCTAssertEqual(p.merchant, "كافيه بيت القهوة")
    }

    func testAmountOnlyIncome() throws {
        let first = "Your a/c 12xx45 is credited with AED 18,250.00 on 25 Nov. Ref 99812"
        let t = try XCTUnwrap(teach(first, amount: "18,250.00", kind: .income))
        let p = try XCTUnwrap(t.read("Your a/c 12xx45 is credited with AED 2,000.00 on 3 Dec. Ref 10233", sender: "NEWBANK"))
        XCTAssertEqual(p.amount, 2000)
        XCTAssertEqual(p.kind, .income)
        XCTAssertEqual(p.currency, "AED")
        XCTAssertNil(p.merchant)
    }

    func testMerchantBeforeAmount() throws {
        let first = "Purchase at NOON.COM for USD 12.99 approved."
        let t = try XCTUnwrap(teach(first, amount: "12.99", merchant: "NOON.COM"))
        XCTAssertEqual(t.currency, "USD")
        let p = try XCTUnwrap(t.read("Purchase at AMAZON AE for USD 30 approved.", sender: "NEWBANK"))
        XCTAssertEqual(p.amount, 30)
        XCTAssertEqual(p.merchant, "AMAZON AE")
    }

    func testDifferentShapeIsNotRead() throws {
        let t = try XCTUnwrap(teach("You spent 45.50 at LULU on 17-11", amount: "45.50", merchant: "LULU"))
        XCTAssertNil(t.read("Your OTP is 4521. Do not share it.", sender: "NEWBANK"))
    }

    func testOtherSenderIsNotRead() throws {
        let t = try XCTUnwrap(teach("You spent 45.50 at LULU on 17-11", amount: "45.50", merchant: "LULU"))
        XCTAssertNil(t.read("You spent 10.00 at KFC on 18-11", sender: "OTHERBANK"))
        XCTAssertNotNil(t.read("You spent 10.00 at KFC on 18-11", sender: nil))   // pasted: no sender
    }

    func testTappingSomethingThatIsNotAnAmountFails() {
        XCTAssertNil(teach("You spent 45.50 at LULU", amount: "LULU"))
    }

    func testLongMessageKeepsOnlyNearbyWords() throws {
        let promo = String(repeating: "Get 5% cashback this weekend with our partners. ", count: 3)
        let first = promo + "Card x9911 used for AED 60.00 at ENOC 1022 Dubai. Balance AED 700.00. Call 600 5 xxxxx"
        let t = try XCTUnwrap(teach(first, amount: "60.00", merchant: "ENOC 1022 Dubai"))
        // A different promo line in front, and a different ending: still read.
        let next = "New: earn miles! Card x9911 used for AED 15.25 at ZOOM MARINA. Balance AED 684.75. Thank you"
        let p = try XCTUnwrap(t.read(next, sender: "NEWBANK"))
        XCTAssertEqual(p.amount, Decimal(string: "15.25"))
        XCTAssertEqual(p.merchant, "ZOOM MARINA")
    }
}
