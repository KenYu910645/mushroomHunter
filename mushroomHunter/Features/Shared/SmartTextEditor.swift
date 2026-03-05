//
//  SmartTextEditor.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides a shared UIKit-backed text editor wrapper that auto-selects text on focus.
//
//  Defined in this file:
//  - SmartTextEditor and coordinator bridge logic.
//
import SwiftUI
import UIKit

struct SmartTextEditor: UIViewRepresentable {
    @Binding var text: String // State or dependency property.
    @Binding var isFirstResponder: Bool // State or dependency property.
    var autocapitalization: UITextAutocapitalizationType = .sentences
    var autocorrection: UITextAutocorrectionType = .yes
    var textAlignment: NSTextAlignment = .natural
    var onChange: ((String) -> Void)? = nil

    func makeUIView(context: Context) -> UITextView { // Handles makeUIView flow.
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.textAlignment = textAlignment
        tv.autocapitalizationType = autocapitalization
        tv.autocorrectionType = autocorrection
        tv.delegate = context.coordinator
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) { // Handles updateUIView flow.
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

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String // State or dependency property.
        @Binding var isFirstResponder: Bool // State or dependency property.
        let onChange: ((String) -> Void)?

        init(text: Binding<String>, isFirstResponder: Binding<Bool>, onChange: ((String) -> Void)?) { // Initializes this type.
            _text = text
            _isFirstResponder = isFirstResponder
            self.onChange = onChange
        }

        func textViewDidChange(_ textView: UITextView) { // Handles textViewDidChange flow.
            let value = textView.text ?? ""
            text = value
            onChange?(value)
        }

        func textViewDidBeginEditing(_ textView: UITextView) { // Handles textViewDidBeginEditing flow.
            isFirstResponder = true
            DispatchQueue.main.async {
                textView.selectAll(nil)
            }
            scrollInputIntoVisibleArea(textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) { // Handles textViewDidEndEditing flow.
            isFirstResponder = false
        }

        /// Scrolls the enclosing scroll container to keep the focused editor visible above keyboard.
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
