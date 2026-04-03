import Foundation
import UserNotifications

/// Manages optional reminders for users to review their architecture.
@MainActor
enum ReviewReminderManager {
    private static let reminderIdentifier = "architectureReviewReminder"
    private static let reminderIntervalKey = "reviewReminderDays"

    /// Whether the user has enabled review reminders.
    static var isEnabled: Bool {
        UserDefaults.standard.integer(forKey: reminderIntervalKey) > 0
    }

    /// Current reminder interval in days (0 = disabled).
    static var intervalDays: Int {
        get { UserDefaults.standard.integer(forKey: reminderIntervalKey) }
        set { UserDefaults.standard.set(newValue, forKey: reminderIntervalKey) }
    }

    /// Request notification permission and schedule a recurring reminder.
    static func enableReminder(intervalDays: Int = 14) {
        self.intervalDays = intervalDays

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
                scheduleReminder(intervalDays: intervalDays)
            }
        }
    }

    /// Cancel and disable the reminder.
    static func disableReminder() {
        intervalDays = 0
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
    }

    /// Reschedule after a snapshot is saved (resets the timer).
    static func rescheduleIfEnabled() {
        guard isEnabled else { return }
        scheduleReminder(intervalDays: intervalDays)
    }

    private static func scheduleReminder(intervalDays: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Time for an Architecture Review"
        content.body = "It's been \(intervalDays) days since you last reviewed your project's architecture."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(intervalDays * 86400),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: reminderIdentifier,
            content: content,
            trigger: trigger
        )

        center.add(request)
    }
}
