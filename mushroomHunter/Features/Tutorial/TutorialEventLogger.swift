//
//  TutorialEventLogger.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides a consistent structured log format for tutorial flow diagnostics.
//
import Foundation

/// Structured tutorial events used for debug logging.
enum TutorialEventType: String {
    /// Tutorial flow started.
    case start
    /// User tapped previous step.
    case back
    /// User advanced to next step.
    case next
    /// Tutorial flow finished at final step.
    case finish
    /// Tutorial flow ended early because view disappeared.
    case cancel
}

/// Shared helper for logging tutorial events with stable key-value output.
enum TutorialEventLogger {
    /// Prints one structured tutorial event line.
    /// - Parameters:
    ///   - screen: Screen identifier such as `room_browse` or `postcard_detail`.
    ///   - scenario: Active tutorial scenario.
    ///   - event: Event type being logged.
    ///   - source: Trigger source such as `first_visit` or `replay`.
    ///   - stepIndex: Zero-based step index when available.
    ///   - stepCount: Total step count when available.
    static func log(
        screen: String,
        scenario: TutorialScenario?,
        event: TutorialEventType,
        source: String,
        stepIndex: Int?,
        stepCount: Int?
    ) {
        let scenarioValue = scenario?.rawValue ?? "none"
        let stepIndexValue = stepIndex.map(String.init) ?? "none"
        let stepCountValue = stepCount.map(String.init) ?? "none"
        print(
            "[TutorialEvent] screen=\(screen) scenario=\(scenarioValue) event=\(event.rawValue) source=\(source) stepIndex=\(stepIndexValue) stepCount=\(stepCountValue)"
        )
    }
}
