//
//  PostcardView.swift
//  mushroomHunter
//
//  Purpose:
//  - Renders postcard listing detail and buyer/seller actions.
//
import SwiftUI

// MARK: - Detail

/// Postcard detail screen with buyer/seller actions for one listing.
struct PostcardView: View {
    /// Controls buy confirmation alert visibility.
    @State private var isBuyConfirmPresented: Bool = false
    /// Controls seller edit sheet visibility.
    @State private var isEditSheetPresented: Bool = false
    /// Controls share invite sheet visibility.
    @State private var isInviteSheetPresented: Bool = false
    /// Listing currently displayed on the detail screen.
    @State private var currentListing: PostcardListing
    /// Indicates whether the buy request is in progress.
    @State private var isBuying: Bool = false
    /// Controls buy success alert visibility.
    @State private var isBuySuccessAlertPresented: Bool = false
    /// Controls generic buy/receive error alert visibility.
    @State private var isBuyErrorAlertPresented: Bool = false
    /// Error message shown in buy/receive error alert.
    @State private var buyErrorMessage: String = ""
    /// Controls seller shipping queue sheet visibility.
    @State private var isShippingSheetPresented: Bool = false
    /// Latest buyer order for current user and listing.
    @State private var buyerOrder: PostcardBuyerOrder?
    /// Controls receive confirmation alert visibility.
    @State private var isReceiveConfirmAlertPresented: Bool = false
    /// Controls "not received yet" alert visibility.
    @State private var isNotReceivedAlertPresented: Bool = false
    /// Controls receive success alert visibility.
    @State private var isReceiveSuccessAlertPresented: Bool = false
    /// Success message shown after buyer confirms receipt.
    @State private var receiveSuccessMessage: String = ""
    /// Seller friend code shown to buyers.
    @State private var sellerFriendCode: String = ""
    /// Controls temporary copied toast visibility.
    @State private var isCopyToastVisible: Bool = false
    /// Current color scheme used for themed background.
    @Environment(\.colorScheme) private var scheme
    /// Dismiss action for this detail screen.
    @Environment(\.dismiss) private var dismiss
    /// Shared user session store.
    @EnvironmentObject private var session: UserSessionStore
    /// Firebase-backed repository for listing/order actions.
    private let repo = FbPostcardRepo()
    /// Fixed aspect ratio for the hero listing image.
    private let imageAspectRatio: CGFloat = 4.0 / 3.0
    /// Maximum width applied to hero listing image container.
    private let detailImageMaxWidth: CGFloat = 300

    /// Initializes the screen with an initial listing payload.
    /// - Parameter listing: Listing selected from browse.
    init(listing: PostcardListing) {
        _currentListing = State(initialValue: listing)
        _sellerFriendCode = State(initialValue: listing.sellerFriendCode)
    }

    /// Indicates whether the current user owns this listing.
    private var isSeller: Bool {
        guard let uid = session.authUid else { return false }
        return uid == currentListing.sellerId
    }

    /// Indicates whether buyer receipt confirmation actions should be shown.
    private var isReceiveConfirmationAvailable: Bool {
        guard let order = buyerOrder else { return false }
        return order.status == .inTransit || order.status == .awaitingBuyerDecision
    }

    /// Indicates whether buyer currently has a pending order state.
    private var isBuyerOrderPending: Bool {
        guard let order = buyerOrder else { return false }
        return order.status == .awaitingSellerSend || isReceiveConfirmationAvailable
    }

    /// Main detail view content.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                        .frame(maxWidth: .infinity)
                        .aspectRatio(imageAspectRatio, contentMode: .fit)

                    if let urlString = currentListing.imageUrl, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            case .empty:
                                ProgressView()
                            @unknown default:
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: detailImageMaxWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                .aspectRatio(imageAspectRatio, contentMode: .fit)

