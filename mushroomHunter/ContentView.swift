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

// MARK: - Session / Auth (Fake for MVP Prototype)

//final class SessionStore: ObservableObject {
//    @Published var isLoggedIn: Bool = false
//    @Published var displayName: String = "Ken"
//
//    func signIn() {
//        // TODO: Replace with Sign in with Apple / Firebase Auth later
//        isLoggedIn = true
//    }
//
//    func signOut() {
//        isLoggedIn = false
//    }
//}

// MARK: - Tabs

struct MainTabView: View {
    var body: some View {
        TabView {
            BrowseView()
                .tabItem {
                    Label("Browse", systemImage: "magnifyingglass")
                }

            HostView()
                .tabItem {
                    Label("Host", systemImage: "plus.circle")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
                }
        }
    }
}

// MARK: - Login
//
//struct LoginView: View {
//    @EnvironmentObject private var session: SessionStore
//
//    var body: some View {
//        NavigationStack {
//            VStack(spacing: 16) {
//                Spacer()
//
//                Image(systemName: "leaf.circle.fill")
//                    .font(.system(size: 64))
//                    .symbolRenderingMode(.hierarchical)
//
//                Text("Mushroom Hunter")
//                    .font(.largeTitle.bold())
//
//                Text("Prototype build — no real backend yet.")
//                    .font(.subheadline)
//                    .foregroundStyle(.secondary)
//
//                Spacer()
//
//                Button {
//                    session.signIn()
//                } label: {
//                    Text("Sign In (Prototype)")
//                        .frame(maxWidth: .infinity)
//                }
//                .buttonStyle(.borderedProminent)
//
//                Text("Replace this later with Sign in with Apple + Firebase.")
//                    .font(.footnote)
//                    .foregroundStyle(.secondary)
//                    .multilineTextAlignment(.center)
//                    .padding(.horizontal)
//
//            }
//            .padding()
//            .navigationTitle("")
//            .navigationBarHidden(true)
//        }
//    }
//}

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var draftName: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    HStack {
                        Text("Display Name")
                        Spacer()
                        Text(session.displayName)
                            .foregroundStyle(.secondary)
                    }

                    TextField("Edit name (prototype)", text: $draftName)
                        .textInputAutocapitalization(.words)

                    Button("Save Name") {
                        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            session.displayName = trimmed
                            draftName = ""
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        session.signOut()
                    } label: {
                        Text("Sign Out")
                    }
                } footer: {
                    Text("This is a prototype profile screen. Later: Firebase user profile, friend code, joined/hosted history.")
                }
            }
            .navigationTitle("Profile")
        }
        .onAppear {
            // prefill with current name for convenience
            draftName = session.displayName
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(SessionStore())
}
