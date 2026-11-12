import Foundation
import UserNotifications
import SEQTAKit

/// The optional morning alert: on each school day with reminders, a notification at the reader's chosen time listing
/// them ("PE uniform · Take tuba"). They're scheduled ahead on the device as dated local notifications, which iOS
/// delivers on time without the app running; no server or background refresh is involved. Each child's alerts are
/// rescheduled whenever that child's timetable is loaded, and cover the two weeks it spans.
enum ReminderAlerts {
    static let enabledKey = "reminderAlertOn"
    /// Minutes after midnight; 7:00 by default.
    static let timeKey = "reminderAlertMinutes"
    static let defaultMinutes = 7 * 60
    private static let prefix = "reminder-"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var minutes: Int { UserDefaults.standard.object(forKey: timeKey) as? Int ?? defaultMinutes }

    /// Replaces one child's pending alerts with those for `reminders` ("yyyy-MM-dd" → notes). `childKey` identifies the
    /// child (account and child ID) so other children's alerts are left alone.
    static func schedule(_ reminders: [String: [ReminderNote]], childKey: String, childName: String) async {
        let center = UNUserNotificationCenter.current()
        await remove(prefix: prefix + childKey + "|")
        guard isEnabled else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let now = Date(), calendar = Calendar.current
        let firstName = childName.split(separator: " ").first.map(String.init) ?? childName
        for (dayKey, notes) in reminders where !notes.isEmpty {
            guard let day = formatter.date(from: dayKey),
                  let fire = calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: day)), fire > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(firstName) today"
            content.body = notes.map(\.text).joined(separator: " · ")
            content.sound = .default
            content.threadIdentifier = prefix + childKey
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let request = UNNotificationRequest(identifier: prefix + childKey + "|" + dayKey, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try? await center.add(request)
        }
    }

    /// Removes pending alerts: every child's, or (with `childKeyPrefix`) those of one account's children.
    static func removeAll(childKeyPrefix: String = "") async { await remove(prefix: prefix + childKeyPrefix) }

    private static func remove(prefix: String) async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Asks for permission to alert, if it hasn't been asked yet. Returns whether alerts can be delivered.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }
}
