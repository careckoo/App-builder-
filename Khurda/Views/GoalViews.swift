import SwiftUI
import SwiftData
import KhurdaCore

struct GoalRow: View {
    let goal: SavingsGoal
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(goal.name, systemImage: goal.symbol).font(.body.weight(.medium))
                Spacer()
                if goal.isReached {
                    Label("Reached", systemImage: "checkmark.seal.fill").font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.relaxed)
                } else {
                    Text("\(goal.saved.formatted(.number.precision(.fractionLength(0)))) of \(Theme.aed(goal.target))")
                        .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            ProgressView(value: goal.progress).tint(goal.isReached ? Theme.relaxed : Theme.accent)
            if !goal.isReached, goal.monthly > 0 {
                Text("\(Theme.aed(goal.monthly)) a month · \(monthsLeftText)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var monthsLeftText: String {
        if let d = goal.targetDate, d < .now {
            return String(localized: "Date passed · \(Theme.aed(goal.target - goal.saved)) to go")
        }
        let date = GoalPlanner.finishDate(target: goal.target, saved: goal.saved, monthly: goal.monthly,
                                          payday: AppSettings.payday, today: .now) ?? .now
        return String(localized: "there by \(date.formatted(.dateTime.month(.wide).year()))")
    }
}

/// Presets people in the UAE save for. The Ramadan & Eid preset is the one OutCap doesn't have.
enum GoalPreset: String, CaseIterable, Identifiable {
    case ramadan, travel, car, wedding, umrah, home, school, emergency, other
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .ramadan: "moon.stars.fill"
        case .travel: "airplane"
        case .car: "car.fill"
        case .wedding: "heart.fill"
        case .umrah: "building.columns.fill"
        case .home: "house.fill"
        case .school: "graduationcap.fill"
        case .emergency: "cross.case.fill"
        case .other: "star.fill"
        }
    }
    var title: LocalizedStringKey {
        switch self {
        case .ramadan: "Ramadan & Eid"
        case .travel: "Travel"
        case .car: "Car"
        case .wedding: "Wedding"
        case .umrah: "Umrah"
        case .home: "Home"
        case .school: "School fees"
        case .emergency: "Emergency fund"
        case .other: "Something else"
        }
    }
}

struct GoalEditor: View {
    var goal: SavingsGoal?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var preset: GoalPreset = .ramadan
    @State private var name = ""
    @State private var target: Decimal = 5000
    @State private var monthly: Decimal = 500
    @State private var saved: Decimal = 0
    @State private var byDate = true
    @State private var deadline = Calendar.dubai.date(byAdding: .month, value: 12, to: .now)!
    @State private var loaded = false
    @State private var month: Planner.Month?

    private var today: Date { .now }
    private var need: GoalPlanner.Need {
        GoalPlanner.need(target: target, saved: saved, deadline: deadline, payday: AppSettings.payday, today: today)
    }
    /// The monthly amount this plan sets aside.
    private var planMonthly: Decimal {
        guard byDate else { return monthly }
        if case let .monthly(m, _, _) = need { return m }
        return 0
    }
    private var finish: Date? {
        GoalPlanner.finishDate(target: target, saved: saved, monthly: monthly, payday: AppSettings.payday, today: today)
    }
    private var fit: GoalPlanner.Fit? {
        guard let month, planMonthly > 0 else { return nil }
        let room = month.room(excludingGoal: goal.map { $0.isReached ? 0 : $0.monthly } ?? 0)
        return GoalPlanner.fit(monthly: planMonthly, room: room, target: target, saved: saved, payday: AppSettings.payday, today: today)
    }

