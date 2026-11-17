import XCTest
@testable import MasroofiCore

/// The sample messages follow the shape of real UAE bank alerts, with fake numbers.
/// Add anonymised real messages here whenever a bank changes its wording.
final class BankMessageParserTests: XCTestCase {
    let parser = BankMessageParser()

    func testEnglishCardPurchase() throws {
        let t = try XCTUnwrap(parser.parse(
            "Card ending 1234 was used for AED 45.50 at CARREFOUR,ABU DHABI AE on 17/11/2026 10:22. Available balance AED 5,230.10",
            sender: "FAB"))
        XCTAssertEqual(t.amount, Decimal(string: "45.50"))
        XCTAssertEqual(t.currency, "AED")
        XCTAssertEqual(t.kind, .purchase)
        XCTAssertEqual(t.merchant, "CARREFOUR")
        XCTAssertEqual(t.cardLast4, "1234")
        XCTAssertEqual(t.balanceAfter, Decimal(string: "5230.10"))
        XCTAssertEqual(t.bankName, "First Abu Dhabi Bank")
        XCTAssertEqual(Categorizer().category(for: t), .groceries)
    }

    func testCreditCardNoSpaceBeforeAmount() throws {
        let t = try XCTUnwrap(parser.parse(
            "Your Cr.Card XXX5678 was used for AED125.00 on 17/11/2026 at TALABAT,DUBAI. Avl Cr. limit is AED 12,000.00"))
        XCTAssertEqual(t.amount, 125)
        XCTAssertEqual(t.merchant, "TALABAT")
        XCTAssertEqual(t.cardLast4, "5678")
        XCTAssertEqual(Categorizer().category(for: t), .delivery)
    }

    func testArabicPurchaseWithArabicDigits() throws {
        let t = try XCTUnwrap(parser.parse(
            "تم خصم مبلغ ٤٥٫٥٠ درهم من بطاقتك المنتهية ب ١٢٣٤ لدى كارفور بتاريخ ١٧/١١/٢٠٢٦. الرصيد المتاح ٥٬٢٣٠٫١٠ درهم"))
        XCTAssertEqual(t.amount, Decimal(string: "45.50"))
        XCTAssertEqual(t.kind, .purchase)
        XCTAssertEqual(t.merchant, "كارفور")
        XCTAssertEqual(t.cardLast4, "1234")
        XCTAssertEqual(t.balanceAfter, Decimal(string: "5230.10"))
        XCTAssertEqual(Categorizer().category(for: t), .groceries)
    }

    func testSalaryCredit() throws {
        let t = try XCTUnwrap(parser.parse(
            "AED 18,500.00 has been credited to your account XXX9012 (Salary). Avl Bal AED 20,100.00"))
        XCTAssertEqual(t.amount, 18500)
        XCTAssertEqual(t.kind, .income)
        XCTAssertEqual(t.merchant, "Salary")
        XCTAssertFalse(t.isExpense)
    }

    func testArabicSalary() throws {
        let t = try XCTUnwrap(parser.parse("تم إيداع راتب بمبلغ 18,500.00 درهم في حسابك رقم ***9012"))
        XCTAssertEqual(t.kind, .income)
        XCTAssertEqual(t.amount, 18500)
    }

    func testATMWithdrawal() throws {
        let t = try XCTUnwrap(parser.parse(
            "AED 500.00 withdrawn from your account XXX9012 at ATM ADCB MUSAFFAH on 17-11-2026. Avl Bal AED 3,600.00"))
        XCTAssertEqual(t.kind, .withdrawal)
        XCTAssertEqual(Categorizer().category(for: t), .cash)
    }

    func testForeignCurrencyOnline() throws {
        let t = try XCTUnwrap(parser.parse("Purchase of USD 15.49 with Debit Card ending 4321 at NETFLIX.COM. Avl Balance is AED 4,100.00."))
        XCTAssertEqual(t.currency, "USD")
        XCTAssertEqual(t.amount, Decimal(string: "15.49"))
        XCTAssertEqual(Categorizer().category(for: t), .subscriptions)
    }

    func testRefund() throws {
        let t = try XCTUnwrap(parser.parse("Refund of AED 89.00 from NOON.COM has been credited to your card ending 1234."))
        XCTAssertEqual(t.kind, .refund)
    }

    func testTransferOut() throws {
        let t = try XCTUnwrap(parser.parse("AED 1,000.00 transferred to AHMED ALI from your account XXX9012 on 17/11/2026."))
        XCTAssertEqual(t.kind, .transferOut)
        XCTAssertEqual(t.merchant, "AHMED ALI")
    }

    func testMerchantContainingBal() throws {
        let t = try XCTUnwrap(parser.parse("Card ending 1234 was used for AED 60.00 at GLOBAL VILLAGE on 17/11/2026. Avl Bal AED 900.00"))
        XCTAssertEqual(t.merchant, "GLOBAL VILLAGE")
        XCTAssertEqual(t.balanceAfter, 900)
    }

    func testArabicFuelWithDirhamSign() throws {
        let t = try XCTUnwrap(parser.parse("عملية شراء بقيمة 120.00 د.إ بالبطاقة رقم 4455 عند أدنوك 512. رصيدك 2,000.00 د.إ"))
        XCTAssertEqual(t.amount, 120)
        XCTAssertEqual(t.cardLast4, "4455")
        XCTAssertEqual(Categorizer().category(for: t), .fuel)
    }

    func testIgnoresOTP() {
        XCTAssertNil(parser.parse("Your OTP for AED 45.50 at AMAZON is 482913. Do not share it with anyone."))
        XCTAssertNil(parser.parse("رمز التحقق الخاص بك هو 482913 لعملية بقيمة 45.50 درهم"))
    }

    func testIgnoresDeclined() {
        XCTAssertNil(parser.parse("Transaction of AED 300.00 at ZARA declined due to insufficient balance."))
    }

    func testIgnoresTextWithoutAmount() {
        XCTAssertNil(parser.parse("Dear customer, your card has been delivered."))
    }

    func testSafeToSpend() {
        let s = SafeToSpend.compute(income: 18500, fixedObligations: 9000, savingsGoal: 2000,
                                    spentBeforeToday: 1500, spentToday: 50, daysLeft: 20)
        XCTAssertEqual(s.dailyAllowance, 300)
        XCTAssertEqual(s.today, 250)
        XCTAssertEqual(s.status, .relaxed)
    }

    func testDuplicate() throws {
        let t = try XCTUnwrap(parser.parse("Card ending 1234 was used for AED 45.50 at CARREFOUR"))
        let now = Date()
        XCTAssertTrue(DuplicateDetector.isDuplicate(t, at: now.addingTimeInterval(60),
                                                    recent: [(DuplicateDetector.fingerprint(t), now)]))
    }
}
