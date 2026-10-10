import SwiftUI
import UserNotifications

struct PendingReadingRoute {
    let planID: String
    let token = UUID()
}

@MainActor
final class ReadingRouteHandler: ObservableObject {
    static let shared = ReadingRouteHandler()
    @Published var pending: PendingReadingRoute?
    func open(planID: String) { pending = PendingReadingRoute(planID: planID) }
    func open(url: URL) {
        guard let id = ReadingRoute.planID(from: url) else { return }
        open(planID: id)
    }
}

final class ReadingNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let id = response.notification.request.content.userInfo["planID"] as? String {
            Task { @MainActor in ReadingRouteHandler.shared.open(planID: id) }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
