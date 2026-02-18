//
//  FriendCode.swift
//  mushroomHunter
//
//  Purpose:
//  - Centralizes friend-code sanitizing, validation, and display formatting.
//
import Foundation

/// Friend-code utility methods shared by profile, mushroom, postcard, and session flows.
enum FriendCode {
    /// Filters non-digit characters and preserves full digit length.
    static func digitsOnly(_ rawValue: String) -> String {
        rawValue.filter(\.isNumber)
    }

    /// Filters non-digit characters and clamps to the configured friend-code length.
    static func clampedDigits(_ rawValue: String) -> String {
        String(digitsOnly(rawValue).prefix(AppConfig.Profile.friendCodeDigits))
    }

    /// Returns localized validation error text, or `nil` if the friend code is valid.
    static func validationError(_ code: String) -> String? {
        if code.isEmpty {
            return NSLocalizedString("profile_friend_code_error_required", comment: "")
        }
        if code.count != AppConfig.Profile.friendCodeDigits {
            return NSLocalizedString("profile_friend_code_error_length", comment: "")
        }
        if code.allSatisfy(\.isNumber) == false {
            return NSLocalizedString("profile_friend_code_error_digits", comment: "")
        }
        return nil
    }

    /// Formats a digit string into groups of four characters for display.
    static func formatted(_ rawValue: String) -> String {
        let digits = rawValue.filter(\.isNumber)
        var chunks: [String] = []
        var chunkStart = digits.startIndex

        while chunkStart < digits.endIndex {
            let chunkEnd = digits.index(chunkStart, offsetBy: 4, limitedBy: digits.endIndex) ?? digits.endIndex
            chunks.append(String(digits[chunkStart..<chunkEnd]))
            chunkStart = chunkEnd
        }

        return chunks.joined(separator: " ")
    }
}
