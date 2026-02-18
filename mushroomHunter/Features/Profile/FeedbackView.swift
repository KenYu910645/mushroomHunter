//
//  FeedbackView.swift
//  mushroomHunter
//
//  Purpose:
//  - Hosts the in-app feedback compose view and its submit payload model.
//
import SwiftUI

/// In-app feedback composer opened from profile settings.
struct FeedbackView: View {
    /// Feedback payload emitted by the compose view when the user taps send.
    struct Payload {
        /// Subject line persisted in Firestore and included in notification emails.
        let subject: String

        /// User-provided feedback body text.
        let body: String
    }

    /// Dismiss action provided by SwiftUI sheet environment.
    @Environment(\.dismiss) private var dismiss

    /// Subject input value.
    @State private var subject: String = ""

    /// Focus request state for subject input.
    @State private var isSubjectFieldFocused: Bool = false

    /// Message input value.
    @State private var messageText: String = ""

    /// Focus request state for message editor.
    @State private var isMessageFieldFocused: Bool = false

    /// Toggles loading overlay while feedback is being submitted.
    @State private var isSubmitting: Bool = false

    /// Stores submit failure details for alert display.
    @State private var submissionError: String? = nil

    /// Controls visibility of the submit failure alert.
    @State private var isSubmissionErrorAlertPresented: Bool = false

    /// Submission callback supplied by the parent profile view.
    let onSend: (Payload) async throws -> Void

    /// Message body with surrounding whitespace removed for validation and submission.
    private var trimmedBody: String {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Subject value that falls back to a localized default when left blank.
    private var resolvedSubject: String {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSubject.isEmpty {
            return NSLocalizedString("feedback_subject_default", comment: "")
        }
        return trimmedSubject
    }

    /// Main feedback form content.
    private var formContent: some View {
        Form {
            Section {
                SelectAllTextField(
                    placeholderKey: "feedback_subject_placeholder",
                    text: $subject,
                    isFirstResponder: $isSubjectFieldFocused,
                    textAlignment: .left
                )
                .frame(height: 22)
                .accessibilityIdentifier("feedback_subject_field")

                SelectAllTextEditor(
                    text: $messageText,
                    isFirstResponder: $isMessageFieldFocused,
                    autocapitalization: .sentences,
                    autocorrection: .yes
                )
                .padding(.horizontal, 2)
                .frame(minHeight: 180)
                .accessibilityIdentifier("feedback_message_editor")
            } header: {
                Text(LocalizedStringKey("feedback_message_label"))
            }

            if AppTesting.isUITesting {
                Section {
                    Button(LocalizedStringKey("common_done")) {
                        subject = "UI Feedback"
                        messageText = "Feedback from UI test flow."
                    }
                    .accessibilityIdentifier("feedback_autofill_button")
                }
            }
        }
    }

    /// Feedback compose UI with toolbar actions and submission-state overlays.
    var body: some View {
        NavigationStack {
            formContent
                .navigationTitle(LocalizedStringKey("feedback_title"))
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(LocalizedStringKey("common_cancel")) {
                            dismiss()
                        }
                        .disabled(isSubmitting)
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(LocalizedStringKey("feedback_send_button")) {
                            submitFeedback()
                        }
                        .disabled(trimmedBody.isEmpty || isSubmitting)
                        .accessibilityIdentifier("feedback_send_button")
                    }
                }
                .overlay {
                    if isSubmitting {
                        ZStack {
                            Color.black.opacity(0.12)
                            ProgressView()
                        }
                        .ignoresSafeArea()
                    }
                }
                .alert(
                    LocalizedStringKey("feedback_submit_failed_title"),
                    isPresented: $isSubmissionErrorAlertPresented
                ) {
                    Button(LocalizedStringKey("common_done")) { }
                } message: {
                    Text(submissionError ?? NSLocalizedString("feedback_submit_failed_message", comment: ""))
                }
        }
    }

    /// Submits feedback payload and handles success/failure UI transitions.
    private func submitFeedback() {
        let payload = Payload(subject: resolvedSubject, body: trimmedBody)

        Task { @MainActor in
            isSubmitting = true
            defer { isSubmitting = false }

            do {
                try await onSend(payload)
                dismiss()
            } catch {
                submissionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                isSubmissionErrorAlertPresented = true
            }
        }
    }
}
