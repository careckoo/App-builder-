import XCTest
@testable import KhurdaCore

final class StatementImportTests: XCTestCase {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        DateComponents(calendar: .dubai, timeZone: .dubaiZone, year: y, month: m, day: d).date!
    }

    func testCSVWithDebitCreditBalance() throws {
        let csv = """
        Emirates NBD Account Statement
        Account Number: 1014xxxxxx5521
        Date,Description,Debit,Credit,Balance
        01/11/2026,Opening Balance,,,"5,000.00"
        02/11/2026,"POS PURCHASE CARD NO.XXXX1234 CARREFOUR MOE,DUBAI AE",245.50,,"4,754.50"
        05/11/2026,ATM CASH WITHDRAWAL 000123,500.00,,"4,254.50"
        27/11/2026,SALARY NOV ACME LLC,,"18,500.00","22,754.50"
        28/11/2026,Closing Balance,,,"22,754.50"
        """
        let a = try XCTUnwrap(StatementImporter.analyze(table: SpreadsheetFiles.csv(csv)))
        XCTAssertEqual(a.rows.count, 3)
        XCTAssertEqual(a.bankName, "Emirates NBD")
        XCTAssertEqual(a.accountLast4, "5521")
        XCTAssertEqual(a.rows[0].amount, Decimal(string: "245.50"))
        XCTAssertEqual(a.rows[0].kind, .purchase)
        XCTAssertEqual(a.rows[0].merchant, "CARREFOUR MOE")
        XCTAssertEqual(a.rows[0].cardLast4, "1234")
        XCTAssertEqual(a.rows[0].date, day(2026, 11, 2))
        XCTAssertEqual(a.rows[1].kind, .withdrawal)
        XCTAssertEqual(a.rows[2].kind, .income)
        XCTAssertEqual(a.rows[2].amount, 18500)
        XCTAssertEqual(a.moneyOut, Decimal(string: "745.50"))
    }

    func testSignedAmountsSemicolonAndArabicHeadings() throws {
        let csv = """
        التاريخ;البيان;المبلغ;الرصيد
        ٠٣/١١/٢٠٢٦;شراء لولو هايبر;-١٢٠٫٥٠;٣٨٧٩٫٥٠
        ٠٤/١١/٢٠٢٦;تحويل إلى أحمد;-٥٠٠;٣٣٧٩٫٥٠
        ٠٥/١١/٢٠٢٦;استرداد نون;٨٩;٣٤٦٨٫٥٠
        """
        let a = try XCTUnwrap(StatementImporter.analyze(table: SpreadsheetFiles.csv(csv)))
        XCTAssertEqual(a.rows.map(\.kind), [.purchase, .transferOut, .refund])
        XCTAssertEqual(a.rows[0].amount, Decimal(string: "120.5"))
        XCTAssertEqual(a.rows[0].merchant, "لولو هايبر")
    }

    func testUnsignedAmountsUseRunningBalanceNewestFirst() throws {
        let csv = """
        Date,Narration,Amount,Balance
        2026-11-10,TALABAT DUBAI,60.00,9440.00
        2026-11-09,SALARY TRANSFER,9000.00,9500.00
        2026-11-08,STARBUCKS MARINA,25.00,500.00
        2026-11-07,ADNOC 123,75.00,525.00
        """
        let a = try XCTUnwrap(StatementImporter.analyze(table: SpreadsheetFiles.csv(csv)))
        XCTAssertEqual(a.rows.map(\.kind), [.purchase, .income, .purchase, .purchase])
        XCTAssertEqual(a.rows[0].merchant, "TALABAT")
    }

    func testDrCrColumnAndMonthFirstDates() throws {
        let csv = """
        Txn Date,Details,Amount,Dr/Cr
        11/25/2026,NETFLIX.COM,39.00,DR
        11/26/2026,REFUND AMAZON.AE,120.00,CR
        """
        let a = try XCTUnwrap(StatementImporter.analyze(table: SpreadsheetFiles.csv(csv)))
        XCTAssertEqual(a.dateFormat, "MM/dd/yyyy")
        XCTAssertEqual(a.rows[0].date, day(2026, 11, 25))
        XCTAssertEqual(a.rows.map(\.kind), [.purchase, .refund])
    }

    func testCreditCardStatementPaymentIsCardPayment() throws {
        let csv = """
        Credit Card Statement - Card Number 5123 XXXX XXXX 8871
        Transaction Date,Description,Amount (AED)
        12-Nov-2026,NOON.COM DUBAI,349.00
        15-Nov-2026,PAYMENT RECEIVED - THANK YOU,2000.00 CR
        """
        let a = try XCTUnwrap(StatementImporter.analyze(table: SpreadsheetFiles.csv(csv)))
        XCTAssertTrue(a.looksLikeCard)
        XCTAssertEqual(a.accountLast4, "8871")
        XCTAssertEqual(a.rows.map(\.kind), [.purchase, .cardPayment])
    }

    func testNoHeadingRowInfersColumns() throws {
        let csv = """
        03/11/2026,LULU HYPERMARKET,150.25,3849.75
        04/11/2026,CAREEM RIDE,32.00,3817.75
        """
        let a = try XCTUnwrap(StatementImporter.analyze(table: SpreadsheetFiles.csv(csv)))
        XCTAssertEqual(a.rows.count, 2)
        XCTAssertEqual(a.rows[1].merchant, "CAREEM RIDE")
    }

    func testPDFLinesWithBalanceAndWrappedDetails() throws {
        let lines = [
            "ABU DHABI COMMERCIAL BANK", "Account No. 123456789012", "Statement period 01/11/2026 - 30/11/2026",
            "Date Description Debit Credit Balance",
            "01/11/2026 Balance Brought Forward 3,000.00",
            "02/11/2026 POS PURCHASE SPINNEYS 112.40 2,887.60",
            "AL WAHDA MALL",
            "04/11/2026 INWARD TRANSFER FROM MOHAMMED 1,000.00 3,887.60",
            "06/11/2026 DEWA BILL PAYMENT 420.00 3,467.60"
        ]
        let a = try XCTUnwrap(StatementImporter.analyze(lines: lines))
        XCTAssertEqual(a.bankName, "ADCB")
        XCTAssertEqual(a.rows.count, 3)
        XCTAssertEqual(a.rows[0].kind, .purchase)
        XCTAssertTrue(a.rows[0].details.contains("AL WAHDA MALL"))
        XCTAssertEqual(a.rows[0].amount, Decimal(string: "112.40"))
        XCTAssertEqual(a.rows[1].kind, .income)
        XCTAssertEqual(a.rows[2].kind, .purchase)
        XCTAssertEqual(a.rows[2].balance, Decimal(string: "3467.60"))
    }

    func testPDFLineWithoutBalanceKeepsNoBalance() throws {
        let lines = [
            "Account Statement",
            "01/11/2026 Opening Balance 1,000.00",
            "02/11/2026 POS SPINNEYS 100.00 900.00",
            "03/11/2026 CAREEM RIDE 20.00",
            "03/11/2026 TALABAT 30.00 850.00",
            "04/11/2026 SALARY ACME 5,000.00 5,850.00"
        ]
        let a = try XCTUnwrap(StatementImporter.analyze(lines: lines))
        XCTAssertEqual(a.rows.count, 4)
        XCTAssertEqual(a.rows[1].amount, 20)
        XCTAssertNil(a.rows[1].balance)   // the amount isn't its own balance
        XCTAssertEqual(a.rows.map(\.kind), [.purchase, .purchase, .purchase, .income])
    }

    func testCardStatementWithSignedAmountsPositiveIsPurchase() throws {
        let csv = """
        Credit Card Statement
        Date,Description,Amount
        12/11/2026,NOON.COM,349.00
        13/11/2026,CARREFOUR CITY CENTRE,120.00
        15/11/2026,PAYMENT RECEIVED THANK YOU,-2000.00
        """
        let a = try XCTUnwrap(StatementImporter.analyze(table: SpreadsheetFiles.csv(csv)))
        XCTAssertEqual(a.rows.map(\.kind), [.purchase, .purchase, .cardPayment])
        XCTAssertEqual(a.moneyOut, 469)
    }

    func testCardPDFWithCreditMarkersAndOwedBalance() throws {
        let lines = [
            "CREDIT CARD STATEMENT", "Card Number 5123 XXXX XXXX 8871",
            "10/11/2026 NOON.COM 349.00 1,349.00",
            "12/11/2026 CARREFOUR 120.00 1,469.00",
            "15/11/2026 PAYMENT THANK YOU 1,000.00 CR 469.00"
        ]
        let a = try XCTUnwrap(StatementImporter.analyze(lines: lines))
        XCTAssertEqual(a.rows.map(\.kind), [.purchase, .purchase, .cardPayment])
    }

    func testMixedSignsWhereTheBalanceSaysPositiveIsOut() throws {
        let csv = """
        Date,Details,Amount,Balance
        01/11/2026,LULU HYPERMARKET,150.00,850.00
        02/11/2026,SALARY ACME,-3000.00,3850.00
        03/11/2026,ENOC STATION,100.00,3750.00
        """
        let a = try XCTUnwrap(StatementImporter.analyze(table: SpreadsheetFiles.csv(csv)))
        XCTAssertEqual(a.rows.map(\.kind), [.purchase, .income, .purchase])
    }

    func testMoneyCells() {
        XCTAssertEqual(Money.parse("123.45000000000001")?.value, Decimal(string: "123.45"))   // Excel float
        XCTAssertEqual(Money.parse("(45.50)")?.value, Decimal(string: "-45.5"))
        XCTAssertEqual(Money.parse("45.50 CR")?.marker, .credit)
        XCTAssertEqual(Money.parse("AED 1,250.00")?.value, 1250)
        XCTAssertNil(Money.parse("Card 1234"))
        XCTAssertNil(Money.parse("12/11/2026"))
    }

    func testDuplicateOfSMS() throws {
        let row = StatementRow(id: 0, date: day(2026, 11, 2), details: "POS CARREFOUR", merchant: "CARREFOUR MOE",
                               amount: 245, currency: "AED", kind: .purchase, balance: nil, cardLast4: "1234")
        let sms = CrossSourceDuplicate.Record(source: .sms, kind: .purchase, amount: 245, currency: "AED", amountAED: 245,
                                              date: day(2026, 11, 2).addingTimeInterval(15 * 3600), merchant: "CARREFOUR", cardLast4: "1234")
        XCTAssertTrue(StatementImporter.isDuplicate(row, amountAED: 245, of: [sms]))
        XCTAssertEqual(StatementImporter.duplicateIndex(row, amountAED: 245, of: [other(sms, amount: 10), sms]), 1)
        var other = sms; other.cardLast4 = "9999"
        XCTAssertFalse(StatementImporter.isDuplicate(row, amountAED: 245, of: [other]))
    }

    private func other(_ r: CrossSourceDuplicate.Record, amount: Decimal) -> CrossSourceDuplicate.Record {
        var r = r; r.amount = amount; r.amountAED = amount; return r
    }

    func testExcelWorkbook() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let files: [String: String] = [
            "[Content_Types].xml": #"<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>"#,
            "xl/workbook.xml": #"<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Txns" sheetId="1" r:id="rId1"/></sheets></workbook>"#,
            "xl/_rels/workbook.xml.rels": #"<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/></Relationships>"#,
            "xl/sharedStrings.xml": #"<?xml version="1.0"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>Date</t></si><si><t>Description</t></si><si><t>Withdrawals</t></si><si><t>Deposits</t></si><si><r><t>LULU </t></r><r><t>HYPERMARKET</t></r></si><si><t>SALARY</t></si></sst>"#,
            "xl/worksheets/sheet1.xml": #"<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c><c r="D1" t="s"><v>3</v></c></row><row r="2"><c r="A2"><v>46329</v></c><c r="B2" t="s"><v>4</v></c><c r="C2"><v>150.75</v></c></row><row r="3"><c r="A3"><v>46330</v></c><c r="B3" t="s"><v>5</v></c><c r="D3"><v>9000</v></c></row></sheetData></worksheet>"#
        ]
        for (path, text) in files {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let out = dir.appendingPathComponent("book.xlsx")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = dir
        zip.arguments = ["-q", "-r", out.path, "[Content_Types].xml", "xl"]
        try zip.run(); zip.waitUntilExit()

        let table = try SpreadsheetFiles.xlsx(Data(contentsOf: out))
        XCTAssertEqual(table[1][1], "LULU HYPERMARKET")
        let a = try XCTUnwrap(StatementImporter.analyze(table: table))
        XCTAssertEqual(a.rows.count, 2)
        XCTAssertEqual(a.rows[0].date, day(2026, 11, 3))
        XCTAssertEqual(a.rows[0].kind, .purchase)
        XCTAssertEqual(a.rows[1].kind, .income)
        XCTAssertEqual(a.rows[1].amount, 9000)
    }
}
