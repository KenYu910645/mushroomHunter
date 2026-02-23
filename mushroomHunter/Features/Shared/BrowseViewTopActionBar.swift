//
//  BrowseViewTopActionBar.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides a reusable top action bar with honey display and search/create buttons.
//
//  Defined in this file:
//  - BrowseViewTopActionBar: shared browse header UI used by Mushroom and Postcard tabs.
//
import SwiftUI

struct BrowseViewTopActionBar: View {
    let honey: Int
    let stars: Int
    let onSearch: (() -> Void)?
    let onCreate: (() -> Void)?
    let searchAccessibilityLabel: LocalizedStringKey?
    let createAccessibilityLabel: LocalizedStringKey?
    let searchButtonIdentifier: String?
    let createButtonIdentifier: String?
    let showActions: Bool
    let isStarsVisible: Bool

    init(
        honey: Int,
        stars: Int,
        onSearch: (() -> Void)?,
        onCreate: (() -> Void)?,
        searchAccessibilityLabel: LocalizedStringKey?,
        createAccessibilityLabel: LocalizedStringKey?,
        searchButtonIdentifier: String?,
        createButtonIdentifier: String?,
        showActions: Bool = true,
        isStarsVisible: Bool = true
    ) {
        self.honey = honey
        self.stars = stars
        self.onSearch = onSearch
        self.onCreate = onCreate
        self.searchAccessibilityLabel = searchAccessibilityLabel
        self.createAccessibilityLabel = createAccessibilityLabel
        self.searchButtonIdentifier = searchButtonIdentifier
        self.createButtonIdentifier = createButtonIdentifier
        self.showActions = showActions
        self.isStarsVisible = isStarsVisible
    }

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image("HoneyIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                    Text("\(honey)")
                        .foregroundStyle(Color.orange)
                        .monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                )

                if isStarsVisible {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(Color.yellow)
                        Text("\(stars)")
                            .foregroundStyle(Color.yellow)
                            .monospacedDigit()
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.yellow.opacity(0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
                    )
                }
            }

            Spacer()

            if showActions {
                HStack(spacing: 12) {
                    Button {
                        onSearch?()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .ifLet(searchAccessibilityLabel) { view, label in
                        view.accessibilityLabel(label)
                    }
                    .ifLet(searchButtonIdentifier) { view, id in
                        view.accessibilityIdentifier(id)
                    }

                    Button {
                        onCreate?()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .ifLet(createAccessibilityLabel) { view, label in
                        view.accessibilityLabel(label)
                    }
                    .ifLet(createButtonIdentifier) { view, id in
                        view.accessibilityIdentifier(id)
                    }
                }
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func ifLet<T, Content: View>(_ value: T?, transform: (Self, T) -> Content) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}
