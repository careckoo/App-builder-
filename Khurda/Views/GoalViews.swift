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
                    Text("\(Theme.aed(goal.saved)) / \(Theme.aed(goal.target))")
                        .font(.callout).monospacedDigit().foregroundStyle(.secondary)
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
        let left = goal.target - goal.saved
        let months = NSDecimalNumber(decimal: left / goal.monthly).doubleValue.rounded(.up)
        let date = Calendar.dubai.date(byAdding: .month, value: Int(months), to: .now) ?? .now
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
    @State private var loaded = false

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
                    TextField("Set aside each month (AED)", value: $monthly, format: .number).keyboardType(.decimalPad)
                    TextField("Already saved (AED)", value: $saved, format: .number).keyboardType(.decimalPad)
                } footer: {
                    Text("The monthly amount comes off your salary on payday, before today's amount is worked out.")
                }
            }
            .navigationTitle(goal == nil ? "New goal" : "Edit goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(target <= 0) }
            }
            .onAppear {
                guard !loaded, let g = goal else { return }
                loaded = true
                name = g.name; target = g.target; monthly = g.monthly; saved = g.saved
            }
        }
    }

    private func save() {
        let typed = name.trimmingCharacters(in: .whitespaces)
        if let g = goal {
            if !typed.isEmpty { g.name = typed }
            g.target = target; g.monthly = monthly; g.saved = saved
        } else {
            let title = typed.isEmpty ? String(localized: preset.localizedTitleResource) : typed
            let g = SavingsGoal(name: title, target: target, monthly: monthly, symbol: preset.symbol)
            g.saved = saved
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
