//
//  PostcardView.swift
//  mushroomHunter
//
//  Purpose:
//  - Renders postcard listing detail and buyer/seller actions.
//
import SwiftUI

// MARK: - Detail

struct PostcardView: View {
    @State private var showBuyConfirm: Bool = false // State or dependency property.
    @State private var showEditSheet: Bool = false // State or dependency property.
    @State private var showInviteSheet: Bool = false // State or dependency property.
    @State private var currentListing: PostcardListing // State or dependency property.
    @State private var isBuying: Bool = false // State or dependency property.
    @State private var showBuySuccessAlert: Bool = false // State or dependency property.
    @State private var showBuyErrorAlert: Bool = false // State or dependency property.
    @State private var buyErrorMessage: String = "" // State or dependency property.
    @State private var showShippingSheet: Bool = false // State or dependency property.
    @State private var buyerOrder: PostcardBuyerOrder? // State or dependency property.
    @State private var showReceiveConfirmAlert: Bool = false // State or dependency property.
    @State private var showNotReceivedAlert: Bool = false // State or dependency property.
    @State private var showReceiveSuccessAlert: Bool = false // State or dependency property.
    @State private var receiveSuccessMessage: String = "" // State or dependency property.
    @State private var sellerFriendCode: String = "" // State or dependency property.
    @State private var showCopyToast: Bool = false // State or dependency property.
    @Environment(\.colorScheme) private var scheme // State or dependency property.
    @Environment(\.dismiss) private var dismiss // State or dependency property.
    @EnvironmentObject private var session: UserSessionStore // State or dependency property.
    private let repo = FirebasePostcardRepository()
    private let imageAspectRatio: CGFloat = 4.0 / 3.0
    private let detailImageMaxWidth: CGFloat = 300

    init(listing: PostcardListing) { // Initializes this type.
        _currentListing = State(initialValue: listing)
    }

    private var isSeller: Bool {
        guard let uid = session.authUid else { return false }
        return uid == currentListing.sellerId
    }

    private var canConfirmReceive: Bool {
        guard let order = buyerOrder else { return false }
        return order.status == .inTransit || order.status == .awaitingBuyerDecision
    }

    private var hasPendingBuyerOrder: Bool {
        guard let order = buyerOrder else { return false }
        return order.status == .awaitingSellerSend || canConfirmReceive
    }

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

                if !isSeller && canConfirmReceive {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(LocalizedStringKey("postcard_receive_prompt"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button {
                                showNotReceivedAlert = true
                            } label: {
                                Text(LocalizedStringKey("postcard_receive_no_button"))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                showReceiveConfirmAlert = true
                            } label: {
                                Text(LocalizedStringKey("postcard_receive_yes_button"))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else if !isSeller && hasPendingBuyerOrder {
                    Text(LocalizedStringKey("postcard_order_pending_message"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if !isSeller {
                    Button {
                        showBuyConfirm = true
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
                        showInviteSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(LocalizedStringKey("postcard_share_accessibility"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showEditSheet = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel(LocalizedStringKey("postcard_edit_accessibility"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showShippingSheet = true
                    } label: {
                        Image(systemName: "shippingbox")
                    }
                    .accessibilityLabel(LocalizedStringKey("postcard_shipping_accessibility"))
                }
            }
        }
        .alert(LocalizedStringKey("postcard_confirm_title"), isPresented: $showBuyConfirm) {
            Button(LocalizedStringKey("common_confirm")) {
                Task { await buyPostcard() }
            }
            Button(LocalizedStringKey("common_cancel"), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("postcard_confirm_message"))
        }
        .alert(LocalizedStringKey("postcard_buy_success_title"), isPresented: $showBuySuccessAlert) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(LocalizedStringKey("postcard_buy_success_message"))
        }
        .alert(LocalizedStringKey("postcard_receive_confirm_title"), isPresented: $showReceiveConfirmAlert) {
            Button(LocalizedStringKey("common_confirm")) {
                Task { await confirmReceive() }
            }
            Button(LocalizedStringKey("common_cancel"), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("postcard_receive_confirm_message"))
        }
        .alert(LocalizedStringKey("postcard_receive_wait_title"), isPresented: $showNotReceivedAlert) {
            Button(LocalizedStringKey("common_ok")) {
                Task { await markNotYetReceived() }
            }
        } message: {
            Text(LocalizedStringKey("postcard_receive_wait_message"))
        }
        .alert(LocalizedStringKey("postcard_receive_success_title"), isPresented: $showReceiveSuccessAlert) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(receiveSuccessMessage)
        }
        .alert(LocalizedStringKey("common_error"), isPresented: $showBuyErrorAlert) {
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
        .sheet(isPresented: $showEditSheet, onDismiss: {
            Task { await refreshListing() }
        }) {
            NavigationStack {
                PostcardFormView(listing: currentListing) {
                    dismiss()
                }
                .navigationTitle(LocalizedStringKey("postcard_edit_title"))
            }
        }
        .sheet(isPresented: $showShippingSheet) {
            NavigationStack {
                PostcardShippingView(postcard: currentListing)
            }
        }
        .sheet(isPresented: $showInviteSheet) {
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
            if showCopyToast {
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

    private func refreshListing() async {
        do {
            if let refreshed = try await repo.fetchPostcard(postcardId: currentListing.id) {
                currentListing = refreshed
                sellerFriendCode = try await repo.fetchUserFriendCode(userId: refreshed.sellerId)
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

    private func formattedFriendCode(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        guard !digits.isEmpty else { return "-" }
        if digits.count <= 4 { return digits }
        if digits.count <= 8 {
            let first = digits.prefix(4)
            let second = digits.suffix(max(0, digits.count - 4))
            return "\(first) \(second)"
        }
        let first = digits.prefix(4)
        let second = digits.dropFirst(4).prefix(4)
        let third = digits.dropFirst(8).prefix(4)
        return "\(first) \(second) \(third)"
    }

    private func copyFriendCode(_ raw: String) {
        let digits = raw.filter { $0.isNumber }
        guard !digits.isEmpty else { return }
        UIPasteboard.general.string = digits
        showCopiedToast()
    }

    private func copyInviteLink(_ link: String) {
        guard !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        UIPasteboard.general.string = link
        showCopiedToast()
    }

    private func showCopiedToast() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showCopyToast = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCopyToast = false
                }
            }
        }
    }

    private func buyPostcard() async {
        guard !isBuying else { return }
        isBuying = true
        defer { isBuying = false }

        do {
            _ = try await repo.buyPostcard(postcardId: currentListing.id)
            await session.refreshProfileFromBackend()
            await refreshListing()
            showBuySuccessAlert = true
        } catch {
            buyErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showBuyErrorAlert = true
        }
    }

    private func confirmReceive() async {
        guard let order = buyerOrder else { return }
        do {
            try await repo.confirmPostcardReceived(orderId: order.id)
            await session.refreshProfileFromBackend()
            await refreshListing()
            receiveSuccessMessage = NSLocalizedString("postcard_receive_success_message", comment: "")
            showReceiveSuccessAlert = true
        } catch {
            buyErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showBuyErrorAlert = true
        }
    }

    private func markNotYetReceived() async {
        guard let order = buyerOrder else { return }
        do {
            try await repo.markPostcardNotYetReceived(orderId: order.id)
            await refreshListing()
        } catch {
            buyErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showBuyErrorAlert = true
        }
    }
}
