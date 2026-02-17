//
//  RoomInviteLink.swift
//  mushroomHunter
//
//  Purpose:
//  - Builds and parses room invite URLs for deep-link/share workflows.
//
//  Defined in this file:
//  - RoomInviteLink URL creation and extraction helpers.
//
import Foundation

enum RoomInviteLink {
    private static let customScheme = "honeyhub"
    private static let roomHost = "room"
    private static let webHost = "mushroomhunter-3a937.web.app"

    static func makeURL(roomId: String) -> URL? {
        guard !roomId.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = customScheme
        components.host = roomHost
        components.path = "/\(roomId)"
        return components.url
    }

    static func parseRoomId(from url: URL) -> String? {
        if url.scheme?.lowercased() == customScheme, url.host?.lowercased() == roomHost {
            return roomId(fromPath: url.path)
        }

        if url.host?.lowercased() == webHost {
            return roomIdFromWebPath(url.path)
        }

        return nil
    }

    private static func roomIdFromWebPath(_ path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "r" else { return nil }
        return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func roomId(fromPath path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
