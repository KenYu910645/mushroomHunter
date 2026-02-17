//
//  PostcardShippingView.swift
//  mushroomHunter
//
//  Purpose:
//  - Renders seller shipping queue and shipment confirmation actions.
//
import SwiftUI


struct PostcardShippingView: View {
    let postcard: PostcardListing

    @Environment(\.dismiss) private var dismiss // State or dependency property.
    @State private var recipients: [PostcardShippingRecipient] = [] // State or dependency property.
    @State private var isLoading: Bool = false // State or dependency property.
    @State private var isSendingOrderId: String? = nil // State or dependency property.
    @State private var errorMessage: String? // State or dependency property.
    @State private var showShipSuccessAlert: Bool = false // State or dependency property.
    private let repo = FirebasePostcardRepository()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            if isLoading && recipients.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if recipients.isEmpty {
                Text(LocalizedStringKey("postcard_shipping_empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recipients) { recipient in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recipient.buyerName)
                            .font(.headline)
                        Text(
                            String(
                                format: NSLocalizedString("postcard_shipping_friend_code_format", comment: ""),
                                recipient.buyerFriendCode.isEmpty ? "-" : recipient.buyerFriendCode
                            )
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        Button {
                            Task { await markSent(recipient) }
                        } label: {
                            if isSendingOrderId == recipient.id {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text(LocalizedStringKey("postcard_shipping_send_button"))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSendingOrderId != nil)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(LocalizedStringKey("postcard_shipping_title"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(LocalizedStringKey("common_close")) {
                    dismiss()
                }
            }
        }
        .task {
            await loadRecipients()
        }
        .refreshable {
            await loadRecipients()
        }
        .alert(LocalizedStringKey("postcard_shipping_sent_title"), isPresented: $showShipSuccessAlert) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(LocalizedStringKey("postcard_shipping_sent_message"))
        }
    }

    private func loadRecipients() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            recipients = try await repo.fetchShippingRecipients(postcardId: postcard.id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func markSent(_ recipient: PostcardShippingRecipient) async {
        guard isSendingOrderId == nil else { return }
        isSendingOrderId = recipient.id
        defer { isSendingOrderId = nil }

        do {
            try await repo.markPostcardSent(orderId: recipient.id)
            recipients.removeAll { $0.id == recipient.id }
            showShipSuccessAlert = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
