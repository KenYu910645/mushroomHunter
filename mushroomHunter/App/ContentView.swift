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
    @State private var pendingRoute: DeepLinkRoute? = nil // State or dependency property.
    var body: some View {
        ZStack {
            ThemedBackground()
            Group {
                if session.isLoggedIn || AppTesting.isUITesting {
                    if session.isProfileComplete || AppTesting.isUITesting {
                        MainTabView()
                    } else {
                        ProfileFormView(mode: .create)
                    }
                } else {
                    LoginView()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didOpenRoomFromPush)) { notif in
            guard let roomId = notif.object as? String else { return }
            pendingRoute = .room(id: roomId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .didOpenPostcardFromLink)) { notif in
            guard let postcardId = notif.object as? String else { return }
            pendingRoute = .postcard(id: postcardId)
        }
        .sheet(item: $pendingRoute) { route in
            switch route {
            case .room(let id):
                NavigationStack {
                    RoomView(vm: RoomViewModel(roomId: id, session: session))
                        .environmentObject(session)
                }
            case .postcard(let id):
                PostcardLinkDestinationView(postcardId: id)
                    .environmentObject(session)
            }
        }
        .fullScreenCover(isPresented: $session.isShowingOnboardingTutorial) {
            TutorialView()
                .environmentObject(session)
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
                session.isShowingOnboardingTutorial = false

                if let postcardId = AppTesting.launchArgumentValue(after: AppTesting.openPostcardArgument) {
                    pendingRoute = .postcard(id: postcardId)
                } else if let roomId = AppTesting.launchArgumentValue(after: AppTesting.openRoomArgument) {
                    pendingRoute = .room(id: roomId)
                }
            }
        }
    }
}

private enum DeepLinkRoute: Identifiable {
    case room(id: String)
    case postcard(id: String)

    var id: String {
        switch self {
        case .room(let id):
            return "room:\(id)"
        case .postcard(let id):
            return "postcard:\(id)"
        }
    }
}

private struct PostcardLinkDestinationView: View {
    let postcardId: String

    @Environment(\.dismiss) private var dismiss // State or dependency property.
    @State private var listing: PostcardListing? // State or dependency property.
    @State private var isLoading: Bool = false // State or dependency property.
    private let repo = FbPostcardRepo()

    var body: some View {
        NavigationStack {
            Group {
                if let listing {
                    PostcardView(listing: listing)
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        LocalizedStringKey("postcard_link_unavailable_title"),
                        systemImage: "qrcode",
                        description: Text(LocalizedStringKey("postcard_link_unavailable_message"))
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(LocalizedStringKey("common_close")) {
                        dismiss()
                    }
                }
            }
            .task {
                await loadPostcard()
            }
        }
    }

    private func loadPostcard() async {
        guard !postcardId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if AppTesting.useMockPostcards {
            if postcardId == AppTesting.fixturePostcardId {
                listing = AppTesting.fixturePostcardListing()
            } else if postcardId == AppTesting.fixtureOwnedPostcardListing().id {
                listing = AppTesting.fixtureOwnedPostcardListing()
            }
            return
        }
        isLoading = true
        defer { isLoading = false }
        listing = try? await repo.fetchPostcard(postcardId: postcardId)
    }
}

// MARK: - Tabs

struct MainTabView: View {
    @EnvironmentObject private var session: UserSessionStore // State or dependency property.
    /// Repository for profile room queries used by tab/app-icon badge aggregation.
    private let profileRepo = FbProfileListRepo()
    /// Repository for postcard order queries used by tab/app-icon badge aggregation.
    private let postcardRepo = FbPostcardRepo()

    var body: some View {
        TabView {
            RoomBrowseView(session: session)
                .tabItem {
                    Label("tab_mushroom", systemImage: "person.3.fill")
                }
                .accessibilityIdentifier("tab_browse")

            PostcardBrowseView()
                .tabItem {
                    Label("tab_postcard", systemImage: "mail")
                }
                .accessibilityIdentifier("tab_postcard")

            ProfileView()
                .tabItem {
                    Label("tab_profile", systemImage: "person.circle")
                }
                .badge(session.profileActionBadgeCount > 0 ? "\(session.profileActionBadgeCount)" : nil)
                .accessibilityIdentifier("tab_profile")
        }
        .task(id: session.authUid) {
            await refreshProfileActionBadgeCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await refreshProfileActionBadgeCount()
            }
        }
        .onChange(of: session.profileActionBadgeCount) { _, latestCount in
            UIApplication.shared.applicationIconBadgeNumber = latestCount
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

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(UserSessionStore())
}
