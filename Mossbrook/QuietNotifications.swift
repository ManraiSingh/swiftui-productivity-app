import UserNotifications

/// Decides how Mossbrook's own notifications show up while the app is open.
/// In strict mode they skip the banner and sound and wait quietly in Notification Center.
final class QuietNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = QuietNotifications()

    /// Set while strict mode is on screen.
    static var strictModeOn = false

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.strictModeOn ? [.list] : [.banner, .sound, .list])
    }
}
