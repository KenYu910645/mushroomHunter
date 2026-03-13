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

/// One durable room rating task that lives in the room clipboard flow.
struct RoomRatingTask: Identifiable, Equatable, Codable {
    /// Stable task document id.
    let id: String
    /// Parent room id this task belongs to.
    let roomId: String
    /// Confirmation cycle id that created this task.
    let confirmationId: String
    /// Confirmation request timestamp used for newest-first ordering.
    let requestedAt: Date
    /// Counterparty uid that will receive the stars.
    let rateeUid: String
    /// Counterparty display name shown in the queue/history row.
    let counterpartName: String
    /// Direction of this room rating task.
    let direction: RoomRatingDirection
    /// Settlement outcome associated with this rating opportunity.
    let settlementOutcome: RaidSettlementOutcome
    /// Current lifecycle state for this rating task.
    var status: RoomRatingTaskStatus
}

/// Host-visible attendee response state used by raid history.
enum RoomRaidConfirmationAttendeeStatus: String, CaseIterable, Codable {
    case confirming = "Confirming"
    case joined = "Joined"
    case seatFull = "SeatFull"
    case noInvite = "NoInvite"
}

/// Direction of one room rating task.
enum RoomRatingDirection: String, CaseIterable, Codable {
    case attendeeToHost = "AttendeeToHost"
    case hostToAttendee = "HostToAttendee"
}

/// Persisted lifecycle state for one room rating task.
enum RoomRatingTaskStatus: String, CaseIterable, Codable {
    case pending = "Pending"
    case rated = "Rated"
    case skipped = "Skipped"
    case closed = "Closed"
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
    case notEnoughHoney = "NotEnoughHoney"
    case waitingConfirmation = "WaitingConfirmation"

    /// Status values treated as active room participation for join-limit counting.
    static var activeStatusRawValues: [String] {
        [host.rawValue, askingToJoin.rawValue, ready.rawValue, notEnoughHoney.rawValue, waitingConfirmation.rawValue]
    }

    /// Returns whether the attendee can still top up deposit and participate in room flows.
    var isActiveParticipant: Bool {
        switch self {
        case .host, .askingToJoin, .ready, .notEnoughHoney, .waitingConfirmation:
            return true
        }
    }

    /// Returns whether post-confirmation rating remains available for this attendee state.
    var isRatingEligibleAfterSettlement: Bool {
        switch self {
        case .ready, .notEnoughHoney:
            return true
        case .host, .askingToJoin, .waitingConfirmation:
            return false
        }
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
    /// For UI: localized short relative time such as "24h ago" or "24 小時前".
    func relativeShortString(now: Date = Date()) -> String { // Handles relativeShortString flow.
        guard let date = self else {
            return NSLocalizedString("common_relative_unknown", comment: "")
        }
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 0 {
            return NSLocalizedString("common_relative_unknown", comment: "")
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return String(
                format: NSLocalizedString("common_relative_minutes_ago", comment: ""),
                minutes
            )
        }

        let hours = minutes / 60
        if hours < 48 {
            return String(
                format: NSLocalizedString("common_relative_hours_ago", comment: ""),
                hours
            )
        }

        let days = hours / 24
        return String(
            format: NSLocalizedString("common_relative_days_ago", comment: ""),
            days
        )
    }
}