    var body: some View {
        NavigationStack {
            Form {
                if goal == nil {
                    Section {
                        Picker("For", selection: $preset) {
                            ForEach(GoalPreset.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                        .onChange(of: preset) { name = "" }
                    }
                }
                Section {
                    TextField("Name (optional)", text: $name)
                    TextField("Target (AED)", value: $target, format: .number).keyboardType(.decimalPad)
                    TextField("Already saved (AED)", value: $saved, format: .number).keyboardType(.decimalPad)
                }
                Section {
                    Picker("Plan by", selection: $byDate) {
                        Text("Date").tag(true)
                        Text("Monthly amount").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if byDate {
                        DatePicker("Reach it by", selection: $deadline, in: Date.now..., displayedComponents: .date)
                        switch need {
                        case .reached: Label("Already reached", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.relaxed)
                        case .tooSoon(let now):
                            Text("Too close for payday savings. You'd need \(Theme.aed(now)) now.").foregroundStyle(Theme.carefulText)
                        case let .monthly(m, n, perDay):
                            Text("Set aside \(Theme.aed(m)) a month (about \(Theme.aed(perDay)) a day) from \(n) paydays")
                                .font(.headline)
                        }
                    } else {
                        TextField("Set aside each month (AED)", value: $monthly, format: .number).keyboardType(.decimalPad)
                        if let finish {
                            Text("You'll reach it in \(finish.formatted(.dateTime.month(.wide).year()))").font(.headline)
                        } else {
                            Text("Add a monthly amount").foregroundStyle(.secondary)
                        }
                    }
                    fitBanner
                } footer: {
                    Text("From your next payday, the monthly amount comes off your salary before today's amount is worked out.")
                }
            }
            .navigationTitle(goal == nil ? "New goal" : "Edit goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(target <= 0) }
            }
            .onAppear {
                month = try? Planner(context: context).month()
                guard !loaded, let g = goal else { return }
                loaded = true
                name = g.name; target = g.target; monthly = g.monthly; saved = g.saved
                byDate = g.planByDate && g.targetDate != nil
                if let d = g.targetDate, d > .now { deadline = d }
            }
        }
    }

    @ViewBuilder private var fitBanner: some View {
        switch fit {
        case .comfortable: Label("Fits your month", systemImage: "checkmark.circle").font(.callout).foregroundStyle(Theme.relaxed)
        case .tight: Label("This fits, but leaves little spare each month.", systemImage: "exclamationmark.circle")
                .font(.callout).foregroundStyle(Theme.carefulText)
        case let .notAffordable(short, earliest):
            VStack(alignment: .leading, spacing: 8) {
                Label("That's \(Theme.aed(short)) a month more than you have spare.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(Theme.over)
                if let earliest {
                    Button("Use \(earliest.formatted(.dateTime.month(.wide).year())) instead") {
                        deadline = earliest; byDate = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        case nil: EmptyView()
        }
    }

    private func save() {
        let typed = name.trimmingCharacters(in: .whitespaces)
        let m = byDate ? planMonthly : monthly
        let date = byDate ? deadline : finish
        if let g = goal {
            if !typed.isEmpty { g.name = typed }
            g.target = target; g.monthly = m; g.saved = saved; g.targetDate = date; g.planByDate = byDate
        } else {
            let title = typed.isEmpty ? String(localized: preset.localizedTitleResource) : typed
            let g = SavingsGoal(name: title, target: target, monthly: m, symbol: preset.symbol, targetDate: date)
            g.saved = saved
            g.planByDate = byDate
            context.insert(g)
        }
        try? context.save()
        dismiss()
    }
}

extension GoalPreset {
    /// Same words as `title`, as a resource so the goal's stored name is in the person's language.
    var localizedTitleResource: LocalizedStringResource {
        switch self {
        case .ramadan: "Ramadan & Eid"
        case .travel: "Travel"
        case .car: "Car"
        case .wedding: "Wedding"
        case .umrah: "Umrah"
        case .home: "Home"
        case .school: "School fees"
        case .emergency: "Emergency fund"
        case .other: "Something else"
        }
    }
}

/// Put money in or take it out of a goal by hand (a bonus, an emergency).
struct GoalDetailView: View {
    @Bindable var goal: SavingsGoal
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Decimal = 0
    @State private var editing = false

    var body: some View {
        Form {
            Section { GoalRow(goal: goal) }
            Section {
                TextField("Amount (AED)", value: $amount, format: .number).keyboardType(.decimalPad)
                HStack {
                    Button("Add to goal", systemImage: "plus.circle") {
                        goal.saved += amount; amount = 0; try? context.save()
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Button("Take out", systemImage: "minus.circle") {
                        goal.saved = max(0, goal.saved - amount); amount = 0; try? context.save()
                    }
                    .buttonStyle(.borderless)
                }
                .disabled(amount <= 0)
            } footer: {
                Text("Khurda adds the monthly amount by itself on payday. Use this for a bonus, or when you need to take some out.")
            }
            Section {
                Button("Edit", systemImage: "pencil") { editing = true }
                Button("Delete goal", systemImage: "trash", role: .destructive) {
                    context.delete(goal); try? context.save(); dismiss()
                }
            }
        }
        .themedBackground()
        .navigationTitle(goal.name)
        .sheet(isPresented: $editing) { GoalEditor(goal: goal) }
    }
}
