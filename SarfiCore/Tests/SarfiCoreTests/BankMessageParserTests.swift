import XCTest
@testable import SarfiCore

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

    // MARK: - Short English keywords match whole words only

    func testCashDepositIsOwnTransferNotPurchase() throws {
        // "pos" used to match inside "deposit". Cash put into a CDM was already counted when it was
        // withdrawn, so it is a move between your own money, not income.
        let t = try XCTUnwrap(parser.parse("Cash deposit of AED 500.00 via CDM at ADCB MUSAFFAH"))
        XCTAssertEqual(t.amount, 500)
        XCTAssertEqual(t.kind, .ownTransfer)
        XCTAssertNil(t.merchant)
        XCTAssertFalse(t.isExpense)
        XCTAssertEqual(Categorizer().category(for: t), .transfer)
    }

    func testTreatmentIsPurchaseNotWithdrawal() throws {
        // "atm" used to match inside "TREATMENT".
        let t = try XCTUnwrap(parser.parse("Card ending 1234 was used for AED 350.00 at DENTAL TREATMENT CLINIC on 17/11/2026"))
        XCTAssertEqual(t.kind, .purchase)
        XCTAssertEqual(t.merchant, "DENTAL TREATMENT CLINIC")
        XCTAssertEqual(Categorizer().category(for: t), .health)
    }

    func testMerchantStartingWithNumber() throws {
        let t = try XCTUnwrap(parser.parse("Card ending 1234 was used for AED 12.00 at 7 ELEVEN"))
        XCTAssertEqual(t.amount, 12)
        XCTAssertEqual(t.merchant, "7 ELEVEN")
    }

    func testLivInsideWordIsNotLivBank() throws {
        let t = try XCTUnwrap(parser.parse("Card ending 1234 was used for AED 25.00 at DELIVEROO on 17/11/2026. Order delivered."))
        XCTAssertEqual(t.merchant, "DELIVEROO")
        XCTAssertNil(t.bankName)
        XCTAssertEqual(Categorizer().category(for: t), .delivery)
    }

    func testMobileRechargeIsPurchase() throws {
        // "paid" inside "prepaid" no longer counts; "recharged" is what makes this a purchase.
        let t = try XCTUnwrap(parser.parse(
            "Your du prepaid number was recharged with AED 50.00 using card ending 1234 at DU ONLINE on 17/11/2026"))
        XCTAssertEqual(t.kind, .purchase)
        XCTAssertEqual(t.amount, 50)
        XCTAssertEqual(t.merchant, "DU ONLINE")
        XCTAssertEqual(t.cardLast4, "1234")
        XCTAssertEqual(Categorizer().category(for: t), .telecom)
    }

    func testCardPaymentAtMerchantIsPurchase() throws {
        let t = try XCTUnwrap(parser.parse("Your card payment of AED 30.00 at STARBUCKS was successful"))
        XCTAssertEqual(t.kind, .purchase)
        XCTAssertEqual(t.merchant, "STARBUCKS")
    }

    // MARK: - B1: "at" before a date, a phone number or "us" is not a merchant

    func testCardPaymentCreditedAtDate() throws {
        let t = try XCTUnwrap(parser.parse("Your payment of AED 2,000.00 has been credited at 16/11/26 15:38 for card ending 5678."))
        XCTAssertEqual(t.kind, .cardPayment)
        XCTAssertNil(t.merchant)
    }

    func testCardPaymentCallUsAtPhone() throws {
        let t = try XCTUnwrap(parser.parse(
            "Dear Customer, your payment of AED2000.00 for card ending with *197 has been credited. For queries call us at 600 50 3335"))
        XCTAssertEqual(t.kind, .cardPayment)
        XCTAssertEqual(t.cardLast4, "197")
    }

    func testCardPaymentBankingWithUsAt() throws {
        let t = try XCTUnwrap(parser.parse(
            "Your payment of AED 2,000.00 for your credit card ending 5678 has been received. Thank you for banking with us at ADCB."))
        XCTAssertEqual(t.kind, .cardPayment)
    }

    // MARK: - B2: card bill wordings

    func testCardBillWordings() throws {
        let messages = [
            "AED 2,000.00 has been debited from your account XXX9012 towards your credit card payment.",
            "Payment of AED 2,000.00 received towards your credit card ending 5678",
            "Thank you for your payment of AED 2,000.00 to your credit card",
            "AED 2,000 paid to your credit card ending 5678",
            "Your Credit card XXX5678 payment of AED 2000 has been received",
            "AED 2,000.00 credited to your credit card ending 5678",
            "Payment of AED 2000 towards card ending 5678 credited.",
            "تم سداد مبلغ 2000 درهم لبطاقتك"
        ]
        for m in messages {
            let t = try XCTUnwrap(parser.parse(m), m)
            XCTAssertEqual(t.kind, .cardPayment, m)
            XCTAssertEqual(t.amount, 2000, m)
            XCTAssertEqual(Categorizer().category(for: t), .transfer, m)
        }
    }

    // MARK: - B3/B4: between your own accounts

    func testOwnTransfers() throws {
        let messages = [
            "AED 5,000.00 transferred from your account XXX9012 to your account XXX3456 on 17/11/2026.",
            "AED 1,000.00 transferred to own account XXX3456",
            "تم تحويل مبلغ 1,000 درهم من حسابك 9012 إلى حسابك 3456",
            "Your Fixed Deposit of AED 10,000.00 has matured and been credited to your account XXX9012.",
            "AED 10,000.00 debited from your account XXX9012 for a new Fixed Deposit.",
            "AED 500.00 moved to your Saving Space Holiday.",
            "AED 2,000.00 transferred to your savings account XXX7777."
        ]
        for m in messages {
            let t = try XCTUnwrap(parser.parse(m), m)
            XCTAssertEqual(t.kind, .ownTransfer, m)
            XCTAssertFalse(t.isExpense, m)
            XCTAssertNil(t.merchant, m)
            XCTAssertEqual(Categorizer().category(for: t), .transfer, m)
        }
    }

    func testSalaryIntoSavingsAccountStaysIncome() throws {
        let t = try XCTUnwrap(parser.parse("AED 18,500.00 salary credited to your savings account XXX7777."))
        XCTAssertEqual(t.kind, .income)
    }

    // MARK: - A6/W2/W3: reminders, statements and prize draws are not transactions

    func testIgnoresRemindersStatementsAndDraws() {
        let messages = [
            "Minimum payment due AED 250.00 on your card ending 5678. Please pay by 05/12/2026.",
            "Reminder: your Tabby payment of AED 200.00 is due on 20/11/2026.",
            "Your credit card statement is ready. Statement balance AED 5,000.00, minimum due AED 250.00, due date 05/12/2026.",
            "Your credit card payment of AED 2,000.00 is due on 25/11/2026.",
            "تذكير: يرجى سداد الحد الأدنى 250 درهم لبطاقتك",
            "Your credit limit has been increased to AED 20,000.00",
            "اربح جوائز قيمة! استخدم بطاقتك بقيمة 100 درهم وادخل السحب",
            "ادخل السحب على جوائز بقيمة 50,000 درهم عند استخدام بطاقتك",
            // m2: real reminder wordings are still skipped.
            "Friendly reminder: your payment of AED 300.00 to ETISALAT is coming up.",
            "Payment reminder: AED 450.00 for your Tamara order."
        ]
        for m in messages { XCTAssertNil(parser.parse(m), m) }
    }

    // m2: "reminder" alone is not a reminder message.
    func testSetAReminderUnderPurchaseStillParses() throws {
        let t = try XCTUnwrap(parser.parse("Your card ending 1234 was used for AED 50.00 at CARREFOUR. Set a reminder in our app."))
        XCTAssertEqual(t.kind, .purchase)
        XCTAssertEqual(t.amount, 50)
        XCTAssertEqual(t.merchant, "CARREFOUR")
        XCTAssertEqual(t.cardLast4, "1234")
        XCTAssertEqual(Categorizer().category(for: t), .groceries)
    }

    func testMerchantStopsAtWithCard() throws {
        let t = try XCTUnwrap(parser.parse("Purchase of AED 75.00 at DU SHOP with card ending 1234 on 17/11/2026"))
        XCTAssertEqual(t.kind, .purchase)
        XCTAssertEqual(t.amount, 75)
        XCTAssertEqual(t.merchant, "DU SHOP")
        XCTAssertEqual(t.cardLast4, "1234")
        XCTAssertEqual(Categorizer().category(for: t), .telecom)
    }

    func testMerchantDropsLeadingThe() throws {
        let t = try XCTUnwrap(parser.parse("Card ending 1234 was used for AED 50.00 at the DUBAI MALL"))
        XCTAssertEqual(t.merchant, "DUBAI MALL")
        XCTAssertEqual(Categorizer().category(for: t), .shopping)
    }

    // MARK: - B7: balance markers are whole words

    func testMerchantsContainingBalanceWords() throws {
        let cases: [(String, Decimal, String)] = [
            ("Purchase at BALI RESTAURANT AED 120.00", 120, "BALI RESTAURANT"),
            ("Trx at GLOBAL VILLAGE AED 50.00 approved", 50, "GLOBAL VILLAGE"),
            ("Purchase at UNLIMITED BURGERS for AED 50.00", 50, "UNLIMITED BURGERS"),
            ("Purchase at FONDUE HOUSE for AED 50.00", 50, "FONDUE HOUSE")
        ]
        for (m, amount, merchant) in cases {
            let t = try XCTUnwrap(parser.parse(m), m)
            XCTAssertEqual(t.kind, .purchase, m)
            XCTAssertEqual(t.amount, amount, m)
            XCTAssertEqual(t.merchant, merchant, m)
        }
    }

    // MARK: - B8/B9: categoriser matches whole words

    func testCategoryKeywordsAreWholeWords() throws {
        let cases: [(String, CategoryID)] = [
            ("NOVOTEL ABU DHABI", .other), ("AFTERNOON TEA LOUNGE", .other), ("MASTER BAKERS", .other),
            ("PALACE DOWNTOWN", .other), ("MCDONALD'S", .dining), ("APPLE.COM/BILL", .subscriptions),
            ("H&M", .shopping), ("ITC", .transport), ("DU ONLINE", .telecom), ("STARBUCKS COFFEE", .dining)
        ]
        for (merchant, expected) in cases {
            let t = try XCTUnwrap(parser.parse("Card ending 1234 was used for AED 50.00 at \(merchant)"), merchant)
            XCTAssertEqual(Categorizer().category(for: t), expected, merchant)
        }
    }

    func testLearnedRulesExactThenLongestWholeWord() {
        func tx(_ m: String) -> ParsedTransaction { ParsedTransaction(amount: 10, merchant: m) }
        XCTAssertEqual(Categorizer(learned: ["cafe x": .family, "cafe": .dining]).category(for: tx("CAFE X")), .family)
        XCTAssertEqual(Categorizer(learned: ["al maya": .dining, "al maya supermarket": .family])
            .category(for: tx("AL MAYA SUPERMARKET MARINA")), .family)
        XCTAssertEqual(Categorizer(learned: ["novo": .entertainment]).category(for: tx("NOVOTEL")), .other)
    }

    // MARK: - W7: sender IDs match exactly or as whole words

    func testSenderMatching() throws {
        let m = "Card ending 1234 was used for AED 10.00 at X"
        XCTAssertEqual(try XCTUnwrap(parser.parse(m, sender: "AD-ADCB")).bankName, "ADCB")
        XCTAssertEqual(try XCTUnwrap(parser.parse(m, sender: "ADCBAlert")).bankName, "ADCB")
        XCTAssertNil(try XCTUnwrap(parser.parse(m, sender: "FABULOUSCO")).bankName)
    }

    // MARK: - B5: exact-text duplicates only when the text pins down one moment

    func testExactTextMatchNeedsTimeOrBalance() throws {
        let plain = "Card ending 1234 was used for AED 15.00 at ADNOC"
        XCTAssertFalse(DuplicateDetector.canMatchByText(plain, parsed: try XCTUnwrap(parser.parse(plain))))
        let timed = "Trx. of AED50.00 on your card ending *822 at etisalat Digital App, UAE is Approved. Trx Date: 16/11/26 15:38"
        XCTAssertTrue(DuplicateDetector.canMatchByText(timed, parsed: try XCTUnwrap(parser.parse(timed))))
        let withBalance = "Card ending 1234 was used for AED 15.00 at ADNOC. Avl Bal AED 900.00"
        XCTAssertTrue(DuplicateDetector.canMatchByText(withBalance, parsed: try XCTUnwrap(parser.parse(withBalance))))
        XCTAssertEqual(DuplicateDetector.normalizedText("AED ١٥٫٠٠\r\n at  ADNOC"), DuplicateDetector.normalizedText("aed 15.00 at ADNOC"))
    }

    // MARK: - Real messages (one UAE bank, Nov 2026), verbatim

    func testRealCreditCardBillPayment() throws {
        let t = try XCTUnwrap(parser.parse(
            "Dear Customer, your payment of AED2000.00 on 13/11/2026 for card ending with *197 has been credited. Thank you"))
        XCTAssertEqual(t.amount, 2000)
        XCTAssertEqual(t.currency, "AED")
        XCTAssertEqual(t.kind, .cardPayment)
        XCTAssertFalse(t.isExpense)
        XCTAssertNil(t.merchant)
        XCTAssertEqual(t.cardLast4, "197")
        XCTAssertEqual(Categorizer().category(for: t), .transfer)
    }

    func testRealTrxEtisalat() throws {
        let t = try XCTUnwrap(parser.parse(
            "Trx. of AED50.00 on your card ending *822 at etisalat Digital App, UAE is Approved. Avl. card bal is 4852.54. Trx Date: 16/11/26 15:38"))
        XCTAssertEqual(t.amount, 50)
        XCTAssertEqual(t.currency, "AED")
        XCTAssertEqual(t.kind, .purchase)
        XCTAssertEqual(t.merchant, "etisalat Digital App")
        XCTAssertEqual(t.cardLast4, "822")
        XCTAssertEqual(t.balanceAfter, Decimal(string: "4852.54"))
        XCTAssertEqual(Categorizer().category(for: t), .telecom)
        let expected = Calendar.dubai.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 15, minute: 38))
        XCTAssertEqual(t.date, expected)
    }

    func testRealTrxCarrefour() throws {
        let t = try XCTUnwrap(parser.parse(
            "Trx. of AED10.79 on your card ending *822 at CARREFOUR HYPERMARKET, UAE is Approved. Avl. card bal is 4902.54. Trx Date: 16/11/26 13:12"))
        XCTAssertEqual(t.amount, Decimal(string: "10.79"))
        XCTAssertEqual(t.kind, .purchase)
        XCTAssertEqual(t.merchant, "CARREFOUR HYPERMARKET")
        XCTAssertEqual(t.cardLast4, "822")
        XCTAssertEqual(t.balanceAfter, Decimal(string: "4902.54"))
        XCTAssertEqual(Categorizer().category(for: t), .groceries)
    }

    func testRealTrxCravia() throws {
        let t = try XCTUnwrap(parser.parse(
            "Trx. of AED34.00 on your card ending *822 at CRAVIA INC LLC, UAE is Approved. Avl. card bal is 4913.33. Trx Date: 16/11/26 13:09"))
        XCTAssertEqual(t.amount, 34)
        XCTAssertEqual(t.kind, .purchase)
        XCTAssertEqual(t.merchant, "CRAVIA INC LLC")
        XCTAssertEqual(t.cardLast4, "822")
        XCTAssertEqual(t.balanceAfter, Decimal(string: "4913.33"))
        XCTAssertEqual(Categorizer().category(for: t), .other)
    }

    // MARK: - Dates

    func testDateOnlyTodayUsesArrivalTime() throws {
        let cal = Calendar.dubai
        let received = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 10, minute: 22)))
        let t = try XCTUnwrap(parser.parse("AED 1,000.00 transferred to AHMED ALI from your account XXX9012 on 17/11/2026.",
                                           receivedAt: received))
        XCTAssertEqual(t.date, received)
    }

    func testDateOnlyEarlierKeepsMessageDay() throws {
        let cal = Calendar.dubai
        let received = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9)))
        let t = try XCTUnwrap(parser.parse("AED 1,000.00 transferred to AHMED ALI from your account XXX9012 on 17/11/2026.",
                                           receivedAt: received))
        XCTAssertEqual(t.date, cal.date(from: DateComponents(year: 2026, month: 11, day: 17)))
    }

    func testCRLFIsNormalised() {
        XCTAssertEqual(BankMessageParser.normalize("AED 5.00\r\nat X"), "AED 5.00 at X")
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