                VStack(alignment: .leading, spacing: 8) {
                    Text(currentListing.title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(currentListing.location.shortLabel)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Text(String(format: NSLocalizedString("postcard_seller_format", comment: ""), currentListing.sellerName))
                        Text(formattedFriendCode(sellerFriendCode))
                            .foregroundStyle(.secondary)
                        Button {
                            copyFriendCode(sellerFriendCode)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LocalizedStringKey("room_copy_host_code_accessibility"))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    HStack {
                        HStack(spacing: 4) {
                            Text("\(currentListing.priceHoney)")
                                .fontWeight(.semibold)
                                .monospacedDigit()
                            Image("HoneyIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                        }
                        Spacer()
                        Text(String(format: NSLocalizedString("postcard_stock_format", comment: ""), currentListing.stock))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }

                    if !currentListing.location.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(currentListing.location.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if !isSeller && isReceiveConfirmationAvailable {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(LocalizedStringKey("postcard_receive_prompt"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button {
                                isNotReceivedAlertPresented = true
                            } label: {
                                Text(LocalizedStringKey("postcard_receive_no_button"))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                isReceiveConfirmAlertPresented = true
                            } label: {
                                Text(LocalizedStringKey("postcard_receive_yes_button"))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else if !isSeller && isBuyerOrderPending {
                    Text(LocalizedStringKey("postcard_order_pending_message"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if !isSeller {
                    Button {
                        if AppTesting.useMockPostcards {
                            Task { await buyPostcard() }
                        } else {
                            isBuyConfirmPresented = true
                        }
                    } label: {
                        if isBuying {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(LocalizedStringKey("postcard_buy_button"))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBuying)
                    .accessibilityIdentifier("postcard_buy_button")
                }
            }
            .padding()
        }
        .background(Theme.backgroundGradient(for: scheme))
        .navigationTitle(LocalizedStringKey("postcard_title"))
        .toolbar {
            if isSeller {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isInviteSheetPresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(LocalizedStringKey("postcard_share_accessibility"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isEditSheetPresented = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel(LocalizedStringKey("postcard_edit_accessibility"))
                    .accessibilityIdentifier("postcard_edit_button")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShippingSheetPresented = true
                    } label: {
                        Image(systemName: "shippingbox")
                    }
                    .accessibilityLabel(LocalizedStringKey("postcard_shipping_accessibility"))
                    .accessibilityIdentifier("postcard_shipping_button")
                }
            }
        }
        .alert(LocalizedStringKey("postcard_confirm_title"), isPresented: $isBuyConfirmPresented) {
            Button(LocalizedStringKey("common_confirm")) {
                Task { await buyPostcard() }
            }
            Button(LocalizedStringKey("common_cancel"), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("postcard_confirm_message"))
        }
        .alert(LocalizedStringKey("postcard_buy_success_title"), isPresented: $isBuySuccessAlertPresented) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(LocalizedStringKey("postcard_buy_success_message"))
        }
        .alert(LocalizedStringKey("postcard_receive_confirm_title"), isPresented: $isReceiveConfirmAlertPresented) {
            Button(LocalizedStringKey("common_confirm")) {
                Task { await confirmReceive() }
            }
            Button(LocalizedStringKey("common_cancel"), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("postcard_receive_confirm_message"))
        }
        .alert(LocalizedStringKey("postcard_receive_wait_title"), isPresented: $isNotReceivedAlertPresented) {
            Button(LocalizedStringKey("common_ok")) {
                Task { await markNotYetReceived() }
            }
        } message: {
            Text(LocalizedStringKey("postcard_receive_wait_message"))
        }
        .alert(LocalizedStringKey("postcard_receive_success_title"), isPresented: $isReceiveSuccessAlertPresented) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(receiveSuccessMessage)
        }
        .alert(LocalizedStringKey("common_error"), isPresented: $isBuyErrorAlertPresented) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(buyErrorMessage)
        }
        .task {
            await refreshListing()
        }
        .refreshable {
            await refreshListing()
        }
        .sheet(isPresented: $isEditSheetPresented, onDismiss: {
            Task { await refreshListing() }
        }) {
            NavigationStack {
                PostcardFormView(listing: currentListing) {
                    dismiss()
                }
                .navigationTitle(LocalizedStringKey("postcard_edit_title"))
            }
        }
        .sheet(isPresented: $isShippingSheetPresented) {
            NavigationStack {
                PostcardShippingView(postcard: currentListing)
            }
        }
        .sheet(isPresented: $isInviteSheetPresented) {
            InviteShareSheet(
                titleKey: LocalizedStringKey("postcard_invite_title"),
                hintText: String(format: NSLocalizedString("postcard_invite_hint", comment: ""), currentListing.title),
                inviteURL: PostcardInviteLink.makeURL(postcardId: currentListing.id),
                shareButtonKey: LocalizedStringKey("postcard_invite_share_button"),
                copyButtonKey: LocalizedStringKey("postcard_invite_copy_button"),
                unavailableDescriptionKey: LocalizedStringKey("postcard_invite_link_unavailable"),
                onCopyInviteLink: copyInviteLink
            )
        }
        .overlay(alignment: .top) {
            if isCopyToastVisible {
                Text(LocalizedStringKey("common_copied"))
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    /// Refreshes listing data, seller friend code, and buyer order state.
    private func refreshListing() async {
        if AppTesting.useMockPostcards {
            currentListing = currentListing.sellerId == AppTesting.userId
                ? AppTesting.fixtureOwnedPostcardListing()
                : AppTesting.fixturePostcardListing()
            sellerFriendCode = currentListing.sellerFriendCode
            return
        }

        do {
            if let refreshed = try await repo.fetchPostcard(postcardId: currentListing.id) {
                currentListing = refreshed
                let cachedFriendCode = refreshed.sellerFriendCode.trimmingCharacters(in: .whitespacesAndNewlines)
                sellerFriendCode = cachedFriendCode
                if !isSeller {
                    buyerOrder = try await repo.fetchLatestBuyerOrder(postcardId: refreshed.id)
                } else {
                    buyerOrder = nil
                }
            } else {
                dismiss()
            }
        } catch {
            // Keep existing content if network refresh fails.
        }
    }

    /// Formats friend code for UI display.
    /// - Parameter raw: Raw friend code value.
    /// - Returns: Grouped friend code string or fallback marker.
    private func formattedFriendCode(_ raw: String) -> String {
        let digits = FriendCode.clampedDigits(raw)
        guard digits.isEmpty == false else { return "-" }
        return FriendCode.formatted(digits)
    }

    /// Copies seller friend code digits to clipboard.
    /// - Parameter raw: Raw seller friend code value.
    private func copyFriendCode(_ raw: String) {
        let digits = FriendCode.digitsOnly(raw)
        guard digits.isEmpty == false else { return }
        UIPasteboard.general.string = digits
        showCopiedToast()
    }

    /// Copies generated invite link to clipboard.
    /// - Parameter link: Invite URL string.
    private func copyInviteLink(_ link: String) {
        guard !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        UIPasteboard.general.string = link
        showCopiedToast()
    }

    /// Shows a short-lived copied toast message.
    private func showCopiedToast() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isCopyToastVisible = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCopyToastVisible = false
                }
            }
        }
    }

    /// Executes buy request for current listing.
    private func buyPostcard() async {
        guard !isBuying else { return }
        isBuying = true
        defer { isBuying = false }

        if AppTesting.useMockPostcards {
            if session.canAffordHoney(currentListing.priceHoney) {
                _ = session.spendHoney(currentListing.priceHoney)
                isBuySuccessAlertPresented = true
            } else {
                buyErrorMessage = NSLocalizedString("postcard_error_not_enough_honey", comment: "")
                isBuyErrorAlertPresented = true
            }
            return
        }

        do {
            _ = try await repo.buyPostcard(postcardId: currentListing.id)
            await session.refreshProfileFromBackend()
            await refreshListing()
            isBuySuccessAlertPresented = true
        } catch {
            buyErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isBuyErrorAlertPresented = true
        }
    }

    /// Confirms postcard receipt for the latest buyer order.
    private func confirmReceive() async {
        guard let order = buyerOrder else { return }
        do {
            try await repo.confirmPostcardReceived(orderId: order.id)
            await session.refreshProfileFromBackend()
            await refreshListing()
            receiveSuccessMessage = NSLocalizedString("postcard_receive_success_message", comment: "")
            isReceiveSuccessAlertPresented = true
        } catch {
            buyErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isBuyErrorAlertPresented = true
        }
    }

    /// Marks the postcard as not yet received for the buyer order.
    private func markNotYetReceived() async {
        guard let order = buyerOrder else { return }
        do {
            try await repo.markPostcardNotYetReceived(orderId: order.id)
            await refreshListing()
        } catch {
            buyErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isBuyErrorAlertPresented = true
        }
    }
}
