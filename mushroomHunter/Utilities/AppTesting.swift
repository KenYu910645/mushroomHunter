//
//  AppTesting.swift
//  mushroomHunter
//
//  Purpose:
//  - Provides app-wide flags and fixtures used by UI testing mode.
//
//  Defined in this file:
//  - AppTesting argument checks and mock-data helpers.
//
import Foundation

enum AppTesting {
    /// Launch argument that enables the shared UI-testing environment.
    static let uiTestingArgument = "--ui-testing"
    /// Launch argument that swaps Mushroom network data for local fixtures.
    static let mockRoomsArgument = "--mock-rooms"
    /// Launch argument that opens the room fixture with the current user already joined.
    static let mockJoinedRoomArgument = "--mock-room-joined"
    /// Launch argument that swaps Postcard network data for local fixtures.
    static let mockPostcardsArgument = "--mock-postcards"
    /// Launch argument key used to deep-link directly into one room.
    static let openRoomArgument = "--ui-open-room"
    /// Launch argument key used to deep-link directly into one postcard.
    static let openPostcardArgument = "--ui-open-postcard"
    /// Stable mock uid used across all UI-test-only data.
    static let userId = "ui-test-user"
    /// In-memory claimed-day storage used by the DailyReward mock implementation.
    private static var mockDailyRewardClaimStorage: [String: Set<Int>] = [:]

