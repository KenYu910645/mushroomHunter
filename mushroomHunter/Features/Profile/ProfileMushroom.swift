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
    /// Joined rooms to render.
    let rooms: [JoinedRoomSummary]

    /// Loading state for joined-room fetch.
    let isLoading: Bool

    /// Optional fetch error message for joined rooms.
    let errorMessage: String?
    /// Callback fired when a joined-room row is tapped.
    let onSelectRoom: (String) -> Void

    /// Equality gate used by `.equatable()` to skip unnecessary redraws.
    static func == (lhs: JoinedRoomsSection, rhs: JoinedRoomsSection) -> Bool {
        lhs.rooms == rhs.rooms
            && lhs.isLoading == rhs.isLoading
            && lhs.errorMessage == rhs.errorMessage
    }

    /// Joined-room list rendering, including loading, empty, and error states.
    var body: some View {
        Group {
            Text(LocalizedStringKey("profile_mushroom_joined_section"))
                .font(.subheadline.weight(.semibold))

            ProfileSectionStateView(
                isLoading: isLoading,
                isEmpty: rooms.isEmpty,
                errorMessage: errorMessage,
                loadingTextKey: LocalizedStringKey("profile_loading_joined")
            ) {
                ForEach(rooms) { room in
                    Button {
                        onSelectRoom(room.id)
                    } label: {
                        ProfileActionHighlightContainer(actionCount: actionCount(for: room.attendeeStatus)) {
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

                                    HStack(spacing: 4) {
                                        Image("HoneyIcon")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 12, height: 12)
                                        Text("\(room.depositHoney)")
                                            .foregroundStyle(Color.orange)
                                            .monospacedDigit()
                                    }
                                    .font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.orange.opacity(0.14))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                                    )

                                    Spacer(minLength: 0)

                                    ProfileStatusBadge(
                                        titleKey: statusKey(for: room.attendeeStatus),
                                        urgency: statusUrgency(for: room.attendeeStatus)
                                    )
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
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

    /// Maps attendee status to profile joined-room status text.
    /// - Parameter status: Current attendee status in this room.
    /// - Returns: Localized key used by the profile joined-room row.
    private func statusKey(for status: AttendeeStatus) -> LocalizedStringKey {
        switch status {
        case .host:
            return LocalizedStringKey("profile_room_status_host")
        case .askingToJoin:
            return LocalizedStringKey("profile_room_status_asking_to_join")
        case .ready:
            return LocalizedStringKey("profile_room_status_ready")
        case .waitingConfirmation:
            return LocalizedStringKey("profile_room_status_waiting_confirmation")
        case .rejected:
            return LocalizedStringKey("profile_room_status_rejected")
        }
    }

    /// Maps attendee status to profile badge urgency color.
    /// - Parameter status: Current attendee status in this room.
    /// - Returns: Urgency palette for status badge.
    private func statusUrgency(for status: AttendeeStatus) -> ProfileStatusUrgency {
        switch status {
        case .ready:
            return .success
        case .askingToJoin, .waitingConfirmation:
            return .warning
        case .rejected:
            return .critical
        case .host:
            return .neutral
        }
    }

    /// Maps attendee status to actionable badge count for joined-room confirmation tasks.
    /// - Parameter status: Current attendee status in this room.
    /// - Returns: `1` when waiting host confirmation response, otherwise `0`.
    private func actionCount(for status: AttendeeStatus) -> Int {
        let isWaitingConfirmation = status == .waitingConfirmation
        return isWaitingConfirmation ? 1 : 0
    }
}

/// Hosted-room list content shown in profile mushroom section.
struct HostedRoomsSection: View, Equatable {
    /// Hosted rooms to render.
    let rooms: [HostedRoomSummary]
    /// Pending attendee join-request counts grouped by hosted room id.
    let pendingJoinRequestCountsByRoomId: [String: Int]

    /// Loading state for hosted-room fetch.
    let isLoading: Bool

    /// Optional fetch error message for hosted rooms.
    let errorMessage: String?

    /// Callback fired when a hosted-room row is tapped.
    let onSelectRoom: (String) -> Void

    /// Equality gate used by `.equatable()` to skip unnecessary redraws.
    static func == (lhs: HostedRoomsSection, rhs: HostedRoomsSection) -> Bool {
        lhs.rooms == rhs.rooms
            && lhs.pendingJoinRequestCountsByRoomId == rhs.pendingJoinRequestCountsByRoomId
            && lhs.isLoading == rhs.isLoading
            && lhs.errorMessage == rhs.errorMessage
    }

    /// Hosted-room list rendering, including loading, empty, and error states.
    var body: some View {
        Group {
            Text(LocalizedStringKey("profile_mushroom_hosted_section"))
                .font(.subheadline.weight(.semibold))

            ProfileSectionStateView(
                isLoading: isLoading,
                isEmpty: rooms.isEmpty,
                errorMessage: errorMessage,
                loadingTextKey: LocalizedStringKey("profile_loading_hosted")
            ) {
                ForEach(rooms) { room in
                    Button {
                        onSelectRoom(room.id)
                    } label: {
                        ProfileActionHighlightContainer(actionCount: pendingJoinRequestCountsByRoomId[room.id] ?? 0) {
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

                                    Spacer(minLength: 0)

                                    ProfileStatusBadge(
                                        titleKey: hostedStatusKey(for: room.roomStatus),
                                        urgency: hostedStatusUrgency(for: room.roomStatus)
                                    )
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
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

    /// Maps hosted-room aggregate status to localized badge title.
    /// - Parameter status: Aggregate hosted-room status from attendee states.
    /// - Returns: Localized key for hosted-room badge.
    private func hostedStatusKey(for status: HostedRoomStatus) -> LocalizedStringKey {
        switch status {
        case .ready:
            return LocalizedStringKey("profile_room_status_ready")
        case .waitingForPlayers:
            return LocalizedStringKey("profile_room_status_waiting_for_players")
        case .waitingConfirmation:
            return LocalizedStringKey("profile_room_status_waiting_confirmation")
        }
    }

    /// Maps hosted-room aggregate status to badge urgency color.
    /// - Parameter status: Aggregate hosted-room status from attendee states.
    /// - Returns: Urgency palette used by hosted-room badge.
    private func hostedStatusUrgency(for status: HostedRoomStatus) -> ProfileStatusUrgency {
        switch status {
        case .ready:
            return .success
        case .waitingForPlayers:
            return .neutral
        case .waitingConfirmation:
            return .warning
        }
    }
}
