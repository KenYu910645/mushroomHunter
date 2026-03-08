//
//  TutorialFloatingHighlightWindowBridge.swift
//  mushroomHunter
//
//  Purpose:
//  - Renders tutorial highlight strokes in a dedicated floating window above navigation bars.
//
import SwiftUI
import UIKit

/// SwiftUI bridge that controls a floating highlight-stroke window for tutorial toolbar targets.
struct TutorialFloatingHighlightWindowBridge: UIViewRepresentable {
    /// Optional screen-space frame for the highlight rectangle.
    let frame: CGRect?
    /// Whether the floating highlight feature should be active.
    let isVisible: Bool

    /// Builds coordinator that owns the floating window lifecycle.
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Creates a transparent anchor view used to resolve the current scene window.
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    /// Updates floating highlight window with latest visibility and frame values.
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update(
            frame: frame,
            isVisible: isVisible,
            sourceWindow: uiView.window
        )
    }

    /// Cleans up floating resources when the bridge is removed.
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.clear()
    }

    /// Coordinator that manages one non-interactive overlay window above the host scene.
    final class Coordinator {
        /// Floating overlay window used to render the topmost highlight stroke.
        private var overlayWindow: UIWindow?
        /// Hosting controller that renders SwiftUI highlight content inside the overlay window.
        private var hostingController: UIHostingController<TutorialFloatingHighlightOverlayView>?

        /// Updates overlay window visibility and highlight frame.
        /// - Parameters:
        ///   - frame: Optional screen-space frame for highlight stroke.
        ///   - isVisible: Whether overlay feature should remain active.
        ///   - sourceWindow: Window from the embedding SwiftUI hierarchy.
        func update(frame: CGRect?, isVisible: Bool, sourceWindow: UIWindow?) {
            guard isVisible, let sourceWindow else {
                clear()
                return
            }

            if overlayWindow == nil || overlayWindow?.windowScene !== sourceWindow.windowScene {
                buildOverlayWindow(sourceWindow: sourceWindow)
            }

            guard let overlayWindow, let hostingController else { return }
            hostingController.rootView = TutorialFloatingHighlightOverlayView(frame: frame)
            overlayWindow.isHidden = false
        }

        /// Builds floating overlay window within the same scene as the source window.
        /// - Parameter sourceWindow: Source scene window from current SwiftUI hierarchy.
        private func buildOverlayWindow(sourceWindow: UIWindow) {
            guard let windowScene = sourceWindow.windowScene else { return }
            let window = UIWindow(windowScene: windowScene)
            window.backgroundColor = .clear
            window.isUserInteractionEnabled = false
            window.windowLevel = sourceWindow.windowLevel + 2

            let hostingController = UIHostingController(
                rootView: TutorialFloatingHighlightOverlayView(frame: nil)
            )
            hostingController.view.backgroundColor = .clear

            window.rootViewController = hostingController
            window.isHidden = false

            self.overlayWindow = window
            self.hostingController = hostingController
        }

        /// Tears down floating overlay resources.
        func clear() {
            overlayWindow?.isHidden = true
            hostingController = nil
            overlayWindow = nil
        }
    }
}

/// Simple stroke-only overlay view rendered in the floating highlight window.
private struct TutorialFloatingHighlightOverlayView: View {
    /// Optional screen-space frame for the highlight stroke.
    let frame: CGRect?

    /// Highlight overlay body.
    var body: some View {
        ZStack {
            if let frame {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.yellow, lineWidth: 2)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
