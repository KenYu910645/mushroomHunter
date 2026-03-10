//
//  TutorialCore.swift
//  mushroomHunter
//
//  Purpose:
//  - Defines core tutorial domain, persistence helpers, and shared overlay runtime.
//
import Foundation
import SwiftUI
import Combine

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

}

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

/// One normalized tutorial step payload used by shared tutorial overlay components.
struct TutorialOverlayStep {
    /// Optional highlight target resolved from registered live anchors.
    let highlightTarget: TutorialHighlightTarget?
    /// Step title shown in the message card.
    let title: String
    /// Step body shown in the message card.
    let message: String
}

/// Shared step-state controller used by tutorial-enabled screens.
@MainActor
final class TutorialStepController: ObservableObject {
    /// Indicates whether tutorial mode is currently active.
    @Published private(set) var isActive: Bool = false
    /// Zero-based current step index.
    @Published private(set) var stepIndex: Int = 0
    /// Ordered step payloads for the active tutorial session.
    private var steps: [TutorialOverlayStep] = []

    /// Current step payload, or nil when tutorial is inactive.
    var currentStep: TutorialOverlayStep? {
        guard isActive, steps.isEmpty == false else { return nil }
        return steps[stepIndex]
    }

    /// Indicates current step is the first step.
    var isFirstStep: Bool {
        stepIndex == 0
    }

    /// Indicates current step is the last step.
    var isLastStep: Bool {
        guard steps.isEmpty == false else { return true }
        return stepIndex >= steps.count - 1
    }

    /// Starts a tutorial session from the first step.
    /// - Parameter steps: Step payloads used by the tutorial flow.
    /// - Returns: `true` when the session starts successfully.
    @discardableResult
    func begin(steps: [TutorialOverlayStep]) -> Bool {
        guard isActive == false, steps.isEmpty == false else { return false }
        self.steps = steps
        stepIndex = 0
        isActive = true
        return true
    }

    /// Moves to the previous step when possible.
    func moveToPreviousStep() {
        guard stepIndex > 0 else { return }
        stepIndex -= 1
    }

    /// Moves to the next step when possible.
    /// - Returns: `true` when caller should finish tutorial instead of advancing.
    func moveToNextStepOrFinish() -> Bool {
        if isLastStep {
            return true
        }
        stepIndex += 1
        return false
    }

    /// Ends the current tutorial session and clears all step state.
    func end() {
        isActive = false
        stepIndex = 0
        steps = []
    }
}

/// Reusable blocking coach-mark overlay used by browse tutorial pages.
struct TutorialCoachOverlay: View {
    /// Active tutorial step payload.
    let step: TutorialOverlayStep
    /// Indicates active step is first in the flow.
    let isFirstStep: Bool
    /// Indicates active step is last in the flow.
    let isLastStep: Bool
    /// Live anchor map collected from descendants.
    let anchors: [TutorialHighlightTarget: [Anchor<CGRect>]]
    /// Optional binding used to mirror toolbar highlight frame into floating top-window stroke.
    let floatingToolbarHighlightFrame: Binding<CGRect?>?
    /// Callback fired when user taps "Back".
    let onBack: () -> Void
    /// Callback fired when user taps "Next"/"Done".
    let onNext: () -> Void

    /// Builds one reusable coach-mark overlay instance.
    /// - Parameters:
    ///   - step: Active tutorial step payload.
    ///   - isFirstStep: Indicates active step is first.
    ///   - isLastStep: Indicates active step is last.
    ///   - anchors: Live anchor map from descendants.
    ///   - floatingToolbarHighlightFrame: Optional floating highlight binding for toolbar targets.
    ///   - onBack: Back action callback.
    ///   - onNext: Next/done action callback.
    init(
        step: TutorialOverlayStep,
        isFirstStep: Bool,
        isLastStep: Bool,
        anchors: [TutorialHighlightTarget: [Anchor<CGRect>]],
        floatingToolbarHighlightFrame: Binding<CGRect?>? = nil,
        onBack: @escaping () -> Void,
        onNext: @escaping () -> Void
    ) {
        self.step = step
        self.isFirstStep = isFirstStep
        self.isLastStep = isLastStep
        self.anchors = anchors
        self.floatingToolbarHighlightFrame = floatingToolbarHighlightFrame
        self.onBack = onBack
        self.onNext = onNext
    }

    /// Coach-mark overlay content rendered above page content.
    var body: some View {
        GeometryReader { proxy in
            let highlightFrame = TutorialHighlightFrameResolver.resolveFrame(
                target: step.highlightTarget,
                anchors: anchors,
                proxy: proxy
            )
            let messageBoxY = TutorialHighlightFrameResolver.resolveMessageBoxCenterY(
                highlightFrame: highlightFrame,
                proxy: proxy
            )
            let isToolbarTarget = step.highlightTarget?.isNavigationToolbarActionTarget == true
            let floatingFrame = isToolbarTarget ? highlightFrame : nil

            ZStack {
                Color.clear
                    .onAppear {
                        floatingToolbarHighlightFrame?.wrappedValue = floatingFrame
                    }
                    .onChange(of: floatingFrame) { _, newValue in
                        floatingToolbarHighlightFrame?.wrappedValue = newValue
                    }

                Color.black.opacity(0.6)
                    .overlay {
                        if let highlightFrame {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .frame(width: highlightFrame.width, height: highlightFrame.height)
                                .position(x: highlightFrame.midX, y: highlightFrame.midY)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                    .ignoresSafeArea()

                if let highlightFrame, !isToolbarTarget {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.yellow, lineWidth: 2)
                        .frame(width: highlightFrame.width, height: highlightFrame.height)
                        .position(x: highlightFrame.midX, y: highlightFrame.midY)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(step.title)
                        .font(.headline)
                    TutorialMessageBox(message: step.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(width: max(0, proxy.size.width - 32), alignment: .leading)
                .position(x: proxy.size.width * 0.5, y: messageBoxY)

                VStack {
                    Spacer()
                    HStack {
                        Button(LocalizedStringKey("tutorial_back")) {
                            onBack()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(isFirstStep ? 0.2 : 0.45), in: Capsule())
                        .disabled(isFirstStep)

                        Spacer(minLength: 0)

                        Button(isLastStep ? String(localized: "common_done") : String(localized: "tutorial_next")) {
                            onNext()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.55), in: Capsule())
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, proxy.safeAreaInsets.bottom + 14)
                }
            }
        }
        .ignoresSafeArea()
    }
}
