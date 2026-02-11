import SwiftUI
import Combine

// MARK: - App Root

struct ContentView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var pendingRoomId: String? = nil

    var body: some View {
        ZStack {
            ThemedBackground()
            Group {
                if session.isLoggedIn {
                    MainTabView()
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
    }
}

private struct RoomLink: Identifiable {
    let id: String
}

// MARK: - Tabs

struct MainTabView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        TabView {
            BrowseView(session: session)
                .tabItem {
                    Label("tab_mushroom", systemImage: "magnifyingglass")
                }

            PostcardTabView()
                .tabItem {
                    Label("tab_postcard", systemImage: "mail")
                }

            ProfileView()
                .tabItem {
                    Label("tab_profile", systemImage: "person.circle")
                }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(SessionStore())
}
