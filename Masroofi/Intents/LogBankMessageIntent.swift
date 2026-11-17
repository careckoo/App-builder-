import AppIntents
import SwiftData
import MasroofiCore

/// The action people add to their Shortcuts automation:
///   Automation → Message → Sender is "ADCB" (or FAB, EmiratesNBD…) → Run Immediately
///   → Masroofi "Log bank message" with the message content.
///
/// iOS does not let any app read SMS directly. This automation is Apple's supported way:
/// the person chooses which senders to forward, once, and after that every bank alert is
/// logged in the background without opening the app or typing a number.
struct LogBankMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Log bank message"
    static let description = IntentDescription("Reads a bank SMS and adds the transaction to Masroofi.",
                                               categoryName: "Tracking")
    static let openAppWhenRun = false

    @Parameter(title: "Message", inputOptions: String.IntentInputOptions(multiline: true))
    var message: String

    @Parameter(title: "Sender", default: nil)
    var sender: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$message)") { \.$sender }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch try TransactionLogger().log(message: message, sender: sender) {
        case let .saved(tx, safe):
            let amount = tx.amount.formatted(.number.precision(.fractionLength(2)))
            let left = safe.today.formatted(.number.precision(.fractionLength(0)))
            let where_ = tx.merchant.isEmpty ? "" : " · \(tx.merchant)"
            if tx.isExpense {
                return .result(dialog: "\(tx.currency) \(amount)\(where_). Left today: AED \(left)")
            } else {
                return .result(dialog: "+\(tx.currency) \(amount)\(where_)")
            }
        case .duplicate:
            return .result(dialog: "Already logged")
        case .notATransaction:
            // OTPs, promos and declined payments end up here on purpose.
            return .result(dialog: "Not a transaction, skipped")
        }
    }
}

/// "How much can I spend today?" — for Siri, Spotlight and the Action button.
struct SafeToSpendTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Safe to spend today"
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let safe = try SafeToSpendCalculator(context: Store.container.mainContext).current()
        let value = NSDecimalNumber(decimal: safe.today).doubleValue
        return .result(value: value, dialog: "You can spend AED \(Int(value)) today, \(safe.daysLeft) days to payday.")
    }
}

/// Makes both actions appear in the Shortcuts app straight after install, in English and Arabic.
struct MasroofiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogBankMessageIntent(),
                    phrases: ["Log bank message in \(.applicationName)"],
                    shortTitle: "Log bank message", systemImageName: "text.bubble.fill")
        AppShortcut(intent: SafeToSpendTodayIntent(),
                    phrases: ["How much can I spend today in \(.applicationName)",
                              "\(.applicationName) safe to spend"],
                    shortTitle: "Safe to spend", systemImageName: "gauge.with.dots.needle.67percent")
    }
}
