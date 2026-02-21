//
//  HoneyMessageBox.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides a shared custom message box used across features.
//
import SwiftUI
import UIKit

/// Button style role used by the shared message box.
enum HoneyMessageBoxButtonRole {
    /// Default neutral action.
    case normal
    /// Lower-emphasis neutral action used for non-primary choices.
    case quiet
    /// Cancel action that dismisses the box without destructive side effects.
    case cancel
    /// Destructive action rendered with warning emphasis.
    case destructive
}

/// Button model rendered by the shared message box.
struct HoneyMessageBoxButton: Identifiable {
    /// Stable identity for SwiftUI list rendering.
    let id: String
    /// Visible button title.
    let title: String
    /// Visual role for color styling.
    let role: HoneyMessageBoxButtonRole
    /// Action callback invoked when tapped.
    let action: () -> Void

    /// Initializes one message-box button model.
    init(id: String, title: String, role: HoneyMessageBoxButtonRole = .normal, action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.role = role
        self.action = action
    }
}

/// Shared custom message box with title, tokenized message, and action buttons.
struct HoneyMessageBox: View {
    /// Message token replaced by inline honey icon when rendering message text.
    private let honeyIconToken: String = "{honey_icon}"
    /// Title text shown at the top of the dialog.
    let title: String
    /// Message text shown below title. Supports `{honey_icon}` token.
    let message: String
    /// Action buttons shown at the bottom of the dialog.
    let buttons: [HoneyMessageBoxButton]

    /// Shared custom message-box layout.
    var body: some View {
        GeometryReader { proxy in
            let screenMidY = UIScreen.main.bounds.midY
            let localMidY = proxy.frame(in: .global).midY
            let centerOffsetY = screenMidY - localMidY

            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    Text(title)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)

                    tokenizedMessage(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    buttonContainer
                }
                .padding(18)
                .frame(maxWidth: 340)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                }
                .padding(.horizontal, 24)
                .offset(y: centerOffsetY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .ignoresSafeArea()
        }
    }

    /// Message renderer that supports inline `{honey_icon}` tokens and line breaks.
    @ViewBuilder
    private func tokenizedMessage(_ rawMessage: String) -> some View {
        let lines = rawMessage.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let segments = line.components(separatedBy: honeyIconToken)
                HStack(alignment: .center, spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        Text(segment)
                        if index < segments.count - 1 {
                            Image("HoneyIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 15)
                        }
                    }
                }
            }
        }
    }

    /// Bottom button layout. Renders two buttons in a row; otherwise uses a stacked layout.
    @ViewBuilder
    private var buttonContainer: some View {
        if buttons.count == 2 {
            HStack(spacing: 10) {
                ForEach(orderedTwoButtons) { button in
                    buttonView(button)
                }
            }
        } else {
            VStack(spacing: 8) {
                ForEach(buttons) { button in
                    buttonView(button)
                }
            }
        }
    }

    /// Ordered two-button actions that always place cancel on the right side.
    private var orderedTwoButtons: [HoneyMessageBoxButton] {
        guard buttons.count == 2 else { return buttons }
        let hasCancelButton = buttons.contains { $0.role == .cancel }
        guard hasCancelButton else { return buttons }

        let firstButton = buttons[0]
        let secondButton = buttons[1]
        if firstButton.role == .cancel, secondButton.role != .cancel {
            return [secondButton, firstButton]
        }
        return buttons
    }

    /// Builds one styled action button in the shared message box.
    private func buttonView(_ button: HoneyMessageBoxButton) -> some View {
        Button {
            button.action()
        } label: {
            Text(button.title)
                .frame(maxWidth: .infinity)
        }
        .modifier(HoneyMessageBoxButtonStyleModifier(role: button.role))
    }
}

/// Shared button-style adapter used by message-box actions.
private struct HoneyMessageBoxButtonStyleModifier: ViewModifier {
    /// Button role used to select style and color treatment.
    let role: HoneyMessageBoxButtonRole

    /// Applies style for one message-box action button.
    func body(content: Content) -> some View {
        switch role {
        case .normal:
            content
                .buttonStyle(.borderedProminent)
        case .quiet:
            content
                .buttonStyle(.bordered)
        case .cancel:
            content
                .buttonStyle(.bordered)
        case .destructive:
            content
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
    }
}
