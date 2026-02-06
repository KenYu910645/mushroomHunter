//
//  RoomDetailsView.swift
//  mushroomHunter
//
//  Created by Ken on 4/2/2026.
//

import SwiftUI

struct RoomDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    let onRoomClosed: (() -> Void)?

    @StateObject private var vm: RoomDetailsViewModel

    // Bid input for viewer/attendee
    @State private var bidText: String = ""

    /// ✅ New initializer: pass VM from caller (BrowseView already does this)
    init(vm: RoomDetailsViewModel, onRoomClosed: (() -> Void)? = nil) {
        _vm = StateObject(wrappedValue: vm)
        self.onRoomClosed = onRoomClosed
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Room")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .bottom) { actionDock }
                .task {
                    if vm.room == nil {
                        await vm.load()
                        syncBidTextFromCurrentState()
                    }
                }
        }
        // If your SessionStore changes login state, VM will refresh role
        // You can trigger this from outside later if needed.
    }

    // MARK: - Main content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.room == nil {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
        } else if let err = vm.errorMessage, vm.room == nil {
            ContentUnavailableView(
                "Unable to load room",
                systemImage: "exclamationmark.triangle",
                description: Text(err)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        } else {
            Form {
                if let err = vm.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                    }
                }

                if let room = vm.room {
                    headerSection(room)
                    roomInfoSection(room)
                    attendeesSection(room)
                }
            }
        }
    }

    private func headerSection(_ room: RoomDetail) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(room.title)
                    .font(.title2.bold())
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Label(
                        room.status == .open ? "Open" : "Closed",
                        systemImage: room.status == .open ? "lock.open" : "lock"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Text("Players: \(room.attendees.count)/\(room.maxPlayers)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func roomInfoSection(_ room: RoomDetail) -> some View {
        Section("Room Info") {
            HStack {
                Text("Host")
                Spacer()
                Text(room.hostName)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Host Stars")
                Spacer()
                Label("\(room.hostStars)", systemImage: "star.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Target Mushroom")
                Spacer()
                Text(mushroomSummary(room.targetMushroom))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                Text("Last Successful Raid")
                Spacer()
                Text(room.lastSuccessfulRaidAt.relativeShortString())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func attendeesSection(_ room: RoomDetail) -> some View {
        Section {
            if room.attendees.isEmpty {
                ContentUnavailableView(
                    "No attendees yet",
                    systemImage: "person.3",
                    description: Text("Be the first to join this room.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(room.attendees) { attendee in
                    AttendeeRow(
                        attendee: attendee,
                        isHostViewing: (vm.role == .host),
                        onKick: {
                            Task {
                                await vm.kick(attendeeId: attendee.id)
                            }
                        }
                    )
                }
            }
        } header: {
            HStack {
                Text("Attendees")
                Spacer()

                Menu {
                    Picker("Sort", selection: $vm.attendeeSort) {
                        ForEach(RoomDetailsViewModel.AttendeeSort.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                        .font(.subheadline)
                }
            }
        }
        .onChange(of: vm.attendeeSort) { _, newValue in
            vm.sortAttendees(by: newValue)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if vm.isLoading {
                ProgressView()
            }
        }
    }

    // MARK: - Bottom action dock

    @ViewBuilder
    private var actionDock: some View {
        if let room = vm.room {
            VStack(spacing: 10) {
                Divider()

                // Bid input for viewer/attendee only
                if vm.capabilities.canJoin || vm.capabilities.canUpdateBid {
                    HStack {
                        Text("Bid (🍯)")
                            .font(.subheadline)

                        Spacer()

                        TextField("0", text: $bidText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: bidText) { _, newValue in
                                let filtered = newValue.filter { $0.isNumber }
                                if filtered != newValue { bidText = filtered }
                            }
                    }
                    .padding(.horizontal)
                }

                HStack(spacing: 10) {
                    // Host actions (placeholder for now)
                    if vm.role == .host {
                        Button {
                            // TODO: implement edit sheet later
                        } label: {
                            Text("Edit Room")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(true) // keep disabled for now

                        Button {
                            Task {
                                await vm.closeRoom()
                                if vm.errorMessage == nil {
                                    onRoomClosed?()      // notify parent (optional)
                                    dismiss()            // ✅ close the detail view immediately
                                }
                            }
                        } label: {
                            Text("Close")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(room.status != .open || vm.isLoading)
                    }

                    // Viewer actions
                    if vm.role == .viewer, vm.capabilities.canJoin {
                        Button {
                            Task {
                                let bid = parseBid(bidText)
                                await vm.join(initialBid: bid)
                                syncBidTextFromCurrentState()
                            }
                        } label: {
                            Text("Join")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(room.status != .open || roomIsFull(room) || vm.isLoading)
                    }

                    // Attendee actions
                    if vm.role == .attendee {
                        Button {
                            Task {
                                let bid = parseBid(bidText)
                                await vm.updateBid(to: bid)
                                syncBidTextFromCurrentState()
                            }
                        } label: {
                            Text("Update Bid")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(room.status != .open)

                        Button(role: .destructive) {
                            Task {
                                await vm.leave()
                                syncBidTextFromCurrentState()
                            }
                        } label: {
                            Text("Leave")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
            .background(.ultraThinMaterial)
        } else {
            EmptyView()
        }
    }

    // MARK: - Helpers

    private func roomIsFull(_ room: RoomDetail) -> Bool {
        room.attendees.count >= room.maxPlayers
    }

    private func parseBid(_ text: String) -> Honey {
        Int(text) ?? 0
    }

    private func mushroomSummary(_ t: MushroomTarget) -> String {
        "\(t.color.rawValue.capitalized) / \(t.attribute.rawValue.capitalized) / \(t.size.rawValue.capitalized)"
    }

    private func syncBidTextFromCurrentState() {
        guard vm.room != nil else { return }
        if vm.role == .attendee, let bid = vm.currentUserBidHoney() {
            bidText = "\(bid)"
        } else if bidText.isEmpty {
            bidText = "0"
        }
    }
}

// MARK: - Attendee Row

private struct AttendeeRow: View {
    let attendee: RoomAttendee
    let isHostViewing: Bool
    let onKick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(attendee.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 6) {
                    Text("🍯 \(attendee.bidHoney)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()

                    if isHostViewing {
                        Menu {
                            Button(role: .destructive) {
                                onKick()
                            } label: {
                                Label("Kick", systemImage: "person.fill.xmark")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 10) {
                Text("Code: \(attendee.friendCodeFormatted)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()

                Label("\(attendee.stars)", systemImage: "star.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
