//
//  SearchTokens.swift
//  mushroomHunter
//
//  Purpose:
//  - Builds normalized search tokens used for indexed text matching.
//
//  Defined in this file:
//  - SearchTokenBuilder normalization and token generation helpers.
//
import Foundation

enum SearchTokenBuilder {
    static func normalize(_ input: String) -> String {
        let lowered = input.lowercased()
        let folded = lowered.folding(options: .diacriticInsensitive, locale: .current)
        let cleaned = folded.map { char -> Character in
            if char.isLetter || char.isNumber { return char }
            if char == " " { return " " }
            return " "
        }
        let collapsed = String(cleaned)
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func queryTokens(from input: String) -> [String] {
        let normalized = normalize(input)
        guard !normalized.isEmpty else { return [] }
        return normalized.split(separator: " ").map { String($0) }
    }

    static func indexTokens(from inputs: [String]) -> [String] {
        let words = inputs
            .flatMap { queryTokens(from: $0) }
            .flatMap { prefixes(for: $0) }
        return Array(Set(words))
    }

    private static func prefixes(for word: String) -> [String] {
        let maxLen = min(word.count, 20)
        guard maxLen >= 2 else { return [] }
        return (2...maxLen).map { idx in
            String(word.prefix(idx))
        }
    }
}
