//
//  RoomDetailsModels.swift
//  mushroomHunter
//
//  Created by Ken on 4/2/2026.
//

import Foundation
import Combine

// MARK: - Core types

/// 🍯 Honey bid stored as Int for MVP (avoid floating point currency)
typealias Honey = Int

/// Basic room status for MVP. Keep it simple.
enum RoomStatus: String, Codable {
    case open
    case closed
}

/// Role of the current user *with respect to this room*.
enum RoomRole: Equatable {
    case host
    case attendee
    case viewer
}

/// UI capabilities derived from role + room state.
struct RoomCapabilities: Equatable {
    let canJoin: Bool
    let canLeave: Bool
    let canEditRoom: Bool
    let canKickAttendees: Bool
    let canUpdateBid: Bool

    static func derive(role: RoomRole, room: RoomDetail) -> RoomCapabilities {
        let isOpen = (room.status == .open)
        let isFull = (room.attendees.count >= room.maxPlayers)

        switch role {
        case .host:
            return .init(
                canJoin: false,
                canLeave: false,
                canEditRoom: true,
                canKickAttendees: true,
                canUpdateBid: false
            )
        case .attendee:
            return .init(
                canJoin: false,
                canLeave: true,
                canEditRoom: false,
                canKickAttendees: false,
                canUpdateBid: isOpen // allow editing bid only if room open
            )
        case .viewer:
            return .init(
                canJoin: isOpen && !isFull,
                canLeave: false,
                canEditRoom: false,
                canKickAttendees: false,
                canUpdateBid: false
            )
        }
    }
}

// MARK: - Room data

/// The “room” object your RoomDetails screen needs.
/// Keep it UI-friendly; later we can map Firestore docs into this.
struct RoomDetail: Identifiable, Equatable {
    let id: String

    // Header
    var title: String

    // Middle info
    var hostName: String
    var hostStars: Int
    var targetMushroom: MushroomTarget

    /// When the room last completed a successful raid.
    /// We’ll display as “24h ago” style in the UI.
    var lastSuccessfulRaidAt: Date?

    // Attendance
    var attendees: [RoomAttendee]
    var maxPlayers: Int

    // Room state
    var status: RoomStatus
}

/// Mushroom targeting info (align with your Host tab)
struct MushroomTarget: Equatable {
    var color: MushroomColor
    var attribute: MushroomAttribute
    var size: MushroomSize
}

enum MushroomColor: String, CaseIterable, Codable {
    case Red, Yellow, Blue, Purple, White, Gray, Pink
}

enum MushroomAttribute: String, CaseIterable, Codable {
    case Normal
    case Fire
    case Water
    case Crystal
    case Electric
    case Poisonous
}

enum MushroomSize: String, CaseIterable, Codable {
    case Small
    case Normal
    case Magnificent
}

// MARK: - Attendees

/// An attendee as shown in the bottom list.
struct RoomAttendee: Identifiable, Equatable {
    /// Use uid when you have auth; for now any unique string.
    let id: String

    var name: String
    /// Stored as digits only (e.g. "123456782345"), format in UI.
    var friendCode: String
    var stars: Int

    /// How much honey the attendee is willing to pay to join.
    var bidHoney: Honey

    /// When they joined (optional but useful for tie-break sorting)
    var joinedAt: Date?
}

// MARK: - Utilities

extension RoomDetail {
    /// Convenience: compute role from current uid.
    func role(forUid uid: String?) -> RoomRole {
        guard let uid else { return .viewer }
        if uid == hostIdGuess { return .host }
        if attendees.contains(where: { $0.id == uid }) { return .attendee }
        return .viewer
    }

    /// Placeholder until you store hostUid explicitly in RoomDetail.
    /// In Step 2 we’ll add hostUid for correctness.
    private var hostIdGuess: String { "HOST_UID_PLACEHOLDER" }
}

extension RoomAttendee {
    /// Format friend code as "1234 5678 2345"
    var friendCodeFormatted: String {
        let digits = friendCode.filter { $0.isNumber }
        var parts: [String] = []
        var i = digits.startIndex
        while i < digits.endIndex {
            let end = digits.index(i, offsetBy: 4, limitedBy: digits.endIndex) ?? digits.endIndex
            parts.append(String(digits[i..<end]))
            i = end
        }
        return parts.joined(separator: " ")
    }
}

extension Optional where Wrapped == Date {
    /// For UI: "24h ago", "10m ago", "2d ago", or "—"
    func relativeShortString(now: Date = Date()) -> String {
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
