import XCTest
@testable import KhurdaCore

final class PlanningTests: XCTestCase {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        DateComponents(calendar: .dubai, timeZone: .dubaiZone, year: y, month: m, day: d).date!
    }

    // MARK: Accounts

    func testEndingsAndMatching() {
        XCTAssertTrue(AccountMatcher.endingsMatch("123", "0123"))
        XCTAssertFalse(AccountMatcher.endingsMatch("1234", "1235"))
        XCTAssertNil(AccountMatcher.normalizeEnding("12"))
        let accounts = [
            AccountRef(id: "a", bankName: "ADCB", type: .current, endings: ["1234"], isSalary: true),
            AccountRef(id: "b", bankName: "ADCB", type: .creditCard, endings: ["8871"], isSalary: false),
            AccountRef(id: "c", bankName: "FAB", type: .creditCard, endings: ["1234"], isSalary: false)
        ]
        XCTAssertEqual(AccountMatcher.match(bankName: "FAB", ending: "1234", kind: .purchase, among: accounts), "c")
        XCTAssertEqual(AccountMatcher.match(bankName: nil, ending: "871", kind: .purchase, among: accounts), "b")
        XCTAssertNil(AccountMatcher.match(bankName: nil, ending: "1234", kind: .purchase, among: accounts))
        XCTAssertEqual(AccountMatcher.match(bankName: "ADCB", ending: nil, kind: .income, among: accounts), "a")
        XCTAssertNil(AccountMatcher.match(bankName: "ADCB", ending: "5555", kind: .purchase, among: accounts))
    }

    // MARK: Commitments

    func testQuarterlyRentAndSchoolTerms() {
        let rent = CommitmentSchedule(amount: 15000, frequency: .everyMonths(3), firstDue: day(2026, 1, 31), instalments: 0)
        XCTAssertEqual(rent.dueDate(index: 2), day(2026, 4, 30))
        XCTAssertEqual(rent.monthlyEquivalent(on: day(2026, 2, 1), paidCount: 0), 5000)
        let school = CommitmentSchedule(amount: 9000, frequency: .months([9, 1, 4]), firstDue: day(2026, 11, 10), instalments: 0)
        XCTAssertEqual(school.dueDate(index: 1), day(2027, 1, 10))
        XCTAssertEqual(school.dueDate(index: 3), day(2027, 9, 10))
        XCTAssertEqual(school.monthlyEquivalent(on: day(2026, 11, 26), paidCount: 0), 2250)
        XCTAssertEqual(Frequency(raw: Frequency.months([9, 1, 4]).raw), .months([9, 1, 4]))
    }

    func testInstalmentsFinish() {
        let car = CommitmentSchedule(amount: 1850, frequency: .monthly, firstDue: day(2026, 12, 5), instalments: 3)
        XCTAssertEqual(car.lastDue, day(2027, 2, 5))
        XCTAssertNil(car.dueDate(index: 4))
        XCTAssertEqual(car.remaining(paidCount: 1)?.amount, 3700)
        XCTAssertEqual(car.monthlyEquivalent(on: .now, paidCount: 3), 0)
        XCTAssertEqual(car.dues(from: day(2026, 11, 27), to: day(2027, 1, 27)).map(\.index), [1, 2])
        XCTAssertEqual(car.next(onOrAfter: day(2027, 1, 6))?.index, 3)
    }

    func testCommitmentMatcher() {
        let dewa = CommitmentMatcher.Candidate(id: 1, title: "Electricity", amount: 600, amountVaries: true, category: .bills,
                                               keywords: ["dewa"], dueDates: [day(2026, 12, 12)])
        let rent = CommitmentMatcher.Candidate(id: 2, title: "Rent", amount: 5000, amountVaries: false, category: .family,
                                               keywords: [], dueDates: [day(2026, 12, 1)])
        XCTAssertEqual(CommitmentMatcher.match(amountAED: 720, merchant: "DEWA ONLINE", category: .bills,
                                               date: day(2026, 12, 10), among: [dewa, rent]), 1)
        XCTAssertNil(CommitmentMatcher.match(amountAED: 720, merchant: "LULU", category: .bills, date: day(2026, 12, 10), among: [dewa]))
        XCTAssertEqual(CommitmentMatcher.match(amountAED: 5000, merchant: "AHMED", category: .family, date: day(2026, 11, 29), among: [rent]), 2)
        XCTAssertNil(CommitmentMatcher.match(amountAED: 5000, merchant: "AHMED", category: .family, date: day(2026, 12, 20), among: [rent]))
    }

    // MARK: Baseline and plan

    func testBaselineTypicalThenHistory() {
        let cycles = [PayCycle(start: day(2026, 10, 27), end: day(2026, 11, 27)),
                      PayCycle(start: day(2026, 9, 27), end: day(2026, 10, 27)),
                      PayCycle(start: day(2026, 8, 27), end: day(2026, 9, 27))]
        let current = PayCycle(start: day(2026, 11, 27), end: day(2026, 12, 27))
        let none = BaselineCalculator.compute(spends: [], completed: cycles, current: current, today: day(2026, 11, 28),
                                              trackedSince: nil, income: 20000, household: .single, ownsCar: false, covered: [])
        XCTAssertEqual(none.source, .typical)
        XCTAssertEqual(none.monthly[.groceries], 1600)
        XCTAssertNil(none.monthly[.fuel])

        var spends: [CategorySpend] = []
        for (i, c) in cycles.enumerated() {
            spends.append(CategorySpend(category: .dining, merchant: "CAFE", amountAED: [800, 1000, 900][i], date: c.start.addingTimeInterval(86400)))
        }
        spends.append(CategorySpend(category: .shopping, merchant: "IPHONE", amountAED: 5000, date: day(2026, 11, 1)))
        let three = BaselineCalculator.compute(spends: spends, completed: cycles, current: current, today: day(2026, 11, 28),
                                               trackedSince: day(2026, 8, 20), income: 20000, household: .single, ownsCar: false, covered: [.telecom])
        XCTAssertEqual(three.source, .history)
        XCTAssertEqual(three.oneOffs.count, 1)
        XCTAssertNil(three.monthly[.shopping])
        XCTAssertNil(three.monthly[.telecom])
        // Middle of 785.5, 883.7, 1014.7 (800, 900, 1000 normalised to 30.44 days).
        XCTAssertEqual(three.monthly[.dining], 880)
    }

    func testMonthPlan() {
        let p = MonthPlan.compute(income: 20000, commitments: 8000, goals: 1000, usualMonthly: 6000, potentialMonthly: 600, cycleDays: 30)
        XCTAssertEqual(p.status, .comfortable)
        XCTAssertEqual(p.dailyTarget, 185)  // (6000×30/30.44 − 300×30/30.44)/30 = 187.2 → 185
        XCTAssertGreaterThan(p.savingsWithTarget, p.expectedSavings)
        let short = MonthPlan.compute(income: 10000, commitments: 7000, goals: 0, usualMonthly: 5000, potentialMonthly: 0, cycleDays: 30)
        XCTAssertEqual(short.status, .short)
        XCTAssertEqual(short.dailyTarget, 100)
        XCTAssertGreaterThan(short.shortBy, 0)
        XCTAssertEqual(MonthPlan.compute(income: 5000, commitments: 6000, goals: 0, usualMonthly: 3000, potentialMonthly: 0, cycleDays: 30).dailyTarget, 0)
    }

    func testSavingsFinder() {
        let baseline = Baseline(monthly: [.dining: 1000, .delivery: 1400], source: .history, cyclesUsed: 3, oneOffs: [])
        let now = day(2026, 12, 10)
        var spends = (0..<10).map { CategorySpend(category: .dining, merchant: "STARBUCKS", amountAED: 25, date: now.addingTimeInterval(Double(-$0) * 86400)) }
        spends.append(CategorySpend(category: .dining, merchant: "NUSR-ET", amountAED: 900, date: now))
        spends.append(CategorySpend(category: .subscriptions, merchant: "NETFLIX.COM", amountAED: 39, date: now))
        spends.append(CategorySpend(category: .subscriptions, merchant: "OSN+", amountAED: 35, date: now))
        spends.append(CategorySpend(category: .other, merchant: "LATE PAYMENT FEE", amountAED: 230, date: now))
        let found = SavingsFinder.find(thisCycle: spends, last30Days: spends, elapsedDays: 14, baseline: baseline,
                                       income: 20000, household: .single, ownsCar: nil)
        XCTAssertTrue(found.contains { if case .fees = $0.kind { return true }; return false })
        XCTAssertTrue(found.contains { if case .overlappingSubscriptions = $0.kind { return true }; return false })
        XCTAssertTrue(found.contains { if case .smallRepeats(let m, _) = $0.kind { return m.contains("STARBUCKS") }; return false })
        XCTAssertTrue(found.contains { $0.category == .delivery })
        XCTAssertEqual(found, found.sorted { $0.monthly > $1.monthly })
    }

    // MARK: Goals

    func testGoalPlanner() {
        let today = day(2026, 11, 26)
        XCTAssertEqual(GoalPlanner.need(target: 1000, saved: 1000, deadline: day(2027, 6, 1), payday: 27, today: today), .reached)
        XCTAssertEqual(GoalPlanner.need(target: 3000, saved: 0, deadline: day(2026, 11, 26), payday: 27, today: today), .tooSoon(neededNow: 3000))
        // Paydays 27 Nov … 27 May = 7.
        guard case let .monthly(m, n, _) = GoalPlanner.need(target: 10000, saved: 0, deadline: day(2027, 5, 31), payday: 27, today: today) else {
            return XCTFail()
        }
        XCTAssertEqual(n, 7)
        XCTAssertEqual(m, 1430)
        XCTAssertEqual(GoalPlanner.finishDate(target: 3000, saved: 0, monthly: 1000, payday: 27, today: today), day(2027, 1, 27))
        guard case let .notAffordable(short, earliest) = GoalPlanner.fit(monthly: 1430, room: 1000, target: 10000, saved: 0, payday: 27, today: today) else {
            return XCTFail()
        }
        XCTAssertEqual(short, 430)
        XCTAssertNotNil(earliest)
        XCTAssertEqual(GoalPlanner.fit(monthly: 500, room: 1000, target: 10000, saved: 0, payday: 27, today: today), .comfortable)
    }
}
