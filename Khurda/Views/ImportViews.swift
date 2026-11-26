import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers
import WidgetKit
import KhurdaCore

/// Import a bank or card statement (Excel, CSV or PDF): pick the file, check what Khurda read, import.
/// Everything is read on the phone.
@MainActor
struct ImportStatementView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Query(sort: \Account.createdAt) private var accounts: [Account]

    enum Step { case choose, review, done }
    @State private var step: Step = .choose
    @State private var picking = false
    @State private var error: LocalizedStringKey?
    @State private var fileName = ""
    @State private var format = "csv"
    @State private var analysis: StatementAnalysis?
    @State private var rows: [ReviewRow] = []
    @State private var accountID: UUID?
    @State private var filter = 0
    @State private var result: (added: Int, skipped: Int)?
    @State private var lockedURL: URL?
    @State private var password = ""

    struct ReviewRow: Identifiable {
        var row: StatementRow
        var category: CategoryID
        var include: Bool
        var duplicate: Bool
        var id: Int { row.id }
    }

    private var arabic: Bool { locale.language.languageCode == "ar" }
    private var shown: [Binding<ReviewRow>] {
        $rows.filter { r in filter == 0 ? !r.wrappedValue.duplicate : r.wrappedValue.duplicate }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .choose: chooseView
                case .review: reviewView
                case .done: doneView
                }
            }
            .themedBackground()
            .navigationTitle("Import a statement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step != .done { Button("Cancel") { dismiss() } }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: Self.types) { result in
                if case let .success(url) = result { read(url) }
            }
            .alert("This PDF is locked", isPresented: Binding(get: { lockedURL != nil }, set: { if !$0 { lockedURL = nil } })) {
                SecureField("Password", text: $password)
                Button("Open") { if let u = lockedURL { read(u, password: password) }; password = "" }
                Button("Cancel", role: .cancel) { password = "" }
            } message: {
                Text("Type its password. It stays on your phone and isn't saved.")
            }
        }
    }

    static let types: [UTType] = [.commaSeparatedText, .tabSeparatedText, .plainText, .pdf,
                                  UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data, UTType("com.microsoft.excel.xls") ?? .data]

    // MARK: Steps

    private var chooseView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 56)).foregroundStyle(Theme.accent)
            Text("Download a statement from your bank's app or website as Excel, CSV or PDF, then pick it here. Nothing leaves your iPhone.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if let error {
                Text(error).foregroundStyle(Theme.over).multilineTextAlignment(.center)
            }
            Button("Choose file", systemImage: "folder") { picking = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Text("Khurda finds the dates, amounts and shops by itself, works out what's money in and money out, sorts each one into a category and skips what you already have.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(28)
    }

    private var reviewView: some View {
        List {
            Section {
                Picker("This file is for", selection: $accountID) {
                    Text("No account").tag(UUID?.none)
                    ForEach(accounts.filter { !$0.isArchived }) { a in
                        Label(a.displayName(arabic: arabic), systemImage: a.type.symbol).tag(UUID?.some(a.id))
                    }
                }
                if let a = analysis, let range = a.dateRange {
                    LabeledContent("Period", value: "\(range.lowerBound.formatted(date: .abbreviated, time: .omitted)) – \(range.upperBound.formatted(date: .abbreviated, time: .omitted))")
                    LabeledContent("Money in", value: Theme.aed(a.moneyIn))
                    LabeledContent("Money out", value: Theme.aed(a.moneyOut))
                }
            } footer: {
                if accounts.isEmpty { Text("Add your accounts and cards in Settings so imports and messages are matched to them.") }
            }
            Section {
                Picker("Show", selection: $filter) {
                    Text("To add \(rows.filter { !$0.duplicate }.count)").tag(0)
                    Text("Already in Khurda \(rows.filter(\.duplicate).count)").tag(1)
                }
                .pickerStyle(.segmented)
                ForEach(shown) { $r in
                    ImportRowView(row: $r, arabic: arabic)
                }
            } footer: {
                Text("Untick anything you don't want. Tap the category to change it.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { importRows() } label: {
                Text("Import \(rows.filter(\.include).count)").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(!rows.contains(where: \.include))
            .padding()
            .background(.bar)
        }
    }

    private var doneView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(Theme.relaxed)
            if let result {
                Text("Added \(result.added) transactions").font(.title2.bold())
                if result.skipped > 0 { Text("Skipped \(result.skipped) you already had.").foregroundStyle(.secondary) }
            }
            Text("Your usual spending and daily target now include this history. See them in Plan and Insights.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
        }
        .padding(28)
    }

    // MARK: Reading

    private func read(_ url: URL, password: String? = nil) {
        error = nil
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        fileName = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        guard let data = try? Data(contentsOf: url) else { error = "We couldn't open this file."; return }
        guard data.count < 10_000_000 else { error = "This file is too big. Try a shorter period."; return }
        var found: StatementAnalysis?
        switch ext {
        case "xls":
            error = "This is an old Excel file (.xls). Open it in Numbers or Excel and save it as .xlsx or CSV."
            return
        case "xlsx":
            format = "xlsx"
            found = (try? SpreadsheetFiles.xlsx(data)).flatMap { StatementImporter.analyze(table: $0, hint: fileName) }
        case "pdf":
            format = "pdf"
            guard let doc = PDFDocument(data: data) else { error = "We couldn't open this file."; return }
            if doc.isLocked {
                if let password, doc.unlock(withPassword: password) {
                } else {
                    if password != nil { error = "That password didn't open it." }
                    lockedURL = url
                    return
                }
            }
            let lines = (0..<min(doc.pageCount, 60)).flatMap { i in
                (doc.page(at: i)?.string ?? "").components(separatedBy: .newlines)
            }
            if lines.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                error = "This PDF is a scan, so there's no text to read yet. Try the Excel or CSV version."
                return
            }
            found = StatementImporter.analyze(lines: lines, hint: fileName)
        default:
            format = "csv"
            found = SpreadsheetFiles.decodeText(data).flatMap { StatementImporter.analyze(table: SpreadsheetFiles.csv($0), hint: fileName) }
        }
        guard let found, !found.rows.isEmpty else {
            error = "We couldn't find a table of transactions in this file. Try the Excel or CSV version from your bank."
            return
        }
        analysis = found
        prepare(found)
        step = .review
    }

    @MainActor
    private func prepare(_ a: StatementAnalysis) {
        // The file's account: its bank and printed digits, or the card endings in its rows.
        let ending = a.accountLast4 ?? Dictionary(grouping: a.rows.compactMap(\.cardLast4), by: { $0 }).max { $0.value.count < $1.value.count }?.key
        let refs = accounts.filter { !$0.isArchived }.map(\.ref)
        accountID = AccountMatcher.match(bankName: a.bankName, ending: ending, kind: .purchase, among: refs)
            .flatMap { id in accounts.first { $0.id.uuidString == id }?.id }
        let logger = TransactionLogger(context: context)
        let categorizer = (try? logger.categorizer()) ?? Categorizer()
        let lo = (a.dateRange?.lowerBound ?? .now).addingTimeInterval(-3 * 86_400)
        let existing = ((try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.date >= lo }))) ?? [])
        let records = existing.map(\.record)
        let fingerprints = Set(existing.map(\.fingerprint))
        var seen: [String: Int] = [:]
        rows = a.rows.map { r in
            let aed = r.amount * (AppSettings.fxToAED[r.currency] ?? 1)
            let fp = Self.fingerprint(r, occurrence: &seen)
            let dup = fingerprints.contains(fp) || StatementImporter.isDuplicate(r, amountAED: aed, of: records)
            return ReviewRow(row: r, category: categorizer.category(for: r.parsed), include: !dup, duplicate: dup)
        }
    }

    static func fingerprint(_ r: StatementRow, occurrence: inout [String: Int]) -> String {
        let day = r.date.formatted(.iso8601.year().month().day())
        let base = "stmt|\(day)|\(r.amount)|\(r.kind.rawValue)|\(r.details.lowercased().filter { $0.isLetter || $0.isNumber })"
        let n = (occurrence[base] ?? 0) + 1
        occurrence[base] = n
        return "\(base)|\(n)"
    }

    // MARK: Import

    @MainActor
    private func importRows() {
        guard let a = analysis else { return }
        let batch = ImportBatch(fileName: fileName, format: format)
        batch.accountID = accountID
        batch.periodStart = a.dateRange?.lowerBound ?? .now
        batch.periodEnd = a.dateRange?.upperBound ?? .now
        context.insert(batch)
        let logger = TransactionLogger(context: context)
        let cycleStart = PayCycle.current(payday: AppSettings.payday).start
        let account = accounts.first { $0.id == accountID }
        var seen: [String: Int] = [:]
        var added = 0
        for r in rows {
            let fp = Self.fingerprint(r.row, occurrence: &seen)
            guard r.include else { continue }
            var parsed = r.row.parsed
            parsed.bankName = account?.bankName ?? a.bankName
            if account?.type == .creditCard, parsed.kind == .income { parsed.kind = .cardPayment }
            let tx = Transaction(parsed: parsed, category: r.category,
                                 amountAED: r.row.amount * (AppSettings.fxToAED[r.row.currency] ?? 1),
                                 source: r.row.details, via: .statement)
            tx.fingerprint = fp
            tx.accountID = accountID
            tx.importBatchID = batch.id
            if let b = r.row.balance { tx.balanceAfter = b }
            // Only this cycle's payments tick off this cycle's commitments.
            if tx.date >= cycleStart { try? logger.matchCommitment(tx) }
            context.insert(tx)
            added += 1
        }
        batch.added = added
        batch.skippedDuplicates = rows.filter(\.duplicate).count
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        result = (added, rows.count - added)
        step = .done
    }
}

