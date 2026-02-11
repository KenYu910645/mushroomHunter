import SwiftUI
import UIKit

struct CreateProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var name: String = ""
    @State private var friendCode: String = ""
    @State private var nameError: String? = nil
    @State private var friendCodeError: String? = nil
    @State private var showValidationAlert: Bool = false
    @State private var isSubmitting: Bool = false

    @State private var nameFieldFocused: Bool = false
    @State private var friendCodeFieldFocused: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(LocalizedStringKey("profile_name"))
                            Spacer()
                            SelectAllTextField(
                                placeholderKey: "profile_name_placeholder",
                                text: $name,
                                isFirstResponder: $nameFieldFocused,
                                textContentType: .name,
                                autocapitalization: .words
                            )
                            .frame(height: 22)
                            .multilineTextAlignment(.trailing)
                        }

                        Text(LocalizedStringKey("profile_name_hint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if let error = nameError {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(LocalizedStringKey("profile_friend_code"))
                            Spacer()
                            SelectAllTextField(
                                placeholderKey: "profile_friend_code_placeholder",
                                text: $friendCode,
                                isFirstResponder: $friendCodeFieldFocused,
                                keyboardType: .numberPad,
                                textContentType: .oneTimeCode,
                                autocapitalization: .none,
                                autocorrection: .no
                            ) { newValue in
                                let digitsOnly = newValue.filter { $0.isNumber }
                                if digitsOnly != newValue {
                                    friendCode = digitsOnly
                                }
                                if friendCode.count > 12 {
                                    friendCode = String(friendCode.prefix(12))
                                }
                                friendCodeError = validateFriendCode(friendCode)
                            }
                            .frame(height: 22)
                            .multilineTextAlignment(.trailing)
                        }

                        Text(LocalizedStringKey("profile_friend_code_hint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if let error = friendCodeError {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    HStack {
                        Spacer()
                        Button(LocalizedStringKey("create_profile_button")) {
                            submit()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSubmitting)
                        Spacer()
                    }
                }
            }
            .navigationTitle(LocalizedStringKey("create_profile_title"))
            .navigationBarTitleDisplayMode(.inline)
            .alert(LocalizedStringKey("create_profile_error_title"), isPresented: $showValidationAlert) {
                Button(LocalizedStringKey("common_ok")) { }
            } message: {
                Text(LocalizedStringKey("create_profile_error_message"))
            }
            .onAppear {
                name = ""
                friendCode = ""
                nameError = nil
                friendCodeError = nil
                nameFieldFocused = true
            }
        }
    }

    private func submit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        nameError = validateName(trimmedName)
        friendCodeError = validateFriendCode(friendCode)

        guard nameError == nil, friendCodeError == nil else {
            showValidationAlert = true
            return
        }

        isSubmitting = true
        Task {
            await session.completeProfile(name: trimmedName, friendCode: friendCode)
            isSubmitting = false
        }
    }

    private func validateName(_ value: String) -> String? {
        if value.isEmpty {
            return NSLocalizedString("create_profile_name_error_required", comment: "")
        }
        return nil
    }

    private func validateFriendCode(_ code: String) -> String? {
        if code.isEmpty { return NSLocalizedString("profile_friend_code_error_required", comment: "") }
        if code.count != 12 { return NSLocalizedString("profile_friend_code_error_length", comment: "") }
        if code.allSatisfy({ $0.isNumber }) == false { return NSLocalizedString("profile_friend_code_error_digits", comment: "") }
        return nil
    }
}

private struct SelectAllTextField: UIViewRepresentable {
    let placeholderKey: String
    @Binding var text: String
    @Binding var isFirstResponder: Bool
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = .name
    var autocapitalization: UITextAutocapitalizationType = .words
    var autocorrection: UITextAutocorrectionType = .no
    var onChange: ((String) -> Void)? = nil

    func makeUIView(context: Context) -> UITextField {
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

    func updateUIView(_ uiView: UITextField, context: Context) {
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

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFirstResponder: $isFirstResponder, onChange: onChange)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        @Binding var isFirstResponder: Bool
        let onChange: ((String) -> Void)?

        init(text: Binding<String>, isFirstResponder: Binding<Bool>, onChange: ((String) -> Void)?) {
            _text = text
            _isFirstResponder = isFirstResponder
            self.onChange = onChange
        }

        @objc func textChanged(_ sender: UITextField) {
            let value = sender.text ?? ""
            text = value
            onChange?(value)
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isFirstResponder = true
            DispatchQueue.main.async {
                textField.selectAll(nil)
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isFirstResponder = false
        }
    }
}
