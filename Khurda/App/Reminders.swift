import Foundation
import SwiftData
import UserNotifications
import KhurdaCore

/// Local reminders for fixed bills and jameya shares: two days before, and on the day, at 10:00.
/// Nothing leaves the phone. Rebuilt whenever bills change and when the app comes to the front, so
/// the next due dates are always scheduled (iOS keeps at most 64 pending notifications).
enum Reminders {
    static let prefix = "khurda.due."

    @MainActor
    static func requestAndReschedule(context: ModelContext) {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            reschedule(context: context)
        }
    }

    struct Due {
        let id: String
        let title: String
        let amount: Decimal
        let date: Date
    }

    /// The next due date of each bill and each jameya share, within the next ~40 days.
    @MainActor
    static func upcoming(context: ModelContext, now: Date = .now) -> [Due] {
        let cal = Calendar.dubai
        var items: [Due] = []
        let horizon = cal.date(byAdding: .day, value: 40, to: now)!
        let today = cal.startOfDay(for: now)

        for bill in (try? context.fetch(FetchDescriptor<Obligation>())) ?? [] where !bill.isPaidThisCycle {
            if let d = nextDate(day: bill.dueDay, after: today, calendar: cal), d <= horizon {
                items.append(Due(id: "bill.\(bill.persistentModelID.hashValue)", title: bill.title, amount: bill.amount, date: d))
            }
        }
        let cycle = PayCycle.current(payday: AppSettings.payday, today: now)
        for j in (try? context.fetch(FetchDescriptor<Jameya>())) ?? [] {
            let s = j.schedule
            for r in 1...s.members {
                let d = s.dueDate(round: r)
                guard d >= today, d <= horizon else { continue }
                if j.isPaid(in: cycle), d < cycle.end { continue }
                items.append(Due(id: "jameya.\(j.persistentModelID.hashValue).\(r)", title: j.name, amount: j.share, date: d))
            }
        }
        return items.sorted { $0.date < $1.date }
    }

    @MainActor
    static func reschedule(context: ModelContext) {
        let items = upcoming(context: context)
        let center = UNUserNotificationCenter.current()
        Task {
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending)
            let cal = Calendar.dubai
            for item in items.prefix(30) {
                for before in [2, 0] {
                    guard let day = cal.date(byAdding: .day, value: -before, to: item.date),
                          var fire = cal.date(bySettingHour: 10, minute: 0, second: 0, of: day),
                          fire > .now else { continue }
                    fire = max(fire, .now.addingTimeInterval(60))
                    let content = UNMutableNotificationContent()
                    content.title = item.title
                    content.body = before == 0
                        ? String(localized: "Due today: \(Theme.aed(item.amount))")
                        : String(localized: "Due in 2 days: \(Theme.aed(item.amount))")
                    content.sound = .default
                    let comps = cal.dateComponents(in: cal.timeZone, from: fire)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    try? await center.add(UNNotificationRequest(identifier: "\(prefix)\(item.id).\(before)",
                                                                content: content, trigger: trigger))
                }
            }
        }
    }

    /// The next date on or after `after` whose day is `day` (clamped to the month's length).
    static func nextDate(day: Int, after: Date, calendar: Calendar) -> Date? {
        for monthOffset in 0...1 {
            guard let month = calendar.date(byAdding: .month, value: monthOffset, to: after) else { continue }
            var comps = calendar.dateComponents([.year, .month], from: month)
            comps.day = 1
            guard let first = calendar.date(from: comps) else { continue }
            let length = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
            comps.day = min(day, length)
            if let d = calendar.date(from: comps).map(calendar.startOfDay), d >= after { return d }
        }
        return nil
    }
}
