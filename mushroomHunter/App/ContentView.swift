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
                    Label("Mushroom", systemImage: "magnifyingglass")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
                }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(SessionStore())
}
