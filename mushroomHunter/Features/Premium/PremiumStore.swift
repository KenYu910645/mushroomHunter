//
//  PremiumStore.swift
//  mushroomHunter
//
//  Purpose:
//  - Owns StoreKit premium product loading, purchase/restore flow, and backend entitlement syncing.
//
//  Defined in this file:
//  - PremiumStore premium subscription manager.
//
import Foundation
import Combine
import StoreKit
import FirebaseFunctions

/// Snapshot of the current premium entitlement resolved from StoreKit.
struct PremiumEntitlementSnapshot {
    /// Indicates whether the subscription is currently active.
    let isActive: Bool
    /// StoreKit product id associated with the entitlement.
    let productId: String
    /// Subscription expiration date when available.
    let expirationDate: Date?

    /// Empty entitlement snapshot used when no active subscription exists.
    static let inactive = PremiumEntitlementSnapshot(
        isActive: false,
        productId: "",
        expirationDate: nil
    )
}

/// Shared StoreKit manager for the single monthly premium subscription.
@MainActor
final class PremiumStore: ObservableObject {
    /// Singleton shared across app screens so transaction updates stay coordinated.
    static let shared = PremiumStore()

    /// StoreKit product currently loaded for the premium paywall.
    @Published private(set) var monthlyProduct: Product? = nil
    /// Indicates whether product metadata is loading from the App Store.
    @Published private(set) var isLoadingProduct: Bool = false
    /// Indicates whether the subscribe action is currently in flight.
    @Published private(set) var isPurchasing: Bool = false
    /// Indicates whether a restore-purchases request is in flight.
    @Published private(set) var isRestoring: Bool = false
    /// Indicates whether entitlement data is being pushed to backend.
    @Published private(set) var isSyncingEntitlement: Bool = false
    /// User-facing status message shown after purchase or restore actions succeed.
    @Published var statusMessage: String? = nil
    /// User-facing error message shown when StoreKit or backend sync fails.
    @Published var errorMessage: String? = nil

    /// Firebase callable handle used to persist subscription status onto the user document.
    private let functions = Functions.functions(region: "us-central1")
    /// Current subscription-update listener task.
    private var transactionUpdatesTask: Task<Void, Never>? = nil
    /// Session currently bound to entitlement refreshes.
    private weak var boundSession: UserSessionStore?
    /// Prevents duplicate transaction listeners across repeated root-view appearances.
    private var isObservingTransactions: Bool = false

    /// Initializes the singleton manager.
    private init() {}

    /// Cancels the StoreKit transaction listener when the singleton is torn down.
    deinit {
        transactionUpdatesTask?.cancel()
    }

    /// Current premium product id used throughout StoreKit and backend sync.
    var monthlyProductId: String {
        AppConfig.Premium.monthlyProductId
    }

    /// Human-readable App Store price string for the premium product.
    var monthlyPriceText: String {
        monthlyProduct?.displayPrice ?? NSLocalizedString("premium_price_unavailable", comment: "")
    }

    /// Prepares the store for the current signed-in session and refreshes entitlement state.
    /// - Parameter session: Shared session state that receives backend-refreshed entitlement values.
    func handleSessionChange(session: UserSessionStore) async {
        boundSession = session
        statusMessage = nil
        errorMessage = nil

        guard AppTesting.isUITesting == false else {
            monthlyProduct = nil
            return
        }

        if isObservingTransactions == false {
            startObservingTransactionUpdates()
        }

        await loadProductIfNeeded()

        guard session.isLoggedIn else {
            return
        }

        await refreshEntitlements(session: session)
    }

    /// Loads the monthly subscription product from App Store Connect.
    func loadProductIfNeeded() async {
        if AppTesting.isUITesting || monthlyProduct != nil || isLoadingProduct {
            return
        }

        isLoadingProduct = true
        defer { isLoadingProduct = false }

        do {
            let products = try await Product.products(for: [monthlyProductId])
            monthlyProduct = products.first
        } catch {
            errorMessage = NSLocalizedString("premium_error_load_product", comment: "")
        }
    }

    /// Starts the purchase flow for the monthly premium subscription.
    /// - Parameter session: Shared session state used for backend refresh after success.
    func purchasePremium(session: UserSessionStore) async {
        guard AppTesting.isUITesting == false else {
            errorMessage = NSLocalizedString("premium_error_unavailable_testing", comment: "")
            return
        }

        await loadProductIfNeeded()

        guard let monthlyProduct else {
            errorMessage = NSLocalizedString("premium_error_product_missing", comment: "")
            return
        }

        isPurchasing = true
        errorMessage = nil
        statusMessage = nil
        defer { isPurchasing = false }

        do {
            let purchaseResult = try await monthlyProduct.purchase()
            switch purchaseResult {
            case .success(let verificationResult):
                let transaction = try verifiedTransaction(from: verificationResult)
                await transaction.finish()
                await refreshEntitlements(session: session)
                statusMessage = NSLocalizedString("premium_purchase_success_message", comment: "")
            case .userCancelled:
                break
            case .pending:
                statusMessage = NSLocalizedString("premium_purchase_pending_message", comment: "")
            @unknown default:
                errorMessage = NSLocalizedString("premium_error_purchase_generic", comment: "")
            }
        } catch {
            errorMessage = normalizedStoreKitErrorMessage(from: error)
        }
    }