private struct ImportRowView: View {
    @Binding var row: ImportStatementView.ReviewRow
    let arabic: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { row.include.toggle() } label: {
                Image(systemName: row.include ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(row.include ? Theme.accent : .secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(row.row.merchant ?? row.row.details).lineLimit(1).font(.body.weight(.medium))
                    Spacer()
                    Text((row.row.isExpense ? "" : "+") + Theme.aed(row.row.amount))
                        .monospacedDigit()
                        .foregroundStyle(row.row.isExpense ? Theme.textPrimary : Theme.relaxed)
                }
                HStack(spacing: 6) {
                    Text(row.row.date.formatted(.dateTime.day().month(.abbreviated)))
                    Menu {
                        ForEach(CategoryID.allCases, id: \.self) { c in
                            Button { row.category = c } label: { Label(arabic ? c.nameAR : c.nameEN, systemImage: c.symbol) }
                        }
                    } label: {
                        Label(arabic ? row.category.nameAR : row.category.nameEN, systemImage: row.category.symbol)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.surfaceSecondary, in: .capsule)
                    }
                    if row.duplicate { Text("Already in Khurda").foregroundStyle(Theme.carefulText) }
                }
                .font(.caption).foregroundStyle(.secondary)
                Text(row.row.details).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
            }
        }
        .opacity(row.include ? 1 : 0.55)
    }
}

/// Settings › Past imports: each file imported, with undo.
struct ImportHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ImportBatch.importedAt, order: .reverse) private var batches: [ImportBatch]
    @State private var undoing: ImportBatch?

    var body: some View {
        List {
            ForEach(batches) { b in
                VStack(alignment: .leading, spacing: 4) {
                    Text(b.fileName).lineLimit(1)
                    Text("\(b.added) added · \(b.importedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Undo import", role: .destructive) { undoing = b }
                }
            }
        }
        .themedBackground()
        .navigationTitle("Past imports")
        .overlay {
            if batches.isEmpty {
                ContentUnavailableView("No imports yet", systemImage: "square.and.arrow.down",
                                       description: Text("Import a statement from Activity or from here."))
            }
        }
        .confirmationDialog("Remove the transactions from this file?", isPresented: Binding(get: { undoing != nil }, set: { if !$0 { undoing = nil } }),
                            titleVisibility: .visible) {
            Button("Undo import", role: .destructive) { if let b = undoing { undo(b) } }
        }
    }

    private func undo(_ b: ImportBatch) {
        let id = b.id
        let txs = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.importBatchID == id }))) ?? []
        txs.forEach(context.delete)
        context.delete(b)
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
