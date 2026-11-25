import AppIntents
import SwiftData
import KhurdaCore

/// The action people add to their Shortcuts automation, for SMS or email:
///   Automation → Message → Sender is "ADCB" (or FAB, EmiratesNBD…) → Run Immediately
///   → Khurda "Log bank message or email" with the message content.
///   Automation → Email → Sender is the bank's alert address → Run Immediately → same action with the email body.
///
/// iOS does not let any app read SMS, email or other apps' notifications directly. These automations
/// are Apple's supported way: the person chooses which senders to forward, once, and after that every
/// bank alert is logged in the background without opening the app or typing a number.
/// The type name stays `LogBankMessageIntent` so automations people already made keep working.
struct LogBankMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "Log bank message or email"
    static let description = IntentDescription("Reads a bank SMS or alert email and adds the transaction to Khurda.",
                                               categoryName: "Tracking")
    static let openAppWhenRun = false

    @Parameter(title: "Message", inputOptions: String.IntentInputOptions(multiline: true))
    var message: String

    @Parameter(title: "Sender", default: nil)
    var sender: String?

    @Parameter(title: "Subject", default: nil)
    var subject: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$message)") {
            \.$sender
            \.$subject
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try TransactionLogger().log(message: message, sender: sender, subject: subject)
        return .result(dialog: LoggedDialog.text(for: outcome))
    }
}

/// Logs an Apple Pay purchase. Set up once:
///   Automation → Transaction → choose cards → Run Immediately → Khurda "Log Apple Pay purchase"
///   with Amount, Merchant and Card or Pass from the Shortcut Input.
/// This works for any bank's card in Wallet, including banks that only send in-app notifications.
struct LogWalletTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Apple Pay purchase"
    static let description = IntentDescription("Adds an Apple Pay purchase from the Wallet Transaction automation to Khurda.",
                                               categoryName: "Tracking")
    static let openAppWhenRun = false

    /// Text, not a number: Shortcuts passes the Wallet amount formatted for the phone's language,
    /// e.g. "AED 45.50" or "د.إ.‏ ٤٥٫٥٠".
    @Parameter(title: "Amount")
    var amount: String

    /// Optional so a purchase without a merchant name still logs instead of stopping to ask.
    @Parameter(title: "Merchant", default: nil)
    var merchant: String?

    @Parameter(title: "Card", default: nil)
    var card: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant)") { \.$card }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try TransactionLogger().logWallet(amountText: amount, merchant: merchant, card: card)
        return .result(dialog: LoggedDialog.text(for: outcome))
    }
}

/// What the Shortcut says after logging, shared by the message and Apple Pay actions.
enum LoggedDialog {
    @MainActor
    static func text(for outcome: TransactionLogger.Outcome) -> IntentDialog {
        switch outcome {
        case let .saved(tx, safe):
            let amount = tx.amount.formatted(.number.precision(.fractionLength(2)))
            let left = safe.today.formatted(.number.precision(.fractionLength(0)))
            let where_ = tx.merchant.isEmpty ? "" : " · \(tx.merchant)"
            if tx.isExpense {
                return "\(tx.currency) \(amount)\(where_). Left today: AED \(left)"
            } else if tx.kind == .cardPayment {
                return "Card bill payment of \(tx.currency) \(amount) logged. It doesn't change today's amount."
            } else if tx.kind == .ownTransfer {
                return "Moved \(tx.currency) \(amount) between your accounts. It doesn't change today's amount."
            } else {
                return "+\(tx.currency) \(amount)\(where_)"
            }
        case .merged:
            // Apple Pay and the bank's SMS or email reported the same purchase.
            return "Already logged. Added the bank's details to it."
        case .duplicate:
            return "Already logged"
        case .notATransaction:
            // OTPs, promos and declined payments end up here on purpose.
            return "Not a transaction, skipped"
        case .keptToTeach:
            return "Khurda couldn't read this one yet. It's waiting in Activity: tap it once to teach Khurda."
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
        // Same as the widget and the home screen: never say a negative amount.
        let value = max(0, NSDecimalNumber(decimal: safe.today).doubleValue)
        return .result(value: value, dialog: "You can spend AED \(Int(value)) today, \(safe.daysLeft) days to payday.")
    }
}

/// Makes the actions appear in the Shortcuts app straight after install, in English and Arabic.
struct KhurdaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogWalletTransactionIntent(),
                    phrases: ["Log Apple Pay purchase in \(.applicationName)"],
                    shortTitle: "Log Apple Pay purchase", systemImageName: "wallet.pass.fill")
        AppShortcut(intent: LogBankMessageIntent(),
                    phrases: ["Log bank message in \(.applicationName)",
                              "Log bank email in \(.applicationName)"],
                    shortTitle: "Log bank message or email", systemImageName: "text.bubble.fill")
        AppShortcut(intent: SafeToSpendTodayIntent(),
                    phrases: ["How much can I spend today in \(.applicationName)",
                              "\(.applicationName) safe to spend"],
                    shortTitle: "Safe to spend", systemImageName: "gauge.with.dots.needle.67percent")
    }
}
