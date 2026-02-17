//
//  ProfileTextField.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides reusable UIKit-backed text field wrappers for Profile forms.
//
//  Defined in this file:
//  - ProfileSelectAllTextField and coordinator bridge logic.
//
import SwiftUI
import UIKit

struct ProfileSelectAllTextField: UIViewRepresentable {
    let placeholderKey: String
    @Binding var text: String // State or dependency property.
    @Binding var isFirstResponder: Bool // State or dependency property.
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = .name
    var autocapitalization: UITextAutocapitalizationType = .words
    var autocorrection: UITextAutocorrectionType = .no
    var onChange: ((String) -> Void)? = nil

    func makeUIView(context: Context) -> UITextField { // Handles makeUIView flow.
        let tf = UITextField()
        tf.borderStyle = .none
        tf.textAlignment = .right
        tf.autocorrectionType = autocorrection
        tf.autocapitalizationType = autocapitalization
        tf.textContentType = textContentType
        tf.keyboardType = keyboardType
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
        }

        func textFieldDidEndEditing(_ textField: UITextField) { // Handles textFieldDidEndEditing flow.
            isFirstResponder = false
        }
    }
}
