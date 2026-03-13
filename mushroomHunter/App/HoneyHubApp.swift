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
    /// Stores in-app notification inbox state shared across tabs.
    @StateObject private var notificationInbox = EventInboxStore.shared
    /// Stores premium StoreKit product state and entitlement syncing.
    @StateObject private var premiumStore = PremiumStore.shared

    /// Configures Firebase before any app view is rendered.
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(notificationInbox)
                .environmentObject(premiumStore)
                .task(id: session.authUid) {
                    await premiumStore.handleSessionChange(session: session)
                }
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
    /// Push types that should update unresolved-action badge counts immediately on receipt.
    private let actionPushTypes: Set<String> = [
        "RAID_CONFIRM_ATTENDEE",
        "JOIN_REQUESTED_HOST",
        "POSTCARD_ORDER_SELLER",
        "POSTCARD_SENT_BUYER",
        "DAILY_REWARD_REMINDER"
    ]

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
        Task { @MainActor in
            EventInboxStore.shared.appendPushNotification(
                userInfo: notification.request.content.userInfo,
                title: notification.request.content.title,
                message: notification.request.content.body
            )
        }
        applyBadgeUpdateFromPush(
            userInfo: notification.request.content.userInfo,
            badgeNumber: notification.request.content.badge?.intValue
        )
        completionHandler([.banner, .sound, .badge])
    }

    /// Routes notification tap events into the room deep-link channel.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            EventInboxStore.shared.appendPushNotification(
                userInfo: response.notification.request.content.userInfo,
                title: response.notification.request.content.title,
                message: response.notification.request.content.body
            )
        }
        applyBadgeUpdateFromPush(
            userInfo: response.notification.request.content.userInfo,
            badgeNumber: response.notification.request.content.badge?.intValue
        )
        routePushNavigation(userInfo: response.notification.request.content.userInfo)
        completionHandler()
    }

    /// Applies the delivered badge count immediately and asks the SwiftUI shell to reconcile server counts.
    /// - Parameters:
    ///   - userInfo: APNs custom payload dictionary.
    ///   - badgeNumber: Delivered APS badge value when present.
    private func applyBadgeUpdateFromPush(userInfo: [AnyHashable: Any], badgeNumber: Int?) {
        let type = (userInfo["type"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard actionPushTypes.contains(type) else { return }

        if let badgeNumber {
            UIApplication.shared.applicationIconBadgeNumber = max(0, badgeNumber)
        }

        NotificationCenter.default.post(
            name: .didReceiveActionPushBadgeUpdate,
            object: badgeNumber
        )
    }

    /// Routes push-tap payload into room/postcard deep-link channels.
    /// - Parameter userInfo: APNs custom payload dictionary.
    private func routePushNavigation(userInfo: [AnyHashable: Any]) {
        let type = (userInfo["type"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let roomId = (userInfo["roomId"] as? String ?? userInfo["room_id"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let postcardId = (userInfo["postcardId"] as? String ?? userInfo["postcard_id"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let orderId = (userInfo["orderId"] as? String ?? userInfo["order_id"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if type == "DAILY_REWARD_REMINDER" {
            NotificationCenter.default.post(name: .didOpenDailyRewardReminder, object: nil)
            return
        }

        if roomId.isEmpty == false {
            if type == "RAID_CONFIRM_ATTENDEE" {
                NotificationCenter.default.post(name: .didOpenRoomConfirmationFromPush, object: roomId)
            } else {
                NotificationCenter.default.post(name: .didOpenRoomFromPush, object: roomId)
            }
            return
        }

        if (type == "POSTCARD_ORDER_SELLER" || type == "POSTCARD_SENT_BUYER"), postcardId.isEmpty == false {
            NotificationCenter.default.post(
                name: .didOpenPostcardOrderFromPush,
                object: ["postcardId": postcardId, "orderId": orderId]
            )
        } else if (type == "POSTCARD_RECEIVED_SELLER" || type == "POSTCARD_RECEIVED_BUYER"),
                  postcardId.isEmpty == false {
            NotificationCenter.default.post(name: .didOpenPostcardFromLink, object: postcardId)
        }
    }
}
