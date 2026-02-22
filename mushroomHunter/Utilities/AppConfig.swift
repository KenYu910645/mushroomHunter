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
        // `isRaidPaymentAdjustmentEnabled`
        // Purpose: controls whether hosts can adjust fixed raid payment in room form.
        // When false, room form hides the adjustment option and uses `disabledRaidPaymentHoney` default.
        static let isRaidPaymentAdjustmentEnabled: Bool = true

        // `disabledRaidPaymentHoney`
        // Purpose: fixed raid payment used when adjustment option is disabled.
        // Keep aligned with product policy copy.
        static let disabledRaidPaymentHoney: Int = 10

        // `enabledRaidPaymentMaxHoney`
        // Purpose: max adjustable payment used by room form when adjustment option is enabled.
        // Keep aligned with product policy copy.
        static let enabledRaidPaymentMaxHoney: Int = 10

        // `browseListFetchLimit`
        // Purpose: max rooms fetched for Mushroom browse.
        // Higher = more data shown, but slower initial load.
        // Suggested range: 20...200.
        static let browseListFetchLimit: Int = 50

        // `browsePriorityDormantThresholdHours`
        // Purpose: no dormancy penalty is applied before this elapsed-hour threshold.
        // Suggested range: 12...168.
        static let browsePriorityDormantThresholdHours: Double = 48

        // `browsePriorityHostStarWeight`
        // Purpose: host-star contribution per star in room browse score.
        // Suggested range: 10...500.
        static let browsePriorityHostStarWeight: Double = 100

        // `browsePriorityDormantHourPenalty`
        // Purpose: score penalty per hour beyond dormancy threshold.
        // Suggested range: 0.1...10.
        static let browsePriorityDormantHourPenalty: Double = 1

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

        // `noFaultEffortFeeRate`
        // Purpose: host effort-fee ratio used when attendee selects "seat full" settlement.
        // Suggested range: 0.05...0.5.
        static let noFaultEffortFeeRate: Double = 0.2

        // `noFaultEffortFeeMinimum`
        // Purpose: minimum effort-fee honey for no-fault seat-full settlement.
        // Suggested range: 1...10.
        static let noFaultEffortFeeMinimum: Int = 1

        // Computes no-fault effort fee from fixed raid cost.
        static func noFaultEffortFee(for fixedRaidCost: Int) -> Int { // Handles noFaultEffortFee flow.
            let normalizedRaidCost = max(0, fixedRaidCost)
            let ratioFee = Int((Double(normalizedRaidCost) * noFaultEffortFeeRate).rounded(.down))
            return max(noFaultEffortFeeMinimum, ratioFee)
        }

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

        // `imageMemoryCacheEntryLimit`
        // Purpose: max decoded postcard images kept in RAM for instant repeat rendering.
        // Suggested range: 50...500.
        static let imageMemoryCacheEntryLimit: Int = 220

        // `imageDiskCacheMaxBytes`
        // Purpose: hard cap for postcard image disk cache folder size.
        // Suggested range: 20MB...500MB depending on device/storage policy.
        static let imageDiskCacheMaxBytes: Int = 120 * 1024 * 1024

        // `imageDiskCachePruneTargetRatio`
        // Purpose: prune target after overflow; cache shrinks to (maxBytes * ratio).
        // Suggested range: 0.6...0.95.
        static let imageDiskCachePruneTargetRatio: Double = 0.8

        // `imageDiskCacheMaxAgeSeconds`
        // Purpose: TTL for one disk cache entry before it is treated as expired.
        // Suggested range: 1 day...90 days.
        static let imageDiskCacheMaxAgeSeconds: TimeInterval = 30 * 24 * 60 * 60

        // `searchDebounceNanoseconds`
        // Purpose: wait time before executing search after typing.
        // 300ms...700ms is usually a good UX range.
        static let searchDebounceNanoseconds: UInt64 = 350_000_000

        // Order timeout settings (hours)
        // Purpose: server/client timestamps for seller shipping and buyer confirmation.
        // Keep aligned with business policy and Cloud Functions timeout sweep logic.
        // Suggested ranges:
        // - seller shipping deadline: 12...336
        // - buyer confirmation deadline: 24...336
        static let sellerShippingDeadlineHours: Int = 72
        static let buyerReceiveReminderHours: Int = 24
        static let buyerConfirmDeadlineHours: Int = 120
    }

    enum Profile {
        // `friendCodeDigits`
        // Purpose: validation length for friend code in create/edit/session flows.
        // Change only if your product rules and backend formats change.
        static let friendCodeDigits: Int = 12
    }

    enum SharedUI {
        // `honeyMessageIconSize`
        // Purpose: inline HoneyIcon point size used in shared tokenized message text.
        // Suggested range: 10...20.
        static let honeyMessageIconSize: CGFloat = 10
    }
}
