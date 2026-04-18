import AppKit
import UserNotifications

@MainActor
enum NotificationService {
    /// Posts a user notification for a completed long-running task.
    /// No-ops when the app is frontmost — the in-app UI is already telling the user.
    /// Authorization is requested lazily the first time a notification would be shown.
    static func notify(title: String, body: String) {
        guard !NSApp.isActive else { return }

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()

            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
                guard granted else { return }
            case .denied:
                return
            case .authorized, .provisional, .ephemeral:
                break
            @unknown default:
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }
}
