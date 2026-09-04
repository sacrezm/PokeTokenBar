import Foundation
import UserNotifications

/// Native banners remain available while the popover is closed. The menu badge
/// is independent of notification permission and Focus settings.
@MainActor
final class TradingNotifications: NSObject, UNUserNotificationCenterDelegate {
    var onOpenTrade: (() -> Void)?

    func install() {
        guard AppEnv.isBundledApp else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    func send(_ activity: TradingActivity) {
        guard AppEnv.isBundledApp else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = activity.title
            content.body = activity.body
            content.sound = .default
            content.userInfo = ["poketokenbarTrade": true]
            try? await center.add(UNNotificationRequest(identifier: activity.id, content: content, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(notification.request.content.userInfo["poketokenbarTrade"] as? Bool == true
                          ? [.banner, .sound] : [])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           response.notification.request.content.userInfo["poketokenbarTrade"] as? Bool == true {
            Task { @MainActor [weak self] in self?.onOpenTrade?() }
        }
        completionHandler()
    }
}
