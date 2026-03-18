import SwiftUI
import UIKit
import BackgroundTasks
import UserNotifications
import WidgetKit
import StoreKit

extension Notification.Name {
    static let deepLinkReceived = Notification.Name("deepLinkReceived")
}

@main
struct AnemOuestApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.requestReview) private var requestReview

    init() {
        // Initialize analytics
        Analytics.initialize()

        // Register background tasks
        BackgroundTaskManager.shared.registerBackgroundTasks()

        // Track app open count for review prompt
        let count = UserDefaults.standard.integer(forKey: "appOpenCount") + 1
        UserDefaults.standard.set(count, forKey: "appOpenCount")
        Analytics.appOpened(count: count)

        // Warmup API endpoints to avoid cold starts (fire-and-forget HEAD requests)
        APIWarmup.fire()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .onAppear {
                    let count = UserDefaults.standard.integer(forKey: "appOpenCount")
                    if count == 3 {
                        requestReview()
                    }
                }
                .onOpenURL { url in
                    // Post notification for MainTabView to handle (it has AppState access)
                    NotificationCenter.default.post(name: .deepLinkReceived, object: url)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    Analytics.appBackgrounded()
                    // 1. Perform an immediate wind check (uses ~30s of background time)
                    BackgroundTaskManager.shared.performImmediateBackgroundCheck()
                    // 2. Schedule future background refreshes via BGTaskScheduler
                    BackgroundTaskManager.shared.scheduleWindCheck()
                    // 3. Schedule heavier processing (multi-model fetch, cache cleanup)
                    BackgroundTaskManager.shared.scheduleDataProcessing()
                }
        }
    }
}

// MARK: - Silent Push Token Manager

final class PushTokenManager {
    static let shared = PushTokenManager()
    private let tokenKey = "apnsDeviceToken"

    var deviceToken: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }

    /// Register token with your server (Vercel API)
    func registerTokenWithServer(_ token: String) {
        guard let url = URL(string: "https://api.levent.live/api/push/register") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "token": token,
            "platform": "ios"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                Log.error("Push token registration failed: \(error)")
            } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                Log.debug("Push token registered successfully")
            }
        }.resume()
    }
}

// MARK: - App Delegate for Notification Handling

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// When true, landscape orientation is allowed (webcam fullscreen only)
    static var allowLandscape = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Set notification delegate to show notifications in foreground
        UNUserNotificationCenter.current().delegate = self

        // Register for silent push notifications (widget refresh)
        application.registerForRemoteNotifications()

        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        // iPad: always allow landscape
        if UIDevice.current.userInterfaceIdiom == .pad {
            return [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight]
        }
        // iPhone: portrait only, except webcam fullscreen
        if AppDelegate.allowLandscape {
            return [.portrait, .landscapeLeft, .landscapeRight]
        }
        return .portrait
    }

    // MARK: - Remote Notifications (Silent Push)

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Convert token to hex string
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Log.debug("APNs device token: \(tokenString)")

        // Save and register with server
        PushTokenManager.shared.deviceToken = tokenString
        PushTokenManager.shared.registerTokenWithServer(tokenString)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Log.error("Failed to register for remote notifications: \(error)")
    }

    /// Handle silent push notification - refresh data and widget
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Log.debug("Received silent push notification")

        // Perform background data refresh
        Task {
            await BackgroundTaskManager.shared.performWindCheck()

            // Reload widget timelines
            WidgetCenter.shared.reloadAllTimelines()

            Log.debug("Silent push: data refreshed, widget reloaded")
            completionHandler(.newData)
        }
    }

    // MARK: - User Notifications

    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner, sound, and badge even when app is open
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification tap here if needed
        completionHandler()
    }
}
