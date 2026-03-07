//
//  TopActionBar.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides a reusable top action bar with honey display and search/create buttons.
//
//  Defined in this file:
//  - TopActionBar: shared browse header UI used by Mushroom and Postcard tabs.
//
import SwiftUI

struct TopActionBar: View {
    /// Honey amount displayed in the left wallet area.
    let honey: Int
    /// Star amount displayed when enabled.
    let stars: Int
    /// Callback fired when search button is tapped.
    let onSearch: (() -> Void)?
    /// Callback fired when create button is tapped.
    let onCreate: (() -> Void)?
    /// Optional search accessibility label.
    let searchAccessibilityLabel: LocalizedStringKey?
    /// Optional create accessibility label.
    let createAccessibilityLabel: LocalizedStringKey?
    /// Optional search accessibility identifier.
    let searchButtonIdentifier: String?
    /// Optional create accessibility identifier.
    let createButtonIdentifier: String?
    /// Controls whether action buttons are shown.
    let showActions: Bool
    /// Controls whether stars badge is shown next to honey badge.
    let isStarsVisible: Bool
    /// Optional tutorial target for the full top action bar bounds.
    let tutorialBarTarget: TutorialHighlightTarget?
    /// Optional tutorial target for honey badge bounds.
    let tutorialHoneyTarget: TutorialHighlightTarget?
    /// Optional tutorial target for search button bounds.
    let tutorialSearchButtonTarget: TutorialHighlightTarget?
    /// Optional tutorial target for create button bounds.
    let tutorialCreateButtonTarget: TutorialHighlightTarget?

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
        isStarsVisible: Bool = true,
        tutorialBarTarget: TutorialHighlightTarget? = nil,
        tutorialHoneyTarget: TutorialHighlightTarget? = nil,
        tutorialSearchButtonTarget: TutorialHighlightTarget? = nil,
        tutorialCreateButtonTarget: TutorialHighlightTarget? = nil
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
        self.tutorialBarTarget = tutorialBarTarget
        self.tutorialHoneyTarget = tutorialHoneyTarget
        self.tutorialSearchButtonTarget = tutorialSearchButtonTarget
        self.tutorialCreateButtonTarget = tutorialCreateButtonTarget
    }

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                ColorfulTag(tone: .honey, font: .subheadline.weight(.semibold)) {
                    HStack(spacing: 4) {
                        Image("HoneyIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                        Text("\(honey)")
                            .monospacedDigit()
                    }
                }
                .tutorialHighlightAnchor(tutorialHoneyTarget)

                if isStarsVisible {
                    ColorfulTag(tone: .star, font: .subheadline.weight(.semibold)) {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                            Text("\(stars)")
                                .monospacedDigit()
                        }
                    }
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
                    .tutorialHighlightAnchor(tutorialSearchButtonTarget)
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
                    .tutorialHighlightAnchor(tutorialCreateButtonTarget)
                    .ifLet(createAccessibilityLabel) { view, label in
                        view.accessibilityLabel(label)
                    }
                    .ifLet(createButtonIdentifier) { view, id in
                        view.accessibilityIdentifier(id)
                    }
                }
            }
        }
        .tutorialHighlightAnchor(tutorialBarTarget)
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
