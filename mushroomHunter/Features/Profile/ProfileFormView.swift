//
//  ProfileFormView.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides a shared profile form used by onboarding (create) and profile editing.
//
import SwiftUI
import UIKit

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
                        .accessibilityIdentifier("profile_form_submit_button")
                        Spacer()
                    }

                    if AppTesting.isUITesting && mode == .edit {
                        Button(LocalizedStringKey("common_done")) {
                            name = "Tester Updated"
                            friendCode = "111122223333"
                        }
                        .accessibilityIdentifier("profile_form_autofill_button")
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .background(
                OutsideTapKeyboardDismissBridge {
                    dismissKeyboard()
                }
            )
            .navigationTitle(titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if mode == .edit {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(LocalizedStringKey("common_cancel")) {
                            dismiss()
                        }
                        .disabled(isSubmitting)
                        .accessibilityIdentifier("profile_form_cancel_button")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(LocalizedStringKey("common_done")) {
                        dismissKeyboard()
                    }
                }
            }
            .overlay {
                if showValidationAlert {
                    HoneyMessageBox(
                        title: NSLocalizedString("create_profile_error_title", comment: ""),
                        message: NSLocalizedString("create_profile_error_message", comment: ""),
                        buttons: [
                            HoneyMessageBoxButton(
                                id: "profile_form_validation_ok",
                                title: NSLocalizedString("common_ok", comment: "")
                            ) {
                                showValidationAlert = false
                            }
                        ]
                    )
                }
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
                .accessibilityIdentifier("profile_form_name_field")
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
                .accessibilityIdentifier("profile_form_friend_code_field")
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
            friendCode = FriendCode.clampedDigits(session.friendCode)
        }
        nameError = nil
        friendCodeError = nil
        nameFieldFocused = true
        friendCodeFieldFocused = false
    }

    /// Applies digit-only friend code input and max-length clamping.
    private func updateFriendCodeDraft(with rawValue: String) {
        friendCode = FriendCode.clampedDigits(rawValue)
        friendCodeError = FriendCode.validationError(friendCode)
    }

    /// Validates inputs and submits profile values to the shared session.
    private func submit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        nameError = validateName(trimmedName)
        friendCodeError = FriendCode.validationError(friendCode)

        guard nameError == nil, friendCodeError == nil else {
            showValidationAlert = true
            return
        }

        Task { @MainActor in
            isSubmitting = true
            defer { isSubmitting = false }
            let saveSource: UserSessionStore.ProfileSaveSource = (mode == .create) ? .onboarding : .edit
            let didSave = await session.saveProfile(name: trimmedName, friendCode: friendCode, source: saveSource)
            if mode == .edit, didSave {
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

    /// Clears profile form focus and asks UIKit to resign the current first responder.
    private func dismissKeyboard() {
        nameFieldFocused = false
        friendCodeFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
