//
//  PostcardView.swift
//  mushroomHunter
//
//  Purpose:
//  - Renders postcard listing detail and buyer/seller actions.
//
import SwiftUI

// MARK: - Detail

/// Codable postcard detail cache payload used for stale-first detail rendering.
struct PostcardDetailCachePayload: Codable {
    /// Cached postcard listing snapshot.
    let listing: PostcardListing
    /// Cached buyer order snapshot when current viewer is a buyer.
    let buyerOrder: PostcardBuyerOrder?
    /// Cached pending shipping count for seller toolbar badge.
    let pendingShippingCount: Int
    /// Cached seller friend code displayed in detail metadata.
    let sellerFriendCode: String
}

/// Postcard detail screen with buyer/seller actions for one listing.
struct PostcardView: View {
    /// Callback fired when this listing is deleted, used by browse to remove stale rows immediately.
    private let onListingDeleted: ((String) -> Void)?
    /// Indicates push/deep-link should open order context immediately after first refresh.
    private let isOpeningOrderPageOnAppear: Bool
    /// Indicates first load should force latest backend state.
    private let isForceRefreshOnAppear: Bool
    /// Controls buy confirmation dialog visibility.
    @State private var isBuyConfirmDialogPresented: Bool = false
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
    /// Count of seller orders that are waiting for shipping actions.
    @State private var pendingShippingCount: Int = 0
    /// Latest buyer order for current user and listing.
    @State private var buyerOrder: PostcardBuyerOrder?
    /// Controls receive confirmation alert visibility.
    @State private var isReceiveConfirmAlertPresented: Bool = false
    /// Controls receive success alert visibility.
    @State private var isReceiveSuccessAlertPresented: Bool = false
    /// Success message shown after buyer confirms receipt.
    @State private var receiveSuccessMessage: String = ""
    /// Seller friend code shown to buyers.
    @State private var sellerFriendCode: String = ""
    /// Controls temporary copied toast visibility.
    @State private var isCopyToastVisible: Bool = false
    /// Tracks whether first-load refresh has already run.
    @State private var isDidRunInitialRefresh: Bool = false
    /// Tracks whether order-context jump is still pending after first refresh.
    @State private var isPendingOpenOrderPageOnAppear: Bool
    /// Current color scheme used for themed background.
    @Environment(\.colorScheme) private var scheme
    /// Dismiss action for this detail screen.
    @Environment(\.dismiss) private var dismiss
    /// Shared user session store.
    @EnvironmentObject private var session: UserSessionStore
    /// Firebase-backed repository for listing/order actions.
    private let repo = FbPostcardRepo()
    /// Shared structured payload cache used for postcard detail stale-first loading.
    private let cache = RoomCache.shared
    /// Shared dirty-bit state used to force refresh after postcard/order mutations.
    private let dirtyBits = CacheDirtyBitStore.shared
    /// Fixed aspect ratio for the hero listing image.
    private let imageAspectRatio: CGFloat = 4.0 / 3.0
    /// Maximum width applied to hero listing image container.
    private let detailImageMaxWidth: CGFloat = 300

    /// Initializes the screen with an initial listing payload.
    /// - Parameters:
    ///   - listing: Listing selected from browse.
    ///   - isOpeningOrderPageOnAppear: True when route comes from order push and should open order context.
    ///   - isForceRefreshOnAppear: True when first refresh should prioritize latest backend state.
    init(
        listing: PostcardListing,
        onListingDeleted: ((String) -> Void)? = nil,
        isOpeningOrderPageOnAppear: Bool = false,
        isForceRefreshOnAppear: Bool = false
    ) {
        self.onListingDeleted = onListingDeleted
        self.isOpeningOrderPageOnAppear = isOpeningOrderPageOnAppear
        self.isForceRefreshOnAppear = isForceRefreshOnAppear
        _currentListing = State(initialValue: listing)
        _sellerFriendCode = State(initialValue: listing.sellerFriendCode)
        _isPendingOpenOrderPageOnAppear = State(initialValue: isOpeningOrderPageOnAppear)
    }

    /// Indicates whether the current user owns this listing.
    private var isSeller: Bool {
        if AppTesting.useMockPostcards, currentListing.sellerId == AppTesting.userId {
            return true
        }
        guard let uid = session.authUid else { return false }
        return uid == currentListing.sellerId
    }

