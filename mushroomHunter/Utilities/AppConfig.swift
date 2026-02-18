//
//  AppConfig.swift
//  mushroomHunter
//
//  Purpose:
//  - Centralizes owner-managed app settings that are not user-adjustable.
//
//  Defined in this file:
//  - AppConfig namespaces for Mushroom, Postcard, Profile, and Network tuning values.
//
import Foundation
import CoreGraphics

enum AppConfig {
    // MARK: - Tuning Guide
    // This file is for owner-managed settings only (not user-facing controls).
    //
    // How to tune safely:
    // - Change one group at a time, then test affected flows on device.
    // - Keep client defaults aligned with Firestore/Cloud Function expectations.
    // - Prefer increasing limits gradually to avoid heavy query/load regressions.
    //
    // Suggested checklist after changing any value:
    // 1) Browse Mushroom + Postcard tabs
    // 2) Host/create room and join room
    // 3) Register/edit postcard and place order
    // 4) Open Profile and verify list sections

    enum Network {
        // `requestTimeoutSeconds`
        // Purpose: timeout for async Firestore-backed loads in UI flows.
        // Increase if users frequently hit timeout on slow networks.
        // Decrease for faster failure/retry UX.
        // Suggested range: 6...20 seconds.
        static let requestTimeoutSeconds: TimeInterval = 10
    }

    enum Mushroom {
        // `browseListFetchLimit`
        // Purpose: max rooms fetched for Mushroom browse.
        // Higher = more data shown, but slower initial load.
        // Suggested range: 20...200.
        static let browseListFetchLimit: Int = 50

        // `profileListFetchLimit`
        // Purpose: max hosted/joined rooms loaded in Profile sections.
        // Suggested range: 20...200.
        static let profileListFetchLimit: Int = 50

        // `defaultMaxPlayersPerRoom`
        // Purpose: fallback room capacity when creating/mapping room docs.
        // Keep aligned with product rules and backend assumptions.
        // Suggested range: 2...20.
        static let defaultMaxPlayersPerRoom: Int = 10

        // `defaultHostRoomLimit`
        // Purpose: default max simultaneously hosted rooms per user.
        // Used as fallback when user doc has no limit values.
        // Suggested range: 1...10.
        static let defaultHostRoomLimit: Int = 1

        // `defaultJoinRoomLimit`
        // Purpose: default max simultaneously joined rooms per user.
        // Suggested range: 1...20.
        static let defaultJoinRoomLimit: Int = 3

        // `defaultFixedRaidCost`
        // Purpose: default honey cost when hosting a new room.
        // Must be >= `minFixedRaidCost`.
        // Suggested range: 1...200.
        static let defaultFixedRaidCost: Int = 10

        // `minFixedRaidCost`
        // Purpose: floor for room join/update deposit validation.
        // Suggested range: 1...50.
        static let minFixedRaidCost: Int = 1

        // `maxFixedRaidCost`
        // Purpose: upper bound in host form Stepper.
        // Suggested range: 100...100_000.
        static let maxFixedRaidCost: Int = 10_000

        // `defaultHostCountryCode`
        // Purpose: fallback country if device region cannot be resolved.
        // Must be an ISO 3166-1 alpha-2 code (e.g. "US", "TW", "JP").
        static let defaultHostCountryCode: String = "US"

        // `attributeFilterValues`
        // Purpose: browse filter source + backend string mapping.
        // IMPORTANT: values must match backend/Firestore attribute strings.
        static let attributeFilterValues: [String] = [
            "All", "Normal", "Fire", "Water", "Crystal", "Electric", "Poisonous"
        ]

        // `colorOptions` / `attributeOptions` / `sizeOptions`
        // Purpose: host form dropdown options.
        // Keep these in sync with enums and localization keys.
        static let colorOptions: [MushroomColor] = [
            .All, .Red, .Yellow, .Blue, .Purple, .White, .Gray, .Pink
        ]

        static let attributeOptions: [MushroomAttribute] = [
            .All, .Normal, .Fire, .Water, .Crystal, .Electric, .Poisonous
        ]

        static let sizeOptions: [MushroomSize] = [
            .All, .Small, .Normal, .Magnificent
        ]
    }

    enum Postcard {
        // `browseListFetchLimit`
        // Purpose: per-page postcard listings fetched for browse/search pagination.
        // Suggested range: 10...100.
        static let browseListFetchLimit: Int = 20

        // `profileListFetchLimit`
        // Purpose: max profile on-shelf/ordered postcard items.
        // Suggested range: 20...300.
        static let profileListFetchLimit: Int = 50

        // `maxPriceHoney`
        // Purpose: clamp user input for postcard price.
        // Keep high enough for market needs but below Int overflow risk.
        // Suggested range: 100...1_000_000_000.
        static let maxPriceHoney: Int = 1_000_000_000

        // `maxStock`
        // Purpose: clamp stock input in register/edit.
        // Suggested range: 1...1_000_000.
        static let maxStock: Int = 1_000_000

        // `maxDetailChars`
        // Purpose: max description detail length in postcard forms.
        // Suggested range: 50...500.
        static let maxDetailChars: Int = 100

        // `maxTitleChars`
        // Purpose: max postcard title length.
        // Suggested range: 10...80.
        static let maxTitleChars: Int = 20

        // `maxProvinceChars`
        // Purpose: max province/region text length.
        // Suggested range: 10...80.
        static let maxProvinceChars: Int = 20

        // `snapshotSize`
        // Purpose: rendered preview size for selected postcard image.
        // Suggested range: 120...260 points.
        static let snapshotSize: CGFloat = 180

        // `thumbnailPixelSize`
        // Purpose: square thumbnail edge length uploaded for browse card display.
        // Suggested range: 128...512.
        static let thumbnailPixelSize: CGFloat = 256

        // `thumbnailCompressionQuality`
        // Purpose: JPEG compression quality for uploaded thumbnail.
        // Suggested range: 0.4...0.9.
        static let thumbnailCompressionQuality: CGFloat = 0.68

        // `searchDebounceNanoseconds`
        // Purpose: wait time before executing search after typing.
        // 300ms...700ms is usually a good UX range.
        static let searchDebounceNanoseconds: UInt64 = 350_000_000

        // Order timeout settings (hours)
        // Purpose: server/client timestamps for shipping/receipt reminders and auto-complete.
        // Keep aligned with business policy and Cloud Functions logic.
        // Suggested ranges:
        // - seller reminder/deadline: 6...168
        // - buyer reminder: 6...168
        // - buyer auto-complete: 24...336
        static let sellerSendReminderHours: Int = 24
        static let sellerSendDeadlineHours: Int = 24
        static let buyerReceiveReminderHours: Int = 24
        static let buyerAutoCompleteHours: Int = 72
    }

    enum Profile {
        // `friendCodeDigits`
        // Purpose: validation length for friend code in create/edit/session flows.
        // Change only if your product rules and backend formats change.
        static let friendCodeDigits: Int = 12
    }
}
