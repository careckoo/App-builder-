import SwiftUI
import SwiftData
import KhurdaCore

// MARK: - Income

/// Settings › Income: salary and any other regular income. The salary's day is payday.
struct IncomeListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \IncomeSource.createdAt) private var incomes: [IncomeSource]
    @State private var editing: IncomeSource?
    @State private var adding = false

    var body: some View {
        List {
            Section {
                ForEach(incomes) { i in
                    Button { editing = i } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(i.name).foregroundStyle(Theme.textPrimary)
                                Text(i.isRegular ? "On the \(i.dayOfMonth)" : "Sometimes")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Theme.aed(i.amount)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
                .onDelete { $0.forEach { context.delete(incomes[$0]) }; try? context.save(); Incomes.sync(context: context) }
                Button("Add income", systemImage: "plus") { adding = true }
            } footer: {
                Text("Only regular income counts in your plan. Bonuses and gifts count when they arrive.")
            }
        }
        .themedBackground()
        .navigationTitle("Income")
        .sheet(item: $editing) { IncomeEditor(income: $0) }
        .sheet(isPresented: $adding) { IncomeEditor(income: nil) }
    }
}

struct IncomeEditor: View {
    let income: IncomeSource?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @State private var name = ""
    @State private var kind = "salary"
    @State private var amount: Decimal = 0
    @State private var day = 27
    @State private var regular = true
    @State private var accountID: UUID?
    @State private var loaded = false

    static let kinds: [(String, LocalizedStringKey)] = [
        ("salary", "Salary"), ("allowance", "Housing allowance"), ("rental", "Rent you receive"), ("pension", "Pension"),
        ("business", "Business"), ("support", "Support from family"), ("other", "Other")
    ]

    var body: some View {
        NavigationStack {
            Form { Section {
                TextField("Name", text: $name)
                Picker("Type", selection: $kind) { ForEach(Self.kinds, id: \.0) { Text($0.1).tag($0.0) } }
                TextField("Amount (AED)", value: $amount, format: .number).keyboardType(.decimalPad)
                Toggle("It's regular", isOn: $regular)
                if regular {
                    Picker("Day it arrives", selection: $day) { ForEach(1...31, id: \.self) { Text("\($0)").tag($0) } }
                }
                Picker("Lands in", selection: $accountID) {
                    Text("Not set").tag(UUID?.none)
                    ForEach(accounts.filter { !$0.isArchived }) { Text($0.displayName(arabic: locale.language.languageCode == "ar")).tag(UUID?.some($0.id)) }
                }
            } footer: {
                if kind == "salary" { Text("Your salary's day is your payday: each pay cycle runs from one salary to the next.") }
            } }
            .navigationTitle(income == nil ? "Add income" : "Edit income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(amount <= 0) }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let i = income {
                    name = i.name; kind = i.kindRaw; amount = i.amount; day = i.dayOfMonth; regular = i.isRegular; accountID = i.accountID
                } else { day = AppSettings.payday }
            }
        }
    }

    @MainActor private func save() {
        let title = name.trimmingCharacters(in: .whitespaces)
        let label = title.isEmpty ? String(localized: String.LocalizationValue(Self.englishName(kind))) : title
        let i = income ?? IncomeSource(name: label, amount: amount, kind: kind, day: day)
        if income == nil { context.insert(i) }
        i.name = label; i.kindRaw = kind; i.amount = amount; i.dayOfMonth = day; i.isRegular = regular; i.accountID = accountID
        if kind == "salary", let a = accounts.first(where: { $0.id == accountID }) {
            accounts.forEach { $0.isSalaryAccount = $0.id == a.id }
        }
        try? context.save()
        Incomes.sync(context: context)
        dismiss()
    }

    static func englishName(_ kind: String) -> String {
        ["salary": "Salary", "allowance": "Housing allowance", "rental": "Rent you receive", "pension": "Pension",
         "business": "Business", "support": "Support from family"][kind] ?? "Other"
    }
}

// MARK: - Accounts

/// Settings › Accounts & cards, grouped by bank. Several banks, several accounts and cards each.
struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query private var transactions: [Transaction]
    @State private var editing: Account?
    @State private var adding = false

    private var arabic: Bool { locale.language.languageCode == "ar" }
    private var byBank: [(String, [Account])] {
        Dictionary(grouping: accounts.filter { !$0.isArchived }) { $0.bankID }
            .map { ($0.key, $0.value) }
            .sorted { ($0.1.first?.createdAt ?? .now) < ($1.1.first?.createdAt ?? .now) }
    }

    var body: some View {
        List {
            ForEach(byBank, id: \.0) { bankID, list in
                Section(bankTitle(bankID, list.first)) {
                    ForEach(list) { a in
                        Button { editing = a } label: { AccountRow(account: a, arabic: arabic, count: count(a)) }
                            .swipeActions {
                                if count(a) == 0 {
                                    Button("Delete", role: .destructive) { context.delete(a); try? context.save() }
                                } else {
                                    Button("Archive") { a.isArchived = true; try? context.save() }
                                }
                            }
                    }
                }
            }
            Section {
                Button("Add an account or card", systemImage: "plus") { adding = true }
            } footer: {
                Text("Only the last digits, never the full number. They help Khurda tell your cards apart.")
            }
            let archived = accounts.filter(\.isArchived)
            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { a in
                        AccountRow(account: a, arabic: arabic, count: count(a))
                            .swipeActions { Button("Restore") { a.isArchived = false; try? context.save() } }
                    }
                }
            }
        }
        .themedBackground()
        .navigationTitle("Accounts & cards")
        .sheet(item: $editing) { AccountEditor(account: $0) }
        .sheet(isPresented: $adding) { AccountEditor(account: nil) }
    }

    private func count(_ a: Account) -> Int { transactions.filter { $0.accountID == a.id }.count }
    private func bankTitle(_ id: String, _ a: Account?) -> String {
        guard let b = BankDirectory.all.first(where: { $0.id == id }) else { return a?.customBankName ?? "" }
        return arabic ? b.nameAR : b.nameEN
    }
}

