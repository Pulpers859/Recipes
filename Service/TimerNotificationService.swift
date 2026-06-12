import Foundation
import UserNotifications

/// Schedules local notifications for cooking-mode timers so a finished timer
/// still reaches the cook when the phone is locked, face-down, or the app is
/// backgrounded — the in-app haptic alone is missed in all of those cases.
final class TimerNotificationService {
    static let shared = TimerNotificationService()
    private init() {}

    private func identifier(for stepID: UUID) -> String {
        "cooking-timer-\(stepID.uuidString)"
    }

    /// Ask for permission the first time a timer is started, not at app
    /// launch, so the prompt appears in a context that explains itself.
    func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func scheduleTimerNotification(stepID: UUID, label: String, recipeTitle: String, fireDate: Date) {
        let content = UNMutableNotificationContent()
        content.title = "\(label) finished"
        content.body = recipeTitle
        content.sound = .default

        let interval = max(fireDate.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: stepID),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    func cancelTimerNotification(stepID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier(for: stepID)]
        )
    }
}
