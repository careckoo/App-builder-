import SwiftUI
import SwiftData
import MasroofiCore

/// First launch: three short steps, about two minutes in total.
/// 1. Salary and payday  2. Pick your banks  3. Add the Shortcuts automation (with a live test).
struct SetupFlowView: View {
    @AppStorage("didFinishSetup", store: AppSettings.defaults) private var didFinishSetup = false
    @State private var step = 0
    @State private var income: Decimal = AppSettings.monthlyIncome
    @State private var payday = AppSettings.payday
    @State private var savings: Decimal = AppSettings.savingsGoal
    @State private var selectedBanks: Set<String> = []

    var body: some View {
        NavigationStack {
            TabView(selection: $step) {
                welcome.tag(0)
                salary.tag(1)
                banks.tag(2)
                ShortcutGuideView(banks: BankDirectory.all.filter { selectedBanks.contains($0.id) }) {
                    AppSettings.monthlyIncome = income
                    AppSettings.payday = payday
                    AppSettings.savingsGoal = savings
                    didFinishSetup = true
                }
                .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "text.bubble.fill").font(.system(size: 64)).foregroundStyle(Theme.accent)
            Text("Your bank already texts you every purchase").font(.title.bold()).multilineTextAlignment(.center)
            Text("Masroofi reads those messages and keeps your budget for you. No typing numbers, no bank passwords, and nothing leaves your iPhone.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
            Button("Let's start") { withAnimation { step = 1 } }.buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(32)
    }

    private var salary: some View {
        Form {
            Section {
                TextField("Monthly salary (AED)", value: $income, format: .number).keyboardType(.numberPad)
                Picker("Payday", selection: $payday) {
                    ForEach(1...28, id: \.self) { Text("\($0)").tag($0) }
                }
                TextField("Save each month (AED)", value: $savings, format: .number).keyboardType(.numberPad)
            } header: {
                Text("Your salary")
            } footer: {
                Text("This is the only time you'll type a number. When your salary SMS arrives, Masroofi uses the real amount.")
            }
            Button("Next") { withAnimation { step = 2 } }.disabled(income <= 0)
        }
    }

    private var banks: some View {
        List {
            Section {
                ForEach(BankDirectory.all) { bank in
                    Button {
                        if selectedBanks.contains(bank.id) { selectedBanks.remove(bank.id) } else { selectedBanks.insert(bank.id) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(bank.nameEN)
                                Text(bank.nameAR).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedBanks.contains(bank.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } header: { Text("Which banks text you?") }
            Button("Next") { withAnimation { step = 3 } }.disabled(selectedBanks.isEmpty)
        }
    }
}

/// Walks the person through creating the Message automation. Apple doesn't let apps create
/// automations themselves, so this screen keeps it to a few clearly-shown taps, then confirms it worked.
struct ShortcutGuideView: View {
    let banks: [Bank]
    var onDone: () -> Void
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var startedAt = Date.now

    private var receivedTest: Bool { transactions.contains { $0.date >= startedAt.addingTimeInterval(-5) } }

    var body: some View {
        List {
            Section {
                step(1, "Open Shortcuts, tap Automation, then New Automation (+).")
                step(2, "Choose Message. Next to Sender, add: \(banks.flatMap(\.senderIDs).prefix(6).joined(separator: ", ")).")
                step(3, "Choose Run Immediately, then tap Next.")
                step(4, "Search for Masroofi, choose “Log bank message”, then tap Message and pick Shortcut Input → Message.")
                step(5, "Tap Done. Repeat for each bank, or add all of them as senders in one automation.")
            } header: {
                Text("Connect your bank messages — one time")
            } footer: {
                Text("If a bank's sender name is different on your phone, use the name exactly as it appears in Messages.")
            }

            Section {
                Button("Open Shortcuts", systemImage: "arrow.up.forward.app") {
                    UIApplication.shared.open(URL(string: "shortcuts://")!)
                }
            }

            Section("Check it works") {
                if receivedTest {
                    Label("Your first bank message arrived", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.relaxed)
                } else {
                    Label("Waiting for your next card payment, or paste an old bank SMS from Today › Paste.",
                          systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                }
            }

            Button(receivedTest ? "Done" : "I'll finish this later") { onDone() }
                .frame(maxWidth: .infinity)
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.callout.bold()).frame(width: 26, height: 26)
                .background(Theme.accent, in: .circle).foregroundStyle(.white)
            Text(text)
        }
        .padding(.vertical, 2)
    }
}

struct SettingsView: View {
    @State private var income = AppSettings.monthlyIncome
    @State private var payday = AppSettings.payday
    @State private var savings = AppSettings.savingsGoal
    @Query private var transactions: [Transaction]

    var body: some View {
        NavigationStack {
            Form {
                Section("Salary") {
                    TextField("Monthly salary (AED)", value: $income, format: .number).keyboardType(.numberPad)
                        .onChange(of: income) { AppSettings.monthlyIncome = income }
                    Picker("Payday", selection: $payday) { ForEach(1...28, id: \.self) { Text("\($0)").tag($0) } }
                        .onChange(of: payday) { AppSettings.payday = payday }
                    TextField("Save each month (AED)", value: $savings, format: .number).keyboardType(.numberPad)
                        .onChange(of: savings) { AppSettings.savingsGoal = savings }
                }
                Section("Automatic tracking") {
                    NavigationLink("Bank message setup") { ShortcutGuideView(banks: BankDirectory.all) {} }
                }
                Section {
                    ShareLink(item: CSVExport.make(transactions), preview: SharePreview("masroofi.csv")) {
                        Label("Export to CSV", systemImage: "square.and.arrow.up")
                    }
                    Button("Language", systemImage: "globe") {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
                } footer: {
                    Text("Your messages and transactions stay on this iPhone. Masroofi has no server and never asks for bank logins.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

enum CSVExport {
    static func make(_ txs: [Transaction]) -> String {
        let iso = ISO8601DateFormatter()
        let rows = txs.sorted { $0.date < $1.date }.map { t in
            [iso.string(from: t.date), t.kind.rawValue, t.merchant, t.category.nameEN, "\(t.amount)", t.currency,
             "\(t.amountAED)", t.cardLast4 ?? "", t.bankName ?? "", t.note]
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: ",")
        }
        return (["date,type,merchant,category,amount,currency,amount_aed,card,bank,note"] + rows).joined(separator: "\n")
    }
}

/// Fixed bills are ticked off when their payment arrives; on payday they start again unticked.
enum CycleReset {
    @MainActor
    static func runIfNeeded(context: ModelContext) {
        let start = PayCycle.current(payday: AppSettings.payday).start
        let key = "lastCycleStart"
        let last = AppSettings.defaults.object(forKey: key) as? Date
        guard last != start else { return }
        (try? context.fetch(FetchDescriptor<Obligation>()))?.forEach { $0.isPaidThisCycle = false }
        AppSettings.defaults.set(start, forKey: key)
    }
}
