//
//  RoomDetailsView.swift
//  mushroomHunter
//
//  Created by Ken on 4/2/2026.
//

import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct RoomDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @Environment(\.colorScheme) private var scheme

    let onRoomClosed: (() -> Void)?

    @StateObject private var vm: RoomDetailsViewModel

    // Bid input for viewer/attendee
    @State private var depositText: String = ""
    @State private var editingRoom: RoomDetail? = nil
    @State private var showJoinSheet: Bool = false
    @State private var joinDepositAmount: Int = 0
    @State private var showDepositSheet: Bool = false
    @State private var updateDepositAmount: Int = 0
    @State private var showJoinConfirmAlert: Bool = false
    @State private var showNotEnoughHoneyAlert: Bool = false
    @State private var showJoinSuccessAlert: Bool = false
    @State private var showUpdateDepositSuccessAlert: Bool = false
    @State private var joinSuccessRoomName: String = ""
    @State private var joinSuccessHoney: Int = 0
    @State private var updateDepositOldAmount: Int = 0
    @State private var updateDepositNewAmount: Int = 0
    @State private var showLeaveConfirmAlert: Bool = false
    @State private var leaveRoomName: String = ""
    @State private var showClaimConfirmAlert: Bool = false
    @State private var showClaimSentAlert: Bool = false
    @State private var showCopyToast: Bool = false
    @State private var showFinishSheet: Bool = false
    @State private var finishSelection: Set<String> = []
    @State private var showRaidConfirmAlert: Bool = false
    @State private var showNextRoundAlert: Bool = false
    @State private var showRaidThanksAlert: Bool = false
    @State private var raidThanksHoney: Int = 0
    @State private var showAttendeeRateHostAlert: Bool = false
    @State private var showNextRoundAfterRating: Bool = false
    @State private var showHostRateAttendeeAlert: Bool = false
    @State private var hostRateAttendeeId: String = ""
    @State private var hostRateAttendeeName: String = ""
    @State private var showRejectResolveAlert: Bool = false
    @State private var rejectAttendeeId: String = ""
    @State private var rejectAttendeeName: String = ""
    @State private var showInviteSheet: Bool = false

    /// ✅ New initializer: pass VM from caller (BrowseView already does this)
    init(vm: RoomDetailsViewModel, onRoomClosed: (() -> Void)? = nil) {
        _vm = StateObject(wrappedValue: vm)
        self.onRoomClosed = onRoomClosed
    }

    var body: some View {
        NavigationStack {
            content
                .accessibilityIdentifier("room_details_screen")
                .navigationTitle(LocalizedStringKey("room_title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .bottom) { actionDock }
                .task {
                    await vm.load()
                    syncDepositTextFromCurrentState()
                }
                .onChange(of: vm.pendingConfirmationForCurrentUser) { _, newValue in
                    showRaidConfirmAlert = newValue
                }
                .onChange(of: vm.hostPendingRatingAttendeeIds) { _, _ in
                    presentNextHostRatingAlertIfNeeded()
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
            presenting: vm.room
        ) { _ in
            Button(LocalizedStringKey("common_yes")) {
                Task {
                    let didConfirm = await vm.respondToRaidConfirmation(accept: true)
                    if didConfirm {
                        raidThanksHoney = vm.room?.fixedRaidCost ?? 0
                        showRaidThanksAlert = true
                    }
                }
            }
            Button(LocalizedStringKey("common_no"), role: .cancel) {
                Task {
                    await vm.respondToRaidConfirmation(accept: false)
                }
            }
        } message: { room in
            Text(String(format: NSLocalizedString("room_raid_confirm_message", comment: ""), room.hostName))
        }
        .alert(LocalizedStringKey("room_raid_thanks_title"), isPresented: $showRaidThanksAlert) {
            Button(LocalizedStringKey("common_ok")) {
                if let room = vm.room,
                   let deposit = vm.currentUserDepositHoney(),
                   deposit < room.fixedRaidCost {
                    showNextRoundAfterRating = true
                }
                showAttendeeRateHostAlert = true
            }
        } message: {
            Text(String(format: NSLocalizedString("room_raid_thanks_message", comment: ""), raidThanksHoney))
        }
        .alert(
            Text(String(format: NSLocalizedString("room_rate_host_title", comment: ""), vm.room?.hostName ?? "Host")),
            isPresented: $showAttendeeRateHostAlert
        ) {
            Button(LocalizedStringKey("room_rate_one_star")) {
                Task {
                    await vm.rateHost(stars: 1)
                    presentNextRoundAlertIfNeeded()
                }
            }
            Button(LocalizedStringKey("room_rate_two_stars")) {
                Task {
                    await vm.rateHost(stars: 2)
                    presentNextRoundAlertIfNeeded()
                }
            }
            Button(LocalizedStringKey("room_rate_three_stars")) {
                Task {
                    await vm.rateHost(stars: 3)
                    presentNextRoundAlertIfNeeded()
                }
            }
            Button(LocalizedStringKey("common_cancel"), role: .cancel) {
                presentNextRoundAlertIfNeeded()
            }
        }
        .alert(
            Text(String(format: NSLocalizedString("room_rate_attendee_title", comment: ""), hostRateAttendeeName)),
            isPresented: $showHostRateAttendeeAlert
        ) {
            Button(LocalizedStringKey("room_rate_one_star")) {
                let attendeeId = hostRateAttendeeId
                Task {
                    await vm.rateAttendee(attendeeId: attendeeId, stars: 1)
                    presentNextHostRatingAlertIfNeeded(excluding: attendeeId)
                }
            }
            Button(LocalizedStringKey("room_rate_two_stars")) {
                let attendeeId = hostRateAttendeeId
                Task {
                    await vm.rateAttendee(attendeeId: attendeeId, stars: 2)
                    presentNextHostRatingAlertIfNeeded(excluding: attendeeId)
                }
            }
            Button(LocalizedStringKey("room_rate_three_stars")) {
                let attendeeId = hostRateAttendeeId
                Task {
                    await vm.rateAttendee(attendeeId: attendeeId, stars: 3)
                    presentNextHostRatingAlertIfNeeded(excluding: attendeeId)
                }
            }
            Button(LocalizedStringKey("common_cancel"), role: .cancel) {
                presentNextHostRatingAlertIfNeeded(excluding: hostRateAttendeeId)
            }
        }
        .alert(LocalizedStringKey("room_next_round_title"), isPresented: $showNextRoundAlert) {
            Button(LocalizedStringKey("room_update_bid")) {
                showDepositSheet = true
            }
            Button {
                leaveRoomName = vm.room?.title ?? ""
                showLeaveConfirmAlert = true
            } label: {
                Text(LocalizedStringKey("room_leave_room"))
                    .foregroundStyle(.red)
            }
        } message: {
            Text(LocalizedStringKey("room_next_round_message"))
        }
        .alert(LocalizedStringKey("room_join_confirm_title"), isPresented: $showJoinConfirmAlert, presenting: vm.room) { room in
            Button(LocalizedStringKey("room_join_confirm_sure")) {
                if joinDepositAmount > session.honey {
                    showNotEnoughHoneyAlert = true
                    return
                }
                Task {
                    await vm.join(initialDeposit: joinDepositAmount)
                    syncDepositTextFromCurrentState()
                    if vm.errorMessage == nil {
                        joinSuccessRoomName = room.title
                        joinSuccessHoney = joinDepositAmount
                        showJoinSuccessAlert = true
                    }
                }
            }
        } message: { room in
            Text(String(format: NSLocalizedString("room_join_confirm_message", comment: ""), joinDepositAmount, room.title))
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
        .alert(LocalizedStringKey("room_join_limit_title"), isPresented: $vm.showJoinLimitAlert) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(vm.joinLimitMessage)
        }
        .alert(LocalizedStringKey("room_update_bid_success_title"), isPresented: $showUpdateDepositSuccessAlert) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(String(format: NSLocalizedString("room_update_bid_success_message", comment: ""), updateDepositOldAmount, updateDepositNewAmount))
        }
        .alert(LocalizedStringKey("room_leave_confirm_title"), isPresented: $showLeaveConfirmAlert) {
            Button(LocalizedStringKey("common_yes"), role: .destructive) {
                Task {
                    await vm.leave()
                    syncDepositTextFromCurrentState()
                }
            }
            Button(LocalizedStringKey("common_cancel"), role: .cancel) {}
        } message: {
            Text(String(format: NSLocalizedString("room_leave_confirm_message", comment: ""), leaveRoomName))
        }
        .alert(LocalizedStringKey("room_claim_confirm_title"), isPresented: $showClaimConfirmAlert) {
            Button(LocalizedStringKey("common_yes")) {
                let selected = Array(finishSelection)
                Task {
                    await vm.finishRaid(attendeeIds: selected)
                    finishSelection.removeAll()
                    showClaimSentAlert = true
                }
            }
            Button(LocalizedStringKey("common_cancel"), role: .cancel) {}
        } message: {
            Text(claimConfirmMessage())
        }
        .alert(LocalizedStringKey("room_claim_sent_title"), isPresented: $showClaimSentAlert) {
            Button(LocalizedStringKey("common_ok")) {}
        } message: {
            Text(LocalizedStringKey("room_claim_sent_message"))
        }
        .alert(LocalizedStringKey("room_reject_alert_title"), isPresented: $showRejectResolveAlert) {
            Button(LocalizedStringKey("room_reject_resolve")) {
                let id = rejectAttendeeId
                Task {
                    await vm.resolveRejectedConfirmation(attendeeId: id)
                }
            }
            Button(LocalizedStringKey("common_cancel"), role: .cancel) {}
        } message: {
            Text(String(format: NSLocalizedString("room_reject_alert_message", comment: ""), rejectAttendeeName))
        }
        .sheet(isPresented: $showJoinSheet) {
            NavigationStack {
                Form {
                    Section {
                        HStack {
                            Text("\(joinDepositAmount)")
                                .font(.title2)
                                .monospacedDigit()
                            Image("HoneyIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Spacer()
                            Text(String(format: NSLocalizedString("room_max_honey_format", comment: ""), session.honey))
                                .foregroundStyle(.secondary)
                        }

                        let minBid = vm.room?.fixedRaidCost ?? 0
                        let maxBid = max(session.honey, 0)
                        let lower = min(minBid, maxBid)
                        Slider(
                            value: Binding(
                                get: { Double(joinDepositAmount) },
                                set: { joinDepositAmount = Int($0) }
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
                        .accessibilityIdentifier("room_join_sheet_cancel_button")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(LocalizedStringKey("common_ok")) {
                            showJoinSheet = false
                            showJoinConfirmAlert = true
                        }
                        .disabled(joinDepositAmount < (vm.room?.fixedRaidCost ?? 0) || joinDepositAmount > session.honey)
                        .accessibilityIdentifier("room_join_sheet_ok_button")
                    }
                }
            }
        }
        .sheet(isPresented: $showDepositSheet) {
            NavigationStack {
                Form {
                    Section {
                        HStack {
                            Text("\(updateDepositAmount)")
                                .font(.title2)
                                .monospacedDigit()
                            Image("HoneyIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Spacer()
                            let currentBid = vm.currentUserDepositHoney() ?? 0
                            let maxBid = max(session.honey + currentBid, 0)
                            Text(String(format: NSLocalizedString("room_max_honey_format", comment: ""), maxBid))
                                .foregroundStyle(.secondary)
                        }

                        let minBid = vm.room?.fixedRaidCost ?? 0
                        let currentBid = vm.currentUserDepositHoney() ?? 0
                        let maxBid = max(session.honey + currentBid, 0)
                        let lower = min(minBid, maxBid)
                        Slider(
                            value: Binding(
                                get: { Double(updateDepositAmount) },
                                set: { updateDepositAmount = Int($0) }
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
                            showDepositSheet = false
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
                            showDepositSheet = false
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(LocalizedStringKey("common_ok")) {
                            showDepositSheet = false
                            Task {
                                updateDepositOldAmount = vm.currentUserDepositHoney() ?? 0
                                updateDepositNewAmount = updateDepositAmount
                                await vm.updateDeposit(to: updateDepositAmount)
                                syncDepositTextFromCurrentState()
                                if vm.errorMessage == nil {
                                    showUpdateDepositSuccessAlert = true
                                }
                            }
                        }
                        .disabled(updateDepositAmount < (vm.room?.fixedRaidCost ?? 0) || updateDepositAmount > max(session.honey + (vm.currentUserDepositHoney() ?? 0), 0))
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
                                ForEach(room.attendees.filter { $0.status != .host }) { attendee in
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
                                            Text(String(format: NSLocalizedString("room_bid_honey_format", comment: ""), attendee.depositHoney))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .disabled(attendee.depositHoney < room.fixedRaidCost || vm.isWaitingConfirmation(attendeeId: attendee.id))
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
                            showFinishSheet = false
                            showClaimConfirmAlert = true
                        }
                        .disabled(finishSelection.isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showInviteSheet) {
            if let room = vm.room {
                RoomInviteSheet(
                    roomTitle: room.title,
                    inviteURL: RoomInviteLink.makeURL(roomId: room.id),
                    onCopyInviteLink: { link in
                        UIPasteboard.general.string = link
                        showCopyToast = true
                        Task {
                            try? await Task.sleep(nanoseconds: 900_000_000)
                            showCopyToast = false
                        }
                    }
                )
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
                    attendeesSection(room)
                }
            }
        .refreshable {
                await vm.load()
                syncDepositTextFromCurrentState()
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

                    Text(String(format: NSLocalizedString("room_attendee_count_format", comment: ""), room.attendees.count, room.maxPlayers))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !room.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(room.location)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Text(String(format: NSLocalizedString("room_target_mushroom_format", comment: ""), mushroomSummary(room.targetMushroom)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Text(String(format: NSLocalizedString("room_last_successful_raid_format", comment: ""), room.lastSuccessfulRaidAt.relativeShortString()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !room.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(room.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
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
                        isHostAttendee: attendee.status == .host,
                        isHostViewing: (vm.role == .host),
                        isPendingConfirmation: vm.isWaitingConfirmation(attendeeId: attendee.id),
                        isRejectedConfirmation: vm.isRejectedConfirmation(attendeeId: attendee.id),
                        onKick: {
                            Task {
                                await vm.kick(attendeeId: attendee.id)
                            }
                        },
                        onResolve: {
                            rejectAttendeeId = attendee.id
                            rejectAttendeeName = attendee.name
                            showRejectResolveAlert = true
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
            }
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
            if vm.role == .host, vm.room != nil {
                Button {
                    showInviteSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline)
                }
                .accessibilityLabel(LocalizedStringKey("room_share_accessibility"))
                .disabled(vm.isLoading)

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
                EmptyView()
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if vm.role == .attendee {
                Button {
                    let currentDeposit = vm.currentUserDepositHoney() ?? 0
                    let fixedCost = vm.room?.fixedRaidCost ?? 0
                    let maxBid = max(session.honey + currentDeposit, 0)
                    updateDepositAmount = min(maxBid, max(currentDeposit, fixedCost))
                    showDepositSheet = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.headline)
                }
                .accessibilityLabel(LocalizedStringKey("room_edit_bid_accessibility"))
                .accessibilityIdentifier("room_edit_bid_button")
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
                    if AppTesting.useMockRooms, vm.role != .attendee {
                        Button {
                            let minBid = room.fixedRaidCost
                            let clamped = max(joinDepositAmount, minBid)
                            joinDepositAmount = min(clamped, session.honey)
                            showJoinSheet = true
                        } label: {
                            Text(LocalizedStringKey("common_join"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("room_join_button")
                        .disabled(vm.isLoading || session.honey < room.fixedRaidCost)
                    }

                    // Host actions (placeholder for now)
                    if vm.role == .host {
                    }

                    // Viewer actions
                    if vm.role == .viewer, vm.capabilities.canJoin {
                        Button {
                            let minBid = room.fixedRaidCost
                            let clamped = max(joinDepositAmount, minBid)
                            joinDepositAmount = min(clamped, session.honey)
                            showJoinSheet = true
                        } label: {
                            Text(LocalizedStringKey("common_join"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("room_join_button")
                        .disabled(vm.isLoading || session.honey < room.fixedRaidCost)
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

    private func syncDepositTextFromCurrentState() {
        guard vm.room != nil else { return }
        if vm.role == .attendee, let bid = vm.currentUserDepositHoney() {
            depositText = "\(bid)"
        } else if depositText.isEmpty {
            depositText = "0"
        }
    }

    private func claimConfirmMessage() -> String {
        guard let room = vm.room else {
            return NSLocalizedString("room_claim_confirm_message", comment: "")
        }
        let selected = room.attendees.filter { finishSelection.contains($0.id) }
        let names = selected.map { $0.name }.sorted()
        let list = names.joined(separator: ", ")
        if list.isEmpty {
            return NSLocalizedString("room_claim_confirm_message", comment: "")
        }
        return String(format: NSLocalizedString("room_claim_confirm_message_with_list", comment: ""), list)
    }

    private func localizedColor(_ color: MushroomColor) -> String {
        switch color {
        case .All: return NSLocalizedString("mushroom_color_all", comment: "")
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
        case .All: return NSLocalizedString("mushroom_attr_all", comment: "")
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
        case .All: return NSLocalizedString("mushroom_size_all", comment: "")
        case .Small: return NSLocalizedString("mushroom_size_small", comment: "")
        case .Normal: return NSLocalizedString("mushroom_size_normal", comment: "")
        case .Magnificent: return NSLocalizedString("mushroom_size_magnificent", comment: "")
        }
    }

    private func presentNextHostRatingAlertIfNeeded(excluding attendeeId: String? = nil) {
        guard vm.role == .host else { return }
        let pending = vm.hostPendingRatingAttendeeIds
            .filter { id in
                guard let attendeeId else { return true }
                return id != attendeeId
            }
            .sorted()

        guard let nextId = pending.first,
              let attendee = vm.attendeeById(nextId) else {
            showHostRateAttendeeAlert = false
            hostRateAttendeeId = ""
            hostRateAttendeeName = ""
            return
        }

        hostRateAttendeeId = attendee.id
        hostRateAttendeeName = attendee.name
        showHostRateAttendeeAlert = true
    }

    private func presentNextRoundAlertIfNeeded() {
        guard showNextRoundAfterRating else { return }
        showNextRoundAfterRating = false
        showNextRoundAlert = true
    }
}

private struct RoomInviteSheet: View {
    @Environment(\.dismiss) private var dismiss

    let roomTitle: String
    let inviteURL: URL?
    let onCopyInviteLink: (String) -> Void

    private let qrContext = CIContext()
    private let qrFilter = CIFilter.qrCodeGenerator()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(String(format: NSLocalizedString("room_invite_hint", comment: ""), roomTitle))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                if let link = inviteURL?.absoluteString,
                   let qr = qrImage(from: link) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260, maxHeight: 260)
                        .padding(12)
                        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.quaternary, lineWidth: 1)
                        )

                    Text(link)
                        .font(.footnote.monospaced())
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .padding(.horizontal)

                    HStack(spacing: 12) {
                        ShareLink(item: link) {
                            Label(LocalizedStringKey("room_invite_share_button"), systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            onCopyInviteLink(link)
                        } label: {
                            Label(LocalizedStringKey("room_invite_copy_button"), systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                } else {
                    ContentUnavailableView(
                        LocalizedStringKey("room_load_error_title"),
                        systemImage: "qrcode",
                        description: Text(LocalizedStringKey("room_invite_link_unavailable"))
                    )
                }

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle(LocalizedStringKey("room_invite_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(LocalizedStringKey("common_done")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func qrImage(from string: String) -> UIImage? {
        let data = Data(string.utf8)
        qrFilter.setValue(data, forKey: "inputMessage")
        qrFilter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = qrFilter.outputImage else { return nil }
        let outputSize = outputImage.extent.size
        guard outputSize.width > 0, outputSize.height > 0 else { return nil }

        let targetSize: CGFloat = 260
        let scaleX = targetSize / outputSize.width
        let scaleY = targetSize / outputSize.height
        let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        guard let cgImage = qrContext.createCGImage(transformedImage, from: transformedImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Attendee Row

private struct AttendeeRow: View {
    let attendee: RoomAttendee
    let isHostAttendee: Bool
    let isHostViewing: Bool
    let isPendingConfirmation: Bool
    let isRejectedConfirmation: Bool
    let onKick: () -> Void
    let onResolve: () -> Void
    let onCopyFriendCode: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(attendee.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 6) {
                    Text(attendee.friendCodeFormatted)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        onCopyFriendCode(attendee.friendCode)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(LocalizedStringKey("room_copy_attendee_code_accessibility"))
                }
            }

            HStack(spacing: 10) {
                if isHostAttendee {
                    Text(LocalizedStringKey("room_status_host"))
                        .font(.footnote)
                        .foregroundStyle(.blue)
                } else {
                    if isPendingConfirmation {
                        Text(LocalizedStringKey("room_status_waiting_confirm"))
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    if isRejectedConfirmation {
                        Text(LocalizedStringKey("room_status_rejected"))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if !isPendingConfirmation, !isRejectedConfirmation {
                        Text(LocalizedStringKey("room_status_ready"))
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                if !isHostAttendee {
                    HStack(spacing: 4) {
                        Image("HoneyIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text(String(format: NSLocalizedString("room_bid_honey_format", comment: ""), attendee.depositHoney))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Label("\(attendee.stars)", systemImage: "star.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if isHostViewing && !isHostAttendee {
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

            HStack {
                Spacer()
                if isHostViewing, isRejectedConfirmation, !isHostAttendee {
                    Button(LocalizedStringKey("room_reject_resolve")) {
                        onResolve()
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