    /// Restores App Store purchases and re-syncs the latest entitlement to backend.
    /// - Parameter session: Shared session state used for backend refresh after restore.
    func restorePurchases(session: UserSessionStore) async {
        guard AppTesting.isUITesting == false else {
            errorMessage = NSLocalizedString("premium_error_unavailable_testing", comment: "")
            return
        }

        isRestoring = true
        errorMessage = nil
        statusMessage = nil
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements(session: session)
            statusMessage = NSLocalizedString("premium_restore_success_message", comment: "")
        } catch {
            errorMessage = normalizedStoreKitErrorMessage(from: error)
        }
    }

    /// Refreshes StoreKit entitlement state and syncs it to backend for the current user.
    /// - Parameter session: Shared session state used for backend refresh after sync.
    func refreshEntitlements(session: UserSessionStore) async {
        guard AppTesting.isUITesting == false else { return }
        errorMessage = nil

        let snapshot = await currentPremiumEntitlement()
        await syncEntitlement(snapshot, session: session)
    }

    /// Resolves the current active premium entitlement from StoreKit current entitlements.
    /// - Returns: Latest active entitlement snapshot, or `.inactive` when none exists.
    private func currentPremiumEntitlement() async -> PremiumEntitlementSnapshot {
        var latestSnapshot = PremiumEntitlementSnapshot.inactive

        for await verificationResult in Transaction.currentEntitlements {
            guard let transaction = try? verifiedTransaction(from: verificationResult) else {
                continue
            }
            guard transaction.productID == monthlyProductId else {
                continue
            }
            guard transaction.revocationDate == nil else {
                continue
            }

            let expirationDate = transaction.expirationDate
            let isActive = expirationDate.map { $0 > Date() } ?? true
            if isActive == false {
                continue
            }

            if let latestExpiration = latestSnapshot.expirationDate,
               let expirationDate,
               latestExpiration >= expirationDate {
                continue
            }

            latestSnapshot = PremiumEntitlementSnapshot(
                isActive: true,
                productId: transaction.productID,
                expirationDate: expirationDate
            )
        }

        return latestSnapshot
    }

    /// Sends the locally verified StoreKit entitlement state to backend and refreshes the shared session.
    /// - Parameters:
    ///   - snapshot: StoreKit-derived premium entitlement state.
    ///   - session: Shared session that should reflect backend truth after sync completes.
    private func syncEntitlement(_ snapshot: PremiumEntitlementSnapshot, session: UserSessionStore) async {
        guard session.authUid?.isEmpty == false else { return }

        isSyncingEntitlement = true
        defer { isSyncingEntitlement = false }

        let expirationDateMillis = snapshot.expirationDate.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) }
        let payload: [String: Any] = [
            "isPremium": snapshot.isActive,
            "productId": snapshot.productId,
            "expirationDateMillis": expirationDateMillis ?? NSNull()
        ]

        do {
            _ = try await functions.httpsCallable("syncPremiumSubscription").call(payload)
            await session.refreshProfileFromBackend()
        } catch {
            errorMessage = NSLocalizedString("premium_error_sync_entitlement", comment: "")
        }
    }

    /// Begins listening for StoreKit transaction updates so renewals and expirations refresh backend state.
    private func startObservingTransactionUpdates() {
        isObservingTransactions = true
        transactionUpdatesTask = Task.detached(priority: .background) { [weak self] in
            for await verificationResult in Transaction.updates {
                guard let self else { return }
                if let transaction = await self.verifiedTransactionFromBackground(verificationResult) {
                    await transaction.finish()
                }
                await self.refreshBoundSessionEntitlement()
            }
        }
    }

    /// Refreshes the currently bound session after a StoreKit transaction update arrives.
    private func refreshBoundSessionEntitlement() async {
        await MainActor.run {
            self.statusMessage = nil
        }
        guard let boundSession else { return }
        await refreshEntitlements(session: boundSession)
    }

    /// Verifies one background transaction update on the main actor and returns it to the detached listener task.
    /// - Parameter verificationResult: Raw StoreKit transaction verification result.
    /// - Returns: Verified transaction when validation succeeds.
    private func verifiedTransactionFromBackground(
        _ verificationResult: VerificationResult<Transaction>
    ) async -> Transaction? {
        await MainActor.run {
            try? self.verifiedTransaction(from: verificationResult)
        }
    }

    /// Unwraps a verified StoreKit transaction or throws when verification fails.
    /// - Parameter verificationResult: Raw StoreKit verification wrapper.
    /// - Returns: Verified transaction.
    private func verifiedTransaction(
        from verificationResult: VerificationResult<Transaction>
    ) throws -> Transaction {
        switch verificationResult {
        case .verified(let transaction):
            return transaction
        case .unverified:
            throw PremiumStoreError.unverifiedTransaction
        }
    }

    /// Maps StoreKit and backend failures into localized paywall error text.
    /// - Parameter error: Original thrown error.
    /// - Returns: User-facing localized message.
    private func normalizedStoreKitErrorMessage(from error: Error) -> String {
        if let premiumError = error as? PremiumStoreError {
            switch premiumError {
            case .unverifiedTransaction:
                return NSLocalizedString("premium_error_unverified_transaction", comment: "")
            }
        }
        return NSLocalizedString("premium_error_purchase_generic", comment: "")
    }
}

/// Premium manager internal error catalog.
private enum PremiumStoreError: Error {
    /// StoreKit transaction could not be cryptographically verified.
    case unverifiedTransaction
}
