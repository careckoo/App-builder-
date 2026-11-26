import SwiftUI
import SwiftData
import Charts
import KhurdaCore

/// "نظرة": will the salary last, the last 7 days, a spending calendar, where it went, and small leaks.
struct InsightsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var numbers: SafeToSpendCalculator.Numbers?
    @State private var safe: SafeToSpend?
    @State private var upcoming: [Reminders.Due] = []
    @State private var month: Planner.Month?
    @State private var importing = false
    @Environment(\.layoutDirection) private var direction

    private var cycle: PayCycle { numbers?.cycle ?? .current(payday: AppSettings.payday) }

    /// Flexible spending this cycle: what today's amount is about.
    private var spends: [Spend] {
        transactions
            .filter { $0.isExpense && !$0.isFixedObligation && $0.date >= cycle.start }
            .map { Spend(merchant: $0.merchant, amountAED: $0.amountAED, date: $0.date) }
    }
    private var totals: [Date: Decimal] { Insights.dailyTotals(spends) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let numbers { forecastCard(numbers) }
                    if let month {
                        usualCard(month)
                        if !month.opportunities.isEmpty { waysToSaveCard(month) }
                    }
                    weekCard
                    CalendarCard(cycle: cycle, totals: totals, allowance: safe?.dailyAllowance ?? 0)
                    categoriesCard
                    leaksCard
                    if !upcoming.isEmpty { upcomingCard }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Insights")
            .sheet(isPresented: $importing) { ImportStatementView() }
            .task(id: transactions.count) {
                let calc = SafeToSpendCalculator(context: context)
                numbers = try? calc.numbers()
                safe = try? calc.current()
                month = try? Planner(context: context).month()
                upcoming = Reminders.upcoming(context: context).filter {
                    $0.date < Calendar.dubai.date(byAdding: .day, value: 14, to: .now)!
                }
            }
        }
    }

    // MARK: Cards

    private func forecastCard(_ n: SafeToSpendCalculator.Numbers) -> some View {
        let spent = n.spentBeforeToday + n.spentToday
        let elapsed = (Calendar.dubai.dateComponents([.day], from: n.cycle.start, to: Calendar.dubai.startOfDay(for: .now)).day ?? 0) + 1
        let f = Insights.forecast(available: n.available, spent: spent, daysElapsed: elapsed, daysLeft: n.cycle.daysLeft())
        let ok = f.leftAtPayday >= 0
        return Card(title: "Will your salary last?", symbol: "calendar.badge.clock") {
            VStack(alignment: .leading, spacing: 6) {
                if f.alreadyOver {
                    Text("Bills and savings already take this cycle's money. Anything you spend now goes over.")
                        .font(.headline).foregroundStyle(Theme.over)
                } else if elapsed < 3 {
                    Text("Ask again in a couple of days, once there's some spending to go on.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(ok ? "At this pace you'll have \(Theme.aed(f.leftAtPayday)) left on payday."
                            : "At this pace the money runs out \(f.shortByDays ?? 1) days before payday.")
                        .font(.headline)
                        .foregroundStyle(ok ? Theme.textPrimary : Theme.over)
                    Text("You spend about \(Theme.aed(f.dailyPace)) a day.").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func catName(_ c: CategoryID) -> String { locale.language.languageCode == "ar" ? c.nameAR : c.nameEN }

    /// What you usually spend a month, per category, with this cycle's pace for comparison.
    private func usualCard(_ m: Planner.Month) -> some View {
        let items = m.baseline.monthly.sorted { $0.value > $1.value }.prefix(7)
        let top = items.first?.value ?? 1
        let elapsed = max(1, (Calendar.dubai.dateComponents([.day], from: cycle.start, to: Calendar.dubai.startOfDay(for: .now)).day ?? 0) + 1)
        return Card(title: "What you usually spend", symbol: "chart.bar.doc.horizontal") {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(Theme.aed(m.baseline.monthlyTotal)) a month · about \(Theme.aed(m.baseline.daily)) a day")
                    .font(.headline)
                ForEach(Array(items), id: \.key) { cat, value in
                    let pace = transactions.filter { $0.isExpense && !$0.isFixedObligation && $0.date >= cycle.start && $0.category == cat }
                        .reduce(Decimal(0)) { $0 + $1.amountAED } * BaselineCalculator.monthDays / Decimal(elapsed)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Label(catName(cat), systemImage: cat.symbol).font(.subheadline)
                            Spacer()
                            Text(Theme.aed(value)).font(.subheadline).monospacedDigit()
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.accent.opacity(0.75))
                                    .frame(width: geo.size.width * min(1, CGFloat(NSDecimalNumber(decimal: value / top).doubleValue)))
                                if elapsed >= 7 {
                                    Rectangle().fill(pace > value * Decimal(string: "1.2")! ? Theme.over : Theme.textSecondary)
                                        .frame(width: 2, height: 10)
                                        .offset(x: (direction == .rightToLeft ? -1 : 1) * geo.size.width * min(1, CGFloat(NSDecimalNumber(decimal: pace / top).doubleValue)))
                                }
                            }
                        }
                        .frame(height: 8)
                    }
                }
                switch m.baseline.source {
                case .typical:
                    Text("Based on typical UAE spending until we see a full month of yours. Import a statement to make it yours now.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Import a statement", systemImage: "square.and.arrow.down") { importing = true }.buttonStyle(.bordered)
                case .blended:
                    Text("Based on your months so far and typical UAE spending.").font(.footnote).foregroundStyle(.secondary)
                case .history:
                    Text("The middle of your last 3 months, big one-offs left out.").font(.footnote).foregroundStyle(.secondary)
                }
                if elapsed >= 7 {
                    Text("The small line is this cycle's pace.").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func waysToSaveCard(_ m: Planner.Month) -> some View {
        Card(title: "Ways to save", symbol: "leaf.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Up to \(Theme.aed(SavingsFinder.total(m.opportunities))) a month").font(.headline).foregroundStyle(Theme.relaxed)
                ForEach(m.opportunities) { o in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: o.category?.symbol ?? "building.columns").foregroundStyle(Theme.accent).frame(width: 22)
                        Text(text(for: o)).font(.subheadline)
                    }
                }
            }
        }
    }

    private func text(for o: Opportunity) -> String {
        let name = o.category.map(catName) ?? ""
        switch o.kind {
        case .aboveUsual(let pct):
            return String(localized: "\(name) is \(pct)% above your usual this month · save \(Theme.aed(o.monthly)) a month")
        case let .aboveTypical(typical, usual):
            return String(localized: "You spend \(Theme.aed(usual)) a month on \(name); around \(Theme.aed(typical)) is typical. Trimming a quarter of the gap saves \(Theme.aed(o.monthly)).")
        case let .smallRepeats(merchant, count):
            return String(localized: "\(count) times at \(merchant) in a month · halve it to save \(Theme.aed(o.monthly))")
        case .overlappingSubscriptions(let names):
            return String(localized: "You pay for \(names.joined(separator: " + ")) · keep one, save \(Theme.aed(o.monthly))")
        case .fees(let total):
            return String(localized: "\(Theme.aed(total)) went on bank fees and charges this month")
        }
    }

    private var weekCard: some View {
        let days = Insights.lastDays(7, totals: totals)
        let allowance = NSDecimalNumber(decimal: safe?.dailyAllowance ?? 0).doubleValue
        let within = Insights.daysWithin(allowance: safe?.dailyAllowance ?? 0, totals: totals, from: cycle.start)
        return Card(title: "Last 7 days", symbol: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: 10) {
                Chart {
                    ForEach(days, id: \.day) { d in
                        let v = NSDecimalNumber(decimal: d.total).doubleValue
                        BarMark(x: .value("Day", d.day, unit: .day), y: .value("AED", v))
                            .foregroundStyle(v > allowance * 1.0001 && allowance > 0 ? Theme.over
                                             : v > allowance * 0.8 && allowance > 0 ? Theme.careful : Theme.accent)
                            .cornerRadius(5)
                    }
                    if allowance > 0 {
                        RuleMark(y: .value("Daily amount", allowance))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day)) { AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                .frame(height: 160)
                Text("\(within.within) of \(within.of) days this cycle within your daily amount")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var categoriesCard: some View {
        let inCycle = transactions.filter { $0.isExpense && $0.date >= cycle.start }
        let byCat = Dictionary(grouping: inCycle, by: \.category)
            .mapValues { $0.reduce(Decimal(0)) { $0 + $1.amountAED } }
            .sorted { $0.value > $1.value }
            .prefix(6)
        let top = byCat.first?.value ?? 1
        return Card(title: "Where it went", symbol: "chart.pie.fill") {
            if byCat.isEmpty {
                Text("Nothing spent yet this cycle.").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(byCat), id: \.key) { cat, total in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(locale.language.languageCode == "ar" ? cat.nameAR : cat.nameEN, systemImage: cat.symbol)
                                    .font(.subheadline)
                                Spacer()
                                Text(Theme.aed(total)).font(.subheadline.weight(.semibold)).monospacedDigit()
                            }
                            GeometryReader { geo in
                                Capsule().fill(Theme.accent.opacity(0.85))
                                    .frame(width: geo.size.width * CGFloat(NSDecimalNumber(decimal: total / top).doubleValue))
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
        }
    }

    private var leaksCard: some View {
        let leaks = Insights.leaks(spends).prefix(3)
        return Card(title: "Small things that add up", symbol: "drop.fill") {
            if leaks.isEmpty {
                Text("No repeat small spending this cycle. Nice.").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(leaks), id: \.merchant) { leak in
                        HStack {
                            Text(leak.merchant).lineLimit(1)
                            Spacer()
                            Text("\(leak.count)× · \(Theme.aed(leak.total))").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    private var upcomingCard: some View {
        Card(title: "Coming up", symbol: "bell.fill") {
            VStack(spacing: 8) {
                ForEach(upcoming, id: \.id) { item in
                    HStack {
                        Text(item.title).lineLimit(1)
                        Spacer()
                        Text(item.date.formatted(.dateTime.day().month(.abbreviated))).foregroundStyle(.secondary)
                        Text(Theme.aed(item.amount)).monospacedDigit().frame(minWidth: 80, alignment: .trailing)
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

/// A rounded card with a small title, used on Insights.
struct Card<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.surface, in: .rect(cornerRadius: 18))
    }
}

/// The pay cycle as a calendar: each day tinted by how it went against the daily amount.
struct CalendarCard: View {
    let cycle: PayCycle
    let totals: [Date: Decimal]
    let allowance: Decimal
    @State private var selected: Date?

    private var days: [Date] {
        let cal = Calendar.dubai
        var d = cycle.start, out: [Date] = []
        while d < cycle.end { out.append(d); d = cal.date(byAdding: .day, value: 1, to: d)! }
        return out
    }

    var body: some View {
        Card(title: "Spending calendar", symbol: "calendar") {
            VStack(alignment: .leading, spacing: 10) {
                let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
                let lead = (Calendar.dubai.component(.weekday, from: cycle.start) - Calendar.current.firstWeekday + 7) % 7
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(Calendar.current.veryShortWeekdaySymbols[(i + Calendar.current.firstWeekday - 1) % 7])
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 34) }
                    ForEach(days, id: \.self) { day in
                        dayCell(day)
                    }
                }
                if let selected {
                    Text("\(selected.formatted(.dateTime.weekday(.wide).day().month())): \(Theme.aed(totals[selected] ?? 0))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let today = Calendar.dubai.startOfDay(for: .now)
        let total = totals[day] ?? 0
        let future = day > today
        let color: Color = future ? Theme.surfaceSecondary.opacity(0.5)
            : allowance <= 0 ? Theme.surfaceSecondary
            : total > allowance ? Theme.over.opacity(0.75)
            : total > allowance * Decimal(string: "0.8")! ? Theme.careful.opacity(0.75)
            : Theme.relaxed.opacity(total == 0 ? 0.25 : 0.6)
        return Text("\(Calendar.dubai.component(.day, from: day))")
            .font(.caption.weight(day == today ? .bold : .regular)).monospacedDigit()
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(color, in: .rect(cornerRadius: 8))
            .overlay { if day == today { RoundedRectangle(cornerRadius: 8).stroke(Theme.accent, lineWidth: 2) } }
            .foregroundStyle(future ? Theme.textSecondary : Theme.textPrimary)
            .onTapGesture { if !future { selected = day } }
    }
}
