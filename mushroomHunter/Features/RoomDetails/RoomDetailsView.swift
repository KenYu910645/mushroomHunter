//
//  RoomDetailsView.swift
//  mushroomHunter
//
//  Created by Ken on 4/2/2026.
//

import SwiftUI
import UIKit

struct RoomDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    let onRoomClosed: (() -> Void)?

    @StateObject private var vm: RoomDetailsViewModel

    // Bid input for viewer/attendee
    @State private var bidText: String = ""
    @State private var editingRoom: RoomDetail? = nil
    @State private var showJoinSheet: Bool = false
    @State private var joinBidAmount: Int = 0
    @State private var showBidSheet: Bool = false
    @State private var updateBidAmount: Int = 0
    @State private var showCopyToast: Bool = false
    @State private var showFinishSheet: Bool = false
    @State private var finishSelection: Set<String> = []
    @State private var showRaidConfirmAlert: Bool = false
    @State private var showNextRoundAlert: Bool = false

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
                    await vm.load()
                    syncBidTextFromCurrentState()
                    await vm.loadPendingRaidClaim()
                }
                .onChange(of: vm.pendingRaidClaim) { _, newValue in
                    showRaidConfirmAlert = (newValue != nil)
                }
        }
        .sheet(item: $editingRoom, onDismiss: {
            Task { await vm.load() }
        }) { room in
            HostView(
                vm: HostViewModel(session: session, room: room),
                onCloseRoom: {
                    Task {
                        await vm.closeRoom()
                        if vm.errorMessage == nil {
                            onRoomClosed?()
                            dismiss()
                        }
                    }
                }
            )
                .environmentObject(session)
        }
        .overlay(alignment: .top) {
            if showCopyToast {
                Text("Copied to clipboard")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.8), in: Capsule())
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .alert(
            "Raid Confirmation",
            isPresented: $showRaidConfirmAlert,
            presenting: vm.pendingRaidClaim
        ) { claim in
            Button("Yes") {
                Task {
                    await vm.respondToRaidClaim(accept: true)
                    showNextRoundAlert = true
                }
            }
            Button("No", role: .cancel) {
                Task {
                    await vm.respondToRaidClaim(accept: false)
                    showNextRoundAlert = true
                }
            }
        } message: { claim in
            Text("\(claim.hostName) claim to invite you to mushroom raid. Did you join the mushroom raid?")
        }
        .alert("Next Round", isPresented: $showNextRoundAlert) {
            Button("Update Bid") {
                showBidSheet = true
            }
            Button("Leave Room", role: .destructive) {
                Task {
                    await vm.leave()
                    syncBidTextFromCurrentState()
                }
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Update your bid to join the next round, or leave the room now.")
        }
        .sheet(isPresented: $showJoinSheet) {
            NavigationStack {
                Form {
                    Section {
                        HStack {
                            Text("\(joinBidAmount)")
                                .font(.title2)
                                .monospacedDigit()
                            Spacer()
                            Text("Max \(session.honey)")
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(joinBidAmount) },
                                set: { joinBidAmount = Int($0) }
                            ),
                            in: 0...Double(max(session.honey, 0)),
                            step: 1
                        )
                    } header: {
                        Text("Bid (🍯)")
                    } footer: {
                        Text("Adjust your honey bid before joining.")
                    }
                }
                .navigationTitle("Join Room")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            showJoinSheet = false
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("OK") {
                            showJoinSheet = false
                            Task {
                                await vm.join(initialBid: joinBidAmount)
                                syncBidTextFromCurrentState()
                            }
                        }
                        .disabled(joinBidAmount <= 0 || joinBidAmount > session.honey)
                    }
                }
            }
        }
        .sheet(isPresented: $showBidSheet) {
            NavigationStack {
                Form {
                    Section {
                        HStack {
                            Text("\(updateBidAmount)")
                                .font(.title2)
                                .monospacedDigit()
                            Spacer()
                            Text("Max \(session.honey)")
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(updateBidAmount) },
                                set: { updateBidAmount = Int($0) }
                            ),
                            in: 0...Double(max(session.honey, 0)),
                            step: 1
                        )
                    } header: {
                        Text("Update Bid (🍯)")
                    } footer: {
                        Text("Adjust your honey bid for this room.")
                    }

                    Section {
                        Button(role: .destructive) {
                            showBidSheet = false
                            Task {
                                await vm.leave()
                                syncBidTextFromCurrentState()
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Text("Leave Room")
                                Spacer()
                            }
                        }
                    }
                }
                .navigationTitle("Edit Bid")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            showBidSheet = false
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("OK") {
                            showBidSheet = false
                            Task {
                                await vm.updateBid(to: updateBidAmount)
                                syncBidTextFromCurrentState()
                            }
                        }
                        .disabled(updateBidAmount < 0 || updateBidAmount > session.honey)
                    }
                }
            }
        }
        .sheet(isPresented: $showFinishSheet) {
            NavigationStack {
                Form {
                    if let room = vm.room {
                        Text("Please select players who come to join the mushroom raid in Pikmin.\nYou will get the honey after the attendee confirms")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Section("Attendees") {
                            if room.attendees.isEmpty {
                                ContentUnavailableView(
                                    "No attendees",
                                    systemImage: "person.3",
                                    description: Text("There are no attendees to select.")
                                )
                                .listRowBackground(Color.clear)
                            } else {
                                ForEach(room.attendees) { attendee in
                                    Toggle(isOn: Binding(
                                        get: { finishSelection.contains(attendee.id) },
                                        set: { isOn in
                                            if isOn {
                                                finishSelection.insert(attendee.id)
                                            } else {
                                                finishSelection.remove(attendee.id)
                                            }
                                        }
                                    )) {
                                        HStack {
                                            Text(attendee.name)
                                            Spacer()
                                            Text("🍯 \(attendee.bidHoney)")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Claim Rewords")
                .navigationBarTitleDisplayMode(.inline)
                // TODO: add the following text in front of the Attendees session: Text("Please select players who come to join the mushroom raid in Pikmin.\n You will get the honey after the attendee confirms")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            showFinishSheet = false
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Confirm") {
                            let selected = Array(finishSelection)
                            showFinishSheet = false
                            Task {
                                await vm.finishRaid(attendeeIds: selected)
                            }
                        }
                        .disabled(finishSelection.isEmpty)
                    }
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
                    hostInfoSection(room)
                    attendeesSection(room)
                }
            }
            .refreshable {
                await vm.load()
                syncBidTextFromCurrentState()
                await vm.loadPendingRaidClaim()
            }
        }
    }

    private func headerSection(_ room: RoomDetail) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(room.title)
                        .font(.title2.bold())
                        .lineLimit(2)

                    Spacer()

                    if !room.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                            Text(room.location)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Text("Attendee: \(room.attendees.count)/\(room.maxPlayers)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !room.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(room.note)
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

    private func hostInfoSection(_ room: RoomDetail) -> some View {
        Section("Host Info") {
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
                Text("Friend Code")
                Spacer()
                HStack(spacing: 6) {
                    Text(room.hostFriendCodeFormatted)
                        .foregroundStyle(.secondary)

                    Button {
                        copyFriendCode(room.hostFriendCode)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy host friend code")
                }
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
                        },
                        onCopyFriendCode: { code in
                            copyFriendCode(code)
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
        ToolbarItem(placement: .topBarTrailing) {
            if vm.role == .host, let room = vm.room {
                Button {
                    editingRoom = room
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                }
                .accessibilityLabel("Edit Room")
                .disabled(vm.isLoading)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if vm.role == .viewer, vm.capabilities.canJoin {
                Button {
                    joinBidAmount = min(max(joinBidAmount, 0), session.honey)
                    showJoinSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                }
                .accessibilityLabel("Join Room")
                .disabled(vm.isLoading)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if vm.role == .attendee {
                Button {
                    updateBidAmount = vm.currentUserBidHoney() ?? 0
                    showBidSheet = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.headline)
                }
                .accessibilityLabel("Edit Bid")
                .disabled(vm.isLoading)
            }
        }
    }

    // MARK: - Bottom action dock

    @ViewBuilder
    private var actionDock: some View {
        if let room = vm.room {
            VStack(spacing: 10) {
                Divider()

                HStack(spacing: 10) {
                    // Host actions (placeholder for now)
                    if vm.role == .host {
                    }

                    // Viewer actions
                    if vm.role == .viewer, vm.capabilities.canJoin {
                    }

                    // Attendee actions
                    if vm.role == .attendee {
                    }

                    // Host actions
                    if vm.role == .host {
                        Button {
                            finishSelection = []
                            showFinishSheet = true
                        } label: {
                            Text("Claim Rewards")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isLoading)
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

    private func copyFriendCode(_ code: String) {
        let digits = code.filter { $0.isNumber }
        guard !digits.isEmpty else { return }
        UIPasteboard.general.string = digits
        showCopyToast = true
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            showCopyToast = false
        }
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
    let onCopyFriendCode: (String) -> Void

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

            HStack {
                Spacer()
                Button {
                    onCopyFriendCode(attendee.friendCode)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy attendee friend code")
            }
        }
        .padding(.vertical, 4)
    }
}
