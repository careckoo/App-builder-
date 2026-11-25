import SwiftUI
import SwiftData
import KhurdaCore

/// "Teach Khurda": the message as tappable words. Tap the amount, then the shop name (or skip), pick
/// what kind of payment it is, and Khurda reads every message of that shape from now on. On the phone only.
struct TeachMessageView: View {
    let message: String
    let sender: String?
    /// The waiting message this came from, removed once it's read.
    var unread: UnreadMessage?
    var onDone: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amountWord: Int?
    @State private var shopWords: ClosedRange<Int>?
    @State private var shopAnchor: Int?
    @State private var noShop = false
    @State private var kind: TransactionKind = .purchase
    @State private var failed = false

    private var words: [Range<String.Index>] { Self.words(in: message) }
    private var step: Int { amountWord == nil ? 0 : (shopWords == nil && !noShop) ? 1 : 2 }

    var body: some View {
        Form {
            Section {
                Text(stepText).font(.headline)
                WordFlow(spacing: 6) {
                    ForEach(words.indices, id: \.self) { i in
                        Button { tap(i) } label: {
                            Text(message[words[i]])
                                .font(.callout)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(background(for: i), in: .rect(cornerRadius: 8))
                                .foregroundStyle(foreground(for: i))
                        }
                        .buttonStyle(.plain)
                        .disabled(step == 2)
                    }
                }
                .environment(\.layoutDirection, Self.isMostlyArabic(message) ? .rightToLeft : .leftToRight)
                .padding(.vertical, 4)
                if step == 1 {
                    Button("There's no shop name") { noShop = true }
                }
            } footer: {
                if step < 2 { Text("Tap a word again to undo. Nothing leaves your iPhone.") }
            }

            if step == 2 {
                Section("What is it?") {
                    Picker("Kind", selection: $kind) {
                        Text("Payment").tag(TransactionKind.purchase)
                        Text("Cash withdrawal").tag(TransactionKind.withdrawal)
                        Text("Transfer out").tag(TransactionKind.transferOut)
                        Text("Money in").tag(TransactionKind.income)
                        Text("Refund").tag(TransactionKind.refund)
                    }
                    .pickerStyle(.menu)
                }
                if let p = preview {
                    Section("Khurda will read") {
                        LabeledContent("Amount", value: "\(p.currency) \(p.amount.formatted(.number.precision(.fractionLength(2))))")
                        LabeledContent("Where", value: p.merchant ?? "—")
                    }
                }
                Section {
                    Button("Start again", role: .destructive) { reset() }
                }
            }
            if failed {
                Text("That doesn't look like an amount. Tap the number with the money in it.")
                    .foregroundStyle(Theme.over)
            }
        }
        .themedBackground()
        .navigationTitle("Teach Khurda")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(step < 2 || template == nil)
            }
        }
    }

    private var stepText: LocalizedStringKey {
        switch step {
        case 0: "1. Tap the amount"
        case 1: "2. Tap the first and last word of the shop name"
        default: "3. Check and save"
        }
    }

    // MARK: Selection

    private func tap(_ i: Int) {
        failed = false
        if step == 0 {
            if amountRange(word: i) == nil { failed = true } else { amountWord = i }
        } else if step == 1 {
            if i == amountWord { amountWord = nil; shopAnchor = nil; return }
            if let a = shopAnchor {
                shopWords = min(a, i)...max(a, i)
                if shopWords!.contains(amountWord!) { shopWords = nil; shopAnchor = nil; failed = true }
            } else {
                shopAnchor = i
            }
        }
    }

    private func reset() { amountWord = nil; shopWords = nil; shopAnchor = nil; noShop = false; failed = false }

    private func background(for i: Int) -> Color {
        if i == amountWord { return Theme.accent }
        if let r = shopWords, r.contains(i) { return Theme.highlight }
        if i == shopAnchor { return Theme.highlight.opacity(0.6) }
        return Theme.surfaceSecondary
    }
    private func foreground(for i: Int) -> Color { i == amountWord ? .white : Theme.textPrimary }

    // MARK: Ranges

    /// The number inside the tapped word ("AED45.50," → "45.50").
    private func amountRange(word i: Int) -> Range<String.Index>? {
        let w = words[i]
        guard let r = message.range(of: "[0-9٠-٩](?:[0-9٠-٩,٬.٫]*[0-9٠-٩])?", options: .regularExpression, range: w),
              AmountText.parse(String(message[r])) != nil else { return nil }
        return r
    }

    /// From the first to the last tapped word, without punctuation at either end ("LULU," → "LULU").
    private var shopRange: Range<String.Index>? {
        guard let r = shopWords else { return nil }
        var lo = words[r.lowerBound].lowerBound, hi = words[r.upperBound].upperBound
        while lo < hi, message[lo].isPunctuation { lo = message.index(after: lo) }
        while hi > lo, message[message.index(before: hi)].isPunctuation { hi = message.index(before: hi) }
        return lo < hi ? lo..<hi : nil
    }

    private var template: MessageTemplate? {
        guard let a = amountWord.flatMap(amountRange(word:)) else { return nil }
        return MessageTemplate.learn(message: message, amount: a, merchant: noShop ? nil : shopRange, kind: kind, sender: sender)
    }
    private var preview: ParsedTransaction? { template?.read(message, sender: sender) }

    @MainActor
    private func save() {
        guard let template else { return }
        // teach() reads (and removes) every waiting message of this shape, this one included.
        _ = try? TransactionLogger(context: context).teach(template, message: message, sender: sender)
        onDone()
        dismiss()
    }

    // MARK: Helpers

    static func words(in text: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var start: String.Index?
        for i in text.indices {
            if text[i].isWhitespace {
                if let s = start { out.append(s..<i); start = nil }
            } else if start == nil { start = i }
        }
        if let s = start { out.append(s..<text.endIndex) }
        return out
    }

    static func isMostlyArabic(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let arabic = letters.filter { (0x0600...0x06FF).contains($0.value) }
        return arabic.count * 2 > letters.count
    }
}

