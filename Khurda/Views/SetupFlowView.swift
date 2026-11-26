import SwiftUI
import SwiftData
import KhurdaCore

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
                    finish()
                }
                .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }

    @Environment(\.modelContext) private var context

    /// Keeps what was entered: the salary as an income, each picked bank as an account.
    private func finish() {
        AppSettings.monthlyIncome = income
        AppSettings.payday = payday
        AppSettings.savingsGoal = savings
        AppSettings.selectedBanks = BankDirectory.all.map(\.id).filter { selectedBanks.contains($0) }
        if (try? context.fetchCount(FetchDescriptor<IncomeSource>())) == 0 {
            context.insert(IncomeSource(name: String(localized: "Salary"), amount: income, day: payday))
        }
        let have = Set(((try? context.fetch(FetchDescriptor<Account>())) ?? []).map(\.bankID))
        for id in AppSettings.selectedBanks where !have.contains(id) {
            context.insert(Account(bankID: id, type: .current))
        }
        try? context.save()
        AppSettings.defaults.set(true, forKey: "didMigrateAccounts")
        didFinishSetup = true
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "text.bubble.fill").font(.system(size: 64)).foregroundStyle(Theme.accent)
            Text("Your bank already texts you every purchase").font(.title.bold()).multilineTextAlignment(.center)
            Text("Khurda reads those messages and keeps your budget for you. No typing numbers, no bank passwords, and nothing leaves your iPhone.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
            Button("Let's start") { withAnimation { step = 1 } }.buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(32)
        .padding(.bottom, 40)   // clear of the page dots
    }

    private var salary: some View {
        Form {
            Section {
                TextField("Monthly salary (AED)", value: $income, format: .number).keyboardType(.numberPad)
                Picker("Payday", selection: $payday) {
                    ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                }
                TextField("Save each month (AED)", value: $savings, format: .number).keyboardType(.numberPad)
            } header: {
                Text("Your salary")
            } footer: {
                Text("This is the only time you'll type a number. When your salary SMS arrives, Khurda uses the real amount.")
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

/// Walks the person through the Shortcuts automations. Apple doesn't let apps create automations
/// or read other apps' notifications, so Khurda offers three sources, each a few clearly-shown taps:
/// Apple Pay (works with any bank card in Wallet), bank SMS, and bank alert emails.
struct ShortcutGuideView: View {
    let banks: [Bank]
    var onDone: () -> Void
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    /// How many transactions existed when this screen opened. Comparing dates doesn't work: a pasted
    /// old SMS keeps its own (earlier) date, and a new one may carry the bank's timestamp.
    @State private var countAtStart: Int?

    private var receivedTest: Bool { countAtStart.map { transactions.count > $0 } ?? false }

    private var senders: String {
        let ids = (banks.isEmpty ? BankDirectory.all : banks).flatMap(\.senderIDs).prefix(6)
        return ids.joined(separator: ", ")
    }

    var body: some View {
        List {
            Section {
                Text("Banks are moving alerts into their own apps, and iPhone doesn't let other apps read those. Set up one or more of these instead.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section {
                step(1, "In Shortcuts, tap Automation, then New Automation (+), and choose Transaction.")
                step(2, "Choose your cards (all of them is fine), choose Run Immediately, then tap Next.")
                step(3, "Search for Khurda and choose “Log Apple Pay purchase”.")
                step(4, "Set Amount, Merchant and Card to the matching Shortcut Input (Amount, Merchant, Card or Pass). Tap Done.")
            } header: {
                Label("Apple Pay — recommended", systemImage: "wallet.pass.fill")
            } footer: {
                Text("Works with any bank card in Apple Wallet, even if your bank only sends app notifications.")
            }

            Section {
                step(1, "In Shortcuts, tap Automation, then New Automation (+), and choose Message.")
                step(2, "Next to Sender, add: \(senders). Choose Run Immediately, then tap Next.")
                step(3, "Search for Khurda, choose “Log bank message or email”, then tap Message and pick Shortcut Input → Message.")
            } header: {
                Label("Bank SMS", systemImage: "message.fill")
            } footer: {
                Text("If your bank still sends SMS. Use the sender name exactly as it appears in Messages.")
            }

            Section {
                step(1, "In your bank's app, turn on email alerts for card transactions.")
                step(2, "In Shortcuts, tap Automation, then New Automation (+), and choose Email.")
                step(3, "Next to Sender, add your bank's alert email address. Choose Run Immediately, then tap Next.")
                step(4, "Search for Khurda, choose “Log bank message or email”, then set Message to the email's body, and Sender and Subject to the email's sender and subject.")
            } header: {
                Label("Bank email alerts", systemImage: "envelope.fill")
            } footer: {
                Text("Catches online and card-swipe payments that don't go through Apple Pay.")
            }

            Section {
                Button("Open Shortcuts", systemImage: "arrow.up.forward.app") {
                    UIApplication.shared.open(URL(string: "shortcuts://")!)
                }
            } footer: {
                Text("Paid cash? Tap + on the Today screen to add it.")
            }

            Section("Check it works") {
                if receivedTest {
                    Label("Your first transaction arrived", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.relaxed)
                } else {
                    Label("Waiting for your next card payment, or paste an old bank SMS from Today › Paste.",
                          systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                }
            }

            Button(receivedTest ? "Done" : "I'll finish this later") { onDone() }
                .frame(maxWidth: .infinity)
        }
        .onAppear { if countAtStart == nil { countAtStart = transactions.count } }
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
    @Environment(\.modelContext) private var context
    @Query private var transactions: [Transaction]
    @Query(sort: \IncomeSource.createdAt) private var incomes: [IncomeSource]
    @Query private var accounts: [Account]
    @State private var payday = AppSettings.payday
    @State private var savings = AppSettings.savingsGoal
    @State private var income = AppSettings.monthlyIncome
    @State private var importing = false
    @AppStorage("appearance", store: AppSettings.defaults) private var appearance = Appearance.light

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { IncomeListView() } label: {
                        LabeledContent("Income", value: "\(Theme.aed(AppSettings.monthlyIncome)) / month")
                    }
                    Picker("Payday", selection: $payday) { ForEach(1...31, id: \.self) { Text("\($0)").tag($0) } }
                        .onChange(of: payday) {
                            AppSettings.payday = payday
                            // The salary's day is payday: keep them the same.
                            incomes.first { $0.kindRaw == "salary" }?.dayOfMonth = payday
                            try? context.save()
                        }
                    NavigationLink { AccountsView() } label: {
                        LabeledContent("Accounts & cards", value: "\(accounts.filter { !$0.isArchived }.count)")
                    }
                    NavigationLink { HouseholdView() } label: { Text("Who's at home") }
                    LabeledContent("Extra to save each month") {
                        TextField("AED", value: $savings, format: .number).keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing).frame(maxWidth: 110)
                            .onChange(of: savings) { AppSettings.savingsGoal = savings }
                    }
                } header: { Text("Your money") }
                Section("Automatic tracking") {
                    NavigationLink("Automatic tracking setup") {
                        ShortcutGuideView(banks: accountBanks) {}
                    }
                    NavigationLink("Messages we couldn't read") { UnreadMessagesView() }
                    NavigationLink("Learned messages") { LearnedTemplatesView() }
                }
                Section("Data") {
                    Button("Import a statement", systemImage: "square.and.arrow.down") { importing = true }
                    NavigationLink { ImportHistoryView() } label: { Label("Past imports", systemImage: "clock.arrow.circlepath") }
                    ShareLink(item: CSVExport.make(transactions), preview: SharePreview("khurda.csv")) {
                        Label("Export to CSV", systemImage: "square.and.arrow.up")
                    }
                }
                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    Button("Language", systemImage: "globe") {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
                } footer: {
                    Text("Your messages and transactions stay on this iPhone. Khurda has no server and never asks for bank logins.")
                }
            }
            .themedBackground()
            .navigationTitle("Settings")
            .sheet(isPresented: $importing) { ImportStatementView() }
            .onAppear { payday = AppSettings.payday; savings = AppSettings.savingsGoal }
        }
    }

    private var accountBanks: [Bank] {
        let ids = Set(accounts.map(\.bankID) + AppSettings.selectedBanks)
        let banks = BankDirectory.all.filter { ids.contains($0.id) }
        return banks.isEmpty ? BankDirectory.all : banks
    }
}

enum CSVExport {
    static func make(_ txs: [Transaction]) -> String {
        let iso = ISO8601DateFormatter()
        let rows = txs.sorted { $0.date < $1.date }.map { t in
            [iso.string(from: t.date), t.kind.rawValue, t.merchant, t.category.nameEN, "\(t.amount)", t.currency,
             "\(t.amountAED)", t.cardLast4 ?? "", t.bankName ?? "", t.note, t.sourceRaw]
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: ",")
        }
        return (["date,type,merchant,category,amount,currency,amount_aed,card,bank,note,source"] + rows).joined(separator: "\n")
    }
}
