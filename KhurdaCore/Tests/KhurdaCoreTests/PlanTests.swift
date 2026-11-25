import XCTest
@testable import KhurdaCore

/// Pay cycles with late paydays, the jameya schedule, and the insights.
final class PlanTests: XCTestCase {
    let cal = Calendar.dubai

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    // MARK: PayCycle

    func testPayday31InShortMonths() {
        // Payday 31: in April it's the 30th, in February the 28th (2027 is not a leap year).
        let april = PayCycle.current(payday: 31, today: date(2027, 4, 15))
        XCTAssertEqual(april.start, cal.startOfDay(for: date(2027, 3, 31)))
        XCTAssertEqual(april.end, cal.startOfDay(for: date(2027, 4, 30)))

        let feb = PayCycle.current(payday: 31, today: date(2027, 2, 28))
        XCTAssertEqual(feb.start, cal.startOfDay(for: date(2027, 2, 28)))
        XCTAssertEqual(feb.end, cal.startOfDay(for: date(2027, 3, 31)))
    }

    func testPayday30AcrossFebruaryInLeapYear() {
        let c = PayCycle.current(payday: 30, today: date(2028, 2, 10))
        XCTAssertEqual(c.start, cal.startOfDay(for: date(2028, 1, 30)))
        XCTAssertEqual(c.end, cal.startOfDay(for: date(2028, 2, 29)))
    }

    func testPayday25Unchanged() {
        let c = PayCycle.current(payday: 25, today: date(2026, 11, 24))
        XCTAssertEqual(c.start, cal.startOfDay(for: date(2026, 10, 25)))
        XCTAssertEqual(c.end, cal.startOfDay(for: date(2026, 11, 25)))
        XCTAssertEqual(c.daysLeft(from: date(2026, 11, 24)), 1)
    }

    // MARK: Jameya

    /// 10 members × AED 1,000, starting January 2027, due on the 27th, my turn is 4th.
    var jameya: JameyaSchedule {
        JameyaSchedule(share: 1000, members: 10, myTurn: 4, firstMonth: date(2027, 1, 5), dueDay: 27)
    }

    func testJameyaPotAndDates() {
        XCTAssertEqual(jameya.pot, 10000)
        XCTAssertEqual(jameya.myPayoutDate, cal.startOfDay(for: date(2027, 4, 27)))
        XCTAssertEqual(jameya.lastDueDate, cal.startOfDay(for: date(2027, 10, 27)))
    }

    func testJameyaDueDayClampsInFebruary() {
        let j = JameyaSchedule(share: 500, members: 3, myTurn: 2, firstMonth: date(2027, 1, 1), dueDay: 31)
        XCTAssertEqual(j.dueDate(round: 2), cal.startOfDay(for: date(2027, 2, 28)))
    }

    func testJameyaPhases() {
        XCTAssertEqual(jameya.phase(on: date(2026, 12, 20)), .notStarted)
        XCTAssertEqual(jameya.phase(on: date(2027, 1, 10)), .saving(roundsUntilTurn: 3))
        XCTAssertEqual(jameya.phase(on: date(2027, 4, 1)), .yourTurn)
        XCTAssertEqual(jameya.phase(on: date(2027, 5, 1)), .payingBack(roundsLeft: 6))
        XCTAssertEqual(jameya.phase(on: date(2027, 10, 30)), .payingBack(roundsLeft: 1))
        XCTAssertEqual(jameya.phase(on: date(2027, 11, 1)), .finished)
    }

    func testJameyaBalance() {
        XCTAssertEqual(jameya.balance(afterRound: 3), 3000)     // saved 3 shares
        XCTAssertEqual(jameya.balance(afterRound: 4), -6000)    // took 10,000 after paying 4,000
        XCTAssertEqual(jameya.balance(afterRound: 10), 0)       // even at the end
    }

    func testJameyaRoundsInPayCycle() {
        // Cycle 27 Feb → 27 Mar 2027 contains the 27 Feb due date (round 2) only.
        let c = PayCycle.current(payday: 27, today: date(2027, 3, 10))
        XCTAssertEqual(jameya.rounds(dueFrom: c.start, to: c.end), [2])
    }

    func testJameyaMatching() {
        XCTAssertTrue(jameya.isShare(1000))
        XCTAssertTrue(jameya.isShare(1005))
        XCTAssertFalse(jameya.isShare(1050))
        XCTAssertTrue(jameya.isPot(10000))
        XCTAssertTrue(jameya.isPot(9000))      // own share skipped in my month
        XCTAssertTrue(jameya.isPot(9950))      // organiser fee within 1%
        XCTAssertFalse(jameya.isPot(5000))
    }

    func testJameyaTurnIsClamped() {
        let j = JameyaSchedule(share: 100, members: 5, myTurn: 9, firstMonth: date(2027, 1, 1), dueDay: 1)
        XCTAssertEqual(j.myTurn, 5)
    }

    // MARK: Insights

    func testForecastOnTrack() {
        // 3,000 to spend, 1,000 spent in 10 days, 20 days left → pace 100, 19 more days → 100 left.
        let f = Insights.forecast(available: 3000, spent: 1000, daysElapsed: 10, daysLeft: 20)
        XCTAssertEqual(f.dailyPace, 100)
        XCTAssertEqual(f.leftAtPayday, 100)
        XCTAssertNil(f.shortByDays)
    }

    func testForecastRunsOut() {
        // 3,000 to spend, 2,000 in 10 days (pace 200), 1,000 left lasts 5 days of the 19 after today.
        let f = Insights.forecast(available: 3000, spent: 2000, daysElapsed: 10, daysLeft: 20)
        XCTAssertEqual(f.leftAtPayday, -2800)
        XCTAssertEqual(f.shortByDays, 14)
    }

    func testLeaksGroupSmallRepeats() {
        let d = date(2026, 11, 1)
        var spends = (0..<5).map { Spend(merchant: $0 % 2 == 0 ? "STARBUCKS #12" : "Starbucks 9", amountAED: 22, date: d) }
        spends += (0..<4).map { _ in Spend(merchant: "CARREFOUR", amountAED: 300, date: d) }   // not small
        spends += (0..<3).map { _ in Spend(merchant: "TALABAT", amountAED: 40, date: d) }      // not frequent
        let leaks = Insights.leaks(spends)
        XCTAssertEqual(leaks.count, 1)
        XCTAssertEqual(leaks.first?.count, 5)
        XCTAssertEqual(leaks.first?.total, 110)
        XCTAssertEqual(leaks.first?.merchant, "STARBUCKS #12")
    }

    func testDailyTotalsAndDaysWithin() {
        let spends = [Spend(merchant: "a", amountAED: 50, date: date(2026, 11, 1, 9)),
                      Spend(merchant: "b", amountAED: 80, date: date(2026, 11, 1, 20)),
                      Spend(merchant: "c", amountAED: 20, date: date(2026, 11, 3))]
        let totals = Insights.dailyTotals(spends)
        XCTAssertEqual(totals[cal.startOfDay(for: date(2026, 11, 1))], 130)
        let last = Insights.lastDays(3, totals: totals, today: date(2026, 11, 3))
        XCTAssertEqual(last.map(\.total), [130, 0, 20])
        let w = Insights.daysWithin(allowance: 100, totals: totals, from: date(2026, 11, 1), today: date(2026, 11, 3))
        XCTAssertEqual(w.within, 2)
        XCTAssertEqual(w.of, 3)
    }
}
