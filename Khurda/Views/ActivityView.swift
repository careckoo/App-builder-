import SwiftUI
import SwiftData
import WidgetKit
import KhurdaCore

/// Every transaction, grouped by day, with search. Tap one to change its category.
struct ActivityView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var unread: [UnreadMessage]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Environment(\.locale) private var locale
    @State private var search = ""
    @State private var accountFilter: UUID?
    @State private var importing = false

    private var filtered: [Transaction] {
        let byAccount = accountFilter.map { id in transactions.filter { $0.accountID == id } } ?? transactions
        guard !search.isEmpty else { return byAccount }
        return byAccount.filter {
            $0.merchant.localizedCaseInsensitiveContains(search)
                || $0.category.nameEN.localizedCaseInsensitiveContains(search)
                || $0.category.nameAR.contains(search)
        }
    }

    private var days: [(Date, [Transaction])] {
        let groups = Dictionary(grouping: filtered) { Calendar.dubai.startOfDay(for: $0.date) }
        return groups.map { ($0.key, $0.value) }.sorted { $0.0 > $1.0 }
    }

    var body: some View {
        NavigationStack {
            List {
                if !unread.isEmpty && search.isEmpty {
                    Section {
                        NavigationLink { UnreadMessagesView() } label: {
                            Label("Messages we couldn't read: \(unread.count)", systemImage: "questionmark.bubble.fill")
                                .foregroundStyle(Theme.carefulText)
                        }
                    }
                }
                ForEach(days, id: \.0) { day, items in
                    Section {
                        ForEach(items) { tx in
                            NavigationLink { TransactionDetailView(tx: tx) } label: { TransactionRow(tx: tx) }
                        }
                    } header: {
                        HStack {
                            Text(day.formatted(.dateTime.weekday(.wide).day().month()))
                            Spacer()
                            let total = items.filter(\.isExpense).reduce(Decimal(0)) { $0 + $1.amountAED }
                            Text(Theme.aed(total)).monospacedDigit()
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search merchants or categories")
            .themedBackground()
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import", systemImage: "square.and.arrow.down") { importing = true }
                }
                if accounts.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("Account", selection: $accountFilter) {
                                Text("All accounts").tag(UUID?.none)
                                ForEach(accounts) { a in
                                    Label(a.displayName(arabic: locale.language.languageCode == "ar"), systemImage: a.type.symbol).tag(UUID?.some(a.id))
                                }
                            }
                        } label: {
                            Image(systemName: accountFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        }
                    }
                }
            }
            .sheet(isPresented: $importing) { ImportStatementView() }
            .overlay {
                if transactions.isEmpty && unread.isEmpty {
                    ContentUnavailableView("Nothing yet", systemImage: "tray",
                                           description: Text("Finish the Shortcuts setup and your next card payment will show up here."))
                }
            }
        }
    }
}

struct TransactionDetailView: View {
    @Bindable var tx: Transaction
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var rememberChoice = true

    var body: some View {
        Form {
            Section {
                LabeledContent("Amount", value: "\(tx.currency) \(tx.amount.formatted(.number.precision(.fractionLength(2))))")
                if tx.currency != "AED" { LabeledContent("Approximately", value: Theme.aed(tx.amountAED, decimals: 2)) }
                TextField("Merchant", text: $tx.merchant)
                if let card = cardText { LabeledContent("Card", value: card) }
                if let bank = tx.bankName { LabeledContent("Bank", value: bank) }
                if !accounts.isEmpty {
                    Picker("Account", selection: $tx.accountID) {
                        Text("Not set").tag(UUID?.none)
                        ForEach(accounts) { Text($0.displayName(arabic: locale.language.languageCode == "ar")).tag(UUID?.some($0.id)) }
                    }
                }
                LabeledContent("Date", value: tx.date.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("From") { Text(sourceLabel) }
            }
            Section("Category") {
                Picker("Category", selection: Binding(get: { tx.category }, set: { setCategory($0) })) {
                    ForEach(CategoryID.allCases, id: \.self) { c in
                        Label(locale.language.languageCode == "ar" ? c.nameAR : c.nameEN, systemImage: c.symbol).tag(c)
                    }
                }
                .pickerStyle(.navigationLink)
                Toggle("Always use this for \(tx.merchant)", isOn: $rememberChoice).disabled(tx.merchant.isEmpty)
                Toggle("This is a fixed bill (rent, school, installment)", isOn: $tx.isFixedObligation)
            }
            Section("Note") { TextField("Add a note", text: $tx.note, axis: .vertical) }
            if let source = tx.sourceMessage {
                Section {
                    Text(source).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                } header: { Text("Original message") } footer: { Text("Stored only on this iPhone.") }
            }
            Section {
                Button("Delete transaction", role: .destructive) { delete() }
            }
        }
        .navigationTitle(tx.merchant.isEmpty ? String(localized: "Transaction") : tx.merchant)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "FAB Cashback •••• 1234", "•••• 1234" or "FAB Cashback".
    private var cardText: String? {
        switch (tx.cardName, tx.cardLast4) {
        case let (name?, last4?) where !name.hasSuffix(last4): "\(name) •••• \(last4)"
        case let (name?, _): name
        case let (nil, last4?): "•••• \(last4)"
        case (nil, nil): nil
        }
    }

    private var sourceLabel: LocalizedStringKey {
        switch tx.source {
        case .wallet: "Apple Pay"
        case .sms: "SMS"
        case .email: "Email"
        case .manual: "Added by hand"
        case .statement: "Bank statement"
        }
    }

    /// Leave the screen first, then delete: this view must not render a deleted model.
    private func delete() {
        let doomed = tx
        let context = context
        dismiss()
        Task { @MainActor in
            // Let the pop animation finish before the object disappears from the store.
            try? await Task.sleep(for: .milliseconds(400))
            context.delete(doomed)
            try? context.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func setCategory(_ c: CategoryID) {
        tx.category = c
        guard rememberChoice, !tx.merchant.isEmpty else { return }
        // One rule per merchant: update it if it exists, otherwise add it.
        let keyword = tx.merchant.lowercased()
        let existing = try? context.fetch(FetchDescriptor<MerchantRule>(predicate: #Predicate { $0.keyword == keyword }))
        if let rule = existing?.first {
            rule.categoryRaw = c.rawValue
            existing?.dropFirst().forEach { context.delete($0) }   // clean up duplicates from older versions
        } else {
            context.insert(MerchantRule(keyword: tx.merchant, category: c))
        }
        // Apply the same choice to earlier purchases at this merchant.
        let name = tx.merchant
        if let same = try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.merchant == name })) {
            same.forEach { $0.category = c }
        }
    }
}
