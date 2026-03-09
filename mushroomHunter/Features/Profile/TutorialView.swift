//
//  TutorialView.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides a deprecated compatibility entry that routes old tutorial callers
//    to the current interactive tutorial catalog flow.
//

import SwiftUI

/// Deprecated compatibility wrapper for the legacy static onboarding tutorial screen.
/// Keep this type so older call sites can compile while the app uses tutorial catalog replay flow.
@available(*, deprecated, message: "Use TutorialCatalogView for interactive tutorial replay.")
struct TutorialView: View {
    /// Dismiss action kept for compatibility in case legacy callers present this view modally.
    @Environment(\.dismiss) private var dismiss

    /// Renders the modern tutorial catalog and exposes a close action in navigation chrome.
    var body: some View {
        TutorialCatalogView()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(LocalizedStringKey("common_close")) {
                        dismiss()
                    }
                }
            }
    }
}
