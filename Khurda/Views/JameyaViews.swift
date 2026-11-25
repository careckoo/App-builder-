import SwiftUI
import SwiftData
import KhurdaCore

/// One row per jameya in the Plan tab: whose turn it is, and whether this cycle's share is paid.
struct JameyaRow: View {
    let jameya: Jameya
    private var cycle: PayCycle { .current(payday: AppSettings.payday) }
    private var schedule: JameyaSchedule { jameya.schedule }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(jameya.name, systemImage: "person.3.fill").font(.body.weight(.semibold))
                Spacer()
                Text(Theme.aed(jameya.share)).monospacedDigit().foregroundStyle(.secondary)
            }
            JameyaTurnsBar(schedule: schedule)
            HStack {
                JameyaPhaseText(schedule: schedule)
                Spacer()
                if jameya.isDue(in: cycle) {
                    Label(jameya.isPaid(in: cycle) ? "Paid" : "Due this cycle",
                          systemImage: jameya.isPaid(in: cycle) ? "checkmark.circle.fill" : "clock")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(jameya.isPaid(in: cycle) ? Theme.relaxed : Theme.careful)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// The months as dots: paid rounds filled, your turn as a sunny star.
struct JameyaTurnsBar: View {
    let schedule: JameyaSchedule
    var body: some View {
        let current = schedule.round(on: .now) ?? (schedule.phase(on: .now) == .finished ? schedule.members + 1 : 0)
        HStack(spacing: 4) {
            ForEach(1...schedule.members, id: \.self) { r in
                ZStack {
                    Capsule()
                        .fill(r < current ? Theme.accent : r == current ? Theme.accent.opacity(0.45) : Theme.surfaceSecondary)
                    if r == schedule.myTurn {
                        Image(systemName: "star.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.highlight)
                    }
                }
                .frame(height: 12)
            }
        }
        .accessibilityLabel(Text("Round \(min(max(current, 1), schedule.members)) of \(schedule.members). Your turn is round \(schedule.myTurn)."))
    }
}

struct JameyaPhaseText: View {
    let schedule: JameyaSchedule
    var body: some View {
        Group {
            switch schedule.phase(on: .now) {
            case .notStarted:
                Text("Starts \(schedule.dueDate(round: 1).formatted(.dateTime.month(.wide).year()))")
            case .saving(let n):
                Text("Your turn in \(n) months · \(schedule.myPayoutDate.formatted(.dateTime.month(.wide)))")
            case .yourTurn:
                Text("Your turn this month: \(Theme.aed(schedule.pot))").foregroundStyle(Theme.relaxed)
            case .payingBack(let n):
                Text("You've had your turn · \(n) shares left")
            case .finished:
                Text("Finished")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Everything about one jameya: the schedule month by month, where you stand, and a manual tick.
struct JameyaDetailView: View {
    @Bindable var jameya: Jameya
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmDelete = false
    private var cycle: PayCycle { .current(payday: AppSettings.payday) }
    private var schedule: JameyaSchedule { jameya.schedule }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    JameyaPhaseText(schedule: schedule).font(.subheadline)
                    JameyaTurnsBar(schedule: schedule)
                    HStack(spacing: 12) {
                        StatTile(title: "Your pot", value: Theme.aed(schedule.pot))
                        StatTile(title: "Your turn", value: schedule.myPayoutDate.formatted(.dateTime.month(.abbreviated).year()))
                    }
                    if let r = schedule.round(on: .now) {
                        let balance = schedule.balance(afterRound: r)
                        Text(balance >= 0 ? "The group is holding \(Theme.aed(balance)) of yours."
                                          : "You've had the pot early: \(Theme.aed(-balance)) still to pay in.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if jameya.isDue(in: cycle) {
                Section {
                    Toggle("This cycle's share is paid", isOn: Binding(
                        get: { jameya.isPaid(in: cycle) },
                        set: { jameya.paidCycleStart = $0 ? cycle.start : nil; save() }))
                } footer: {
                    Text("Ticked by itself when a bank transfer of \(Theme.aed(jameya.share)) arrives. Until then it's set aside from your daily amount.")
                }
            }
            if schedule.phase(on: .now) == .yourTurn || jameya.receivedPot {
                Section {
                    Toggle("I've received the pot", isOn: Binding(get: { jameya.receivedPot },
                                                                 set: { jameya.receivedPot = $0; save() }))
                }
            }

            Section("Months") {
                ForEach(1...schedule.members, id: \.self) { r in
                    HStack {
                        Text("\(r)").font(.callout.monospacedDigit()).frame(width: 28)
                            .foregroundStyle(.secondary)
                        Text(schedule.dueDate(round: r).formatted(.dateTime.day().month(.wide).year()))
                        Spacer()
                        if r == schedule.myTurn {
                            Label("Your turn", systemImage: "star.fill").labelStyle(.titleAndIcon)
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                        } else if schedule.dueDate(round: r) < Calendar.dubai.startOfDay(for: .now) {
                            Image(systemName: "checkmark").foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if !jameya.organiser.isEmpty {
                Section { LabeledContent("Organiser", value: jameya.organiser) }
            }

            Section {
                Button("Edit", systemImage: "pencil") { editing = true }
                Button("Delete jameya", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .themedBackground()
        .navigationTitle(jameya.name)
        .sheet(isPresented: $editing) { JameyaEditor(jameya: jameya) }
        .confirmationDialog("Delete this jameya?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(jameya); save(); dismiss()
            }
        } message: {
            Text("Its share stops being set aside. Your transactions stay.")
        }
    }

    @MainActor
    private func save() {
        try? context.save()
        Reminders.reschedule(context: context)
    }
}

/// Add or edit a jameya. Five questions, with the pot and your month shown live.
struct JameyaEditor: View {
    var jameya: Jameya?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var share: Decimal = 1000
    @State private var members = 10
    @State private var myTurn = 1
    @State private var firstMonth = Date.now
    @State private var dueDay = AppSettings.payday
    @State private var organiser = ""
    @State private var loaded = false

    private var preview: JameyaSchedule {
        JameyaSchedule(share: share, members: members, myTurn: myTurn, firstMonth: firstMonth, dueDay: dueDay)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Work jameya", text: $name)
                    TextField("Monthly share (AED)", value: $share, format: .number).keyboardType(.decimalPad)
                    Stepper("Members: \(members)", value: $members, in: 2...36)
                        .onChange(of: members) { myTurn = min(myTurn, members) }
                    Stepper("Your turn: \(myTurn)", value: $myTurn, in: 1...members)
                } footer: {
                    Text("Holding two shares? Count them as two members and pick your first turn.")
                }
                Section {
                    DatePicker("First month", selection: $firstMonth, displayedComponents: .date)
                    Picker("Paid on day", selection: $dueDay) { ForEach(1...31, id: \.self) { Text("\($0)").tag($0) } }
                    TextField("Organiser (optional)", text: $organiser)
                }
                Section {
                    LabeledContent("Pot", value: Theme.aed(preview.pot))
                    LabeledContent("Your month", value: preview.myPayoutDate.formatted(.dateTime.month(.wide).year()))
                    LabeledContent("Ends", value: preview.lastDueDate.formatted(.dateTime.month(.wide).year()))
                } footer: {
                    Text("The share is set aside from your daily amount each month, like a bill. Your pot won't be counted as spending money.")
                }
            }
            .navigationTitle(jameya == nil ? "New jameya" : "Edit jameya")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || share <= 0)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded, let j = jameya else { return }
        loaded = true
        name = j.name; share = j.share; members = j.members; myTurn = j.myTurn
        firstMonth = j.firstMonth; dueDay = j.dueDay; organiser = j.organiser
    }

    @MainActor
    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let j = jameya {
            j.name = trimmed; j.share = share; j.members = members; j.myTurn = myTurn
            j.firstMonth = firstMonth; j.dueDay = dueDay; j.organiser = organiser
        } else {
            context.insert(Jameya(name: trimmed, share: share, members: members, myTurn: myTurn,
                                  firstMonth: firstMonth, dueDay: dueDay, organiser: organiser))
        }
        try? context.save()
        Reminders.requestAndReschedule(context: context)
        dismiss()
    }
}
