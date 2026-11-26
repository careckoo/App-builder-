import SwiftUI
import SwiftData
import KhurdaCore

extension CommitmentType {
    var title: LocalizedStringKey {
        switch self {
        case .rent: "Rent"
        case .loan: "Loan instalment"
        case .carLoan: "Car loan"
        case .cardInstalment: "Card instalment plan"
        case .schoolFees: "School fees"
        case .telecom: "Phone & internet"
        case .utilities: "Electricity & water"
        case .insurance: "Insurance"
        case .bnpl: "Tabby / Tamara"
        case .familySupport: "Family support"
        case .subscription: "Subscription"
        case .domesticWorker: "Domestic worker salary"
        case .charity: "Charity / sadaqah"
        case .other: "Something else"
        }
    }
    var titleResource: LocalizedStringResource {
        switch self {
        case .rent: "Rent"
        case .loan: "Loan instalment"
        case .carLoan: "Car loan"
        case .cardInstalment: "Card instalment plan"
        case .schoolFees: "School fees"
        case .telecom: "Phone & internet"
        case .utilities: "Electricity & water"
        case .insurance: "Insurance"
        case .bnpl: "Tabby / Tamara"
        case .familySupport: "Family support"
        case .subscription: "Subscription"
        case .domesticWorker: "Domestic worker salary"
        case .charity: "Charity / sadaqah"
        case .other: "Something else"
        }
    }
}

/// One row in Plan › Commitments: a bill-like commitment (a jameya uses `JameyaRow`).
struct CommitmentRow: View {
    @Bindable var bill: Obligation
    let cycle: PayCycle
    @Environment(\.modelContext) private var context

