import SwiftUI
import SwiftData
import Charts
import SarfiCore

/// The "Plan" tab: where the money went this pay cycle, category budgets, and fixed bills.
struct BudgetsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Query private var transactions: [Transaction]
    @Query(sort: \Budget.limit, order: .reverse) private var budgets: [Budget]
    @Query(sort: \Obligation.dueDay) private var obligations: [Obligation]
    @State private var addingBudget = false
    @State private var addingBill = false

    private var cycle: PayCycle { .current(payday: AppSettings.payday) }

    private var spentByCategory: [(CategoryID, Decimal)] {
        let inCycle = transactions.filter { $0.isExpense && $0.date >= cycle.start }
        let grouped = Dictionary(grouping: inCycle, by: \.category)
            .mapValues { $0.reduce(Decimal(0)) { $0 + $1.amountAED } }
        return grouped.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    private func name(_ c: CategoryID) -> String { locale.language.languageCode == "ar" ? c.nameAR : c.nameEN }

    var body: some View {
        NavigationStack {
            List {
                if !spentByCategory.isEmpty {
                    Section("This pay cycle") {
                        Chart(spentByCategory, id: \.0) { item in
                            SectorMark(angle: .value("AED", NSDecimalNumber(decimal: item.1).doubleValue),
                                       innerRadius: .ratio(0.62), angularInset: 1.5)
                                .foregroundStyle(by: .value("Category", name(item.0)))
                                .cornerRadius(4)
                        }
                        .frame(height: 220)
                        .padding(.vertical, 8)
                    }
                }

                Section {
                    ForEach(budgets) { b in
                        let spent = spentByCategory.first { $0.0 == b.category }?.1 ?? 0
                        BudgetRow(name: name(b.category), symbol: b.category.symbol, spent: spent, limit: b.limit)
                    }
                    .onDelete { $0.forEach { context.delete(budgets[$0]) } }
                    Button("Add a budget", systemImage: "plus") { addingBudget = true }
                } header: { Text("Budgets") }

                Section {
                    ForEach(obligations) { bill in
                        HStack {
                            Image(systemName: bill.isPaidThisCycle ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(bill.isPaidThisCycle ? Theme.relaxed : .secondary)
                            VStack(alignment: .leading) {
                                Text(bill.title)
                                Text("Due on the \(bill.dueDay)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Theme.aed(bill.amount)).monospacedDigit()
                        }
                    }
                    .onDelete { $0.forEach { context.delete(obligations[$0]) } }
                    Button("Add a fixed bill", systemImage: "plus") { addingBill = true }
                } header: { Text("Fixed bills") } footer: {
                    Text("Rent, school fees, DEWA or TAQA, Tabby and Tamara installments. They're set aside before your daily amount is worked out, and ticked off when the bank message arrives.")
                }
            }
            .navigationTitle("Plan")
            .sheet(isPresented: $addingBudget) { AddBudgetView() }
            .sheet(isPresented: $addingBill) { AddBillView() }
        }
    }
}

struct BudgetRow: View {
    let name: String, symbol: String, spent: Decimal, limit: Decimal
    private var ratio: Double { limit == 0 ? 0 : NSDecimalNumber(decimal: spent / limit).doubleValue }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(name, systemImage: symbol)
                Spacer()
                Text("\(Theme.aed(spent)) / \(Theme.aed(limit))").font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: min(ratio, 1))
                .tint(ratio > 1 ? Theme.over : ratio > 0.8 ? Theme.careful : Theme.accent)
        }
        .padding(.vertical, 4)
    }
}

struct AddBudgetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @State private var category: CategoryID = .delivery
    @State private var limit: Decimal = 500

    var body: some View {
        NavigationStack {
            Form {
                Picker("Category", selection: $category) {
                    ForEach(CategoryID.allCases.filter { $0 != .income }, id: \.self) {
                        Text(locale.language.languageCode == "ar" ? $0.nameAR : $0.nameEN).tag($0)
                    }
                }
                TextField("Monthly limit (AED)", value: $limit, format: .number).keyboardType(.decimalPad)
            }
            .navigationTitle("Add a budget")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { context.insert(Budget(category: category, limit: limit)); dismiss() }
                }
            }
        }
    }
}

struct AddBillView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var amount: Decimal = 0
    @State private var dueDay = 1

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name, e.g. Rent", text: $title)
                TextField("Amount (AED)", value: $amount, format: .number).keyboardType(.decimalPad)
                Stepper("Due on the \(dueDay)", value: $dueDay, in: 1...31)
            }
            .navigationTitle("Add a fixed bill")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(Obligation(title: title, amount: amount, dueDay: dueDay, category: .bills))
                        dismiss()
                    }
                    .disabled(title.isEmpty || amount <= 0)
                }
            }
        }
    }
}
