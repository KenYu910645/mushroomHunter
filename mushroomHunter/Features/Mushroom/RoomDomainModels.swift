//
//  RoomDomainModels.swift
//  mushroomHunter
//
//  Purpose:
//  - Declares shared Mushroom room domain models and supporting enums.
//
//  Defined in this file:
//  - RoomDetail, RoomAttendee, status enums, and related value types.
//
import Foundation

// MARK: - Core types

/// Honey deposit stored as Int for MVP (avoid floating point currency)
typealias Honey = Int

/// Role of the current user *with respect to this room*.
enum RoomRole: Equatable {
    case host
    case attendee
    case viewer
}

// MARK: - Room data

/// The “room” object your Room screen needs.
/// Keep it UI-friendly; later we can map Firestore docs into this.
struct RoomDetail: Identifiable, Equatable, Codable {
    let id: String

    // Header
    var title: String
    var location: String
    var description: String

    // Middle info
    var targetMushroom: MushroomTarget
    var fixedRaidCost: Int

    /// When the room last completed a successful raid.
    /// We’ll display as “24h ago” style in the UI.
    var lastSuccessfulRaidAt: Date?
    /// Historical raid confirmation snapshots, latest first.
    var raidConfirmationHistory: [RoomRaidConfirmationRecord]

    // Attendance
    var attendees: [RoomAttendee]
    var maxPlayers: Int
}

/// One room-level raid confirmation record with attendee-level statuses.
struct RoomRaidConfirmationRecord: Identifiable, Equatable, Codable {
    /// Stable confirmation id shared across invited attendees.
    let id: String
    /// Time when this confirmation cycle was created by the host.
    let requestedAt: Date
    /// Snapshot of attendee statuses for this confirmation cycle.
    var attendeeResults: [RoomRaidConfirmationAttendeeResult]
}

/// One attendee status row inside a raid confirmation history record.
struct RoomRaidConfirmationAttendeeResult: Identifiable, Equatable, Codable {
    /// Attendee uid.
    let id: String
    /// Attendee display name snapshot captured when record was created.
    var name: String
    /// Host-visible invitation response status for this attendee.
    var status: RoomRaidConfirmationAttendeeStatus
}

/// Host-visible attendee response state used by raid history.
enum RoomRaidConfirmationAttendeeStatus: String, CaseIterable, Codable {
    case confirming = "Confirming"
    case joined = "Joined"
    case seatFull = "SeatFull"
    case noInvite = "NoInvite"
}

/// Mushroom targeting info (align with your Host tab)
struct MushroomTarget: Equatable, Codable {
    var color: MushroomColor
    var attribute: MushroomAttribute
    var size: MushroomSize
}

enum MushroomColor: String, CaseIterable, Codable {
    case All
    case Red
    case Yellow
    case Blue
    case Purple
    case White
    case Gray
    case Pink
}

enum MushroomAttribute: String, CaseIterable, Codable {
    case All
    case Normal
    case Fire
    case Water
    case Crystal
    case Electric
    case Poisonous
}

enum MushroomSize: String, CaseIterable, Codable {
    case All
    case Small
    case Normal
    case Magnificent
}

// MARK: - Attendees

/// An attendee as shown in the bottom list.
struct RoomAttendee: Identifiable, Equatable, Codable {
    /// Use uid when you have auth; for now any unique string.
    let id: String

    var name: String
    /// Stored as digits only (e.g. "123456782345"), format in UI.
    var friendCode: String
    var stars: Int

    /// How much honey the attendee has deposited for this room.
    var depositHoney: Honey
    /// Join greeting message sent by this attendee.
    var joinGreetingMessage: String

    /// When they joined (optional but useful for tie-break sorting)
    var joinedAt: Date?

    /// Current attendee state in this room.
    var status: AttendeeStatus
    /// Host should rate this attendee for the latest confirmed raid.
    var isHostRatingRequired: Bool
    /// Pending confirmation queue keyed by confirmation id with request timestamp.
    var pendingConfirmationRequests: [String: Date]
}

enum AttendeeStatus: String, CaseIterable, Codable {
    case host = "Host"
    case askingToJoin = "AskingToJoin"
    case ready = "Ready"
    case waitingConfirmation = "WaitingConfirmation"

    /// Status values treated as active room participation for join-limit counting.
    static var activeStatusRawValues: [String] {
        [host.rawValue, askingToJoin.rawValue, ready.rawValue, waitingConfirmation.rawValue]
    }
}

/// Attendee escrow settlement result for a raid confirmation request.
enum RaidSettlementOutcome: String, CaseIterable, Codable {
    case joinedSuccess = "JoinedSuccess"
    case seatFullNoFault = "SeatFullNoFault"
    case missedInvitation = "MissedInvitation"
}

// MARK: - Utilities

extension RoomDetail {
    var hostAttendee: RoomAttendee? {
        attendees.first(where: { $0.status == .host })
    }

    var hostId: String? {
        hostAttendee?.id
    }

    var hostName: String {
        hostAttendee?.name ?? "Host"
    }
}

extension RoomAttendee {
    /// Format friend code as "1234 5678 2345"
    var friendCodeFormatted: String {
        FriendCode.formatted(friendCode)
    }

    /// Whether this attendee has at least one unprocessed raid confirmation request.
    var isWaitingConfirmation: Bool {
        !pendingConfirmationRequests.isEmpty || status == .waitingConfirmation
    }

    /// Pending confirmation queue sorted from latest request to oldest request.
    var pendingConfirmationQueueLatestFirst: [(id: String, requestedAt: Date)] {
        pendingConfirmationRequests
            .map { (id: $0.key, requestedAt: $0.value) }
            .sorted { lhs, rhs in
                lhs.requestedAt > rhs.requestedAt
            }
    }
}

extension Optional where Wrapped == Date {
    /// For UI: "24h ago", "10m ago", "2d ago", or "—"
    func relativeShortString(now: Date = Date()) -> String { // Handles relativeShortString flow.
        guard let date = self else { return "—" }
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 0 { return "—" }

        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }

        let hours = minutes / 60
        if hours < 48 { return "\(hours)h ago" }

        let days = hours / 24
        return "\(days)d ago"
    }
}