    /// True when the app is running inside UI automation mode.
    static var isUITesting: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains(uiTestingArgument)
    }

    /// True when Mushroom screens should use local fixtures instead of Firebase.
    static var useMockRooms: Bool {
        let args = ProcessInfo.processInfo.arguments
        return isUITesting || args.contains(mockRoomsArgument)
    }

    /// True when the room fixture should include the current user as an attendee.
    static var useMockJoinedRoom: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains(mockJoinedRoomArgument)
    }

    /// True when Postcard screens should use local fixtures instead of Firebase.
    static var useMockPostcards: Bool {
        let args = ProcessInfo.processInfo.arguments
        return isUITesting || args.contains(mockPostcardsArgument)
    }

    /// Fixture room id used by UI tests and room deep-link helpers.
    static var fixtureRoomId: String { "ui-test-room-001" }

    /// Fixture Mushroom browse listing used by UI tests.
    static func fixtureListing() -> RoomListing {
        RoomListing(
            id: fixtureRoomId,
            title: "UI Test Room",
            mushroomType: "Fire",
            joinedPlayers: 1,
            maxPlayers: AppConfig.Mushroom.defaultMaxPlayersPerRoom,
            hostUid: "host-user",
            hostStars: 3,
            location: "US New York",
            createdAt: Date().addingTimeInterval(-1800),
            lastSuccessfulRaidAt: Date().addingTimeInterval(-900),
            expiresAt: nil
        )
    }

    /// Fixture Mushroom room detail used by UI tests.
    static func fixtureRoom(includeCurrentUser: Bool) -> RoomDetail {
        var attendees: [RoomAttendee] = [
            RoomAttendee(
                id: "host-user",
                name: "Host Tester",
                friendCode: "123456789012",
                stars: 3,
                depositHoney: AppConfig.Mushroom.defaultFixedRaidCost,
                joinGreetingMessage: "Host fixture attendee.",
                joinedAt: Date().addingTimeInterval(-300),
                status: .host,
                isHostRatingRequired: false,
                pendingConfirmationRequests: [:]
            )
        ]

        if includeCurrentUser {
            attendees.append(
                RoomAttendee(
                    id: userId,
                    name: "UI Tester",
                    friendCode: "999988887777",
                    stars: 1,
                    depositHoney: 12,
                    joinGreetingMessage: "UI fixture join greeting.",
                    joinedAt: Date(),
                    status: .ready,
                    isHostRatingRequired: false,
                    pendingConfirmationRequests: [:]
                )
            )
        }

        return RoomDetail(
            id: fixtureRoomId,
            title: "UI Test Room",
            location: "US New York",
            description: "Fixture room for UI automation.",
            targetMushroom: MushroomTarget(color: .Red, attribute: .Fire, size: .Normal),
            fixedRaidCost: AppConfig.Mushroom.defaultFixedRaidCost,
            lastSuccessfulRaidAt: Date().addingTimeInterval(-3600),
            raidConfirmationHistory: [],
            attendees: attendees,
            maxPlayers: AppConfig.Mushroom.defaultMaxPlayersPerRoom
        )
    }

    /// Fixture postcard listing id used by UI tests.
    static var fixturePostcardId: String { "ui-test-postcard-001" }
    /// Fixture postcard seller id used by UI tests.
    static var fixtureSellerId: String { "ui-test-seller" }
    /// Fixture sold-out postcard id used by UI tests.
    static var fixtureSoldOutPostcardId: String { "ui-test-postcard-sold-out" }

    /// Fixture postcard listing used by buyer-flow UI tests.
    static func fixturePostcardListing() -> PostcardListing {
        PostcardListing(
            id: fixturePostcardId,
            sellerId: fixtureSellerId,
            title: "UI Test Postcard",
            priceHoney: 10,
            location: PostcardLocation(country: "Taiwan", province: "Taipei", detail: "UI Test"),
            sellerName: "Seller Tester",
            sellerFriendCode: "123456789012",
            stock: 3,
            imageUrl: nil,
            thumbnailUrl: nil,
            createdAt: Date()
        )
    }

    /// Fixture postcard listing owned by the current user.
    static func fixtureOwnedPostcardListing() -> PostcardListing {
        PostcardListing(
            id: "ui-test-postcard-owned",
            sellerId: userId,
            title: "UI Owned Postcard",
            priceHoney: 20,
            location: PostcardLocation(country: "Taiwan", province: "Kaohsiung", detail: "Owned"),
            sellerName: "UI Tester",
            sellerFriendCode: "999988887777",
            stock: 2,
            imageUrl: nil,
            thumbnailUrl: nil,
            createdAt: Date()
        )
    }

    /// Fixture sold-out postcard listing used by sold-out UI tests.
    static func fixtureSoldOutPostcardListing() -> PostcardListing {
        PostcardListing(
            id: fixtureSoldOutPostcardId,
            sellerId: "ui-test-seller-sold-out",
            title: "UI Sold Out Postcard",
            priceHoney: 12,
            location: PostcardLocation(country: "Japan", province: "Tokyo", detail: "Sold Out"),
            sellerName: "Seller Sold Out",
            sellerFriendCode: "111122223333",
            stock: 0,
            imageUrl: nil,
            thumbnailUrl: nil,
            createdAt: Date().addingTimeInterval(-7200)
        )
    }

    /// Fixture seller shipping recipients used by seller shipping UI tests.
    static func fixtureShippingRecipients() -> [PostcardShippingRecipient] {
        [
            PostcardShippingRecipient(
                id: "ui-test-order-001",
                buyerId: "ui-test-buyer-001",
                buyerName: "Buyer Tester",
                buyerFriendCode: "000011112222",
                status: .awaitingShipping
            )
        ]
    }

    /// Reads the value placed after one launch argument key.
    static func launchArgumentValue(after key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let keyIndex = args.firstIndex(of: key) else { return nil }
        let valueIndex = args.index(after: keyIndex)
        guard valueIndex < args.endIndex else { return nil }
        return args[valueIndex]
    }

    /// Returns the mock claimed-day set for one DailyReward month.
    /// - Parameter monthKey: Month key in `YYYY-MM` form.
    /// - Returns: Claimed day numbers for the requested month.
    static func mockDailyRewardClaimedDays(forMonthKey monthKey: String) -> Set<Int> {
        mockDailyRewardClaimStorage[monthKey] ?? []
    }

    /// Records one claimed reward day inside the UI-test mock store.
    /// - Parameters:
    ///   - day: Claimed day number.
    ///   - monthKey: Month key in `YYYY-MM` form.
    static func addMockDailyRewardClaim(day: Int, monthKey: String) {
        guard day > 0 else { return }
        var claimedDays = mockDailyRewardClaimStorage[monthKey] ?? []
        claimedDays.insert(day)
        mockDailyRewardClaimStorage[monthKey] = claimedDays
    }
}
