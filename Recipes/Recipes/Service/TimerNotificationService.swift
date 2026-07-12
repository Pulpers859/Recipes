import Foundation
import UserNotifications

/// Schedules local notifications for cooking-mode timers so a finished timer
/// still reaches the cook when the phone is locked, face-down, or the app is
/// backgrounded — the in-app haptic alone is missed in all of those cases.
final class TimerNotificationService {
    static let shared = TimerNotificationService()
    private init() {}

    private static let deniedKey = "timer_notifications_denied"

    var isNotificationDenied: Bool {
        UserDefaults.standard.bool(forKey: Self.deniedKey)
    }

    private func identifier(for stepID: UUID) -> String {
        "cooking-timer-\(stepID.uuidString)"
    }

    /// Ask for permission the first time a timer is started, not at app
    /// launch, so the prompt appears in a context that explains itself.
    func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    UserDefaults.standard.set(!granted, forKey: Self.deniedKey)
                }
            case .denied:
                UserDefaults.standard.set(true, forKey: Self.deniedKey)
            default:
                UserDefaults.standard.set(false, forKey: Self.deniedKey)
            }
        }
    }

    /// Queries the live permission state (the cached UserDefaults flag lags
    /// the first-ever prompt) and reports on the main queue. Also refreshes
    /// the cached flag as a side effect.
    func notificationsDenied(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let denied = settings.authorizationStatus == .denied
            UserDefaults.standard.set(denied, forKey: Self.deniedKey)
            DispatchQueue.main.async { completion(denied) }
        }
    }

    func scheduleTimerNotification(stepID: UUID, label: String, recipeTitle: String, fireDate: Date) {
        let content = UNMutableNotificationContent()
        content.title = "\(label) finished"
        content.body = recipeTitle
        content.sound = .default
        // A cooking timer is exactly what time-sensitive is for: it should
        // break through Focus. The system downgrades it gracefully when the
        // entitlement isn't present.
        content.interruptionLevel = .timeSensitive

        let interval = max(fireDate.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: stepID),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if error != nil {
                // The in-app countdown still runs; leave a crash-clue trail
                // for "my timer never rang" reports.
                AnalyticsService.shared.track("timer_notification_schedule_failed")
            }
        }
    }

    func cancelTimerNotification(stepID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier(for: stepID)]
        )
    }
}
