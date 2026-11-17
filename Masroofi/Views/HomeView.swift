import SwiftUI
import SwiftData
import MasroofiCore

/// The first screen: one number, a ring, and today's spending. Everything else is one tap away.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var safe: SafeToSpend?
    @State private var showPaste = false

    private var todays: [Transaction] {
        let start = Calendar.dubai.startOfDay(for: .now)
        return transactions.filter { $0.date >= start }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let safe { SafeToSpendRing(safe: safe).padding(.top, 8) }

                    if let safe {
                        HStack(spacing: 12) {
                            StatTile(title: "Left until payday", value: Theme.aed(safe.leftForCycle))
                            StatTile(title: "Days to payday", value: "\(safe.daysLeft)")
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Today").font(.title3.bold())
                        if todays.isEmpty {
                            ContentUnavailableView("No spending yet today",
                                                   systemImage: "sparkles",
                                                   description: Text("Bank messages appear here by themselves."))
                        } else {
                            ForEach(todays) { TransactionRow(tx: $0) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("Masroofi")
            .toolbar {
                Button { showPaste = true } label: { Label("Paste a message", systemImage: "doc.on.clipboard") }
            }
            .sheet(isPresented: $showPaste) { PasteMessageView() }
            .task(id: transactions.count) { safe = try? SafeToSpendCalculator(context: context).current() }
        }
    }
}

struct SafeToSpendRing: View {
    let safe: SafeToSpend

    private var progress: Double {
        guard safe.dailyAllowance > 0 else { return 1 }
        let spent = safe.dailyAllowance - safe.today
        return min(1, max(0, NSDecimalNumber(decimal: spent / safe.dailyAllowance).doubleValue))
    }

    private var message: LocalizedStringKey {
        switch safe.status {
        case .relaxed: "You're doing great"
        case .onTrack: "On track"
        case .careful: "Go easy for the rest of today"
        case .over: "Over today's amount — tomorrow adjusts"
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 18)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.color(for: safe.status), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.8), value: progress)
            VStack(spacing: 4) {
                Text("Safe to spend today").font(.subheadline).foregroundStyle(.secondary)
                Text(Theme.aed(max(0, safe.today)))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                Text(message).font(.footnote.weight(.medium)).foregroundStyle(Theme.color(for: safe.status))
            }
            .padding(36)
        }
        .frame(width: 270, height: 270)
        .accessibilityElement(children: .combine)
    }
}

struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }
}

struct TransactionRow: View {
    let tx: Transaction
    @Environment(\.locale) private var locale

    private var categoryName: String { locale.language.languageCode == "ar" ? tx.category.nameAR : tx.category.nameEN }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tx.category.symbol)
                .font(.body)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.12), in: .circle)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.merchant.isEmpty ? categoryName : tx.merchant).font(.body.weight(.medium)).lineLimit(1)
                Text("\(categoryName) · \(tx.date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text((tx.isExpense ? "−" : "+") + tx.amount.formatted(.number.precision(.fractionLength(2))))
                    .font(.body.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(tx.isExpense ? Color.primary : Theme.relaxed)
                Text(tx.currency).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// For banks or messages the automation missed: paste the SMS, see what was understood, save.
struct PasteMessageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var result: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text).frame(minHeight: 140)
                } footer: {
                    Text("Paste a bank SMS in Arabic or English.")
                }
                if let preview = BankMessageParser().parse(text) {
                    Section("We understood") {
                        LabeledContent("Amount", value: "\(preview.currency) \(preview.amount)")
                        LabeledContent("Where", value: preview.merchant ?? "—")
                        LabeledContent("Card", value: preview.cardLast4.map { "•••• \($0)" } ?? "—")
                    }
                } else if !text.isEmpty {
                    Text("This doesn't look like a transaction.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Paste a message")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        _ = try? TransactionLogger(context: context).log(message: text, sender: nil)
                        dismiss()
                    }
                    .disabled(BankMessageParser().parse(text) == nil)
                }
            }
            .onAppear { if let clip = UIPasteboard.general.string { text = clip } }
        }
    }
}
