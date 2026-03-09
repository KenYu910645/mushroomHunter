//
//  FeatureTutorialCoordinator.swift
//  mushroomHunter
//
//  Purpose:
//  - Centralizes tutorial start-decision logic so view files focus on rendering.
//
import Foundation

/// Decision payload returned by tutorial coordinators for first-load flows.
enum FeatureTutorialDecision {
    /// Begin tutorial with the specified scenario.
    case start(TutorialScenario)
    /// Continue with normal backend loading flow.
    case continueNormalFlow
}

/// Shared coordinator that determines whether each feature should start tutorial mode.
enum FeatureTutorialCoordinator {
    /// Resolves room tutorial decision before first backend room load.
    /// - Parameters:
    ///   - overrideScenario: Replay override provided by tutorial catalog entry point.
    ///   - isUITesting: Indicates UI test mode where feature tutorials are disabled.
    ///   - initialRoleSeed: Role hint seeded by browse route before backend load.
    ///   - isRoomHostScenarioCompleted: Completion flag for room host scenario.
    ///   - isRoomPersonalScenarioCompleted: Completion flag for room personal scenario.
    /// - Returns: Start scenario or continue with normal load.
    static func resolveRoomPreloadDecision(
        overrideScenario: TutorialScenario?,
        isUITesting: Bool,
        initialRoleSeed: RoomRole?,
        isRoomHostScenarioCompleted: Bool,
        isRoomPersonalScenarioCompleted: Bool
    ) -> FeatureTutorialDecision {
        if overrideScenario == .roomPersonalFirstVisit {
            return .start(.roomPersonalFirstVisit)
        }
        if overrideScenario == .roomHostFirstVisit {
            return .start(.roomHostFirstVisit)
        }
        if isUITesting {
            return .continueNormalFlow
        }
        if initialRoleSeed == .host, !isRoomHostScenarioCompleted {
            return .start(.roomHostFirstVisit)
        }
        if initialRoleSeed != nil, initialRoleSeed != .host, !isRoomPersonalScenarioCompleted {
            return .start(.roomPersonalFirstVisit)
        }
        return .continueNormalFlow
    }

    /// Resolves room tutorial decision after backend room load.
    /// - Parameters:
    ///   - role: Room role resolved from backend payload.
    ///   - isRoomHostScenarioCompleted: Completion flag for room host scenario.
    ///   - isRoomPersonalScenarioCompleted: Completion flag for room personal scenario.
    /// - Returns: Start scenario or continue with normal flow.
    static func resolveRoomPostloadDecision(
        role: RoomRole,
        isRoomHostScenarioCompleted: Bool,
        isRoomPersonalScenarioCompleted: Bool
    ) -> FeatureTutorialDecision {
        if role == .host, !isRoomHostScenarioCompleted {
            return .start(.roomHostFirstVisit)
        }
        if role != .host, !isRoomPersonalScenarioCompleted {
            return .start(.roomPersonalFirstVisit)
        }
        return .continueNormalFlow
    }

    /// Resolves postcard tutorial decision before first backend detail load.
    /// - Parameters:
    ///   - overrideScenario: Replay override provided by tutorial catalog entry point.
    ///   - isUITesting: Indicates UI test mode where feature tutorials are disabled.
    ///   - isSeller: Whether current viewer is listing owner.
    ///   - isPostcardSellerScenarioCompleted: Completion flag for postcard seller scenario.
    ///   - isPostcardBuyerScenarioCompleted: Completion flag for postcard buyer scenario.
    /// - Returns: Start scenario or continue with normal load.
    static func resolvePostcardPreloadDecision(
        overrideScenario: TutorialScenario?,
        isUITesting: Bool,
        isSeller: Bool,
        isPostcardSellerScenarioCompleted: Bool,
        isPostcardBuyerScenarioCompleted: Bool
    ) -> FeatureTutorialDecision {
        if overrideScenario == .postcardBuyerFirstVisit {
            return .start(.postcardBuyerFirstVisit)
        }
        if overrideScenario == .postcardSellerFirstVisit {
            return .start(.postcardSellerFirstVisit)
        }
        if isUITesting {
            return .continueNormalFlow
        }
        if isSeller, !isPostcardSellerScenarioCompleted {
            return .start(.postcardSellerFirstVisit)
        }
        if !isSeller, !isPostcardBuyerScenarioCompleted {
            return .start(.postcardBuyerFirstVisit)
        }
        return .continueNormalFlow
    }

    /// Resolves postcard tutorial decision after backend detail refresh.
    /// - Parameters:
    ///   - isSeller: Whether current viewer is listing owner after refresh.
    ///   - isPostcardSellerScenarioCompleted: Completion flag for postcard seller scenario.
    ///   - isPostcardBuyerScenarioCompleted: Completion flag for postcard buyer scenario.
    /// - Returns: Start scenario or continue with normal flow.
    static func resolvePostcardPostloadDecision(
        isSeller: Bool,
        isPostcardSellerScenarioCompleted: Bool,
        isPostcardBuyerScenarioCompleted: Bool
    ) -> FeatureTutorialDecision {
        if isSeller, !isPostcardSellerScenarioCompleted {
            return .start(.postcardSellerFirstVisit)
        }
        if !isSeller, !isPostcardBuyerScenarioCompleted {
            return .start(.postcardBuyerFirstVisit)
        }
        return .continueNormalFlow
    }
}
