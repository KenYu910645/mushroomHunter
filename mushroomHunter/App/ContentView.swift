import SwiftUI
import Combine

// MARK: - App Root

struct ContentView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            if session.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
    }
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
