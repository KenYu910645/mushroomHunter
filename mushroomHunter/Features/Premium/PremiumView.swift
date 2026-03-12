//
//  PremiumView.swift
//  mushroomHunter
//
//  Purpose:
//  - Presents the premium subscription paywall, current status, and purchase controls.
//
//  Defined in this file:
//  - PremiumView premium subscription screen.
//
import SwiftUI

/// Premium subscription screen shown from the Profile tab.
struct PremiumView: View {
    /// Shared session state used to render current premium status and wallet benefits.
    @EnvironmentObject private var session: UserSessionStore
    /// Shared premium manager that owns StoreKit and backend syncing.
    @EnvironmentObject private var premiumStore: PremiumStore
    /// Dismiss action for the sheet presentation.
    @Environment(\.dismiss) private var dismiss

    /// Body content for the premium paywall screen.
    var body: some View {
        NavigationStack {
            List {
                statusSection
                benefitsSection
                purchaseSection
                legalSection
            }
            .navigationTitle(LocalizedStringKey("premium_title"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityIdentifier("premium_close_button")
                }
            }
            .task {
                await premiumStore.loadProductIfNeeded()
            }
            .overlay {
                if let statusMessage = premiumStore.statusMessage, statusMessage.isEmpty == false {
                    MessageBox(
                        title: NSLocalizedString("premium_title", comment: ""),
                        message: statusMessage,
                        buttons: [
                            MessageBoxButton(
                                id: "premium_status_ok",
                                title: NSLocalizedString("common_ok", comment: "")
                            ) {
                                premiumStore.statusMessage = nil
                            }
                        ]
                    )
                }

                if let errorMessage = premiumStore.errorMessage, errorMessage.isEmpty == false {
                    MessageBox(
                        title: NSLocalizedString("common_error", comment: ""),
                        message: errorMessage,
                        buttons: [
                            MessageBoxButton(
                                id: "premium_error_ok",
                                title: NSLocalizedString("common_ok", comment: "")
                            ) {
                                premiumStore.errorMessage = nil
                            }
                        ]
                    )
                }
            }
        }
    }

    /// Current subscription status summary shown at the top of the paywall.
    private var statusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(session.isPremium ? LocalizedStringKey("premium_status_active") : LocalizedStringKey("premium_status_inactive"))
                    .font(.headline)

                Text(session.isPremium ? renewalMessage : NSLocalizedString("premium_status_free_summary", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if premiumStore.isSyncingEntitlement {
                    ProgressView(LocalizedStringKey("premium_syncing"))
                        .accessibilityIdentifier("premium_syncing_indicator")
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Benefit list describing what premium unlocks for the user.
    private var benefitsSection: some View {
        Section(LocalizedStringKey("premium_benefits_header")) {
            benefitRow(
                titleKey: "premium_benefit_daily_reward_title",
                detailKey: "premium_benefit_daily_reward_detail"
            )
            benefitRow(
                titleKey: "premium_benefit_host_limit_title",
                detailKey: "premium_benefit_host_limit_detail"
            )
            benefitRow(
                titleKey: "premium_benefit_join_limit_title",
                detailKey: "premium_benefit_join_limit_detail"
            )
        }
    }

    /// Purchase controls with price, subscribe action, and restore action.
    private var purchaseSection: some View {
        Section(LocalizedStringKey("premium_purchase_header")) {
            LabeledContent(LocalizedStringKey("premium_monthly_price_label")) {
                if premiumStore.isLoadingProduct {
                    Text(LocalizedStringKey("common_loading"))
                } else {
                    Text(premiumStore.monthlyPriceText)
                }
            }

            Button {
                Task {
                    await premiumStore.purchasePremium(session: session)
                }
            } label: {
                if premiumStore.isPurchasing {
                    ProgressView()
                } else {
                    Text(session.isPremium ? LocalizedStringKey("premium_subscribe_manage_button") : LocalizedStringKey("premium_subscribe_button"))
                }
            }
            .disabled(premiumStore.isPurchasing || premiumStore.isRestoring || premiumStore.isLoadingProduct || premiumStore.monthlyProduct == nil)
            .accessibilityIdentifier("premium_subscribe_button")

            Button {
                Task {
                    await premiumStore.restorePurchases(session: session)
                }
            } label: {
                if premiumStore.isRestoring {
                    ProgressView()
                } else {
                    Text(LocalizedStringKey("premium_restore_button"))
                }
            }
            .disabled(premiumStore.isPurchasing || premiumStore.isRestoring)
            .accessibilityIdentifier("premium_restore_button")
        }
    }

    /// Legal links displayed to support App Store review requirements for subscriptions.
    private var legalSection: some View {
        Section(LocalizedStringKey("premium_legal_header")) {
            if let termsURL = URL(string: AppConfig.Premium.termsURLString) {
                Link(LocalizedStringKey("premium_terms_button"), destination: termsURL)
            } else {
                Text(LocalizedStringKey("premium_terms_button"))
            }

            if let privacyURL = URL(string: AppConfig.Premium.privacyURLString) {
                Link(LocalizedStringKey("premium_privacy_button"), destination: privacyURL)
            } else {
                Text(LocalizedStringKey("premium_privacy_button"))
            }

            Text(LocalizedStringKey("premium_legal_footer"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// One benefit row used by the paywall summary list.
    /// - Parameters:
    ///   - titleKey: Localized title key.
    ///   - detailKey: Localized detail/body key.
    /// - Returns: Styled benefit summary row.
    private func benefitRow(titleKey: String, detailKey: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(titleKey))
                .font(.headline)
            Text(LocalizedStringKey(detailKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// Localized renewal summary for active premium subscriptions.
    private var renewalMessage: String {
        guard let premiumExpirationDate = session.premiumExpirationDate else {
            return NSLocalizedString("premium_status_active_summary", comment: "")
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return String(
            format: NSLocalizedString("premium_status_renews_format", comment: ""),
            formatter.string(from: premiumExpirationDate)
        )
    }
}