struct AccountRow: View {
    let account: Account
    let arabic: Bool
    var count: Int = 0
    var body: some View {
        HStack {
            Image(systemName: account.type.symbol).foregroundStyle(Theme.accent).frame(width: 28)
            VStack(alignment: .leading) {
                Text(account.displayName(arabic: arabic)).foregroundStyle(Theme.textPrimary)
                Text("\(AccountEditor.typeName(account.type)) · \(count) transactions").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if account.isSalaryAccount {
                Text("Salary").font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.highlight, in: .capsule)
            }
        }
    }
}

struct AccountEditor: View {
    let account: Account?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @State private var bankID = BankDirectory.all[0].id
    @State private var customBank = ""
    @State private var type: AccountType = .current
    @State private var nickname = ""
    @State private var last4 = ""
    @State private var more = ""
    @State private var salary = false
    @State private var loaded = false

    static func typeName(_ t: AccountType) -> LocalizedStringKey {
        switch t {
        case .current: "Account"
        case .savings: "Savings"
        case .creditCard: "Credit card"
        case .prepaid: "Prepaid"
        case .bnpl: "Buy now, pay later"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Bank", selection: $bankID) {
                        ForEach(BankDirectory.all) { Text(locale.language.languageCode == "ar" ? $0.nameAR : $0.nameEN).tag($0.id) }
                        Text("Other bank").tag("other")
                    }
                    if bankID == "other" { TextField("Bank name", text: $customBank) }
                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases, id: \.self) { Text(Self.typeName($0)).tag($0) }
                    }
                    TextField("Nickname (optional)", text: $nickname)
                }
                Section {
                    TextField("Last 4 digits", text: $last4).keyboardType(.numberPad)
                        .onChange(of: last4) { last4 = String(last4.filter(\.isNumber).suffix(4)) }
                    TextField("More endings (optional)", text: $more).keyboardType(.numbersAndPunctuation)
                } footer: {
                    Text("Debit card number ending, if different, or a supplementary card. Separate with commas.")
                }
                if type == .current || type == .savings {
                    Toggle("Salary goes here", isOn: $salary)
                }
            }
            .navigationTitle(account == nil ? "Add an account or card" : "Edit account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(bankID == "other" && customBank.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let a = account {
                    bankID = a.bankID; customBank = a.customBankName; type = a.type; nickname = a.nickname
                    last4 = a.last4; more = a.otherEndingsRaw; salary = a.isSalaryAccount
                } else if let first = AppSettings.selectedBanks.first {
                    bankID = first
                }
            }
        }
    }

    private func save() {
        let a = account ?? Account(bankID: bankID, type: type)
        if account == nil { context.insert(a) }
        a.bankID = bankID; a.customBankName = bankID == "other" ? customBank : ""; a.type = type
        a.nickname = nickname.trimmingCharacters(in: .whitespaces); a.last4 = last4
        a.otherEndingsRaw = more.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "،" })
            .compactMap { AccountMatcher.normalizeEnding(String($0)) }.joined(separator: ",")
        a.isSalaryAccount = salary && (type == .current || type == .savings)
        if a.isSalaryAccount { accounts.filter { $0.id != a.id }.forEach { $0.isSalaryAccount = false } }
        if bankID != "other", !AppSettings.selectedBanks.contains(bankID) { AppSettings.selectedBanks.append(bankID) }
        try? context.save()
        dismiss()
    }
}

/// Settings › Your money › Who's at home: sets typical spending until Khurda has seen a month of yours.
struct HouseholdView: View {
    @State private var household = AppSettings.household
    @State private var car: Int = AppSettings.ownsCar.map { $0 ? 1 : 2 } ?? 0

    var body: some View {
        Form { Section {
            Picker("Who's at home", selection: $household) {
                Text("Just me").tag(Household.single)
                Text("Me and my partner").tag(Household.couple)
                Text("Family with children").tag(Household.family)
            }
            .pickerStyle(.inline)
            .onChange(of: household) { AppSettings.household = household }
            Picker("Do you have a car?", selection: $car) {
                Text("Not set").tag(0)
                Text("Yes").tag(1)
                Text("No").tag(2)
            }
            .onChange(of: car) { AppSettings.ownsCar = car == 0 ? nil : car == 1 }
        } footer: {
            Text("Used only for typical UAE spending, until Khurda has seen a full month of yours.")
        } }
        .themedBackground()
        .navigationTitle("Who's at home")
    }
}
