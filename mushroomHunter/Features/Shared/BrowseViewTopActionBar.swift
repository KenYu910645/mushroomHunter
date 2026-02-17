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
    let onSearch: (() -> Void)?
    let onCreate: (() -> Void)?
    let searchAccessibilityLabel: LocalizedStringKey?
    let createAccessibilityLabel: LocalizedStringKey?
    let searchButtonIdentifier: String?
    let createButtonIdentifier: String?
    let showActions: Bool

    init(
        honey: Int,
        onSearch: (() -> Void)?,
        onCreate: (() -> Void)?,
        searchAccessibilityLabel: LocalizedStringKey?,
        createAccessibilityLabel: LocalizedStringKey?,
        searchButtonIdentifier: String?,
        createButtonIdentifier: String?,
        showActions: Bool = true
    ) {
        self.honey = honey
        self.onSearch = onSearch
        self.onCreate = onCreate
        self.searchAccessibilityLabel = searchAccessibilityLabel
        self.createAccessibilityLabel = createAccessibilityLabel
        self.searchButtonIdentifier = searchButtonIdentifier
        self.createButtonIdentifier = createButtonIdentifier
        self.showActions = showActions
    }

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image("HoneyIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text("\(honey)")
                    .font(.subheadline.weight(.semibold))
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
