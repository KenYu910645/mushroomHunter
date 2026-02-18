//
//  HoneyHubApp.swift
//  mushroomHunter
//
//  Purpose:
//  - Defines HoneyHub startup, Firebase setup, and app delegate wiring.
//
//  Defined in this file:
//  - HoneyHubApp entry point and AppDelegate notification handling.
//
import SwiftUI
import FirebaseCore
import GoogleSignIn
import FirebaseMessaging
import UserNotifications

@main
struct HoneyHubApp: App {
    /// Bridges UIKit app delegate callbacks into the SwiftUI lifecycle.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    /// Stores sign-in and profile completion state shared across root views.
    @StateObject private var session = UserSessionStore()

    /// Configures Firebase before any app view is rendered.
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .onOpenURL { url in
                    // Let GoogleSignIn handle the redirect back into the app
                    if GIDSignIn.sharedInstance.handle(url) {
                        return
                    }

                    if let roomId = RoomInviteLink.parseRoomId(from: url) {
                        NotificationCenter.default.post(name: .didOpenRoomFromPush, object: roomId)
                        return
                    }

                    if let postcardId = PostcardInviteLink.parsePostcardId(from: url) {
                        NotificationCenter.default.post(name: .didOpenPostcardFromLink, object: postcardId)
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    /// Requests notification permissions and configures Firebase Messaging delegate.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }
        Messaging.messaging().delegate = self
        return true
    }

    /// Forwards APNs device token to Firebase Cloud Messaging.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    /// Publishes refreshed FCM token so profile sync can upload it to backend.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        NotificationCenter.default.post(name: .didReceiveFcmToken, object: token)
    }

    /// Shows push notifications with banner/sound/badge while app is foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Routes notification tap events into the room deep-link channel.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let roomId = userInfo["roomId"] as? String ?? userInfo["room_id"] as? String {
            NotificationCenter.default.post(name: .didOpenRoomFromPush, object: roomId)
        }
        completionHandler()
    }
}
