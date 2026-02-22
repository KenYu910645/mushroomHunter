//
//  OutsideTapKeyboardDismissBridge.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides a shared UIKit bridge that dismisses keyboard on outside taps without interfering with scroll gestures.
//
import SwiftUI
import UIKit

/// Adds a UIKit tap recognizer to dismiss keyboard on outside taps without affecting scroll gestures.
struct OutsideTapKeyboardDismissBridge: UIViewRepresentable {
    /// Callback executed when user taps outside text input controls.
    let onOutsideTap: () -> Void

    /// Creates a transparent bridge view used to attach the tap recognizer to the hosting controller view.
    func makeUIView(context: Context) -> UIView { // Handles makeUIView flow.
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    /// Ensures the recognizer is attached to the latest hosting view.
    func updateUIView(_ uiView: UIView, context: Context) { // Handles updateUIView flow.
        context.coordinator.attachRecognizer(from: uiView)
    }

    /// Builds coordinator that owns recognizer lifecycle.
    func makeCoordinator() -> Coordinator { // Handles makeCoordinator flow.
        Coordinator(onOutsideTap: onOutsideTap)
    }

    /// Cleans up attached recognizer when the bridge view is removed.
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) { // Handles dismantleUIView flow.
        coordinator.detachRecognizer()
    }

    /// Coordinator that routes outside taps to keyboard dismissal callback.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Callback fired when an outside tap is detected.
        private let onOutsideTap: () -> Void
        /// Installed recognizer instance.
        private var recognizer: UITapGestureRecognizer?
        /// View currently hosting the recognizer.
        private weak var hostView: UIView?

        /// Initializes coordinator with outside-tap callback.
        init(onOutsideTap: @escaping () -> Void) { // Initializes this type.
            self.onOutsideTap = onOutsideTap
        }

        /// Attaches recognizer to the closest view-controller root view.
        func attachRecognizer(from bridgeView: UIView) {
            guard let resolvedHostView = resolveHostView(from: bridgeView) else { return }
            if hostView === resolvedHostView { return }
            detachRecognizer()

            let installedRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleOutsideTap))
            installedRecognizer.cancelsTouchesInView = false
            installedRecognizer.delegate = self
            resolvedHostView.addGestureRecognizer(installedRecognizer)
            recognizer = installedRecognizer
            hostView = resolvedHostView
        }

        /// Detaches recognizer from current host view.
        func detachRecognizer() {
            if let recognizer, let hostView {
                hostView.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            hostView = nil
        }

        /// Handles tap recognizer callback.
        @objc private func handleOutsideTap() {
            onOutsideTap()
        }

        /// Prevents recognizer from reacting to taps inside text input controls.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { // Handles gestureRecognizer shouldReceive flow.
            guard let touchedView = touch.view else { return true }
            return !isTextInputView(touchedView)
        }

        /// Allows control taps to continue normally while still dismissing keyboard.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { // Handles gestureRecognizer shouldRecognizeSimultaneouslyWith flow.
            true
        }

        /// Resolves the best host view for recognizer installation.
        private func resolveHostView(from bridgeView: UIView) -> UIView? {
            var responder: UIResponder? = bridgeView
            while let currentResponder = responder {
                if let viewController = currentResponder as? UIViewController {
                    return viewController.view
                }
                responder = currentResponder.next
            }
            return bridgeView.window
        }

        /// Returns whether the tapped view belongs to a text input control hierarchy.
        private func isTextInputView(_ view: UIView) -> Bool {
            if view is UITextField || view is UITextView {
                return true
            }
            if let superview = view.superview {
                return isTextInputView(superview)
            }
            return false
        }
    }
}
