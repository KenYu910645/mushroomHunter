//
//  ProfileSectionStateView.swift
//  mushroomHunter
//
//  Purpose:
//  - Reuses loading/error/empty/content state rendering for profile section lists.
//
import SwiftUI

/// Generic container that renders error, loading, empty, and content states for profile lists.
struct ProfileSectionStateView<Content: View, Empty: View>: View {
    /// Loading state for current section fetch.
    let isLoading: Bool

    /// Whether the backing collection is empty.
    let isEmpty: Bool

    /// Optional error message shown above content.
    let errorMessage: String?

    /// Localized loading label shown with a progress view.
    let loadingTextKey: LocalizedStringKey

    /// View builder for non-empty section rows.
    let content: () -> Content

    /// View builder for empty-state placeholder UI.
    let emptyContent: () -> Empty

    /// Creates state container with section-specific empty/content builders.
    init(
        isLoading: Bool,
        isEmpty: Bool,
        errorMessage: String?,
        loadingTextKey: LocalizedStringKey,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder emptyContent: @escaping () -> Empty
    ) {
        self.isLoading = isLoading
        self.isEmpty = isEmpty
        self.errorMessage = errorMessage
        self.loadingTextKey = loadingTextKey
        self.content = content
        self.emptyContent = emptyContent
    }

    /// Unified rendering for section state transitions.
    var body: some View {
        Group {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            if isLoading && isEmpty {
                HStack {
                    ProgressView()
                    Text(loadingTextKey)
                        .foregroundStyle(.secondary)
                }
            } else if isEmpty {
                emptyContent()
            } else {
                content()
            }
        }
    }
}
