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
    @Environment(\.colorScheme) private var scheme

    let onRoomClosed: (() -> Void)?

    @StateObject private var vm: RoomDetailsViewModel

    // Bid input for viewer/attendee
    @State private var bidText: String = ""
    @State private var editingRoom: RoomDetail? = nil
    @State private var showJoinSheet: Bool = false
    @State private var joinBidAmount: Int = 0
    @State private var showBidSheet: Bool = false
    @State private var updateBidAmount: Int = 0
    @State private var showJoinConfirmAlert: Bool = false
    @State private var showNotEnoughHoneyAlert: Bool = false
    @State private var showJoinSuccessAlert: Bool = false
    @State private var showUpdateBidSuccessAlert: Bool = false
    @State private var joinSuccessRoomName: String = ""
    @State private var joinSuccessHoney: Int = 0
    @State private var updateBidOldAmount: Int = 0
    @State private var updateBidNewAmount: Int = 0
    @State private var showLeaveConfirmAlert: Bool = false
    @State private var leaveRoomName: String = ""
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
                .navigationTitle(LocalizedStringKey("room_title"))
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
                Text(LocalizedStringKey("common_copied"))
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
            LocalizedStringKey("room_raid_confirm_title"),
            isPresented: $showRaidConfirmAlert,
            presenting: vm.pendingRaidClaim
        ) { claim in
            Button(LocalizedStringKey("common_yes")) {
                Task {
                    await vm.respondToRaidClaim(accept: true)
                    showNextRoundAlert = true
                }
            }
            Button(LocalizedStringKey("common_no"), role: .cancel) {
                Task {
                    await vm.respondToRaidClaim(accept: false)
                    showNextRoundAlert = true
                }
            }
        } message: { claim in
            Text(String(format: NSLocalizedString("room_raid_confirm_message", comment: ""), claim.hostName))
        }
        .alert(LocalizedStringKey("room_next_round_title"), isPresented: $showNextRoundAlert) {
            Button(LocalizedStringKey("room_update_bid")) {
                showBidSheet = true
            }
            Button(LocalizedStringKey("room_leave_room"), role: .destructive) {
                leaveRoomName = vm.room?.title ?? ""
                showLeaveConfirmAlert = true
            }
            Button(LocalizedStringKey("common_later"), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("room_next_round_message"))
        }
        .alert(LocalizedStringKey("room_join_confirm_title"), isPresented: $showJoinConfirmAlert, presenting: vm.room) { room in
            Button(LocalizedStringKey("room_join_confirm_sure")) {
                if joinBidAmount > session.honey {
                    showNotEnoughHoneyAlert = true
                    return
                }
                Task {
                    await vm.join(initialBid: joinBidAmount)
                    syncBidTextFromCurrentState()
                    if vm.errorMessage == nil {
                        joinSuccessRoomName = room.title
                        joinSuccessHoney = joinBidAmount
                        showJoinSuccessAlert = true
                    }
                }
            }
            Button(LocalizedStringKey("common_cancel"), role: .cancel) {}
        } message: { room in
            Text(String(format: NSLocalizedString("room_join_confirm_message", comment: ""), joinBidAmount, room.title))
        }
        .alert(LocalizedStringKey("room_not_enough_honey_title"), isPresented: $showNotEnoughHoneyAlert) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(String(format: NSLocalizedString("room_not_enough_honey_message", comment: ""), session.honey))
        }
        .alert(LocalizedStringKey("room_join_success_title"), isPresented: $showJoinSuccessAlert) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(String(format: NSLocalizedString("room_join_success_message", comment: ""), joinSuccessRoomName, joinSuccessHoney))
        }
        .alert(LocalizedStringKey("room_update_bid_success_title"), isPresented: $showUpdateBidSuccessAlert) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(String(format: NSLocalizedString("room_update_bid_success_message", comment: ""), updateBidOldAmount, updateBidNewAmount))
        }
        .alert(LocalizedStringKey("room_leave_confirm_title"), isPresented: $showLeaveConfirmAlert) {
            Button(LocalizedStringKey("common_yes"), role: .destructive) {
                Task {
                    await vm.leave()
                    syncBidTextFromCurrentState()
                }
            }
            Button(LocalizedStringKey("common_cancel"), role: .cancel) {}
        } message: {
            Text(String(format: NSLocalizedString("room_leave_confirm_message", comment: ""), leaveRoomName))
        }
        .sheet(isPresented: $showJoinSheet) {
            NavigationStack {
                Form {
                    Section {
                        HStack {
                            Text("\(joinBidAmount)")
                                .font(.title2)
                                .monospacedDigit()
                            Image(systemName: "drop.fill")
                                .foregroundStyle(.yellow)
                            Spacer()
                            Text(String(format: NSLocalizedString("room_max_honey_format", comment: ""), session.honey))
                                .foregroundStyle(.secondary)
                        }

                        let minBid = vm.room?.minBid ?? 0
                        let maxBid = max(session.honey, 0)
                        let lower = min(minBid, maxBid)
                        Slider(
                            value: Binding(
                                get: { Double(joinBidAmount) },
                                set: { joinBidAmount = Int($0) }
                            ),
                            in: Double(lower)...Double(maxBid),
                            step: 1
                        )
                    } header: {
                        Text(LocalizedStringKey("room_bid_header"))
                    } footer: {
                        Text(LocalizedStringKey("room_bid_footer"))
                    }
                }
                .navigationTitle(LocalizedStringKey("room_join_title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(LocalizedStringKey("common_cancel")) {
                            showJoinSheet = false
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(LocalizedStringKey("common_ok")) {
                            showJoinSheet = false
                            showJoinConfirmAlert = true
                        }
                        .disabled(joinBidAmount < (vm.room?.minBid ?? 0) || joinBidAmount > session.honey)
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
                            Image(systemName: "drop.fill")
                                .foregroundStyle(.yellow)
                            Spacer()
                            let currentBid = vm.currentUserBidHoney() ?? 0
                            let maxBid = max(session.honey + currentBid, 0)
                            Text(String(format: NSLocalizedString("room_max_honey_format", comment: ""), maxBid))
                                .foregroundStyle(.secondary)
                        }

                        let minBid = vm.room?.minBid ?? 0
                        let currentBid = vm.currentUserBidHoney() ?? 0
                        let maxBid = max(session.honey + currentBid, 0)
                        let lower = min(minBid, maxBid)
                        Slider(
                            value: Binding(
                                get: { Double(updateBidAmount) },
                                set: { updateBidAmount = Int($0) }
                            ),
                            in: Double(lower)...Double(maxBid),
                            step: 1
                        )
                    } header: {
                        Text(LocalizedStringKey("room_update_bid_header"))
                    } footer: {
                        Text(LocalizedStringKey("room_update_bid_footer"))
                    }

                    Section {
                        Button(role: .destructive) {
                            showBidSheet = false
                            leaveRoomName = vm.room?.title ?? ""
                            showLeaveConfirmAlert = true
                        } label: {
                            HStack {
                                Spacer()
                                Text(LocalizedStringKey("room_leave_room"))
                                Spacer()
                            }
                        }
                    }
                }
                .navigationTitle(LocalizedStringKey("room_edit_bid_title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(LocalizedStringKey("common_cancel")) {
                            showBidSheet = false
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(LocalizedStringKey("common_ok")) {
                            showBidSheet = false
                            Task {
                                updateBidOldAmount = vm.currentUserBidHoney() ?? 0
                                updateBidNewAmount = updateBidAmount
                                await vm.updateBid(to: updateBidAmount)
                                syncBidTextFromCurrentState()
                                if vm.errorMessage == nil {
                                    showUpdateBidSuccessAlert = true
                                }
                            }
                        }
                        .disabled(updateBidAmount < (vm.room?.minBid ?? 0) || updateBidAmount > max(session.honey + (vm.currentUserBidHoney() ?? 0), 0))
                    }
                }
            }
        }
        .sheet(isPresented: $showFinishSheet) {
            NavigationStack {
                Form {
                    if let room = vm.room {
                        Text(LocalizedStringKey("room_finish_hint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Section(LocalizedStringKey("room_attendees_header")) {
                            if room.attendees.isEmpty {
                                ContentUnavailableView(
                                    LocalizedStringKey("room_no_attendees_title"),
                                    systemImage: "person.3",
                                    description: Text(LocalizedStringKey("room_no_attendees_description"))
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
                                            Text(String(format: NSLocalizedString("room_bid_honey_format", comment: ""), attendee.bidHoney))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle(LocalizedStringKey("room_claim_rewards_title"))
                .navigationBarTitleDisplayMode(.inline)
                // TODO: add the following text in front of the Attendees session: Text("Please select players who come to join the mushroom raid in Pikmin.\n You will get the honey after the attendee confirms")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(LocalizedStringKey("common_cancel")) {
                            showFinishSheet = false
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(LocalizedStringKey("common_confirm")) {
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
            ProgressView(LocalizedStringKey("common_loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.backgroundGradient(for: scheme))
        } else if let err = vm.errorMessage, vm.room == nil {
            ContentUnavailableView(
                LocalizedStringKey("room_load_error_title"),
                systemImage: "exclamationmark.triangle",
                description: Text(err)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.backgroundGradient(for: scheme))
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
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundGradient(for: scheme))
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
                    Text(String(format: NSLocalizedString("room_attendee_count_format", comment: ""), room.attendees.count, room.maxPlayers))
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
        Section(LocalizedStringKey("room_info_section")) {
            HStack {
                Text(LocalizedStringKey("room_target_mushroom"))
                Spacer()
                Text(mushroomSummary(room.targetMushroom))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                Text(LocalizedStringKey("room_last_successful_raid"))
                Spacer()
                Text(room.lastSuccessfulRaidAt.relativeShortString())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func hostInfoSection(_ room: RoomDetail) -> some View {
        Section(LocalizedStringKey("room_host_info_section")) {
            HStack {
                Text(LocalizedStringKey("room_host_label"))
                Spacer()
                Text(room.hostName)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(LocalizedStringKey("room_host_stars_label"))
                Spacer()
                Label("\(room.hostStars)", systemImage: "star.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(LocalizedStringKey("room_friend_code_label"))
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
                    .accessibilityLabel(LocalizedStringKey("room_copy_host_code_accessibility"))
                }
            }
        }
    }

    private func attendeesSection(_ room: RoomDetail) -> some View {
        Section {
            if room.attendees.isEmpty {
                ContentUnavailableView(
                    LocalizedStringKey("room_attendees_empty_title"),
                    systemImage: "person.3",
                    description: Text(LocalizedStringKey("room_attendees_empty_description"))
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
                Text(LocalizedStringKey("room_attendees_header"))
                Spacer()

                Menu {
                    Picker(LocalizedStringKey("common_sort"), selection: $vm.attendeeSort) {
                        ForEach(RoomDetailsViewModel.AttendeeSort.allCases) { s in
                            Text(LocalizedStringKey(s.localizedKey))
                                .tag(s)
                        }
                    }
                } label: {
                    Label(LocalizedStringKey("common_sort"), systemImage: "arrow.up.arrow.down")
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
                .accessibilityLabel(LocalizedStringKey("room_edit_room_accessibility"))
                .disabled(vm.isLoading)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if vm.role == .viewer, vm.capabilities.canJoin {
                Button {
                    let minBid = vm.room?.minBid ?? 0
                    let clamped = max(joinBidAmount, minBid)
                    joinBidAmount = min(clamped, session.honey)
                    showJoinSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                }
                .accessibilityLabel(LocalizedStringKey("room_join_room_accessibility"))
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
                .accessibilityLabel(LocalizedStringKey("room_edit_bid_accessibility"))
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
                            Text(LocalizedStringKey("room_claim_rewards_title"))
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
        let color = localizedColor(t.color)
        let attribute = localizedAttribute(t.attribute)
        let size = localizedSize(t.size)
        return "\(color) / \(attribute) / \(size)"
    }

    private func syncBidTextFromCurrentState() {
        guard vm.room != nil else { return }
        if vm.role == .attendee, let bid = vm.currentUserBidHoney() {
            bidText = "\(bid)"
        } else if bidText.isEmpty {
            bidText = "0"
        }
    }

    private func localizedColor(_ color: MushroomColor) -> String {
        switch color {
        case .Red: return NSLocalizedString("mushroom_color_red", comment: "")
        case .Yellow: return NSLocalizedString("mushroom_color_yellow", comment: "")
        case .Blue: return NSLocalizedString("mushroom_color_blue", comment: "")
        case .Purple: return NSLocalizedString("mushroom_color_purple", comment: "")
        case .White: return NSLocalizedString("mushroom_color_white", comment: "")
        case .Gray: return NSLocalizedString("mushroom_color_gray", comment: "")
        case .Pink: return NSLocalizedString("mushroom_color_pink", comment: "")
        }
    }

    private func localizedAttribute(_ attribute: MushroomAttribute) -> String {
        switch attribute {
        case .Normal: return NSLocalizedString("mushroom_attr_normal", comment: "")
        case .Fire: return NSLocalizedString("mushroom_attr_fire", comment: "")
        case .Water: return NSLocalizedString("mushroom_attr_water", comment: "")
        case .Crystal: return NSLocalizedString("mushroom_attr_crystal", comment: "")
        case .Electric: return NSLocalizedString("mushroom_attr_electric", comment: "")
        case .Poisonous: return NSLocalizedString("mushroom_attr_poisonous", comment: "")
        }
    }

    private func localizedSize(_ size: MushroomSize) -> String {
        switch size {
        case .Small: return NSLocalizedString("mushroom_size_small", comment: "")
        case .Normal: return NSLocalizedString("mushroom_size_normal", comment: "")
        case .Magnificent: return NSLocalizedString("mushroom_size_magnificent", comment: "")
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
                    Text(String(format: NSLocalizedString("room_bid_honey_format", comment: ""), attendee.bidHoney))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()

                    if isHostViewing {
                        Menu {
                            Button(role: .destructive) {
                                onKick()
                            } label: {
                                Label(LocalizedStringKey("room_kick"), systemImage: "person.fill.xmark")
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
                Text(String(format: NSLocalizedString("room_code_format", comment: ""), attendee.friendCodeFormatted))
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
                .accessibilityLabel(LocalizedStringKey("room_copy_attendee_code_accessibility"))
            }
        }
        .padding(.vertical, 4)
    }
}
