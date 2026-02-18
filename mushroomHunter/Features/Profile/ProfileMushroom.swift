//
//  ProfileMushroom.swift
//  mushroomHunter
//
//  Purpose:
//  - Hosts profile mushroom list sections for joined and hosted rooms.
//
import SwiftUI

/// Joined-room list content shown in profile mushroom section.
struct JoinedRoomsSection: View, Equatable {
    /// Shared session used to build room detail view models.
    @EnvironmentObject private var session: UserSessionStore

    /// Joined rooms to render.
    let rooms: [JoinedRoomSummary]

    /// Loading state for joined-room fetch.
    let isLoading: Bool

    /// Optional fetch error message for joined rooms.
    let errorMessage: String?

    /// Equality gate used by `.equatable()` to skip unnecessary redraws.
    static func == (lhs: JoinedRoomsSection, rhs: JoinedRoomsSection) -> Bool {
        lhs.rooms == rhs.rooms
            && lhs.isLoading == rhs.isLoading
            && lhs.errorMessage == rhs.errorMessage
    }

    /// Joined-room list rendering, including loading, empty, and error states.
    var body: some View {
        ProfileSectionStateView(
            isLoading: isLoading,
            isEmpty: rooms.isEmpty,
            errorMessage: errorMessage,
            loadingTextKey: LocalizedStringKey("profile_loading_joined")
        ) {
            ForEach(rooms) { room in
                NavigationLink {
                    RoomView(vm: RoomViewModel(roomId: room.id, session: session))
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(room.title)
                            .font(.headline)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Text(
                                String(
                                    format: NSLocalizedString("profile_players_format", comment: ""),
                                    room.joinedCount,
                                    room.maxPlayers
                                )
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                            Text(
                                String(
                                    format: NSLocalizedString("profile_bid_format", comment: ""),
                                    room.depositHoney
                                )
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } emptyContent: {
                ContentUnavailableView(
                    LocalizedStringKey("profile_joined_empty_title"),
                    systemImage: "person.2"
                )
                .listRowBackground(Color.clear)
        }
    }
}

/// Hosted-room list content shown in profile mushroom section.
struct HostedRoomsSection: View, Equatable {
    /// Shared session used to build room detail view models.
    @EnvironmentObject private var session: UserSessionStore

    /// Hosted rooms to render.
    let rooms: [HostedRoomSummary]

    /// Loading state for hosted-room fetch.
    let isLoading: Bool

    /// Optional fetch error message for hosted rooms.
    let errorMessage: String?

    /// Callback invoked when a hosted room closes from the room detail view.
    let onRoomClosed: () -> Void

    /// Equality gate used by `.equatable()` to skip unnecessary redraws.
    static func == (lhs: HostedRoomsSection, rhs: HostedRoomsSection) -> Bool {
        lhs.rooms == rhs.rooms
            && lhs.isLoading == rhs.isLoading
            && lhs.errorMessage == rhs.errorMessage
    }

    /// Hosted-room list rendering, including loading, empty, and error states.
    var body: some View {
        ProfileSectionStateView(
            isLoading: isLoading,
            isEmpty: rooms.isEmpty,
            errorMessage: errorMessage,
            loadingTextKey: LocalizedStringKey("profile_loading_hosted")
        ) {
            ForEach(rooms) { room in
                NavigationLink {
                    RoomView(
                        vm: RoomViewModel(roomId: room.id, session: session),
                        onRoomClosed: onRoomClosed
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(room.title)
                            .font(.headline)
                            .lineLimit(1)

                        Text(
                            String(
                                format: NSLocalizedString("profile_players_format", comment: ""),
                                room.joinedCount,
                                room.maxPlayers
                            )
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } emptyContent: {
                ContentUnavailableView(
                    LocalizedStringKey("profile_hosted_empty_title"),
                    systemImage: "house"
                )
                .listRowBackground(Color.clear)
        }
    }
}
