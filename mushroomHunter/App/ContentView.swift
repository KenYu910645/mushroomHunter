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
    /// Repository for profile room queries used by tab/app-icon badge aggregation.
    private let profileRepo = FbProfileListRepo()
    /// Repository for postcard order queries used by tab/app-icon badge aggregation.
    private let postcardRepo = FbPostcardRepo()
    /// Currently selected tab in app shell.
    @State private var selectedTab: RootTab = .mushroom
    /// Pending mushroom push-link route consumed by Room browse navigation stack.
    @State private var pendingRoomPushRoute: RoomBrowsePushRoute? = nil
    /// Pending postcard push-link route consumed by Postcard browse navigation stack.
    @State private var pendingPostcardPushRoute: PostcardBrowsePushRoute? = nil
    /// Tab selection binding that ignores user tab-tap changes while any tutorial is active.
    private var tabSelectionBinding: Binding<RootTab> {
        Binding(
            get: { selectedTab },
            set: { nextTab in
                guard !session.isFeatureTutorialActive else { return }
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
        .toolbar(session.isFeatureTutorialActive ? .hidden : .visible, for: .tabBar)
        .background(
            TabBarInteractionLockBridge(
                isTabBarInteractionEnabled: !session.isFeatureTutorialActive
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
        .task(id: session.authUid) {
            await refreshProfileActionBadgeCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await refreshProfileActionBadgeCount()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveActionPushBadgeUpdate)) { notif in
            if let badgeCount = notif.object as? Int {
                session.updateProfileActionBadgeCount(badgeCount)
            }
            Task {
                await refreshProfileActionBadgeCount()
            }
        }
        .onChange(of: session.profileActionBadgeCount) { _, latestCount in
            UIApplication.shared.applicationIconBadgeNumber = latestCount
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

    /// Recomputes profile actionable counts and applies them to tab/app icon badges.
    private func refreshProfileActionBadgeCount() async {
        if AppTesting.isUITesting || !session.isLoggedIn {
            session.updateProfileActionBadgeCount(0)
            return
        }

        guard let userId = session.authUid, userId.isEmpty == false else {
            session.updateProfileActionBadgeCount(0)
            return
        }

        do {
            async let joinedRoomsLoad: [JoinedRoomSummary] = profileRepo.fetchMyJoinedRooms(
                limit: AppConfig.Mushroom.profileListFetchLimit
            )
            async let hostedRoomsLoad: [HostedRoomSummary] = profileRepo.fetchMyHostedRooms(
                limit: AppConfig.Mushroom.profileListFetchLimit
            )
            async let sellerOrderCountsLoad: [String: Int] = postcardRepo.fetchSellerPendingOrderCountsByPostcardId(
                userId: userId
            )
            async let buyerPendingReceiveCountLoad: Int = postcardRepo.fetchBuyerPendingReceiveCount(
                userId: userId
            )

            let joinedRooms = try await joinedRoomsLoad
            let hostedRooms = try await hostedRoomsLoad
            let sellerOrderCountsByPostcardId = try await sellerOrderCountsLoad
            let buyerPendingReceiveCount = try await buyerPendingReceiveCountLoad

            let hostedRoomIds = hostedRooms.map { $0.id }
            let pendingJoinRequestCountsByRoomId = try await profileRepo.fetchHostPendingJoinRequestCounts(
                roomIds: hostedRoomIds
            )

            let joinerPendingConfirmationCount = joinedRooms.reduce(0) { partial, room in
                let isWaitingConfirmation = room.attendeeStatus == .waitingConfirmation
                return partial + (isWaitingConfirmation ? 1 : 0)
            }
            let hostPendingJoinRequestCount = pendingJoinRequestCountsByRoomId.values.reduce(0, +)
            let sellerPendingOrderCount = sellerOrderCountsByPostcardId.values.reduce(0, +)
            let totalBadgeCount = joinerPendingConfirmationCount
                + hostPendingJoinRequestCount
                + sellerPendingOrderCount
                + buyerPendingReceiveCount
            session.updateProfileActionBadgeCount(totalBadgeCount)
        } catch {
            // Keep current badge count when refresh fails.
        }
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
