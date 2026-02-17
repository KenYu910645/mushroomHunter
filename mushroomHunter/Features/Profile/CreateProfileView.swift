//
//  CreateProfileView.swift
//  mushroomHunter
//
//  Purpose:
//  - Implements first-time profile creation UI and validation behavior.
//
//  Defined in this file:
//  - CreateProfileView form state, validation, and submit actions.
//
import SwiftUI

struct CreateProfileView: View {
    @EnvironmentObject private var session: UserSessionStore // State or dependency property.
    @State private var name: String = "" // State or dependency property.
    @State private var friendCode: String = "" // State or dependency property.
    @State private var nameError: String? = nil // State or dependency property.
    @State private var friendCodeError: String? = nil // State or dependency property.
    @State private var showValidationAlert: Bool = false // State or dependency property.
    @State private var isSubmitting: Bool = false // State or dependency property.
    @State private var nameFieldFocused: Bool = false // State or dependency property.
    @State private var friendCodeFieldFocused: Bool = false // State or dependency property.
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
                                autocapitalization: .words,
                                textAlignment: .right
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
                                autocorrection: .no,
                                textAlignment: .right
                            ) { newValue in
                                let digitsOnly = newValue.filter { $0.isNumber }
                                if digitsOnly != newValue {
                                    friendCode = digitsOnly
                                }
                                if friendCode.count > AppConfig.Profile.friendCodeDigits {
                                    friendCode = String(friendCode.prefix(AppConfig.Profile.friendCodeDigits))
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
        if code.count != AppConfig.Profile.friendCodeDigits { return NSLocalizedString("profile_friend_code_error_length", comment: "") }
        if code.allSatisfy({ $0.isNumber }) == false { return NSLocalizedString("profile_friend_code_error_digits", comment: "") }
        return nil
    }
}
