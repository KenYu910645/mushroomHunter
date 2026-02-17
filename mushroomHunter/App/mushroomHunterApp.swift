//
//  mushroomHunterApp.swift
//  mushroomHunter
//
//  Purpose:
//  - Defines application startup, Firebase setup, and app delegate wiring.
//
//  Defined in this file:
//  - mushroomHunterApp entry point and AppDelegate notification handling.
//
import SwiftUI
import FirebaseCore
import GoogleSignIn
import FirebaseMessaging
import UserNotifications

@main
struct mushroomHunterApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var session = SessionStore() // State or dependency property.
    init() { // Initializes this type.
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
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
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

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) { // Handles application flow.
        Messaging.messaging().apnsToken = deviceToken
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) { // Handles messaging flow.
        guard let token = fcmToken else { return }
        NotificationCenter.default.post(name: .didReceiveFcmToken, object: token)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

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
