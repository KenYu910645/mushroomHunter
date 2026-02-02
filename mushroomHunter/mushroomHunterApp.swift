//
//  mushroomHunterApp.swift
//  mushroomHunter
//
//  Created by Ken on 2/2/2026.
//

import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct mushroomHunterApp: App {
    @StateObject private var session = SessionStore()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .onOpenURL { url in
                    // Let GoogleSignIn handle the redirect back into the app
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
