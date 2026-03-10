//
//  TutorialMessageBox.swift
//  mushroomHunter
//
//  Purpose:
//  - Renders tutorial message text with optional bullet rows using "*" line prefixes.
//
import SwiftUI

/// Message body renderer used by tutorial overlays.
/// Lines prefixed with `*` or `＊` are displayed as bullet rows.
struct TutorialMessageBox: View {
    /// Raw message text from tutorial configuration.
    let message: String

    /// Parsed message lines preserving order for mixed paragraph/bullet rendering.
    private var parsedLines: [ParsedLine] {
        parseMessageLines(from: message)
    }

    /// Tutorial message content with per-line rendering.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parsedLines.enumerated()), id: \.offset) { _, line in
                switch line.kind {
                case .paragraph:
                    Text(line.text)
                        .fixedSize(horizontal: false, vertical: true)
                case .bullet:
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                        Text(line.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Splits and classifies tutorial message lines.
    /// - Parameter message: Original multi-line tutorial message text.
    /// - Returns: Ordered line models with paragraph or bullet classification.
    private func parseMessageLines(from message: String) -> [ParsedLine] {
        message
            .components(separatedBy: .newlines)
            .map { rawLine in
                let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)
                if let bulletContent = trimmedLine.removingBulletPrefix() {
                    return ParsedLine(kind: .bullet, text: bulletContent)
                }
                return ParsedLine(kind: .paragraph, text: trimmedLine)
            }
            .filter { !$0.text.isEmpty }
    }
}

private extension TutorialMessageBox {
    /// One parsed line from tutorial message text.
    struct ParsedLine {
        /// Rendering mode for this line.
        let kind: Kind
        /// Display content for this line.
        let text: String

        /// Supported rendering kinds for parsed lines.
        enum Kind {
            /// Plain paragraph line.
            case paragraph
            /// Bullet line parsed from an asterisk prefix.
            case bullet
        }
    }
}

private extension String {
    /// Removes supported bullet prefixes and returns bullet body text.
    /// - Returns: Bullet body when this line starts with `*` or `＊`; otherwise `nil`.
    func removingBulletPrefix() -> String? {
        if hasPrefix("*") {
            let bulletBody = dropFirst().trimmingCharacters(in: .whitespaces)
            return bulletBody.isEmpty ? nil : bulletBody
        }
        if hasPrefix("＊") {
            let bulletBody = dropFirst().trimmingCharacters(in: .whitespaces)
            return bulletBody.isEmpty ? nil : bulletBody
        }
        return nil
    }
}
