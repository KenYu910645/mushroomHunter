import Foundation

enum AppTesting {
    static let uiTestingArgument = "--ui-testing"
    static let mockRoomsArgument = "--mock-rooms"
    static let userId = "ui-test-user"

    static var isUITesting: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains(uiTestingArgument)
    }

    static var useMockRooms: Bool {
        let args = ProcessInfo.processInfo.arguments
        return isUITesting || args.contains(mockRoomsArgument)
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
            maxPlayers: 10,
            hostName: "Host Tester",
            location: "US New York",
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
                depositHoney: 10,
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
            fixedRaidCost: 10,
            lastSuccessfulRaidAt: Date().addingTimeInterval(-3600),
            attendees: attendees,
            maxPlayers: 10
        )
    }
}
