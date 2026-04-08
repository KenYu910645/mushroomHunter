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

/// Parsed payload for a private App Review access deep link.
struct ReviewAccessPayload: Equatable {
    /// Static secret extracted from the review-access URL query string.
    let secret: String
}

/// Builds and parses private review-access URLs used by App Review.
enum ReviewAccessLink {
    /// Custom URL scheme shared with the rest of the app deep-link routes.
    private static let customScheme = "honeyhub"
    /// Hosted Firebase web domain used by invite and review links.
    private static let webHost = "mushroomhunter-3a937.web.app"

    /// Parses a review-access payload when the incoming URL matches the private review route.
    /// - Parameter url: Incoming app-open URL.
    /// - Returns: Parsed review-access payload, or `nil` when the URL is unrelated.
    static func parsePayload(from url: URL) -> ReviewAccessPayload? {
        let isCustomReviewRoute = (
            url.scheme?.lowercased() == customScheme &&
            url.host?.lowercased() == AppConfig.ReviewAccount.accessHost.lowercased()
        )
        let isHostedReviewRoute = (
            url.host?.lowercased() == webHost &&
            normalizeHostedPath(url.path) == AppConfig.ReviewAccount.accessWebPath.lowercased()
        )
        guard isCustomReviewRoute || isHostedReviewRoute else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let secret = components?.queryItems?
            .first(where: { $0.name == AppConfig.ReviewAccount.accessSecretQueryItem })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ReviewAccessPayload(secret: secret)
    }

    /// Normalizes a hosted URL path for case-insensitive review-route matching.
    /// - Parameter path: Raw URL path.
    /// - Returns: Lowercased path with one leading slash and no trailing slash.
    private static func normalizeHostedPath(_ path: String) -> String {
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard trimmedPath.isEmpty == false else { return "/" }
        return "/" + trimmedPath.lowercased()
    }
}

enum PostcardInviteLink {
    private static let customScheme = "honeyhub"
    private static let postcardHost = "postcard"
    private static let webHost = "mushroomhunter-3a937.web.app"

    static func makeURL(postcardId: String) -> URL? {
        guard !postcardId.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = customScheme
        components.host = postcardHost
        components.path = "/\(postcardId)"
        return components.url
    }

    static func parsePostcardId(from url: URL) -> String? {
        if url.scheme?.lowercased() == customScheme, url.host?.lowercased() == postcardHost {
            return postcardId(fromPath: url.path)
        }

        if url.host?.lowercased() == webHost {
            return postcardIdFromWebPath(url.path)
        }

        return nil
    }

    private static func postcardIdFromWebPath(_ path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "p" else { return nil }
        return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func postcardId(fromPath path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
