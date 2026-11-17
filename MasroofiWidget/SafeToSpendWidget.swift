import WidgetKit
import SwiftUI
import SwiftData
import MasroofiCore

/// Home Screen and Lock Screen widget: today's safe-to-spend number.
/// Reloaded by `TransactionLogger` every time a bank message is logged.
struct SafeToSpendEntry: TimelineEntry {
    let date: Date
    let safe: SafeToSpend?
}

struct SafeToSpendProvider: TimelineProvider {
    func placeholder(in context: Context) -> SafeToSpendEntry {
        SafeToSpendEntry(date: .now, safe: .compute(income: 15000, fixedObligations: 7000, savingsGoal: 1500,
                                                    spentBeforeToday: 2000, spentToday: 80, daysLeft: 18))
    }

    func getSnapshot(in context: Context, completion: @escaping (SafeToSpendEntry) -> Void) {
        Task { @MainActor in completion(SafeToSpendEntry(date: .now, safe: try? SafeToSpendCalculator(context: Store.container.mainContext).current())) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SafeToSpendEntry>) -> Void) {
        Task { @MainActor in
            let entry = SafeToSpendEntry(date: .now, safe: try? SafeToSpendCalculator(context: Store.container.mainContext).current())
            // Refresh just after midnight in the UAE, when a new day's amount starts.
            let midnight = Calendar.dubai.startOfDay(for: .now.addingTimeInterval(86_400)).addingTimeInterval(60)
            completion(Timeline(entries: [entry], policy: .after(midnight)))
        }
    }
}

struct SafeToSpendWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SafeToSpendEntry

    var body: some View {
        if let safe = entry.safe {
            switch family {
            case .accessoryCircular:
                Gauge(value: max(0, NSDecimalNumber(decimal: safe.today).doubleValue),
                      in: 0...max(1, NSDecimalNumber(decimal: safe.dailyAllowance).doubleValue)) {
                    Text("AED")
                } currentValueLabel: {
                    Text(Int(truncating: NSDecimalNumber(decimal: max(0, safe.today))), format: .number)
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryInline:
                Text("Today: \(Theme.aed(max(0, safe.today)))")
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Text("Safe to spend today").font(.caption).foregroundStyle(.secondary)
                    Text(Theme.aed(max(0, safe.today)))
                        .font(.system(.title, design: .rounded).bold())
                        .foregroundStyle(Theme.color(for: safe.status))
                        .minimumScaleFactor(0.6)
                    Spacer()
                    Text("\(safe.daysLeft) days to payday").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Open Masroofi to finish setup").font(.caption)
        }
    }
}

@main
struct SafeToSpendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SafeToSpend", provider: SafeToSpendProvider()) { entry in
            SafeToSpendWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Safe to spend")
        .description("How much you can spend today and still reach payday.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}
