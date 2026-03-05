//
//  MessageBox.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides a shared custom message box used across features.
//
import SwiftUI
import UIKit

/// Button style role used by the shared message box.
enum MessageBoxButtonRole {
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
struct MessageBoxButton: Identifiable {
    /// Stable identity for SwiftUI list rendering.
    let id: String
    /// Visible button title.
    let title: String
    /// Visual role for color styling.
    let role: MessageBoxButtonRole
    /// Action callback invoked when tapped.
    let action: () -> Void

    /// Initializes one message-box button model.
    init(id: String, title: String, role: MessageBoxButtonRole = .normal, action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.role = role
        self.action = action
    }
}

/// Shared custom message box with title, tokenized message, and action buttons.
struct MessageBox: View {
    /// Message token replaced by inline honey icon when rendering message text.
    private let honeyIconToken: String = "{honey_icon}"
    /// Inline honey icon square size in points, centralized in app config.
    private let honeyIconSize: CGFloat = AppConfig.SharedUI.honeyMessageIconSize
    /// Title text shown at the top of the dialog.
    let title: String
    /// Message text shown below title. Supports `{honey_icon}` token.
    let message: String
    /// Action buttons shown at the bottom of the dialog.
    let buttons: [MessageBoxButton]

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

    /// Builds one inline SwiftUI text run where `{honey_icon}` tokens become inline image glyphs.
    private func tokenizedMessage(_ rawMessage: String) -> Text {
        let segments = rawMessage.components(separatedBy: honeyIconToken)
        var combinedText = Text("")

        for (index, segment) in segments.enumerated() {
            combinedText = combinedText + Text(segment)
            if index < segments.count - 1 {
                combinedText = combinedText + Text(honeyInlineImage())
            }
        }

        return combinedText
    }

    /// Builds one pre-scaled `HoneyIcon` image so inline `Text(Image(...))` respects configured size.
    private func honeyInlineImage() -> Image {
        guard let sourceImage = UIImage(named: "HoneyIcon") else {
            return Image(systemName: "drop.fill")
        }

        let targetSize = CGSize(width: honeyIconSize, height: honeyIconSize)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resizedImage = renderer.image { _ in
            sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return Image(uiImage: resizedImage)
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
    private var orderedTwoButtons: [MessageBoxButton] {
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
    private func buttonView(_ button: MessageBoxButton) -> some View {
        Button {
            button.action()
        } label: {
            Text(button.title)
                .frame(maxWidth: .infinity)
        }
        .modifier(MessageBoxButtonStyleModifier(role: button.role))
    }
}

/// Shared button-style adapter used by message-box actions.
private struct MessageBoxButtonStyleModifier: ViewModifier {
    /// Button role used to select style and color treatment.
    let role: MessageBoxButtonRole

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
