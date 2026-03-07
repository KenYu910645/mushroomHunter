//
//  TutorialProgress.swift
//  mushroomHunter
//
//  Purpose:
//  - Adds per-user local persistence helpers for interactive tutorial completion state.
//
import Foundation

extension UserSessionStore {
    /// Prefix for scenario-specific tutorial completion keys.
    private var tutorialCompletionKeyPrefix: String {
        "mh.tutorial"
    }

    /// Builds one user-scoped key for a tutorial scenario completion flag.
    /// - Parameter scenario: Tutorial scenario to scope.
    /// - Returns: Persisted key segment before uid scoping.
    private func tutorialCompletionKey(for scenario: TutorialScenario) -> String {
        "\(tutorialCompletionKeyPrefix).\(scenario.rawValue).completed"
    }

    /// Returns whether the signed-in user already completed a scenario tutorial.
    /// - Parameter scenario: Target tutorial scenario.
    /// - Returns: `true` when completion was already persisted for current uid.
    func isTutorialScenarioCompleted(_ scenario: TutorialScenario) -> Bool {
        guard let uid = authUid else { return false }
        let key = scopedKey(tutorialCompletionKey(for: scenario), uid: uid)
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Persists a tutorial scenario as completed for current signed-in user.
    /// - Parameter scenario: Target tutorial scenario.
    func markTutorialScenarioCompleted(_ scenario: TutorialScenario) {
        guard let uid = authUid else { return }
        let key = scopedKey(tutorialCompletionKey(for: scenario), uid: uid)
        UserDefaults.standard.set(true, forKey: key)
    }
}
