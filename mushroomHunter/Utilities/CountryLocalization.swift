//
//  CountryLocalization.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides shared locale-aware country and room-location display helpers.
//
//  Defined in this file:
//  - CountryLocalization and RoomLocationLocalization utilities.
//
import Foundation

/// Shared country-name resolver used across room and postcard displays.
enum CountryLocalization {
    /// Fallback locale used to resolve legacy English country names.
    private static let englishLocale = Locale(identifier: "en_US_POSIX")

    /// Returns a locale-aware display name for a stored country value.
    /// Supports values saved as region code (for example `TW`) and localized/English names.
    static func displayName(forStoredCountryValue value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return "" }

        guard let countryCode = resolvedCountryCode(forStoredCountryValue: trimmedValue) else {
            return trimmedValue
        }
        return Locale.current.localizedString(forRegionCode: countryCode) ?? trimmedValue
    }

    /// Resolves ISO region code from a stored country value.
    /// - Parameter value: Stored country value from backend.
    /// - Returns: ISO region code when recognized.
    static func resolvedCountryCode(forStoredCountryValue value: String) -> String? {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedValue.count == 2 {
            let uppercaseCode = normalizedValue.uppercased()
            if Locale.isoRegionCodes.contains(uppercaseCode) {
                return uppercaseCode
            }
        }

        let normalizedMatchKey = normalizedCountryComparisonKey(normalizedValue)
        guard !normalizedMatchKey.isEmpty else { return nil }

        let localesToCheck: [Locale] = [Locale.current, englishLocale]
        for locale in localesToCheck {
            for regionCode in Locale.isoRegionCodes {
                guard let localizedName = locale.localizedString(forRegionCode: regionCode) else { continue }
                if normalizedCountryComparisonKey(localizedName) == normalizedMatchKey {
                    return regionCode
                }
            }
        }
        return nil
    }

    /// Normalizes country names for resilient locale-insensitive comparisons.
    /// - Parameter value: Country string to normalize.
    /// - Returns: Lowercased, width-insensitive, diacritic-insensitive comparison key.
    private static func normalizedCountryComparisonKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

/// Shared room-location formatter that localizes stored country names in `Country, City` text.
enum RoomLocationLocalization {
    /// Returns room location with localized country display while preserving city text.
    /// Supports separators used by room form parsing.
    static func displayLabel(forStoredLocation location: String) -> String {
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLocation.isEmpty else { return "" }

        let separators = [", ", " - ", " – ", " — "]
        for separator in separators {
            let parts = trimmedLocation.components(separatedBy: separator)
            if parts.count >= 2 {
                let countryPart = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let cityPart = parts.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
                let localizedCountry = CountryLocalization.displayName(forStoredCountryValue: countryPart)
                if cityPart.isEmpty { return localizedCountry }
                return "\(localizedCountry), \(cityPart)"
            }
        }

        return CountryLocalization.displayName(forStoredCountryValue: trimmedLocation)
    }
}
