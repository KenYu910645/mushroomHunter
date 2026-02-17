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

// MARK: - App Root

struct ContentView: View {
    @EnvironmentObject private var session: SessionStore // State or dependency property.
    @State private var pendingRoute: DeepLinkRoute? = nil // State or dependency property.
    var body: some View {
        ZStack {
            ThemedBackground()
            Group {
                if session.isLoggedIn || AppTesting.isUITesting {
                    if session.isProfileComplete || AppTesting.isUITesting {
                        MainTabView()
                    } else {
                        CreateProfileView()
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
                RoomDetailsView(vm: RoomDetailsViewModel(roomId: id, session: session))
                    .environmentObject(session)
            case .postcard(let id):
                PostcardLinkDestinationView(postcardId: id)
                    .environmentObject(session)
            }
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
    private let repo = FirebasePostcardRepository()

    var body: some View {
        NavigationStack {
            Group {
                if let listing {
                    PostcardDetailView(listing: listing)
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
        isLoading = true
        defer { isLoading = false }
        listing = try? await repo.fetchPostcard(postcardId: postcardId)
    }
}

// MARK: - Tabs

struct MainTabView: View {
    @EnvironmentObject private var session: SessionStore // State or dependency property.
    var body: some View {
        TabView {
            RoomBrowseView(session: session)
                .tabItem {
                    Label("tab_mushroom", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("tab_browse")

            PostcardTabView()
                .tabItem {
                    Label("tab_postcard", systemImage: "mail")
                }
                .accessibilityIdentifier("tab_postcard")

            ProfileView()
                .tabItem {
                    Label("tab_profile", systemImage: "person.circle")
                }
                .accessibilityIdentifier("tab_profile")
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(SessionStore())
}
