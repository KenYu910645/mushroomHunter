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
    /// Cached seller stars shown beside the seller name.
    let sellerStars: Int
    /// Cached pending rating task for the current viewer, if any.
    let pendingRatingContext: PostcardOrderRatingContext?
}

/// Postcard detail screen with buyer/seller actions for one listing.
struct PostcardView: View {
    /// Explicit tutorial presentation phase used by postcard detail flow.
    private enum PostcardTutorialPhase {
        /// Tutorial is not currently presented.
        case inactive
        /// Tutorial started from first-visit auto trigger.
        case firstVisit(TutorialScenario)
        /// Tutorial started from replay entry point.
        case replay(TutorialScenario)
    }

    /// Callback fired when this listing is deleted, used by browse to remove stale rows immediately.
    private let onListingDeleted: ((String) -> Void)?
    /// Optional postcard detail tutorial override used by replay entry points.
    private let tutorialScenarioOverride: TutorialScenario?
    /// Optional callback fired when replayed postcard detail tutorial finishes.
    private let onTutorialReplayFinished: (() -> Void)?
    /// Indicates push/deep-link should open order context immediately after first refresh.
    private let isOpeningOrderPageOnAppear: Bool
    /// Indicates first load should force latest backend state.
    private let isForceRefreshOnAppear: Bool
    /// Original listing id passed from browse/push route before tutorial scene overrides.
    private let initialListingId: String
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
    /// Pending completed-order rating task for the current viewer.
    @State private var pendingRatingContext: PostcardOrderRatingContext?
    /// Controls the room-style 1/2/3 star dialog visibility for postcard completion.
    @State private var isRatingDialogPresented: Bool = false
    /// Seller friend code shown to buyers.
    @State private var sellerFriendCode: String = ""
    /// Seller stars shown beside the seller name.
    @State private var sellerStars: Int = 0
    /// Controls temporary copied toast visibility.
    @State private var isCopyToastVisible: Bool = false
    /// Tracks whether first-load refresh has already run.
    @State private var isDidRunInitialRefresh: Bool = false
    /// Tracks whether order-context jump is still pending after first refresh.
    @State private var isPendingOpenOrderPageOnAppear: Bool
    /// Shared tutorial step-state controller for postcard detail coach marks.
    @StateObject private var postcardTutorialController = TutorialStepController()
    /// Explicit postcard tutorial phase for first-visit/replay/inactive states.
    @State private var postcardTutorialPhase: PostcardTutorialPhase = .inactive
    /// Optional floating toolbar highlight frame rendered in a top window.
    @State private var postcardTutorialFloatingHighlightFrame: CGRect? = nil
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
        tutorialScenarioOverride: TutorialScenario? = nil,
        onTutorialReplayFinished: (() -> Void)? = nil,
        isOpeningOrderPageOnAppear: Bool = false,
        isForceRefreshOnAppear: Bool = false
    ) {
        self.onListingDeleted = onListingDeleted
        self.tutorialScenarioOverride = tutorialScenarioOverride
        self.onTutorialReplayFinished = onTutorialReplayFinished
        self.isOpeningOrderPageOnAppear = isOpeningOrderPageOnAppear
        self.isForceRefreshOnAppear = isForceRefreshOnAppear
        self.initialListingId = listing.id
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

    /// Title shown in the postcard completion rating dialog.
    private var ratingDialogTitle: String {
        let counterpartName = pendingRatingContext?.counterpartName ?? (isSeller ? "Buyer" : "Seller")
        let titleKey = isSeller ? "postcard_msg_rate_buyer_title" : "postcard_msg_rate_seller_title"
        return String(format: NSLocalizedString(titleKey, comment: ""), counterpartName)
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
                    } else if let tutorialAssetName = TutorialScene.tutorialPostcardSnapshotAssetName(for: currentListing.id) {
                        TutorialPostcardSnapshotImageView(
                            assetName: tutorialAssetName,
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
                .tutorialHighlightAnchor(isPostcardTutorialActive ? .postcardDetailSnapshot : nil)

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
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(String(format: NSLocalizedString("postcard_seller_format", comment: ""), currentListing.sellerName))
                            Spacer(minLength: 0)
                            ColorfulTag(tone: .star, font: .footnote.weight(.semibold)) {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                    Text("\(sellerStars)")
                                        .monospacedDigit()
                                }
                            }
                        }
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
                .tutorialHighlightAnchor(isPostcardTutorialActive ? .postcardDetailInfoSection : nil)

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
                            .tutorialHighlightAnchor(isPostcardTutorialActive ? .postcardBuyerBuyButton : nil)
                            .accessibilityIdentifier("postcard_buy_button")
                        }
                    }
                }
            }
            .padding()
        }
        .background(Theme.backgroundGradient(for: scheme))
        .allowsHitTesting(!isPostcardTutorialActive)
        .background(
            TutorialHightlighAnchorUI(
                frame: postcardTutorialFloatingHighlightFrame,
                isVisible: isPostcardTutorialActive
            )
        )
        .toolbar {
            if isSeller {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !AppTesting.isUITesting {
                        Button {
                            isInviteSheetPresented = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .tutorialHighlightAnchor(isPostcardTutorialActive ? .postcardSellerShareButton : nil)
                        .accessibilityLabel(LocalizedStringKey("postcard_share_accessibility"))
                        .accessibilityIdentifier("postcard_share_button")
                        .disabled(isPostcardTutorialActive)
                    }

                    Button {
                        isShippingSheetPresented = true
                    } label: {
                        shippingToolbarIcon
                    }
                    .tutorialHighlightAnchor(isPostcardTutorialActive ? .postcardSellerShippingButton : nil)
                    .accessibilityLabel(LocalizedStringKey("postcard_shipping_accessibility"))
                    .accessibilityIdentifier("postcard_shipping_button")
                    .disabled(isPostcardTutorialActive)

                    if !AppTesting.isUITesting {
                        Button {
                            isEditSheetPresented = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .tutorialHighlightAnchor(isPostcardTutorialActive ? .postcardSellerEditButton : nil)
                        .accessibilityLabel(LocalizedStringKey("postcard_edit_accessibility"))
                        .accessibilityIdentifier("postcard_edit_button")
                        .disabled(isPostcardTutorialActive)
                    }
                }
            }
        }
        .task {
            guard !isDidRunInitialRefresh else { return }
            isDidRunInitialRefresh = true
            await handleInitialPostcardLoadFlow()
        }
        .refreshable {
            guard !isPostcardTutorialActive else { return }
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
            if isPostcardTutorialActive {
                Color.clear
            }
        }
        .overlayPreferenceValue(TutorialHighlightAnchorPreferenceKey.self) { anchors in
            if isPostcardTutorialActive {
                postcardDetailTutorialOverlay(anchors: anchors)
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
            } else if isRatingDialogPresented, pendingRatingContext != nil {
                MessageBox(
                    title: ratingDialogTitle,
                    message: "",
                    buttons: [
                        MessageBoxButton(
                            id: "postcard_rate_one_star",
                            title: NSLocalizedString("room_msg_rate_one_star", comment: ""),
                            role: .quiet
                        ) {
                            isRatingDialogPresented = false
                            Task { await submitPostcardRating(stars: 1) }
                        },
                        MessageBoxButton(
                            id: "postcard_rate_two_stars",
                            title: NSLocalizedString("room_msg_rate_two_stars", comment: ""),
                            role: .quiet
                        ) {
                            isRatingDialogPresented = false
                            Task { await submitPostcardRating(stars: 2) }
                        },
                        MessageBoxButton(
                            id: "postcard_rate_three_stars",
                            title: NSLocalizedString("room_msg_rate_three_stars", comment: ""),
                            role: .quiet
                        ) {
                            isRatingDialogPresented = false
                            Task { await submitPostcardRating(stars: 3) }
                        },
                        MessageBoxButton(
                            id: "postcard_rate_cancel",
                            title: NSLocalizedString("common_cancel", comment: ""),
                            role: .cancel
                        ) {
                            isRatingDialogPresented = false
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
        .onDisappear {
            if isPostcardTutorialActive {
                TutorialEventLogger.log(
                    screen: "postcard_detail",
                    scenario: activePostcardTutorialScenario,
                    event: .cancel,
                    source: postcardTutorialSourceLabel,
                    stepIndex: postcardTutorialController.stepIndex,
                    stepCount: currentPostcardTutorialScene?.steps.count
                )
                postcardTutorialController.end()
                session.endFeatureTutorialPresentation()
                postcardTutorialPhase = .inactive
            }
            postcardTutorialFloatingHighlightFrame = nil
        }
    }

    /// Refreshes listing data, seller friend code, and buyer order state.
    private func refreshListing(postcardId: String? = nil, isForceRefresh: Bool = false) async {
        let resolvedPostcardId = postcardId ?? currentListing.id
        let isListingDirty = await dirtyBits.isPostcardDetailDirty(postcardId: resolvedPostcardId)
        let isShouldForceRefresh = isForceRefresh || isListingDirty
        if !isShouldForceRefresh, await loadDetailFromCache() {
            return
        }
        if AppTesting.useMockPostcards {
            currentListing = currentListing.sellerId == AppTesting.userId
                ? AppTesting.fixtureOwnedPostcardListing()
                : AppTesting.fixturePostcardListing()
            sellerFriendCode = currentListing.sellerFriendCode
            sellerStars = isSeller ? max(0, session.stars) : 3
            pendingShippingCount = isSeller ? AppTesting.fixtureShippingRecipients().count : 0
            pendingRatingContext = nil
            isRatingDialogPresented = false
            return
        }

        do {
            if isShouldForceRefresh {
                await session.refreshProfileFromBackend()
            }
            if let refreshed = try await repo.fetchPostcard(postcardId: resolvedPostcardId) {
                currentListing = refreshed
                let cachedFriendCode = refreshed.sellerFriendCode.trimmingCharacters(in: .whitespacesAndNewlines)
                sellerFriendCode = cachedFriendCode
                sellerStars = try await repo.fetchUserStars(userId: refreshed.sellerId)
                await dirtyBits.clearPostcardDetailDirty(postcardId: refreshed.id)
                if !isSeller {
                    buyerOrder = try await repo.fetchLatestBuyerOrder(postcardId: refreshed.id)
                    pendingShippingCount = 0
                    let refreshedRatingContext = try await repo.fetchLatestBuyerRatingContext(postcardId: refreshed.id)
                    applyPendingRatingContext(refreshedRatingContext)
                } else {
                    buyerOrder = nil
                    await refreshPendingShippingCount(postcardId: refreshed.id)
                    let refreshedRatingContext = try await repo.fetchLatestSellerRatingContext(postcardId: refreshed.id)
                    applyPendingRatingContext(refreshedRatingContext)
                }
                await saveDetailToCache()
            } else {
                onListingDeleted?(resolvedPostcardId)
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
            await refreshListing(isForceRefresh: true)
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
        sellerStars = payload.value.sellerStars
        applyPendingRatingContext(payload.value.pendingRatingContext)
        return true
    }

    /// Saves current postcard detail state into structured cache.
    private func saveDetailToCache() async {
        let payload = PostcardDetailCachePayload(
            listing: currentListing,
            buyerOrder: buyerOrder,
            pendingShippingCount: pendingShippingCount,
            sellerFriendCode: sellerFriendCode,
            sellerStars: sellerStars,
            pendingRatingContext: pendingRatingContext
        )
        await cache.save(payload, key: detailCacheKey())
    }

    /// Applies latest pending rating task and presents the dialog when one is available.
    /// - Parameter context: Newly fetched pending rating task for the current viewer.
    private func applyPendingRatingContext(_ context: PostcardOrderRatingContext?) {
        pendingRatingContext = context
        isRatingDialogPresented = context != nil
    }

    /// Submits stars for the current postcard completion rating task.
    /// - Parameter stars: Number of stars between 1 and 3.
    private func submitPostcardRating(stars: Int) async {
        guard let ratingContext = pendingRatingContext else { return }

        do {
            if isSeller {
                try await repo.rateBuyerAfterCompletion(orderId: ratingContext.id, stars: stars)
            } else {
                try await repo.rateSellerAfterCompletion(orderId: ratingContext.id, stars: stars)
            }
            await dirtyBits.markPostcardDetailDirty(postcardId: currentListing.id)
            await session.refreshProfileFromBackend()
            await refreshListing(isForceRefresh: true)
        } catch {
            buyErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            isBuyErrorAlertPresented = true
        }
    }

    /// Current postcard detail tutorial scenario configuration.
    private var currentPostcardTutorialScene: TutorialScene.PostcardDetailTutorial.Scenario? {
        switch activePostcardTutorialScenario {
        case .postcardBuyerFirstVisit:
            return TutorialScene.PostcardBuyer.scenario
        case .postcardSellerFirstVisit:
            return TutorialScene.PostcardSeller.scenario
        case .mushroomBrowseFirstVisit,
             .roomPersonalFirstVisit,
             .roomHostFirstVisit,
             .postcardBrowseFirstVisit,
             .none:
            return nil
        }
    }

    /// Current postcard step converted into shared overlay step shape.
    private var currentPostcardOverlayStep: TutorialOverlayStep? {
        postcardTutorialController.currentStep
    }

    /// Indicates current postcard tutorial step is first.
    private var isPostcardTutorialFirstStep: Bool {
        postcardTutorialController.isFirstStep
    }

    /// Indicates current postcard tutorial step is last.
    private var isPostcardTutorialLastStep: Bool {
        postcardTutorialController.isLastStep
    }

    /// Indicates postcard detail tutorial overlay is currently active.
    private var isPostcardTutorialActive: Bool {
        switch postcardTutorialPhase {
        case .inactive:
            return false
        case .firstVisit, .replay:
            return postcardTutorialController.isActive
        }
    }

    /// Blocking highlight overlay rendered above live postcard detail content.
    /// - Parameter anchors: Live anchor map collected from detail descendants.
    @ViewBuilder
    private func postcardDetailTutorialOverlay(
        anchors: [TutorialHighlightTarget: [Anchor<CGRect>]]
    ) -> some View {
        if let overlayStep = currentPostcardOverlayStep {
            TutorialCoachOverlay(
                step: overlayStep,
                isFirstStep: isPostcardTutorialFirstStep,
                isLastStep: isPostcardTutorialLastStep,
                anchors: anchors,
                floatingToolbarHighlightFrame: $postcardTutorialFloatingHighlightFrame,
                onBack: showPreviousPostcardTutorialStep,
                onNext: advancePostcardTutorialStep
            )
        }
    }

    /// Handles initial detail load with tutorial-first flow for first entry scenarios.
    private func handleInitialPostcardLoadFlow() async {
        let postcardPreloadDecision = TurorialTrigger.resolvePostcardPreloadDecision(
            overrideScenario: tutorialScenarioOverride,
            isUITesting: AppTesting.isUITesting,
            isSeller: isSeller,
            isPostcardSellerScenarioCompleted: session.isTutorialScenarioCompleted(.postcardSellerFirstVisit),
            isPostcardBuyerScenarioCompleted: session.isTutorialScenarioCompleted(.postcardBuyerFirstVisit)
        )
        if case .start(let preloadScenario) = postcardPreloadDecision {
            beginPostcardTutorial(scenario: preloadScenario)
            return
        }
        if AppTesting.isUITesting {
            await refreshListing(isForceRefresh: isForceRefreshOnAppear)
            finalizePendingOrderPageAutoOpen()
            return
        }

        await refreshListing(isForceRefresh: isForceRefreshOnAppear)

        let postcardPostloadDecision = TurorialTrigger.resolvePostcardPostloadDecision(
            isSeller: isSeller,
            isPostcardSellerScenarioCompleted: session.isTutorialScenarioCompleted(.postcardSellerFirstVisit),
            isPostcardBuyerScenarioCompleted: session.isTutorialScenarioCompleted(.postcardBuyerFirstVisit)
        )
        if case .start(let postloadScenario) = postcardPostloadDecision {
            beginPostcardTutorial(scenario: postloadScenario)
            return
        }

        finalizePendingOrderPageAutoOpen()
    }

    /// Opens seller order queue once when push route requested auto-open behavior.
    private func finalizePendingOrderPageAutoOpen() {
        if isPendingOpenOrderPageOnAppear, isSeller {
            isShippingSheetPresented = true
        }
        isPendingOpenOrderPageOnAppear = false
    }

    /// Starts postcard interactive tutorial and applies fake tutorial detail scene.
    /// - Parameter scenario: Target postcard tutorial scenario.
    private func beginPostcardTutorial(scenario: TutorialScenario) {
        guard !isPostcardTutorialActive else { return }
        postcardTutorialPhase = tutorialScenarioOverride == nil ? .firstVisit(scenario) : .replay(scenario)
        guard let tutorialConfig = currentPostcardTutorialScene,
              tutorialConfig.steps.isEmpty == false else {
            postcardTutorialPhase = .inactive
            return
        }
        let overlaySteps = tutorialConfig.steps.map { tutorialStep in
            TutorialOverlayStep(
                highlightTarget: tutorialStep.highlightTarget,
                title: tutorialStep.title,
                message: tutorialStep.message
            )
        }
        guard postcardTutorialController.begin(steps: overlaySteps) else {
            postcardTutorialPhase = .inactive
            return
        }
        applyPostcardTutorialScene(tutorialConfig, scenario: scenario)
        session.beginFeatureTutorialPresentation()
        TutorialEventLogger.log(
            screen: "postcard_detail",
            scenario: scenario,
            event: .start,
            source: postcardTutorialSourceLabel,
            stepIndex: postcardTutorialController.stepIndex,
            stepCount: currentPostcardTutorialScene?.steps.count
        )
    }

    /// Applies fake postcard detail scene for the active tutorial.
    /// - Parameters:
    ///   - tutorialConfig: Resolved tutorial scene data.
    ///   - scenario: Active postcard tutorial scenario.
    private func applyPostcardTutorialScene(
        _ tutorialConfig: TutorialScene.PostcardDetailTutorial.Scenario,
        scenario: TutorialScenario
    ) {
        let sessionUserId = session.authUid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var tutorialListing = tutorialConfig.fakeListing
        if scenario == .postcardSellerFirstVisit, !sessionUserId.isEmpty {
            tutorialListing = PostcardListing(
                id: tutorialListing.id,
                sellerId: sessionUserId,
                title: tutorialListing.title,
                priceHoney: tutorialListing.priceHoney,
                location: tutorialListing.location,
                sellerName: session.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? tutorialListing.sellerName
                    : session.displayName,
                sellerFriendCode: session.friendCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? tutorialListing.sellerFriendCode
                    : session.friendCode,
                stock: tutorialListing.stock,
                imageUrl: tutorialListing.imageUrl,
                thumbnailUrl: tutorialListing.thumbnailUrl,
                createdAt: tutorialListing.createdAt
            )
        }
        if scenario == .postcardBuyerFirstVisit, !sessionUserId.isEmpty, tutorialListing.sellerId == sessionUserId {
            tutorialListing = PostcardListing(
                id: tutorialListing.id,
                sellerId: "tutorial-postcard-buyer-seller",
                title: tutorialListing.title,
                priceHoney: tutorialListing.priceHoney,
                location: tutorialListing.location,
                sellerName: tutorialListing.sellerName,
                sellerFriendCode: tutorialListing.sellerFriendCode,
                stock: tutorialListing.stock,
                imageUrl: tutorialListing.imageUrl,
                thumbnailUrl: tutorialListing.thumbnailUrl,
                createdAt: tutorialListing.createdAt
            )
        }

        currentListing = tutorialListing
        sellerFriendCode = tutorialListing.sellerFriendCode
        sellerStars = scenario == .postcardSellerFirstVisit ? max(0, session.stars) : 3
        pendingShippingCount = tutorialConfig.fakePendingShippingCount
        if let fakeBuyerOrderStatus = tutorialConfig.fakeBuyerOrderStatus {
            buyerOrder = PostcardBuyerOrder(
                id: "tutorial-buyer-order-\(tutorialListing.id)",
                postcardId: tutorialListing.id,
                status: fakeBuyerOrderStatus,
                holdHoney: tutorialListing.priceHoney,
                createdAt: Date().addingTimeInterval(-900)
            )
        } else {
            buyerOrder = nil
        }
    }

    /// Moves postcard tutorial to previous step when available.
    private func showPreviousPostcardTutorialStep() {
        postcardTutorialController.moveToPreviousStep()
        TutorialEventLogger.log(
            screen: "postcard_detail",
            scenario: activePostcardTutorialScenario,
            event: .back,
            source: postcardTutorialSourceLabel,
            stepIndex: postcardTutorialController.stepIndex,
            stepCount: currentPostcardTutorialScene?.steps.count
        )
    }

    /// Advances postcard tutorial to next step or completes when on final step.
    private func advancePostcardTutorialStep() {
        if postcardTutorialController.moveToNextStepOrFinish() {
            finishPostcardTutorial()
            return
        }
        TutorialEventLogger.log(
            screen: "postcard_detail",
            scenario: activePostcardTutorialScenario,
            event: .next,
            source: postcardTutorialSourceLabel,
            stepIndex: postcardTutorialController.stepIndex,
            stepCount: currentPostcardTutorialScene?.steps.count
        )
    }

    /// Completes postcard tutorial and restores normal detail data flow.
    private func finishPostcardTutorial() {
        let finishedScenario = activePostcardTutorialScenario
        let isReplayFlow: Bool
        switch postcardTutorialPhase {
        case .replay:
            isReplayFlow = true
        case .inactive, .firstVisit:
            isReplayFlow = false
        }
        TutorialEventLogger.log(
            screen: "postcard_detail",
            scenario: finishedScenario,
            event: .finish,
            source: postcardTutorialSourceLabel,
            stepIndex: postcardTutorialController.stepIndex,
            stepCount: currentPostcardTutorialScene?.steps.count
        )
        postcardTutorialController.end()
        postcardTutorialFloatingHighlightFrame = nil
        session.endFeatureTutorialPresentation()
        postcardTutorialPhase = .inactive

        if isReplayFlow {
            onTutorialReplayFinished?()
            return
        }

        if let finishedScenario {
            session.markTutorialScenarioCompleted(finishedScenario)
        }
        Task {
            await refreshListing(postcardId: initialListingId, isForceRefresh: true)
            finalizePendingOrderPageAutoOpen()
        }
    }

    /// Active postcard tutorial scenario resolved from explicit phase.
    private var activePostcardTutorialScenario: TutorialScenario? {
        switch postcardTutorialPhase {
        case .inactive:
            return nil
        case .firstVisit(let scenario), .replay(let scenario):
            return scenario
        }
    }

    /// Stable postcard tutorial source label used for structured logging.
    private var postcardTutorialSourceLabel: String {
        switch postcardTutorialPhase {
        case .replay:
            return "replay"
        case .inactive, .firstVisit:
            return "first_visit"
        }
    }

}