    /// Indicates whether buyer receipt confirmation actions should be shown.
    private var isReceiveConfirmationAvailable: Bool {
        guard let order = buyerOrder else { return false }
        return order.status == .shipped
    }

    /// Indicates whether buyer currently has a pending order state.
    private var isBuyerOrderPending: Bool {
        guard let order = buyerOrder else { return false }
        return order.status == .sellerConfirmPending ||
            order.status == .awaitingShipping ||
            isReceiveConfirmationAvailable
    }

    /// Purchase confirmation message with tokenized honey icon and postcard title.
    private var purchaseConfirmMessage: String {
        let line1 = String(
            format: NSLocalizedString("postcard_msg_purchase_line1_template", comment: ""),
            currentListing.priceHoney,
            currentListing.title
        )
        let line2 = NSLocalizedString("postcard_msg_purchase_line2", comment: "")
        return "\(line1)\n\(line2)"
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
                        CachedPostcardImageView(
                            imageURL: url,
                            fallbackSystemImageName: "photo",
                            fallbackIconFont: .largeTitle
                        )
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
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(currentListing.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                        ColorfulTag(tone: .honey, font: .subheadline.weight(.semibold)) {
                            HStack(spacing: 4) {
                                Image("HoneyIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16, height: 16)
                                Text("\(currentListing.priceHoney)")
                                    .monospacedDigit()
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(currentListing.location.shortLabel)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: NSLocalizedString("postcard_seller_format", comment: ""), currentListing.sellerName))
                        HStack(spacing: 6) {
                            Text("\(NSLocalizedString("profile_friend_code", comment: "")): \(formattedFriendCode(sellerFriendCode))")
                            Button {
                                copyFriendCode(sellerFriendCode)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(LocalizedStringKey("room_copy_host_code_accessibility"))
                        }
                        if isSeller {
                            Text("Stock: \(currentListing.stock)")
                                .monospacedDigit()
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if !currentListing.location.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(currentListing.location.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if !isSeller {
                    Divider()
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        if let buyerStatusText = buyerStatusText {
                            Text(buyerStatusText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if isReceiveConfirmationAvailable {
                            Button {
                                isReceiveConfirmAlertPresented = true
                            } label: {
                                Text(LocalizedStringKey("postcard_receive_complete_button"))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("postcard_receive_complete_button")
                        } else if !isBuyerOrderPending {
                            Button {
                                if AppTesting.useMockPostcards {
                                    Task { await buyPostcard() }
                                } else {
                                    isBuyConfirmDialogPresented = true
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
                }
            }
            .padding()
        }
        .background(Theme.backgroundGradient(for: scheme))
        .toolbar {
            if isSeller {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !AppTesting.isUITesting {
                        Button {
                            isInviteSheetPresented = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(LocalizedStringKey("postcard_share_accessibility"))
                        .accessibilityIdentifier("postcard_share_button")
                    }

                    Button {
                        isShippingSheetPresented = true
                    } label: {
                        shippingToolbarIcon
                    }
                    .accessibilityLabel(LocalizedStringKey("postcard_shipping_accessibility"))
                    .accessibilityIdentifier("postcard_shipping_button")

                    if !AppTesting.isUITesting {
                        Button {
                            isEditSheetPresented = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel(LocalizedStringKey("postcard_edit_accessibility"))
                        .accessibilityIdentifier("postcard_edit_button")
                    }
                }
            }
        }
        .task {
            guard !isDidRunInitialRefresh else { return }
            isDidRunInitialRefresh = true
            await refreshListing(isForceRefresh: isForceRefreshOnAppear)
            if isPendingOpenOrderPageOnAppear, isSeller {
                isShippingSheetPresented = true
            }
            isPendingOpenOrderPageOnAppear = false
        }
        .refreshable {
            await refreshListing(isForceRefresh: true)
        }
        .sheet(isPresented: $isEditSheetPresented, onDismiss: {
            Task { await refreshListing() }
        }) {
            NavigationStack {
                PostcardCreateEditView(
                    listing: currentListing,
                    onDeleted: {
                        onListingDeleted?(currentListing.id)
                        dismiss()
                    },
                    onUpdated: { updatedListing in
                        currentListing = updatedListing
                        sellerFriendCode = updatedListing.sellerFriendCode
                    }
                )
                .navigationTitle(LocalizedStringKey("postcard_edit_title"))
            }
        }
        .sheet(isPresented: $isShippingSheetPresented, onDismiss: {
            Task { await refreshListing() }
        }) {
            NavigationStack {
                PostcardOrdersView(postcard: currentListing)
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
        .overlay {
            if isBuyConfirmDialogPresented {
                MessageBox(
                    title: NSLocalizedString("postcard_msg_purchase_title", comment: ""),
                    message: purchaseConfirmMessage,
                    buttons: [
                        MessageBoxButton(
                            id: "postcard_buy_confirm_order",
                            title: NSLocalizedString("postcard_msg_purchase_order_button", comment: "")
                        ) {
                            isBuyConfirmDialogPresented = false
                            Task { await buyPostcard() }
                        },
                        MessageBoxButton(
                            id: "postcard_buy_confirm_cancel",
                            title: NSLocalizedString("postcard_msg_purchase_cancel_button", comment: ""),
                            role: .cancel
                        ) {
                            isBuyConfirmDialogPresented = false
                        }
                    ]
                )
            } else if isReceiveConfirmAlertPresented {
                MessageBox(
                    title: NSLocalizedString("postcard_msg_receive_confirm_title", comment: ""),
                    message: NSLocalizedString("postcard_msg_receive_confirm_message", comment: ""),
                    buttons: [
                        MessageBoxButton(
                            id: "postcard_receive_confirm_confirm",
                            title: NSLocalizedString("postcard_msg_receive_confirm_received_button", comment: "")
                        ) {
                            isReceiveConfirmAlertPresented = false
                            Task { await confirmReceive() }
                        },
                        MessageBoxButton(
                            id: "postcard_receive_confirm_cancel",
                            title: NSLocalizedString("common_cancel", comment: ""),
                            role: .cancel
                        ) {
                            isReceiveConfirmAlertPresented = false
                        }
                    ]
                )
            } else if isBuySuccessAlertPresented {
                MessageBox(
                    title: NSLocalizedString("postcard_msg_buy_success_title", comment: ""),
                    message: NSLocalizedString("postcard_msg_buy_success_message", comment: ""),
                    buttons: [
                        MessageBoxButton(
                            id: "postcard_buy_success_ok",
                            title: NSLocalizedString("common_ok", comment: "")
                        ) {
                            isBuySuccessAlertPresented = false
                        }
                    ]
                )
            } else if isReceiveSuccessAlertPresented {
                MessageBox(
                    title: NSLocalizedString("postcard_msg_receive_success_title", comment: ""),
                    message: receiveSuccessMessage,
                    buttons: [
                        MessageBoxButton(
                            id: "postcard_receive_success_ok",
                            title: NSLocalizedString("common_ok", comment: "")
                        ) {
                            isReceiveSuccessAlertPresented = false
                        }
                    ]
                )
            } else if isBuyErrorAlertPresented {
                MessageBox(
                    title: NSLocalizedString("common_error", comment: ""),
                    message: buyErrorMessage,
                    buttons: [
                        MessageBoxButton(
                            id: "postcard_buy_error_ok",
                            title: NSLocalizedString("common_ok", comment: "")
                        ) {
                            isBuyErrorAlertPresented = false
                        }
                    ]
                )
            }
        }
    }

    /// Refreshes listing data, seller friend code, and buyer order state.
    private func refreshListing(isForceRefresh: Bool = false) async {
        let isListingDirty = await dirtyBits.isPostcardDetailDirty(postcardId: currentListing.id)
        let isShouldForceRefresh = isForceRefresh || isListingDirty
        if !isShouldForceRefresh, await loadDetailFromCache() {
            return
        }
        if AppTesting.useMockPostcards {
            currentListing = currentListing.sellerId == AppTesting.userId
                ? AppTesting.fixtureOwnedPostcardListing()
                : AppTesting.fixturePostcardListing()
            sellerFriendCode = currentListing.sellerFriendCode
            pendingShippingCount = isSeller ? AppTesting.fixtureShippingRecipients().count : 0
            return
        }

        do {
            if isShouldForceRefresh {
                await session.refreshProfileFromBackend()
            }
            if let refreshed = try await repo.fetchPostcard(postcardId: currentListing.id) {
                currentListing = refreshed
                let cachedFriendCode = refreshed.sellerFriendCode.trimmingCharacters(in: .whitespacesAndNewlines)
                sellerFriendCode = cachedFriendCode
                await dirtyBits.clearPostcardDetailDirty(postcardId: refreshed.id)
                if !isSeller {
                    buyerOrder = try await repo.fetchLatestBuyerOrder(postcardId: refreshed.id)
                    pendingShippingCount = 0
                } else {
                    buyerOrder = nil
                    await refreshPendingShippingCount(postcardId: refreshed.id)
                }
                await saveDetailToCache()
            } else {
                onListingDeleted?(currentListing.id)
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
            await dirtyBits.markPostcardBrowseDirty()
            await dirtyBits.markPostcardDetailDirty(postcardId: currentListing.id)
            await session.refreshProfileFromBackend()
            await refreshListing()
            isBuySuccessAlertPresented = true
        } catch {
            buyErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isBuyErrorAlertPresented = true
        }
    }

    /// Returns current pending-order message shown to buyer.
    private var buyerOrderPendingMessage: LocalizedStringKey {
        guard let order = buyerOrder else { return LocalizedStringKey("postcard_order_pending_message") }
        switch order.status {
        case .sellerConfirmPending, .awaitingShipping:
            return LocalizedStringKey("postcard_order_waiting_shipping_message")
        case .shipped:
            return LocalizedStringKey("postcard_order_waiting_buyer_confirm_message")
        default:
            return LocalizedStringKey("postcard_order_pending_message")
        }
    }

    /// Status text shown in buyer action section.
    private var buyerStatusText: LocalizedStringKey? {
        guard let order = buyerOrder else { return nil }
        switch order.status {
        case .sellerConfirmPending, .awaitingShipping:
            return LocalizedStringKey("postcard_status_waiting_seller_ship")
        case .shipped:
            return LocalizedStringKey("postcard_status_shipped_on_way")
        default:
            return buyerOrderPendingMessage
        }
    }

    /// Confirms postcard receipt for the latest buyer order.
    private func confirmReceive() async {
        guard let order = buyerOrder else { return }
        do {
            try await repo.confirmPostcardReceived(orderId: order.id)
            await dirtyBits.markPostcardBrowseDirty()
            await dirtyBits.markPostcardDetailDirty(postcardId: currentListing.id)
            await session.refreshProfileFromBackend()
            await refreshListing()
            receiveSuccessMessage = NSLocalizedString("postcard_msg_receive_success_message", comment: "")
            isReceiveSuccessAlertPresented = true
        } catch {
            buyErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isBuyErrorAlertPresented = true
        }
    }

    /// Toolbar shipping icon with a red dot indicator when seller has pending orders.
    @ViewBuilder
    private var shippingToolbarIcon: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "list.clipboard")

            if pendingShippingCount > 0 {
                ProfileActionDot()
                    .offset(x: 6, y: -4)
            }
        }
        .accessibilityValue(
            Text(
                pendingShippingCount > 0
                    ? "\(pendingShippingCount)"
                    : "0"
            )
        )
    }

    /// Refreshes seller pending-shipping order count for badge rendering.
    /// - Parameter postcardId: Listing id to scope shipping recipients query.
    private func refreshPendingShippingCount(postcardId: String) async {
        do {
            pendingShippingCount = try await repo.fetchShippingRecipients(postcardId: postcardId).count
        } catch {
            // Keep last badge count if recipient refresh fails.
        }
    }

    /// Returns stable cache key for current postcard detail payload.
    /// - Returns: Namespaced postcard detail cache key.
    private func detailCacheKey() -> String {
        "postcard.detail.\(currentListing.id)"
    }

    /// Applies cached postcard detail payload when available.
    /// - Returns: `true` when cached detail payload is loaded into state.
    private func loadDetailFromCache() async -> Bool {
        guard let payload = await cache.load(key: detailCacheKey(), as: PostcardDetailCachePayload.self) else {
            return false
        }
        currentListing = payload.value.listing
        buyerOrder = payload.value.buyerOrder
        pendingShippingCount = payload.value.pendingShippingCount
        sellerFriendCode = payload.value.sellerFriendCode
        return true
    }

    /// Saves current postcard detail state into structured cache.
    private func saveDetailToCache() async {
        let payload = PostcardDetailCachePayload(
            listing: currentListing,
            buyerOrder: buyerOrder,
            pendingShippingCount: pendingShippingCount,
            sellerFriendCode: sellerFriendCode
        )
        await cache.save(payload, key: detailCacheKey())
    }

}
