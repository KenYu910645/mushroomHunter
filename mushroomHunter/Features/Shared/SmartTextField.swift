//
//  SmartTextField.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides a shared UIKit-backed text field wrapper that auto-selects text on focus.
//
//  Defined in this file:
//  - SmartTextField and coordinator bridge logic.
//
import SwiftUI
import UIKit

struct SmartTextField: UIViewRepresentable {
    let placeholderKey: String
    @Binding var text: String // State or dependency property.
    @Binding var isFirstResponder: Bool // State or dependency property.
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = .name
    var autocapitalization: UITextAutocapitalizationType = .words
    var autocorrection: UITextAutocorrectionType = .no
    var textAlignment: NSTextAlignment = .left
    var onChange: ((String) -> Void)? = nil

    func makeUIView(context: Context) -> UITextField { // Handles makeUIView flow.
        let tf = UITextField()
        tf.borderStyle = .none
        tf.textAlignment = textAlignment
        tf.autocorrectionType = autocorrection
        tf.autocapitalizationType = autocapitalization
        tf.textContentType = textContentType
        tf.keyboardType = keyboardType
        tf.returnKeyType = .done
        tf.enablesReturnKeyAutomatically = true
        tf.placeholder = NSLocalizedString(placeholderKey, comment: "")
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        tf.delegate = context.coordinator
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) { // Handles updateUIView flow.
        if uiView.text != text {
            uiView.text = text
        }
        if isFirstResponder, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
            DispatchQueue.main.async {
                uiView.selectAll(nil)
            }
        } else if !isFirstResponder, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { // Handles makeCoordinator flow.
        Coordinator(text: $text, isFirstResponder: $isFirstResponder, onChange: onChange)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String // State or dependency property.
        @Binding var isFirstResponder: Bool // State or dependency property.
        let onChange: ((String) -> Void)?

        init(text: Binding<String>, isFirstResponder: Binding<Bool>, onChange: ((String) -> Void)?) { // Initializes this type.
            _text = text
            _isFirstResponder = isFirstResponder
            self.onChange = onChange
        }

        @objc func textChanged(_ sender: UITextField) {
            let value = sender.text ?? ""
            text = value
            onChange?(value)
        }

        func textFieldDidBeginEditing(_ textField: UITextField) { // Handles textFieldDidBeginEditing flow.
            isFirstResponder = true
            DispatchQueue.main.async {
                textField.selectAll(nil)
            }
            scrollInputIntoVisibleArea(textField)
        }

        func textFieldDidEndEditing(_ textField: UITextField) { // Handles textFieldDidEndEditing flow.
            isFirstResponder = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool { // Handles textFieldShouldReturn flow.
            textField.resignFirstResponder()
            isFirstResponder = false
            return true
        }

        /// Scrolls the enclosing scroll container to keep the focused field visible above keyboard.
        private func scrollInputIntoVisibleArea(_ view: UIView) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard let scrollView = self.resolveEnclosingScrollView(for: view) else { return }
                let targetRect = view.convert(view.bounds, to: scrollView).insetBy(dx: 0, dy: -28)
                scrollView.scrollRectToVisible(targetRect, animated: true)
            }
        }

        /// Finds the nearest parent scroll view that contains the edited control.
        private func resolveEnclosingScrollView(for view: UIView) -> UIScrollView? {
            var currentSuperview = view.superview
            while let superview = currentSuperview {
                if let scrollView = superview as? UIScrollView {
                    return scrollView
                }
                currentSuperview = superview.superview
            }
            return nil
        }
    }
}
