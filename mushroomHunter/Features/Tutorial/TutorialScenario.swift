//
//  TutorialScenario.swift
//  mushroomHunter
//
//  Purpose:
//  - Defines all in-app interactive tutorial scenarios and display metadata.
//
import SwiftUI

/// One tutorial scenario that can be auto-triggered or replayed from Help.
enum TutorialScenario: String, CaseIterable, Identifiable {
    /// Mushroom browse first-entry tutorial.
    case mushroomBrowseFirstVisit
    /// Room detail tutorial for personal (non-host) role.
    case roomPersonalFirstVisit
    /// Room detail tutorial for host role.
    case roomHostFirstVisit
    /// Postcard browse first-entry tutorial.
    case postcardBrowseFirstVisit
    /// Postcard detail tutorial for buyer role.
    case postcardBuyerFirstVisit
    /// Postcard detail tutorial for seller role.
    case postcardSellerFirstVisit

    /// Stable identity used by SwiftUI lists.
    var id: String {
        rawValue
    }

    /// Localized title key shown in tutorial lists.
    var titleKey: LocalizedStringKey {
        switch self {
        case .mushroomBrowseFirstVisit:
            return LocalizedStringKey("tutorial_scenario_mushroom_browse_title")
        case .roomPersonalFirstVisit:
            return LocalizedStringKey("tutorial_scenario_room_personal_title")
        case .roomHostFirstVisit:
            return LocalizedStringKey("tutorial_scenario_room_host_title")
        case .postcardBrowseFirstVisit:
            return LocalizedStringKey("tutorial_scenario_postcard_browse_title")
        case .postcardBuyerFirstVisit:
            return LocalizedStringKey("tutorial_scenario_postcard_buyer_title")
        case .postcardSellerFirstVisit:
            return LocalizedStringKey("tutorial_scenario_postcard_seller_title")
        }
    }

    /// Localized subtitle key shown in tutorial lists.
    var subtitleKey: LocalizedStringKey {
        switch self {
        case .mushroomBrowseFirstVisit:
            return LocalizedStringKey("tutorial_scenario_mushroom_browse_subtitle")
        case .roomPersonalFirstVisit:
            return LocalizedStringKey("tutorial_scenario_room_personal_subtitle")
        case .roomHostFirstVisit:
            return LocalizedStringKey("tutorial_scenario_room_host_subtitle")
        case .postcardBrowseFirstVisit:
            return LocalizedStringKey("tutorial_scenario_postcard_browse_subtitle")
        case .postcardBuyerFirstVisit:
            return LocalizedStringKey("tutorial_scenario_postcard_buyer_subtitle")
        case .postcardSellerFirstVisit:
            return LocalizedStringKey("tutorial_scenario_postcard_seller_subtitle")
        }
    }

    /// Indicates whether this scenario currently has an implemented interactive flow.
    var isImplemented: Bool {
        switch self {
        case .mushroomBrowseFirstVisit:
            return true
        case .roomPersonalFirstVisit,
             .roomHostFirstVisit,
             .postcardBrowseFirstVisit,
             .postcardBuyerFirstVisit,
             .postcardSellerFirstVisit:
            return false
        }
    }
}
