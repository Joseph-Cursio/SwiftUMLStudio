import Foundation
import UserNotifications

/// Manages optional reminders for users to review their architecture.
@MainActor
enum ReviewReminderManager {
    private static let reminderIdentifier = "architectureReviewReminder"
    private static let reminderIntervalKey = "reviewReminderDays"

    /// Whether the user has enabled review reminders.
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: reminderIntervalKey) > 0
    }

    /// Current reminder interval in days (0 = disabled).
    static func intervalDays(defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: reminderIntervalKey)
    }

    /// Set the reminder interval in days.
    static func setIntervalDays(_ value: Int, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: reminderIntervalKey)
    }

    /// Request notification permission and schedule a recurring reminder.
    static func enableReminder(intervalDays: Int = 14, defaults: UserDefaults = .standard) {
        setIntervalDays(intervalDays, defaults: defaults)

        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            if granted {
                scheduleReminder(intervalDays: intervalDays)
            }
        }
    }

    /// Cancel and disable the reminder.
    static func disableReminder(defaults: UserDefaults = .standard) {
        setIntervalDays(0, defaults: defaults)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
    }

    /// Reschedule after a snapshot is saved (resets the timer).
    static func rescheduleIfEnabled(defaults: UserDefaults = .standard) {
        guard isEnabled(defaults: defaults) else { return }
        scheduleReminder(intervalDays: intervalDays(defaults: defaults))
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
