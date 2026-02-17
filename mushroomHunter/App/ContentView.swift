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
    @State private var pendingRoomId: String? = nil // State or dependency property.
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
            pendingRoomId = roomId
        }
        .sheet(item: Binding(
            get: { pendingRoomId.map { RoomLink(id: $0) } },
            set: { pendingRoomId = $0?.id }
        )) { link in
            RoomDetailsView(vm: RoomDetailsViewModel(roomId: link.id, session: session))
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
            }
        }
    }
}

private struct RoomLink: Identifiable {
    let id: String
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
