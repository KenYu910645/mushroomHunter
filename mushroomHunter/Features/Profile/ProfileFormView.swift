//
//  ProfileFormView.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides a shared profile form used by onboarding (create) and profile editing.
//
import SwiftUI

/// Shared profile form used in create and edit flows.
struct ProfileFormView: View {
    /// Supported form presentation modes.
    enum Mode {
        /// First-time profile creation flow shown after sign-in.
        case create

        /// Profile editing flow shown from the profile tab.
        case edit
    }

    /// Shared user session used for profile updates.
    @EnvironmentObject private var session: UserSessionStore

    /// Dismiss action for sheet-based edit presentation.
    @Environment(\.dismiss) private var dismiss

    /// Current form mode driving title, button label, and initialization behavior.
    let mode: Mode

    /// Draft display name value.
    @State private var name: String = ""

    /// Draft friend code value.
    @State private var friendCode: String = ""

    /// Validation message for display name field.
    @State private var nameError: String? = nil

    /// Validation message for friend code field.
    @State private var friendCodeError: String? = nil

    /// Toggles generic validation alert when submit fails validation.
    @State private var showValidationAlert: Bool = false

    /// Toggles submit button disablement and prevents duplicate requests.
    @State private var isSubmitting: Bool = false

    /// Focus state for display name field.
    @State private var nameFieldFocused: Bool = false

    /// Focus state for friend code field.
    @State private var friendCodeFieldFocused: Bool = false

    /// Form title key based on mode.
    private var titleKey: LocalizedStringKey {
        switch mode {
        case .create:
            return LocalizedStringKey("create_profile_title")
        case .edit:
            return LocalizedStringKey("edit_profile_title")
        }
    }

    /// Primary action label key based on mode.
    private var actionKey: LocalizedStringKey {
        switch mode {
        case .create:
            return LocalizedStringKey("create_profile_button")
        case .edit:
            return LocalizedStringKey("edit_profile_button")
        }
    }

    /// Root form content including name and friend-code fields.
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    nameFieldSection
                    friendCodeFieldSection
                }

                Section {
                    HStack {
                        Spacer()
                        Button(actionKey) {
                            submit()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSubmitting)
                        Spacer()
                    }
                }
            }
            .navigationTitle(titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if mode == .edit {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(LocalizedStringKey("common_cancel")) {
                            dismiss()
                        }
                        .disabled(isSubmitting)
                    }
                }
            }
            .alert(LocalizedStringKey("create_profile_error_title"), isPresented: $showValidationAlert) {
                Button(LocalizedStringKey("common_ok")) { }
            } message: {
                Text(LocalizedStringKey("create_profile_error_message"))
            }
            .onAppear {
                initializeFormValues()
            }
        }
    }

    /// Name row with hint and validation message.
    private var nameFieldSection: some View {
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

            if let nameError {
                Text(nameError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    /// Friend-code row with digit filtering and validation message.
    private var friendCodeFieldSection: some View {
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
                    updateFriendCodeDraft(with: newValue)
                }
                .frame(height: 22)
                .multilineTextAlignment(.trailing)
            }

            Text(LocalizedStringKey("profile_friend_code_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let friendCodeError {
                Text(friendCodeError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    /// Initializes form state using either blank defaults or current profile values.
    private func initializeFormValues() {
        switch mode {
        case .create:
            name = ""
            friendCode = ""
        case .edit:
            name = session.displayName
            friendCode = session.friendCode.filter(\.isNumber)
        }
        nameError = nil
        friendCodeError = nil
        nameFieldFocused = true
        friendCodeFieldFocused = false
    }

    /// Applies digit-only friend code input and max-length clamping.
    private func updateFriendCodeDraft(with rawValue: String) {
        let digitsOnly = rawValue.filter(\.isNumber)
        friendCode = String(digitsOnly.prefix(AppConfig.Profile.friendCodeDigits))
        friendCodeError = validateFriendCode(friendCode)
    }

    /// Validates inputs and submits profile values to the shared session.
    private func submit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        nameError = validateName(trimmedName)
        friendCodeError = validateFriendCode(friendCode)

        guard nameError == nil, friendCodeError == nil else {
            showValidationAlert = true
            return
        }

        Task { @MainActor in
            isSubmitting = true
            defer { isSubmitting = false }
            await session.completeProfile(name: trimmedName, friendCode: friendCode)
            if mode == .edit {
                dismiss()
            }
        }
    }

    /// Validates display name according to create/edit profile requirements.
    private func validateName(_ value: String) -> String? {
        if value.isEmpty {
            return NSLocalizedString("create_profile_name_error_required", comment: "")
        }
        return nil
    }

    /// Validates friend code according to app-level profile rules.
    private func validateFriendCode(_ code: String) -> String? {
        if code.isEmpty {
            return NSLocalizedString("profile_friend_code_error_required", comment: "")
        }
        if code.count != AppConfig.Profile.friendCodeDigits {
            return NSLocalizedString("profile_friend_code_error_length", comment: "")
        }
        if code.allSatisfy(\.isNumber) == false {
            return NSLocalizedString("profile_friend_code_error_digits", comment: "")
        }
        return nil
    }
}
