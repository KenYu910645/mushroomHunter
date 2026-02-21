//
//  RoomView.swift
//  mushroomHunter
//
//  Purpose:
//  - Renders the Mushroom room details screen and user actions UI.
//
//  Defined in this file:
//  - RoomView layout and presentation/alert flow glue.
//
import SwiftUI
import UIKit

struct RoomView: View {
    @Environment(\.dismiss) private var dismiss // State or dependency property.
    @EnvironmentObject private var session: UserSessionStore // State or dependency property.
    @Environment(\.colorScheme) private var scheme // State or dependency property.
    let onRoomClosed: (() -> Void)?

    @StateObject private var vm: RoomViewModel // State or dependency property.
    @State private var editingRoom: RoomDetail? = nil // State or dependency property.
    @State private var showJoinSheet: Bool = false // State or dependency property.
    @State private var joinDepositAmount: Int = 0 // State or dependency property.
    @State private var joinGreetingMessage: String = NSLocalizedString("room_join_greeting_default", comment: "") // Greeting message submitted together with join deposit.
    @State private var isJoinGreetingFocused: Bool = false // Controls first-responder focus for the join greeting editor.
    @State private var showDepositSheet: Bool = false // State or dependency property.
    @State private var updateDepositAmount: Int = 0 // State or dependency property.
    @State private var showJoinConfirmAlert: Bool = false // State or dependency property.
    @State private var showNotEnoughHoneyAlert: Bool = false // State or dependency property.
    @State private var showJoinSuccessAlert: Bool = false // State or dependency property.
    @State private var showUpdateDepositSuccessAlert: Bool = false // State or dependency property.
    @State private var joinSuccessRoomName: String = "" // State or dependency property.
    @State private var joinSuccessHoney: Int = 0 // State or dependency property.
    @State private var updateDepositOldAmount: Int = 0 // State or dependency property.
    @State private var updateDepositNewAmount: Int = 0 // State or dependency property.
    @State private var showLeaveConfirmAlert: Bool = false // State or dependency property.
    @State private var leaveRoomName: String = "" // State or dependency property.
    @State private var showClaimConfirmAlert: Bool = false // State or dependency property.
    @State private var showClaimSentAlert: Bool = false // State or dependency property.
    @State private var isCopyToastVisible: Bool = false // Controls temporary copied-toast visibility.
    @State private var showFinishSheet: Bool = false // State or dependency property.
    @State private var finishSelection: Set<String> = [] // State or dependency property.
    @State private var showRaidConfirmAlert: Bool = false // State or dependency property.
    @State private var showNextRoundAlert: Bool = false // State or dependency property.
    @State private var showRaidThanksAlert: Bool = false // State or dependency property.
    @State private var raidThanksHoney: Int = 0 // State or dependency property.
    @State private var isShowingNoFaultSettlementAlert: Bool = false // Indicates no-fault seat-full settlement result should be shown.
    @State private var noFaultSettlementHoney: Int = 0 // Latest effort-fee honey transferred from no-fault seat-full settlement.
    @State private var showAttendeeRateHostAlert: Bool = false // State or dependency property.
    @State private var showNextRoundAfterRating: Bool = false // State or dependency property.
    @State private var showHostRateAttendeeAlert: Bool = false // State or dependency property.
    @State private var hostRateAttendeeId: String = "" // State or dependency property.
    @State private var hostRateAttendeeName: String = "" // State or dependency property.
    @State private var showRejectResolveAlert: Bool = false // State or dependency property.
    @State private var rejectAttendeeId: String = "" // State or dependency property.
    @State private var rejectAttendeeName: String = "" // State or dependency property.
    @State private var showInviteSheet: Bool = false // State or dependency property.
    /// ✅ New initializer: pass VM from caller (RoomBrowseView already does this)
    init(vm: RoomViewModel, onRoomClosed: (() -> Void)? = nil) { // Initializes this type.
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
            RoomFormView(
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
            if isCopyToastVisible {
                Text(LocalizedStringKey("common_copied"))
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            messageBoxOverlay
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

                    Section {
                        ZStack(alignment: .topLeading) {
                            if joinGreetingMessage.isEmpty {
                                Text(LocalizedStringKey("room_join_greeting_placeholder"))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 6)
                            }
                            SelectAllTextEditor(
                                text: $joinGreetingMessage,
                                isFirstResponder: $isJoinGreetingFocused,
                                autocapitalization: .sentences,
                                autocorrection: .yes
                            ) { latestValue in
                                let maxLength = 100
                                if latestValue.count > maxLength {
                                    joinGreetingMessage = String(latestValue.prefix(maxLength))
                                }
                            }
                            .frame(minHeight: 88)
                            .accessibilityIdentifier("room_join_sheet_greeting_editor")
                        }
                    } header: {
                        Text(LocalizedStringKey("room_join_greeting_header"))
                    } footer: {
                        Text(LocalizedStringKey("room_join_greeting_footer"))
                    }
                }
                .navigationTitle(LocalizedStringKey("room_join_title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(LocalizedStringKey("common_cancel")) {
                            showJoinSheet = false
                            isJoinGreetingFocused = false
                        }
                        .accessibilityIdentifier("room_join_sheet_cancel_button")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(LocalizedStringKey("common_ok")) {
                            showJoinSheet = false
                            isJoinGreetingFocused = false
                            showJoinConfirmAlert = true
                        }
                        .disabled(
                            joinDepositAmount < (vm.room?.fixedRaidCost ?? 0)
                            || joinDepositAmount > session.honey
                            || joinGreetingMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                        .accessibilityIdentifier("room_join_sheet_ok_button")
                    }
                }
                .onAppear {
                    if joinGreetingMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        joinGreetingMessage = NSLocalizedString("room_join_greeting_default", comment: "")
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
                            if AppTesting.useMockRooms {
                                showDepositSheet = false
                                Task { await vm.leave() }
                            } else {
                                showDepositSheet = false
                                leaveRoomName = vm.room?.title ?? ""
                                showLeaveConfirmAlert = true
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Text(LocalizedStringKey("room_leave_room"))
                                Spacer()
                            }
                        }
                        .accessibilityIdentifier("room_leave_button")
                    } footer: {
                        Text(LocalizedStringKey("room_leave_room_footer"))
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
                        showCopiedToast()
                    }
                )
            }
        }
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
                        isAskingToJoin: vm.isAskingToJoin(attendeeId: attendee.id),
                        isPendingConfirmation: vm.isWaitingConfirmation(attendeeId: attendee.id),
                        isRejectedConfirmation: vm.isRejectedConfirmation(attendeeId: attendee.id),
                        onKick: {
                            Task {
                                await vm.kick(attendeeId: attendee.id)
                            }
                        },
                        onApproveJoinApplication: {
                            Task {
                                await vm.approveJoinApplication(attendeeId: attendee.id)
                            }
                        },
                        onRejectJoinApplication: {
                            Task {
                                await vm.rejectJoinApplication(attendeeId: attendee.id)
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
                    Image(systemName: "pencil")
                        .font(.headline)
                }
                .accessibilityLabel(LocalizedStringKey("room_edit_room_accessibility"))
                .disabled(vm.isLoading)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if vm.role == .attendee, vm.isCurrentUserAllowedToEditDeposit {
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
                            joinGreetingMessage = NSLocalizedString("room_join_greeting_default", comment: "")
                            showJoinSheet = true
                        } label: {
                            Text(LocalizedStringKey("common_join"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("room_join_button")
                        .disabled(vm.isLoading || session.honey < room.fixedRaidCost)
                    } else if vm.canJoin {
                        Button {
                            let minBid = room.fixedRaidCost
                            let clamped = max(joinDepositAmount, minBid)
                            joinDepositAmount = min(clamped, session.honey)
                            joinGreetingMessage = NSLocalizedString("room_join_greeting_default", comment: "")
                            showJoinSheet = true
                        } label: {
                            Text(LocalizedStringKey("common_join"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("room_join_button")
                        .disabled(vm.isLoading || session.honey < room.fixedRaidCost)
                    }

                    if vm.role == .host {
                        Button {
                            finishSelection = Set(vm.raidSettlementTargetAttendeeIds())
                            showClaimConfirmAlert = true
                        } label: {
                            Text(LocalizedStringKey("room_claim_rewards_title"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isLoading || vm.raidSettlementTargetAttendeeIds().isEmpty)
                    }

                    if AppTesting.useMockRooms {
                        Button(role: .destructive) {
                            Task {
                                await vm.leave()
                            }
                        } label: {
                            Text(LocalizedStringKey("room_leave_room"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("room_leave_button")
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

    @ViewBuilder
    private var messageBoxOverlay: some View {
        if showRaidConfirmAlert, let room = vm.room {
            HoneyMessageBox(
                title: NSLocalizedString("room_msg_raid_confirm_title", comment: ""),
                message: String(format: NSLocalizedString("room_msg_raid_confirm_message", comment: ""), room.hostName),
                buttons: [
                    HoneyMessageBoxButton(
                        id: "room_raid_confirm_joined_success",
                        title: NSLocalizedString("room_msg_raid_confirm_joined_success_button", comment: "")
                    ) {
                        showRaidConfirmAlert = false
                        Task {
                            let isConfirmed = await vm.respondToRaidConfirmation(settlementOutcome: .joinedSuccess)
                            if isConfirmed {
                                raidThanksHoney = vm.room?.fixedRaidCost ?? 0
                                showRaidThanksAlert = true
                            }
                        }
                    },
                    HoneyMessageBoxButton(
                        id: "room_raid_confirm_seat_full",
                        title: NSLocalizedString("room_msg_raid_confirm_seat_full_button", comment: "")
                    ) {
                        showRaidConfirmAlert = false
                        Task {
                            let currentDeposit = vm.currentUserDepositHoney() ?? 0
                            let isConfirmed = await vm.respondToRaidConfirmation(settlementOutcome: .seatFullNoFault)
                            if isConfirmed {
                                let fixedRaidCost = vm.room?.fixedRaidCost ?? 0
                                let noFaultEffortFee = AppConfig.Mushroom.noFaultEffortFee(for: fixedRaidCost)
                                noFaultSettlementHoney = min(currentDeposit, noFaultEffortFee)
                                isShowingNoFaultSettlementAlert = true
                            }
                        }
                    },
                    HoneyMessageBoxButton(
                        id: "room_raid_confirm_missed_invite",
                        title: NSLocalizedString("room_msg_raid_confirm_missed_invite_button", comment: ""),
                        role: .cancel
                    ) {
                        showRaidConfirmAlert = false
                        Task {
                            await vm.respondToRaidConfirmation(settlementOutcome: .missedInvitation)
                        }
                    }
                ]
            )
        } else if showRaidThanksAlert {
            HoneyMessageBox(
                title: NSLocalizedString("room_msg_raid_thanks_title", comment: ""),
                message: String(format: NSLocalizedString("room_msg_raid_thanks_message", comment: ""), raidThanksHoney),
                buttons: [
                    HoneyMessageBoxButton(
                        id: "room_raid_thanks_ok",
                        title: NSLocalizedString("common_ok", comment: "")
                    ) {
                        showRaidThanksAlert = false
                        if let room = vm.room,
                           let deposit = vm.currentUserDepositHoney(),
                           deposit < room.fixedRaidCost {
                            showNextRoundAfterRating = true
                        }
                        showAttendeeRateHostAlert = true
                    }
                ]
            )
        } else if isShowingNoFaultSettlementAlert {
            HoneyMessageBox(
                title: NSLocalizedString("room_msg_settlement_no_fault_title", comment: ""),
                message: String(format: NSLocalizedString("room_msg_settlement_no_fault_message", comment: ""), noFaultSettlementHoney),
                buttons: [
                    HoneyMessageBoxButton(
                        id: "room_settlement_no_fault_ok",
                        title: NSLocalizedString("common_ok", comment: "")
                    ) {
                        isShowingNoFaultSettlementAlert = false
                    }
                ]
            )
        } else if showAttendeeRateHostAlert {
            HoneyMessageBox(
                title: String(format: NSLocalizedString("room_msg_rate_host_title", comment: ""), vm.room?.hostName ?? "Host"),
                message: "",
                buttons: [
                    HoneyMessageBoxButton(
                        id: "room_rate_host_one",
                        title: NSLocalizedString("room_msg_rate_one_star", comment: ""),
                        role: .quiet
                    ) {
                        showAttendeeRateHostAlert = false
                        Task {
                            await vm.rateHost(stars: 1)
                            presentNextRoundAlertIfNeeded()
                        }
                    },
                    HoneyMessageBoxButton(
                        id: "room_rate_host_two",
                        title: NSLocalizedString("room_msg_rate_two_stars", comment: ""),
                        role: .quiet
                    ) {
                        showAttendeeRateHostAlert = false
                        Task {
                            await vm.rateHost(stars: 2)
                            presentNextRoundAlertIfNeeded()
                        }
                    },
                    HoneyMessageBoxButton(
                        id: "room_rate_host_three",
                        title: NSLocalizedString("room_msg_rate_three_stars", comment: ""),
                        role: .quiet
                    ) {
                        showAttendeeRateHostAlert = false
                        Task {
                            await vm.rateHost(stars: 3)
                            presentNextRoundAlertIfNeeded()
                        }
                    },
                    HoneyMessageBoxButton(
                        id: "room_rate_host_cancel",
                        title: NSLocalizedString("common_cancel", comment: ""),
                        role: .cancel
                    ) {
                        showAttendeeRateHostAlert = false
                        presentNextRoundAlertIfNeeded()
                    }
                ]
            )
        } else if showHostRateAttendeeAlert {
            HoneyMessageBox(
                title: String(format: NSLocalizedString("room_msg_rate_attendee_title", comment: ""), hostRateAttendeeName),
                message: "",
                buttons: [
                    HoneyMessageBoxButton(
                        id: "room_rate_attendee_one",
                        title: NSLocalizedString("room_msg_rate_one_star", comment: ""),
                        role: .quiet
                    ) {
                        let attendeeId = hostRateAttendeeId
                        showHostRateAttendeeAlert = false
                        Task {
                            await vm.rateAttendee(attendeeId: attendeeId, stars: 1)
                            presentNextHostRatingAlertIfNeeded(excluding: attendeeId)
                        }
                    },
                    HoneyMessageBoxButton(
                        id: "room_rate_attendee_two",
                        title: NSLocalizedString("room_msg_rate_two_stars", comment: ""),
                        role: .quiet
                    ) {
                        let attendeeId = hostRateAttendeeId
                        showHostRateAttendeeAlert = false
                        Task {
                            await vm.rateAttendee(attendeeId: attendeeId, stars: 2)
                            presentNextHostRatingAlertIfNeeded(excluding: attendeeId)
                        }
                    },
                    HoneyMessageBoxButton(
                        id: "room_rate_attendee_three",
                        title: NSLocalizedString("room_msg_rate_three_stars", comment: ""),
                        role: .quiet
                    ) {
                        let attendeeId = hostRateAttendeeId
                        showHostRateAttendeeAlert = false
                        Task {
                            await vm.rateAttendee(attendeeId: attendeeId, stars: 3)
                            presentNextHostRatingAlertIfNeeded(excluding: attendeeId)
                        }
                    },
                    HoneyMessageBoxButton(
                        id: "room_rate_attendee_cancel",
                        title: NSLocalizedString("common_cancel", comment: ""),
                        role: .cancel
                    ) {
                        showHostRateAttendeeAlert = false
                        presentNextHostRatingAlertIfNeeded(excluding: hostRateAttendeeId)
                    }
                ]
            )
        } else if showNextRoundAlert {
            HoneyMessageBox(
                title: NSLocalizedString("room_msg_next_round_title", comment: ""),
                message: NSLocalizedString("room_msg_next_round_message", comment: ""),
                buttons: [
                    HoneyMessageBoxButton(
                        id: "room_next_round_update_bid",
                        title: NSLocalizedString("room_update_bid", comment: "")
                    ) {
                        showNextRoundAlert = false
                        showDepositSheet = true
                    },
                    HoneyMessageBoxButton(
                        id: "room_next_round_leave",
                        title: NSLocalizedString("room_leave_room", comment: ""),
                        role: .destructive
                    ) {
                        showNextRoundAlert = false
                        leaveRoomName = vm.room?.title ?? ""
                        showLeaveConfirmAlert = true
                    }
                ]
            )
        } else if showJoinConfirmAlert, let room = vm.room {
            HoneyMessageBox(
                title: NSLocalizedString("room_msg_join_confirm_title", comment: ""),
                message: String(format: NSLocalizedString("room_msg_join_confirm_message", comment: ""), joinDepositAmount, room.title),
                buttons: [
                    HoneyMessageBoxButton(
                        id: "room_join_confirm_yes",
                        title: NSLocalizedString("room_msg_join_confirm_confirm_button", comment: "")
                    ) {
                        showJoinConfirmAlert = false
                        if joinDepositAmount > session.honey {
                            showNotEnoughHoneyAlert = true
                            return
                        }
                        Task {
                            await vm.join(initialDeposit: joinDepositAmount, greetingMessage: joinGreetingMessage)
                            if vm.errorMessage == nil {
                                joinSuccessRoomName = room.title
                                joinSuccessHoney = joinDepositAmount
                                showJoinSuccessAlert = true
                            }
                        }
                    },
                    HoneyMessageBoxButton(
                        id: "room_join_confirm_cancel",
                        title: NSLocalizedString("common_cancel", comment: ""),
                        role: .cancel
                    ) {
                        showJoinConfirmAlert = false
                    }
                ]
            )
        } else if showNotEnoughHoneyAlert {
            HoneyMessageBox(
                title: NSLocalizedString("room_msg_not_enough_honey_title", comment: ""),
                message: String(format: NSLocalizedString("room_msg_not_enough_honey_message", comment: ""), session.honey),
                buttons: [
                    HoneyMessageBoxButton(
                        id: "room_not_enough_honey_ok",
                        title: NSLocalizedString("common_ok", comment: "")
                    ) {
                        showNotEnoughHoneyAlert = false
                    }
                ]
            )
        } else if showJoinSuccessAlert {
            HoneyMessageBox(
                title: NSLocalizedString("room_msg_join_success_title", comment: ""),
                message: String(format: NSLocalizedString("room_msg_join_success_message", comment: ""), joinSuccessRoomName, joinSuccessHoney),
                buttons: [
                    HoneyMessageBoxButton(
                        id: "room_join_success_ok",
                        title: NSLocalizedString("common_ok", comment: "")
                    ) {
                        showJoinSuccessAlert = false
                    }
                ]
            )
        } else if vm.showJoinLimitAlert {
            HoneyMessageBox(
                title: NSLocalizedString("room_msg_join_limit_title", comment: ""),
                message: vm.joinLimitMessage,
                buttons: [
                    HoneyMessageBoxButton(
                        id: "room_join_limit_ok",
                        title: NSLocalizedString("common_ok", comment: "")
                    ) {
                        vm.showJoinLimitAlert = false
                    }
                ]
            )
        } else if showUpdateDepositSuccessAlert {
            HoneyMessageBox(
                title: NSLocalizedString("room_msg_update_deposit_success_title", comment: ""),
                message: String(format: NSLocalizedString("room_msg_update_deposit_success_message", comment: ""), updateDepositOldAmount, updateDepositNewAmount),
                buttons: [
                    HoneyMessageBoxButton(
                        id: "room_update_deposit_success_ok",
                        title: NSLocalizedString("common_ok", comment: "")
                    ) {
                        showUpdateDepositSuccessAlert = false
                    }
                ]
            )
        } else if showLeaveConfirmAlert {
            HoneyMessageBox(
                title: NSLocalizedString("room_msg_leave_confirm_title", comment: ""),
                message: String(format: NSLocalizedString("room_msg_leave_confirm_message", comment: ""), leaveRoomName),
                buttons: [
                    HoneyMessageBoxButton(
                        id: "room_leave_confirm_yes",
                        title: NSLocalizedString("common_yes", comment: ""),
                        role: .destructive
                    ) {
                        showLeaveConfirmAlert = false
                        Task {
                            await vm.leave()
                        }
                    },
                    HoneyMessageBoxButton(
                        id: "room_leave_confirm_cancel",
                        title: NSLocalizedString("common_cancel", comment: ""),
                        role: .cancel
                    ) {
                        showLeaveConfirmAlert = false
                    }
                ]
            )
        } else if showClaimConfirmAlert {
            HoneyMessageBox(
                title: NSLocalizedString("room_msg_claim_confirm_title", comment: ""),
                message: claimConfirmMessage(),
                buttons: [
                    HoneyMessageBoxButton(
                        id: "room_claim_confirm_yes",
                        title: NSLocalizedString("common_yes", comment: "")
                    ) {
                        showClaimConfirmAlert = false
                        let selected = Array(finishSelection)
                        Task {
                            await vm.finishRaid(attendeeIds: selected)
                            if vm.errorMessage == nil {
                                finishSelection.removeAll()
                                showClaimSentAlert = true
                            }
                        }
                    },
                    HoneyMessageBoxButton(
                        id: "room_claim_confirm_cancel",
                        title: NSLocalizedString("common_cancel", comment: ""),
                        role: .cancel
                    ) {
                        showClaimConfirmAlert = false
                    }
                ]
            )
        } else if showClaimSentAlert {
            HoneyMessageBox(
                title: NSLocalizedString("room_msg_claim_sent_title", comment: ""),
                message: NSLocalizedString("room_msg_claim_sent_message", comment: ""),
                buttons: [
                    HoneyMessageBoxButton(
                        id: "room_claim_sent_ok",
                        title: NSLocalizedString("common_ok", comment: "")
                    ) {
                        showClaimSentAlert = false
                    }
                ]
            )
        } else if showRejectResolveAlert {
            HoneyMessageBox(
                title: NSLocalizedString("room_msg_reject_alert_title", comment: ""),
                message: String(format: NSLocalizedString("room_msg_reject_alert_message", comment: ""), rejectAttendeeName, rejectAttendeeName),
                buttons: [
                    HoneyMessageBoxButton(
                        id: "room_msg_reject_resend_button",
                        title: NSLocalizedString("room_msg_reject_resend_button", comment: ""),
                        role: .cancel
                    ) {
                        let attendeeId = rejectAttendeeId
                        showRejectResolveAlert = false
                        Task {
                            await vm.resendRejectedConfirmation(attendeeId: attendeeId)
                        }
                    },
                    HoneyMessageBoxButton(
                        id: "room_reject_give_up",
                        title: NSLocalizedString("room_msg_reject_giveup_button", comment: ""),
                        role: .destructive
                    ) {
                        let attendeeId = rejectAttendeeId
                        showRejectResolveAlert = false
                        Task {
                            await vm.giveUpRejectedConfirmation(attendeeId: attendeeId)
                        }
                    }
                ]
            )
        }
    }

    private func copyFriendCode(_ code: String) {
        let digits = code.filter { $0.isNumber }
        guard !digits.isEmpty else { return }
        UIPasteboard.general.string = digits
        showCopiedToast()
    }

    /// Shows a short-lived copied toast message.
    private func showCopiedToast() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isCopyToastVisible = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCopyToastVisible = false
                }
            }
        }
    }

    private func claimConfirmMessage() -> String {
        NSLocalizedString("room_msg_claim_confirm_message", comment: "")
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

private struct AttendeeRow: View {
    let attendee: RoomAttendee // Attendee model rendered by this row.
    let isHostAttendee: Bool // True when this attendee is the room host.
    let isHostViewing: Bool // True when the current user viewing this screen is host.
    let isAskingToJoin: Bool // True when this attendee is pending host join approval.
    let isPendingConfirmation: Bool // True when attendee has a pending raid confirmation.
    let isRejectedConfirmation: Bool // True when attendee raid confirmation was rejected.
    let onKick: () -> Void // Callback to kick this attendee from the room.
    let onApproveJoinApplication: () -> Void // Callback to approve join application for this attendee.
    let onRejectJoinApplication: () -> Void // Callback to reject join application for this attendee.
    let onResolve: () -> Void // Callback to resolve rejected confirmation state.
    let onCopyFriendCode: (String) -> Void // Callback to copy attendee friend code.

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
                    if isAskingToJoin {
                        Text(LocalizedStringKey("room_status_asking_to_join"))
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
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

                    if !isAskingToJoin, !isPendingConfirmation, !isRejectedConfirmation {
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
                        if isAskingToJoin {
                            Button {
                                onApproveJoinApplication()
                            } label: {
                                Label(LocalizedStringKey("room_join_application_accept"), systemImage: "checkmark.circle")
                            }

                            Button(role: .destructive) {
                                onRejectJoinApplication()
                            } label: {
                                Label(LocalizedStringKey("room_join_application_reject"), systemImage: "xmark.circle")
                            }
                        } else {
                            Button(role: .destructive) {
                                onKick()
                            } label: {
                                Label(LocalizedStringKey("room_kick"), systemImage: "person.fill.xmark")
                            }
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
                if isHostViewing, isRejectedConfirmation, !isHostAttendee, !isAskingToJoin {
                    Button(LocalizedStringKey("room_reject_resolve")) {
                        onResolve()
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }

            if isHostViewing, isAskingToJoin, !attendee.joinGreetingMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text(LocalizedStringKey("room_join_greeting_label"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(attendee.joinGreetingMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RoomInviteSheet: View {
    let roomTitle: String // Title rendered in invite hint text.
    let inviteURL: URL? // Room invite URL encoded into QR/share actions.
    let onCopyInviteLink: (String) -> Void // Callback when user copies invite link.

    var body: some View {
        InviteShareSheet(
            titleKey: LocalizedStringKey("room_invite_title"),
            hintText: String(format: NSLocalizedString("room_invite_hint", comment: ""), roomTitle),
            inviteURL: inviteURL,
            shareButtonKey: LocalizedStringKey("room_invite_share_button"),
            copyButtonKey: LocalizedStringKey("room_invite_copy_button"),
            unavailableDescriptionKey: LocalizedStringKey("room_invite_link_unavailable"),
            onCopyInviteLink: onCopyInviteLink
        )
    }
}