    private var due: Bool { bill.isDue(in: cycle) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: bill.type.symbol).foregroundStyle(Theme.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.title).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Theme.aed(bill.amount)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                if bill.amountVaries { Text("about").font(.caption2).foregroundStyle(.secondary) }
            }
            if due && !bill.isFinished {
                Button {
                    bill.setPaid(!bill.isPaidThisCycle)
                    try? context.save()
                } label: {
                    Image(systemName: bill.isPaidThisCycle ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(bill.isPaidThisCycle ? Theme.relaxed : .secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .opacity(due || bill.isFinished ? 1 : 0.6)
    }

    private var subtitle: String {
        if bill.isFinished { return String(localized: "Finished") }
        var parts: [String] = []
        if let left = bill.schedule.remaining(paidCount: bill.paidCount), let last = bill.schedule.lastDue {
            parts.append(String(localized: "\(left.payments) payments left · ends \(last.formatted(.dateTime.month(.abbreviated).year()))"))
        } else {
            parts.append(Self.frequencyText(bill.frequency))
        }
        if !due, let next = bill.next() {
            parts.append(String(localized: "Next: \(next.formatted(.dateTime.day().month(.abbreviated)))"))
        } else if bill.firstDue == nil || bill.isMonthly {
            parts.append(String(localized: "Due on the \(bill.dueDay)"))
        }
        return parts.joined(separator: " · ")
    }

    static func frequencyText(_ f: Frequency) -> String {
        switch f {
        case .monthly: String(localized: "Monthly")
        case .everyMonths(12): String(localized: "Yearly")
        case .everyMonths(let n): String(localized: "Every \(n) months")
        case .months(let m):
            m.map { Calendar.current.shortMonthSymbols[$0 - 1] }.joined(separator: ", ")
        case .once: String(localized: "One payment")
        }
    }
}

/// Add or edit a commitment. Picking "Jameya" opens the jameya editor instead.
struct CommitmentEditor: View {
    var bill: Obligation?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Query(sort: \Account.createdAt) private var accounts: [Account]

    @State private var type: CommitmentType = .rent
    @State private var title = ""
    @State private var amount: Decimal = 0
    @State private var varies = false
    @State private var frequency = 0       // index into `frequencies`
    @State private var months: Set<Int> = [9, 1, 4]
    @State private var next = Date.now
    @State private var fixedCount = false
    @State private var left = 12
    @State private var keyword = ""
    @State private var accountID: UUID?
    @State private var loaded = false
    @State private var deleting = false
    /// The schedule as loaded, to tell whether Save needs to re-anchor it.
    @State private var loadedSchedule: CommitmentSchedule?

    private static let frequencies: [(LocalizedStringKey, (Set<Int>) -> Frequency)] = [
        ("Monthly", { _ in .monthly }), ("Every 3 months", { _ in .everyMonths(3) }), ("Every 4 months", { _ in .everyMonths(4) }),
        ("Every 6 months", { _ in .everyMonths(6) }), ("Yearly", { _ in .everyMonths(12) }),
        ("Choose months", { .months($0.sorted()) }), ("One payment", { _ in .once })
    ]

    var body: some View {
        NavigationStack {
            Form {
                if bill == nil {
                    Section {
                        Picker("Type", selection: $type) {
                            ForEach(CommitmentType.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                        .onChange(of: type) { applyDefaults() }
                    }
                }
                form
            }
            .navigationTitle(bill == nil ? "Add a commitment" : "Edit commitment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(amount <= 0 || (frequency == 5 && months.isEmpty))
                }
            }
            .onAppear(perform: load)
            .confirmationDialog("Delete this commitment? Past payments stay in Activity.", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let bill { context.delete(bill); try? context.save(); Reminders.reschedule(context: context) }
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder private var form: some View {
        Section {
            TextField("Name", text: $title)
            TextField("Amount (AED)", value: $amount, format: .number).keyboardType(.decimalPad)
            Toggle("Amount changes each time", isOn: $varies)
        }
        Section {
            Picker("How often", selection: $frequency) {
                ForEach(Self.frequencies.indices, id: \.self) { Text(Self.frequencies[$0].0).tag($0) }
            }
            if frequency == 5 {
                MonthChips(selected: $months)
            }
            DatePicker("Next payment", selection: $next, displayedComponents: .date)
            if type.asksInstalments || fixedCount {
                Toggle("Fixed number of payments", isOn: $fixedCount)
                if fixedCount {
                    Stepper("Payments left: \(left)", value: $left, in: 1...360)
                    if let last = schedule.lastDue {
                        Text("Last payment: \(last.formatted(.dateTime.month(.wide).year()))").foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            if type == .cardInstalment {
                Text("Only for an instalment plan or an old balance you're paying off. Everyday card spending is already counted.")
            } else if type == .rent {
                Text("Paying rent by cheques? 4 cheques a year is every 3 months.")
            }
        }
        Section {
            Picker("Paid from", selection: $accountID) {
                Text("Any account").tag(UUID?.none)
                ForEach(accounts.filter { !$0.isArchived }) { Text($0.displayName(arabic: locale.language.languageCode == "ar")).tag(UUID?.some($0.id)) }
            }
            TextField("Recognise it by", text: $keyword)
        } footer: {
            Text("A word from the bank message, e.g. DEWA. When that payment arrives, Khurda ticks it off by itself.")
        }
        if bill != nil {
            Section { Button("Delete", role: .destructive) { deleting = true } }
        }
    }

    private var chosenFrequency: Frequency { Self.frequencies[frequency].1(months) }
    private var schedule: CommitmentSchedule {
        // `next` is the first payment still to make, so `left` payments run from it (as saved).
        CommitmentSchedule(amount: amount, frequency: chosenFrequency, firstDue: Calendar.dubai.startOfDay(for: next),
                           instalments: fixedCount ? left : 0)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let b = bill {
            type = b.type; title = b.title; amount = b.amount; varies = b.amountVaries
            keyword = b.matchKeyword; accountID = b.accountID
            // The first payment still to make: this cycle's (even if its day has gone) unless it's paid.
            let cycle = PayCycle.current(payday: AppSettings.payday)
            next = b.next(after: b.isPaidThisCycle ? max(.now, cycle.end) : cycle.start)
                ?? b.firstDue ?? Obligation.anchor(day: b.dueDay)
            fixedCount = b.instalments > 0
            left = max(1, b.instalments - b.paidCount)
            switch b.frequency {
            case .monthly: frequency = 0
            case .everyMonths(3): frequency = 1
            case .everyMonths(4): frequency = 2
            case .everyMonths(6): frequency = 3
            case .everyMonths(12): frequency = 4
            case .everyMonths: frequency = 0
            case .months(let m): frequency = 5; months = Set(m)
            case .once: frequency = 6
            }
            loadedSchedule = schedule
        } else {
            applyDefaults()
        }
    }

    private func applyDefaults() {
        guard bill == nil else { return }
        title = String(localized: type.titleResource)
        varies = type.amountVaries
        keyword = type.keywords.first ?? ""
        fixedCount = type.asksInstalments
        if type == .bnpl { left = 4 }
        switch type.defaultFrequency {
        case .everyMonths(3): frequency = 1
        case .everyMonths(12): frequency = 4
        case .months(let m): frequency = 5; months = Set(m)
        default: frequency = 0
        }
    }

    @MainActor private func save() {
        let cal = Calendar.dubai
        let b = bill ?? Obligation(title: title, amount: amount, dueDay: cal.component(.day, from: next), category: type.category)
        if bill == nil { context.insert(b) }
        let name = title.trimmingCharacters(in: .whitespaces)
        b.title = name.isEmpty ? String(localized: type.titleResource) : name
        b.amount = amount
        b.type = type
        b.categoryRaw = type.category.rawValue
        b.amountVaries = varies
        b.matchKeyword = keyword.trimmingCharacters(in: .whitespaces)
        b.accountID = accountID
        // A new schedule is counted from the next payment still to make: earlier ones are history.
        // Renaming or a new amount keeps the schedule, and whether it's paid this cycle, as they were:
        // un-ticking it would set this cycle's payment aside a second time.
        let s = schedule
        let changed = bill == nil || loadedSchedule.map {
            $0.frequency != s.frequency || $0.firstDue != s.firstDue || $0.instalments != s.instalments
        } ?? true
        if changed {
            b.frequency = chosenFrequency
            b.dueDay = cal.component(.day, from: next)
            b.firstDue = s.firstDue
            b.paidCount = 0
            b.instalments = s.instalments
        }
        try? context.save()
        Reminders.requestAndReschedule(context: context)
        dismiss()
    }
}

private struct MonthChips: View {
    @Binding var selected: Set<Int>
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 6) {
            ForEach(1...12, id: \.self) { m in
                Button { if selected.contains(m) { selected.remove(m) } else { selected.insert(m) } } label: {
                    Text(Calendar.current.shortMonthSymbols[m - 1]).font(.caption)
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(selected.contains(m) ? Theme.accent : Theme.surfaceSecondary, in: .rect(cornerRadius: 8))
                        .foregroundStyle(selected.contains(m) ? .white : Theme.textPrimary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Plan › Your month: income, commitments, goals and usual spending; the daily target and what you'll save.
struct YourMonthCard: View {
    let month: Planner.Month
    var onUseTarget: () -> Void

    private var plan: MonthPlan { month.plan }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your month").font(.headline)
                Spacer()
                Text("\(month.numbers.cycle.start.formatted(.dateTime.day().month(.abbreviated))) – \(month.numbers.cycle.end.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            line("Income", month.numbers.income, sign: "")
            line("Commitments", month.commitmentsThisCycle, sign: "−")
            if month.goalsThisCycle > 0 { line("Goals", month.goalsThisCycle, sign: "−") }
            line("Usually spend", plan.usual, sign: "−")
            Divider()
            HStack {
                Text("Expected to save").font(.subheadline.weight(.semibold))
                Spacer()
                Text(Theme.aed(plan.expectedSavings)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(plan.expectedSavings < 0 ? Theme.over : Theme.relaxed)
            }
            statusLine
            Divider()
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily target").font(.caption).foregroundStyle(.secondary)
                    Text("\(Theme.aed(plan.dailyTarget)) a day").font(.title3.bold()).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("If you keep to it").font(.caption).foregroundStyle(.secondary)
                    Text(Theme.aed(plan.savingsWithTarget)).font(.title3.bold()).monospacedDigit().foregroundStyle(Theme.relaxed)
                }
            }
            if plan.dailyTarget > 0 {
                let applied = AppSettings.savingsGoal > 0 && abs(AppSettings.savingsGoal - month.extraForTarget) < 10
                Button(applied ? "Target in use" : "Use this target", systemImage: applied ? "checkmark" : "target") { onUseTarget() }
                    .buttonStyle(.borderedProminent).disabled(applied)
                    .frame(maxWidth: .infinity)
                Text("Sets aside \(Theme.aed(month.extraForTarget)) this cycle, so today's amount from now to payday is your daily target.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(baselineNote).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func line(_ label: LocalizedStringKey, _ value: Decimal, sign: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text("\(sign) \(Theme.aed(value))").monospacedDigit()
        }
        .font(.subheadline)
    }

    @ViewBuilder private var statusLine: some View {
        switch plan.status {
        case .comfortable: Label("You've got room", systemImage: "checkmark.circle").font(.caption).foregroundStyle(Theme.relaxed)
        case .tight: Label("It fits, just", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Theme.carefulText)
        case .short:
            Label("Commitments and usual spending are \(Theme.aed(plan.shortBy)) more than your income", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(Theme.over)
        }
    }

    private var baselineNote: LocalizedStringKey {
        switch month.baseline.source {
        case .typical: "Usual spending is based on typical UAE spending until Khurda sees a full month of yours. Import a statement to make it yours now."
        case .blended: "Usual spending mixes your own months so far with typical UAE spending."
        case .history: "Usual spending is the middle of your last 3 months, big one-offs left out."
        }
    }
}
