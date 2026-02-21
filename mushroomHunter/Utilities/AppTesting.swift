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
    static let uiTestingArgument = "--ui-testing"
    static let mockRoomsArgument = "--mock-rooms"
    static let mockJoinedRoomArgument = "--mock-room-joined"
    static let mockPostcardsArgument = "--mock-postcards"
    static let openRoomArgument = "--ui-open-room"
    static let openPostcardArgument = "--ui-open-postcard"
    static let userId = "ui-test-user"

    static var isUITesting: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains(uiTestingArgument)
    }

    static var useMockRooms: Bool {
        let args = ProcessInfo.processInfo.arguments
        return isUITesting || args.contains(mockRoomsArgument)
    }

    static var useMockJoinedRoom: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains(mockJoinedRoomArgument)
    }

    static var useMockPostcards: Bool {
        let args = ProcessInfo.processInfo.arguments
        return isUITesting || args.contains(mockPostcardsArgument)
    }

    static var fixtureRoomId: String { "ui-test-room-001" }

    static func fixtureListing() -> RoomListing {
        RoomListing(
            id: fixtureRoomId,
            title: "UI Test Room",
            mushroomType: "Fire",
            targetColor: "Red",
            targetAttribute: "Fire",
            targetSize: "Normal",
            joinedPlayers: 1,
            maxPlayers: AppConfig.Mushroom.defaultMaxPlayersPerRoom,
            hostName: "Host Tester",
            hostStars: 3,
            location: "US New York",
            createdAt: Date().addingTimeInterval(-1800),
            lastSuccessfulRaidAt: Date().addingTimeInterval(-900),
            expiresAt: nil
        )
    }

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
                needsHostRating: false
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
                    needsHostRating: false
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
            attendees: attendees,
            maxPlayers: AppConfig.Mushroom.defaultMaxPlayersPerRoom
        )
    }

    static var fixturePostcardId: String { "ui-test-postcard-001" }
    static var fixtureSellerId: String { "ui-test-seller" }

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

    static func launchArgumentValue(after key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let keyIndex = args.firstIndex(of: key) else { return nil }
        let valueIndex = args.index(after: keyIndex)
        guard valueIndex < args.endIndex else { return nil }
        return args[valueIndex]
    }
}
