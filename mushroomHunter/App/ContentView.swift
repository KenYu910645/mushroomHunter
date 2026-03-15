//
//  ContentView.swift
//  mushroomHunter
//
//  Purpose:
//  - Defines the app root view and top-level tab/sign-in routing.
//
//  Defined in this file:
//  - ContentView and themed background helpers used by the app shell.
//
import SwiftUI
import Combine
import UIKit

// MARK: - App Root

struct ContentView: View {
    @EnvironmentObject private var session: UserSessionStore // State or dependency property.
    var body: some View {
        ZStack {
            ThemedBackground()
            Group {
                if session.isLoggedIn || AppTesting.isUITesting {
                    if session.isProfileComplete || AppTesting.isUITesting {
                        MainTabView()
                    } else {
                        ProfileCreateEditView(mode: .create)
                    }
                } else {
                    LoginView()
                }
            }
        }
    }
}

// MARK: - Tabs

struct MainTabView: View {
    /// Tab ids used by tab-selection routing from deep links and pushes.
    private enum RootTab: Hashable {
        case mushroom
        case postcard
        case profile
    }

    @EnvironmentObject private var session: UserSessionStore // State or dependency property.
    /// Shared notification inbox state used for action-event badge aggregation.
    @EnvironmentObject private var notificationInbox: EventInboxStore
    /// Currently selected tab in app shell.
    @State private var selectedTab: RootTab = .mushroom
    /// Pending mushroom push-link route consumed by Room browse navigation stack.
    @State private var pendingRoomPushRoute: RoomBrowsePushRoute? = nil
    /// Pending postcard push-link route consumed by Postcard browse navigation stack.
    @State private var pendingPostcardPushRoute: PostcardBrowsePushRoute? = nil
    /// Controls the app-root DailyReward sheet used by push/inbox routing.
    @State private var isGlobalDailyRewardPresented: Bool = false
    /// Tab selection binding that ignores user tab-tap changes while any tutorial is active.
    private var tabSelectionBinding: Binding<RootTab> {
        Binding(
            get: { selectedTab },
            set: { nextTab in
                guard !session.isFeatureTutorialChromeLocked else { return }
                selectedTab = nextTab
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelectionBinding) {
            RoomBrowseView(
                session: session,
                pendingPushRoute: $pendingRoomPushRoute
            )
                .tabItem {
                    Label("tab_mushroom", systemImage: "person.3.fill")
                }
                .tag(RootTab.mushroom)
                .accessibilityIdentifier("tab_browse")

            PostcardBrowseView(
                pendingPushRoute: $pendingPostcardPushRoute
            )
                .tabItem {
                    Label("tab_postcard", systemImage: "mail")
                }
                .tag(RootTab.postcard)
                .accessibilityIdentifier("tab_postcard")

            ProfileView()
                .tabItem {
                    Label("tab_profile", systemImage: "person.circle")
                }
                .tag(RootTab.profile)
                .accessibilityIdentifier("tab_profile")
        }
        .sheet(isPresented: $isGlobalDailyRewardPresented) {
            DailyRewardView()
                .environmentObject(session)
                .environmentObject(notificationInbox)
        }
        .toolbar(session.isFeatureTutorialChromeLocked ? .hidden : .visible, for: .tabBar)
        .background(
            TabBarInteractionLockBridge(
                isTabBarInteractionEnabled: !session.isFeatureTutorialChromeLocked
            )
            .frame(width: 0, height: 0)
        )
        .onReceive(NotificationCenter.default.publisher(for: .didOpenRoomFromPush)) { notif in
            guard let roomId = notif.object as? String else { return }
            selectedTab = .mushroom
            pendingRoomPushRoute = RoomBrowsePushRoute(
                roomId: roomId,
                isOpeningConfirmationQueue: false,
                isForceRefresh: true
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .didOpenRoomConfirmationFromPush)) { notif in
            guard let roomId = notif.object as? String else { return }
            selectedTab = .mushroom
            pendingRoomPushRoute = RoomBrowsePushRoute(
                roomId: roomId,
                isOpeningConfirmationQueue: true,
                isForceRefresh: true
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .didOpenPostcardFromLink)) { notif in
            guard let postcardId = notif.object as? String else { return }
            selectedTab = .postcard
            pendingPostcardPushRoute = PostcardBrowsePushRoute(
                postcardId: postcardId,
                isOpeningOrderPage: false,
                isForceRefresh: true
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .didOpenPostcardOrderFromPush)) { notif in
            guard let payload = notif.object as? [String: String] else { return }
            let postcardId = (payload["postcardId"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard postcardId.isEmpty == false else { return }
            selectedTab = .postcard
            pendingPostcardPushRoute = PostcardBrowsePushRoute(
                postcardId: postcardId,
                isOpeningOrderPage: true,
                isForceRefresh: true
                )
        }
        .onReceive(NotificationCenter.default.publisher(for: .didOpenDailyRewardReminder)) { _ in
            isGlobalDailyRewardPresented = true
        }
        .task(id: session.authUid) {
            await refreshAppShellState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await refreshAppShellState()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveActionPushBadgeUpdate)) { notif in
            Task {
                if let badgeCount = notif.object as? Int {
                    UIApplication.shared.applicationIconBadgeNumber = max(0, badgeCount)
                }
                await refreshAppShellState()
            }
        }
        .onChange(of: notificationInbox.unresolvedActionBadgeCountExcludingDailyReward) { _, _ in
            applyAppIconBadge()
        }
        .onChange(of: session.isDailyRewardPending) { _, _ in
            applyAppIconBadge()
        }
        .onAppear {
            if AppTesting.isUITesting {
                session.isLoggedIn = true
                session.authUid = AppTesting.userId
                session.displayName = "UI Tester"
                session.friendCode = "999988887777"
                session.stars = 1
                session.honey = 100
                session.isProfileComplete = true
                session.updateDailyRewardPendingState(AppTesting.isMockDailyRewardPendingToday)
                Task { @MainActor in
                    await notificationInbox.refreshFromServer()
                    applyAppIconBadge()
                }

                if let postcardId = AppTesting.launchArgumentValue(after: AppTesting.openPostcardArgument) {
                    selectedTab = .postcard
                    pendingPostcardPushRoute = PostcardBrowsePushRoute(
                        postcardId: postcardId,
                        isOpeningOrderPage: false,
                        isForceRefresh: true
                    )
                } else if let roomId = AppTesting.launchArgumentValue(after: AppTesting.openRoomArgument) {
                    selectedTab = .mushroom
                    pendingRoomPushRoute = RoomBrowsePushRoute(
                        roomId: roomId,
                        isOpeningConfirmationQueue: false,
                        isForceRefresh: true
                    )
                }
            }
        }
    }

    /// Refreshes shared app-shell state that drives app icon badge and global push routes.
    private func refreshAppShellState() async {
        guard session.isLoggedIn else {
            session.updateDailyRewardPendingState(false)
            UIApplication.shared.applicationIconBadgeNumber = 0
            return
        }

        if AppTesting.isUITesting == false {
            await session.refreshProfileFromBackend()
        }
        await notificationInbox.refreshFromServer()
        applyAppIconBadge()
    }

    /// Applies the current app icon badge using unresolved action count plus pending DailyReward state.
    private func applyAppIconBadge() {
        let badgeCount = notificationInbox.unresolvedActionBadgeCountExcludingDailyReward
            + (session.isDailyRewardPending ? 1 : 0)
        UIApplication.shared.applicationIconBadgeNumber = max(0, badgeCount)
    }
}

private extension UserSessionStore {
    /// Returns whether tutorial presentation should hide and lock the root tab bar right now.
    var isFeatureTutorialChromeLocked: Bool {
        isFeatureTutorialActive || isFeatureTutorialTransitionPending
    }
}

/// UIKit bridge that toggles root tab-bar interaction while feature tutorials are active.
private struct TabBarInteractionLockBridge: UIViewRepresentable {
    /// Indicates whether tab-bar taps should be accepted.
    let isTabBarInteractionEnabled: Bool

    /// Creates a no-op carrier view used only to trigger update callbacks.
    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    /// Applies tab-bar interaction lock whenever tutorial state changes.
    /// - Parameters:
    ///   - uiView: Carrier view instance.
    ///   - context: SwiftUI update context.
    func updateUIView(_ uiView: UIView, context: Context) {
        applyTabBarInteractionState()
        DispatchQueue.main.async {
            applyTabBarInteractionState()
        }
    }

    /// Resolves root tab bar controller from key window and toggles tutorial tab-bar state.
    private func applyTabBarInteractionState() {
        guard let tabBarController = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController?
            .findTabBarController()
        else {
            return
        }
        tabBarController.tabBar.isHidden = !isTabBarInteractionEnabled
        tabBarController.tabBar.isUserInteractionEnabled = isTabBarInteractionEnabled
    }
}

/// Shared helper to resolve a tab bar controller from any root view-controller tree.
private extension UIViewController {
    /// Returns first reachable tab bar controller in this subtree.
    func findTabBarController() -> UITabBarController? {
        if let tabBarController = self as? UITabBarController {
            return tabBarController
        }
        for child in children {
            if let tabBarController = child.findTabBarController() {
                return tabBarController
            }
        }
        if let presentedViewController,
           let tabBarController = presentedViewController.findTabBarController() {
            return tabBarController
        }
        return nil
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(UserSessionStore())
}