/// Words laid out like text: left to right (mirrored for Arabic), wrapping to new lines.
struct WordFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += line + spacing; line = 0 }
            x += s.width + spacing; line = max(line, s.height); widest = max(widest, x)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; line = max(line, s.height)
        }
    }
}

/// Messages that came in but weren't understood, with a way to teach Khurda or dismiss each one.
struct UnreadMessagesView: View {
    @Query(sort: \UnreadMessage.receivedAt, order: .reverse) private var unread: [UnreadMessage]
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            Section {
                ForEach(unread) { m in
                    NavigationLink {
                        TeachMessageView(message: m.text, sender: m.sender, unread: m)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.text).lineLimit(3).font(.callout)
                            Text("\(m.sender ?? "") \(m.receivedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { $0.forEach { context.delete(unread[$0]) }; try? context.save() }
            } footer: {
                Text("Bank messages Khurda couldn't read. Tap one and show Khurda the amount once; it reads every message like it from then on.")
            }
        }
        .themedBackground()
        .navigationTitle("Couldn't read")
        .overlay {
            if unread.isEmpty {
                ContentUnavailableView("All read", systemImage: "checkmark.bubble", description: Text("Every bank message so far was understood."))
            }
        }
    }
}

/// Settings › Learned messages: what Khurda was taught, with delete.
struct LearnedTemplatesView: View {
    @Query(sort: \LearnedTemplate.createdAt, order: .reverse) private var learned: [LearnedTemplate]
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            ForEach(learned) { t in
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.example).lineLimit(3).font(.callout)
                    Text("Read \(t.timesUsed) times since").font(.caption).foregroundStyle(.secondary)
                }
            }
            .onDelete { $0.forEach { context.delete(learned[$0]) }; try? context.save() }
        }
        .themedBackground()
        .navigationTitle("Learned messages")
        .overlay {
            if learned.isEmpty {
                ContentUnavailableView("Nothing learned yet", systemImage: "graduationcap",
                                       description: Text("When a bank message isn't understood, you can teach Khurda from Paste or from Activity."))
            }
        }
    }
}
