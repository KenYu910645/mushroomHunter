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
    /// Explicit tutorial presentation phase used by room detail flow.
    private enum RoomTutorialPhase {
        /// Tutorial is not currently presented.
        case inactive
        /// Tutorial started from first-visit auto trigger.
        case firstVisit(TutorialScenario)
        /// Tutorial started from replay entry point.
        case replay(TutorialScenario)
    }

    @Environment(\.dismiss) private var dismiss // State or dependency property.
    @EnvironmentObject private var session: UserSessionStore // State or dependency property.
    @Environment(\.colorScheme) private var scheme // State or dependency property.
    let onRoomClosed: (() -> Void)?
    /// Optional room tutorial override for replay entry points.
    private let tutorialScenarioOverride: TutorialScenario?
    /// Optional callback fired when replayed room tutorial finishes.
    private let onTutorialReplayFinished: (() -> Void)?
    /// Indicates push/deep-link should open attendee confirmation queue on first appearance.
    private let isOpeningConfirmationQueueOnAppear: Bool
    /// Indicates first load should force latest backend payload.
    private let isForceRefreshOnAppear: Bool

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
    @State private var updateDepositOldAmount: Int = 0 // State or dependency property.
    @State private var updateDepositNewAmount: Int = 0 // State or dependency property.
    @State private var showLeaveConfirmAlert: Bool = false // State or dependency property.
    @State private var leaveRoomName: String = "" // State or dependency property.
    @State private var showClaimConfirmAlert: Bool = false // State or dependency property.
    @State private var showClaimSentAlert: Bool = false // State or dependency property.
    @State private var isCopyToastVisible: Bool = false // Controls temporary copied-toast visibility.
    @State private var showFinishSheet: Bool = false // State or dependency property.
    @State private var finishSelection: Set<String> = [] // State or dependency property.
    @State private var isRaidConfirmationQueueSheetPresented: Bool = false // Controls attendee confirmation queue sheet visibility.
    @State private var isRaidHistorySheetPresented: Bool = false // Controls host raid-history sheet visibility.
    @State private var isRaidConfirmationResponding: Bool = false // Indicates attendee confirmation response transaction is currently running.
    @State private var showNextRoundAlert: Bool = false // State or dependency property.
    @State private var showRaidThanksAlert: Bool = false // State or dependency property.
    @State private var raidThanksHoney: Int = 0 // State or dependency property.
    @State private var raidRemainingDepositHoney: Int = 0 // Remaining honey still deposited in the room after joined-success settlement.
    @State private var isShowingNoFaultSettlementAlert: Bool = false // Indicates no-fault seat-full settlement result should be shown.
    @State private var noFaultSettlementHoney: Int = 0 // Latest effort-fee honey transferred from no-fault seat-full settlement.
    @State private var showAttendeeRateHostAlert: Bool = false // State or dependency property.
    @State private var showNextRoundAfterRating: Bool = false // State or dependency property.
    @State private var showHostRateAttendeeAlert: Bool = false // State or dependency property.
    @State private var hostRateAttendeeId: String = "" // State or dependency property.
    @State private var hostRateAttendeeName: String = "" // State or dependency property.
    @State private var showInviteSheet: Bool = false // State or dependency property.
    @State private var isDidRunInitialLoad: Bool = false // Ensures first-load sequence executes only once.
    @State private var isPendingOpenConfirmationQueueOnAppear: Bool // Tracks one-time auto-open request for attendee confirmation queue.
    @StateObject private var roomTutorialController = TutorialStepController() // Shared tutorial step-state controller for room detail coach marks.
    @State private var roomTutorialPhase: RoomTutorialPhase = .inactive // Explicit room tutorial phase for first-visit/replay/inactive states.
    @State private var roomTutorialFloatingHighlightFrame: CGRect? = nil // Optional floating toolbar highlight frame rendered in a top window.
    /// ✅ New initializer: pass VM from caller (RoomBrowseView already does this)
    init(
        vm: RoomViewModel,
        onRoomClosed: (() -> Void)? = nil,
        tutorialScenarioOverride: TutorialScenario? = nil,
        onTutorialReplayFinished: (() -> Void)? = nil,
        isOpeningConfirmationQueueOnAppear: Bool = false,
        isForceRefreshOnAppear: Bool = false
    ) { // Initializes this type.
        self.tutorialScenarioOverride = tutorialScenarioOverride
        self.onTutorialReplayFinished = onTutorialReplayFinished
        self.isOpeningConfirmationQueueOnAppear = isOpeningConfirmationQueueOnAppear
        self.isForceRefreshOnAppear = isForceRefreshOnAppear
        _vm = StateObject(wrappedValue: vm)
        self.onRoomClosed = onRoomClosed
        _isPendingOpenConfirmationQueueOnAppear = State(initialValue: isOpeningConfirmationQueueOnAppear)
    }

    var body: some View {
        NavigationStack {
            content
                .accessibilityIdentifier("room_details_screen")
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .bottom) { actionDock }
                .task {
                    guard !isDidRunInitialLoad else { return }
                    isDidRunInitialLoad = true
                    await handleInitialRoomLoadFlow()
                }
                .onChange(of: vm.hostPendingRatingAttendeeIds) { _, _ in
                    presentNextHostRatingAlertIfNeeded()
                }
        }
        .sheet(item: $editingRoom, onDismiss: {
            Task { await vm.load(forceRefresh: true) }
        }) { room in
            RoomCreateEditView(
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
        .overlay {
            if isRoomTutorialActive {
                Color.clear
            }
        }
        .overlayPreferenceValue(TutorialHighlightAnchorPreferenceKey.self) { anchors in
            if isRoomTutorialActive {
                roomTutorialOverlay(anchors: anchors)
            }
        }
        .background(
            TutorialHightlighAnchorUI(
                frame: roomTutorialFloatingHighlightFrame,
                isVisible: isRoomTutorialActive
            )
        )
        .onDisappear {
            if isRoomTutorialActive {
                TutorialEventLogger.log(
                    screen: "room_detail",
                    scenario: activeRoomTutorialScenario,
                    event: .cancel,
                    source: roomTutorialSourceLabel,
                    stepIndex: roomTutorialController.stepIndex,
                    stepCount: currentRoomTutorialScene?.steps.count
                )
                roomTutorialController.end()
                session.endFeatureTutorialPresentation()
                roomTutorialPhase = .inactive
            }
            roomTutorialFloatingHighlightFrame = nil
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

                        let minimumRequiredDeposit = AppConfig.Mushroom.minimumRequiredDepositHoney
                        let maximumAvailableDeposit = max(session.honey, 0)
                        let lower = min(minimumRequiredDeposit, maximumAvailableDeposit)
                        Slider(
                            value: Binding(
                                get: { Double(joinDepositAmount) },
                                set: { joinDepositAmount = Int($0) }
                            ),
                            in: Double(lower)...Double(maximumAvailableDeposit),
                            step: 1
                        )
                    } header: {
                        Text(LocalizedStringKey("room_join_deposit_header"))
                    } footer: {
                        Text(LocalizedStringKey("room_join_deposit_footer"))
                    }

                    Section {
                        ZStack(alignment: .topLeading) {
                            if joinGreetingMessage.isEmpty {
                                Text(LocalizedStringKey("room_join_greeting_placeholder"))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 6)
                            }
                            SmartTextEditor(
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
                            joinDepositAmount < AppConfig.Mushroom.minimumRequiredDepositHoney
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
                            let currentDeposit = vm.currentUserDepositHoney() ?? 0
                            let maximumAvailableDeposit = max(session.honey + currentDeposit, 0)
                            Text(String(format: NSLocalizedString("room_max_honey_format", comment: ""), maximumAvailableDeposit))
                                .foregroundStyle(.secondary)
                        }

                        let minimumRequiredDeposit = AppConfig.Mushroom.minimumRequiredDepositHoney
                        let currentDeposit = vm.currentUserDepositHoney() ?? 0
                        let maximumAvailableDeposit = max(session.honey + currentDeposit, 0)
                        let lower = min(minimumRequiredDeposit, maximumAvailableDeposit)
                        Slider(
                            value: Binding(
                                get: { Double(updateDepositAmount) },
                                set: { updateDepositAmount = Int($0) }
                            ),
                            in: Double(lower)...Double(maximumAvailableDeposit),
                            step: 1
                        )
                    } header: {
                        Text(LocalizedStringKey("room_update_deposit_header"))
                    } footer: {
                        Text(LocalizedStringKey("room_update_deposit_footer"))
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
                .navigationTitle(LocalizedStringKey("room_edit_deposit_title"))
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
                        .disabled(updateDepositAmount < AppConfig.Mushroom.minimumRequiredDepositHoney || updateDepositAmount > max(session.honey + (vm.currentUserDepositHoney() ?? 0), 0))
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
                                            Text(String(format: NSLocalizedString("room_deposit_honey_format", comment: ""), attendee.depositHoney))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .disabled(attendee.depositHoney < AppConfig.Mushroom.minimumRequiredDepositHoney)
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
        .sheet(isPresented: $isRaidConfirmationQueueSheetPresented) {
            NavigationStack {
                RoomRaidConfirmationQueueView(
                    queueItems: pendingRaidConfirmationQueueItems,
                    isResponding: isRaidConfirmationResponding,
                    onClose: { isRaidConfirmationQueueSheetPresented = false },
                    onRefresh: {
                        await vm.load(forceRefresh: true)
                    },
                    onRespond: { queueItem, settlementOutcome in
                        isRaidConfirmationQueueSheetPresented = false
                        Task { await respondToRaidConfirmation(queueItem: queueItem, settlementOutcome: settlementOutcome) }
                    }
                )
            }
        }
        .sheet(isPresented: $isRaidHistorySheetPresented) {
            NavigationStack {
                RoomRaidHistoryView(
                    historyItems: raidHistoryItemsLatestFirst,
                    onClose: { isRaidHistorySheetPresented = false },
                    onRefresh: {
                        await vm.load(forceRefresh: true)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let err = vm.errorMessage {
                        Text(err)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if let room = vm.room {
                        headerSection(room)
                        attendeeCardsContent(room)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .refreshable {
                guard !isRoomTutorialActive else { return }
                await vm.load(forceRefresh: true)
            }
            .background(Theme.backgroundGradient(for: scheme))
            .allowsHitTesting(!isRoomTutorialActive)
        }
    }

    private func headerSection(_ room: RoomDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(room.title)
                    .font(.title2.bold())
                    .lineLimit(2)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                    Text(String(format: NSLocalizedString("room_attendee_count_number_format", comment: ""), room.attendees.count, room.maxPlayers))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if !room.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(RoomLocationLocalization.displayLabel(forStoredLocation: room.location))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if !room.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(room.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .tutorialHighlightAnchor(isRoomTutorialActive ? .roomHeaderSection : nil)
    }

    /// Renders attendee cards as top-level siblings in room content.
    /// This keeps each attendee card parallel to header section in the view hierarchy.
    private func attendeeCardsContent(_ room: RoomDetail) -> some View {
        let renderedAttendees = tutorialRenderedAttendees(fallbackAttendees: room.attendees)
        return Group {
            if renderedAttendees.isEmpty {
                emptyAttendeeCard
            } else {
                if isRoomTutorialActive {
                    tutorialStaticAttendeeCard(attendees: renderedAttendees, index: 0)
                    tutorialStaticAttendeeCard(attendees: renderedAttendees, index: 1)
                    tutorialStaticAttendeeCard(attendees: renderedAttendees, index: 2)
                    tutorialStaticAttendeeCard(attendees: renderedAttendees, index: 3)
                    tutorialStaticAttendeeCard(attendees: renderedAttendees, index: 4)
                    tutorialStaticAttendeeCard(attendees: renderedAttendees, index: 5)
                } else {
                    ForEach(Array(renderedAttendees.enumerated()), id: \.element.id) { index, attendee in
                        attendeeRow(
                            attendee: attendee,
                            index: index
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    /// Shared empty attendee card shown when room has no attendees.
    private var emptyAttendeeCard: some View {
        ContentUnavailableView(
            LocalizedStringKey("room_attendees_empty_title"),
            systemImage: "person.3",
            description: Text(LocalizedStringKey("room_attendees_empty_description"))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Returns attendee rows that should be rendered in the attendee section.
    /// Tutorial mode uses scenario-static rows instead of runtime room payload so tutorial anchors remain stable.
    /// - Parameter fallbackAttendees: Runtime room attendees used outside tutorial mode and as fallback.
    /// - Returns: Attendees that should be displayed in the current render mode.
    private func tutorialRenderedAttendees(fallbackAttendees: [RoomAttendee]) -> [RoomAttendee] {
        guard isRoomTutorialActive, let tutorialConfig = currentRoomTutorialScene else {
            return fallbackAttendees
        }
        let now = Date()
        let currentUid = vm.currentUserId ?? "tutorial-current-user"
        return tutorialConfig.fakeRoom.attendees.map { fakeAttendee in
            let attendeeId = fakeAttendee.isCurrentUser ? currentUid : fakeAttendee.id
            let pendingConfirmationRequests = Dictionary(
                uniqueKeysWithValues: fakeAttendee.pendingConfirmationRequestOffsets.enumerated().map { offsetIndex, offsetSeconds in
                    ("tutorial-render-confirm-\(attendeeId)-\(offsetIndex)", now.addingTimeInterval(offsetSeconds))
                }
            )
            return RoomAttendee(
                id: attendeeId,
                name: fakeAttendee.name.value(for: TutorialScene.currentLanguage),
                friendCode: fakeAttendee.friendCode,
                stars: fakeAttendee.stars,
                depositHoney: fakeAttendee.depositHoney,
                joinGreetingMessage: fakeAttendee.joinGreetingMessage.value(for: TutorialScene.currentLanguage),
                joinedAt: now.addingTimeInterval(fakeAttendee.joinedAtOffsetSeconds),
                status: fakeAttendee.status,
                isHostRatingRequired: fakeAttendee.isHostRatingRequired,
                pendingConfirmationRequests: pendingConfirmationRequests
            )
        }
    }

    /// Renders one attendee row with shared interaction handlers and tutorial target wiring.
    /// - Parameters:
    ///   - attendee: Attendee model to render.
    ///   - index: Stable display index used by tutorial row-index target.
    @ViewBuilder
    private func attendeeRow(
        attendee: RoomAttendee,
        index: Int,
        rowHighlightTargetOverride: TutorialHighlightTarget? = nil
    ) -> some View {
        /// Row index target used by legacy/tutorial compatibility steps.
        let rowHighlightTarget = rowHighlightTargetOverride ?? tutorialHighlightTargetForAttendeeRow(index: index)
        AttendeeRow(
            attendee: attendee,
            tutorialHighlightTarget: rowHighlightTarget,
            isHostAttendee: attendee.status == .host,
            isHostViewing: (vm.role == .host),
            isAskingToJoin: vm.isAskingToJoin(attendeeId: attendee.id),
            isPendingConfirmation: vm.isWaitingConfirmation(attendeeId: attendee.id),
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
            onCopyFriendCode: { code in
                copyFriendCode(code)
            }
        )
    }

    /// Renders a fixed tutorial attendee slot by index.
    /// This keeps tutorial row anchors stable while still reusing the production attendee row view.
    /// - Parameters:
    ///   - attendees: Source attendee list.
    ///   - index: Slot index to render.
    @ViewBuilder
    private func tutorialStaticAttendeeCard(
        attendees: [RoomAttendee],
        index: Int
    ) -> some View {
        if attendees.indices.contains(index) {
            let attendee = attendees[index]
            let rowHighlightTarget = TutorialHighlightTarget.roomAttendeeRow(index: index)
            let semanticHighlightTarget = tutorialStaticSemanticTargetForSlot(
                index: index,
                attendee: attendee
            )
            /// Aggregated list target used by "Attendee list" tutorial step to cover top three attendee cards together.
            let topThreeAggregateTarget: TutorialHighlightTarget? = index < 3 ? .roomAttendeeTopThreeArea : nil
            AttendeeRow(
                attendee: attendee,
                tutorialHighlightTarget: nil,
                isHostAttendee: attendee.status == .host,
                isHostViewing: (vm.role == .host),
                isAskingToJoin: vm.isAskingToJoin(attendeeId: attendee.id),
                isPendingConfirmation: vm.isWaitingConfirmation(attendeeId: attendee.id),
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
                onCopyFriendCode: { code in
                    copyFriendCode(code)
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .tutorialHighlightAnchors(
                [semanticHighlightTarget, rowHighlightTarget, topThreeAggregateTarget].compactMap { $0 }
            )
        }
    }

    /// Resolves deterministic semantic target for tutorial static attendee slots.
    /// This bypasses runtime ordering/state drift so key tutorial anchors are always present.
    /// - Parameters:
    ///   - index: Static slot index in tutorial-mode attendee list.
    ///   - attendee: Attendee model rendered in this slot.
    /// - Returns: Semantic tutorial target bound to this static slot.
    private func tutorialStaticSemanticTargetForSlot(
        index: Int,
        attendee: RoomAttendee
    ) -> TutorialHighlightTarget? {
        guard isRoomTutorialActive else { return nil }
        if index == 0 {
            return .roomHostInfoFriendCodeArea
        }
        if index == 1 {
            return .roomFirstNonHostStatusStrip
        }
        if attendee.status == .askingToJoin {
            return .roomPendingJoinActionButtons
        }
        return nil
    }

    /// Resolves attendee-row tutorial highlight target from row index.
    /// - Parameter index: Zero-based index of attendee in rendered list order.
    /// - Returns: Stable attendee-row target when index is non-negative.
    private func tutorialHighlightTargetForAttendeeRow(
        index: Int
    ) -> TutorialHighlightTarget? {
        guard isRoomTutorialActive else { return nil }
        return TutorialHighlightTarget.roomAttendeeRow(index)
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
            if vm.role == .host {
                Button {
                    showInviteSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline)
                }
                .tutorialHighlightAnchor(isRoomTutorialActive ? .roomHostShareButton : nil)
                .accessibilityLabel(LocalizedStringKey("room_share_accessibility"))
                .disabled(isRoomTutorialActive || vm.isLoading || vm.room == nil)

            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if vm.role == .host {
                Button {
                    isRaidHistorySheetPresented = true
                } label: {
                    Image(systemName: "list.clipboard")
                        .font(.headline)
                }
                .tutorialHighlightAnchor(isRoomTutorialActive ? .roomHostRaidHistoryButton : nil)
                .accessibilityLabel(LocalizedStringKey("room_raid_history_accessibility"))
                .accessibilityIdentifier("room_raid_history_button")
                .disabled(isRoomTutorialActive || vm.isLoading)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if vm.role == .host {
                Button {
                    guard let room = vm.room else { return }
                    editingRoom = room
                } label: {
                    Image(systemName: "pencil")
                        .font(.headline)
                }
                .tutorialHighlightAnchor(isRoomTutorialActive ? .roomHostEditRoomButton : nil)
                .accessibilityLabel(LocalizedStringKey("room_edit_room_accessibility"))
                .disabled(isRoomTutorialActive || vm.isLoading || vm.room == nil)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if vm.role == .attendee {
                Button {
                    isRaidConfirmationQueueSheetPresented = true
                } label: {
                    raidConfirmationToolbarIcon
                }
                .tutorialHighlightAnchor(isRoomTutorialActive ? .roomAttendeeConfirmationButton : nil)
                .accessibilityLabel(LocalizedStringKey("room_confirmation_queue_accessibility"))
                .accessibilityIdentifier("room_confirmation_queue_button")
                .disabled(isRoomTutorialActive || vm.isLoading)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if vm.role == .attendee {
                Button {
                    let currentDeposit = vm.currentUserDepositHoney() ?? 0
                    let fixedCost = AppConfig.Mushroom.minimumRequiredDepositHoney
                    let maximumAvailableDeposit = max(session.honey + currentDeposit, 0)
                    updateDepositAmount = min(maximumAvailableDeposit, max(currentDeposit, fixedCost))
                    showDepositSheet = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.headline)
                }
                .tutorialHighlightAnchor(isRoomTutorialActive ? .roomAttendeeEditDepositButton : nil)
                .accessibilityLabel(LocalizedStringKey("room_edit_deposit_accessibility"))
                .accessibilityIdentifier("room_edit_deposit_button")
                .disabled(isRoomTutorialActive || vm.isLoading || vm.isCurrentUserAllowedToEditDeposit == false)
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
                            let minimumRequiredDeposit = AppConfig.Mushroom.minimumRequiredDepositHoney
                            let clamped = max(joinDepositAmount, minimumRequiredDeposit)
                            joinDepositAmount = min(clamped, session.honey)
                            joinGreetingMessage = NSLocalizedString("room_join_greeting_default", comment: "")
                            showJoinSheet = true
                        } label: {
                            Text(LocalizedStringKey("common_join"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("room_join_button")
                        .disabled(vm.isLoading || session.honey < AppConfig.Mushroom.minimumRequiredDepositHoney)
                    } else if vm.canJoin {
                        Button {
                            let minimumRequiredDeposit = AppConfig.Mushroom.minimumRequiredDepositHoney
                            let clamped = max(joinDepositAmount, minimumRequiredDeposit)
                            joinDepositAmount = min(clamped, session.honey)
                            joinGreetingMessage = NSLocalizedString("room_join_greeting_default", comment: "")
                            showJoinSheet = true
                        } label: {
                            Text(LocalizedStringKey("common_join"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("room_join_button")
                        .disabled(vm.isLoading || session.honey < AppConfig.Mushroom.minimumRequiredDepositHoney)
                    }

                    if vm.role == .host {
                        Button {
                            finishSelection = Set(vm.raidSettlementTargetAttendeeIds())
                            showClaimConfirmAlert = true
                        } label: {
                            Text(LocalizedStringKey("room_claim_rewards_title"))
                                .frame(maxWidth: .infinity)
                        }
                        .tutorialHighlightAnchor(isRoomTutorialActive ? .roomHostClaimButton : nil)
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

    /// Current room tutorial scenario configuration.
    private var currentRoomTutorialScene: TutorialScene.RoomDetailTutorial.Scenario? {
        switch activeRoomTutorialScenario {
        case .roomPersonalFirstVisit:
            return TutorialScene.RoomJoiner.scenario
        case .roomHostFirstVisit:
            return TutorialScene.RoomHost.scenario
        case .mushroomBrowseFirstVisit,
             .postcardBrowseFirstVisit,
             .postcardBuyerFirstVisit,
             .postcardSellerFirstVisit,
             .none:
            return nil
        }
    }

    /// Current room step converted into shared overlay step shape.
    private var currentRoomOverlayStep: TutorialOverlayStep? {
        roomTutorialController.currentStep
    }

    /// Indicates current room tutorial step is first.
    private var isRoomTutorialFirstStep: Bool {
        roomTutorialController.isFirstStep
    }

    /// Indicates current room tutorial step is last.
    private var isRoomTutorialLastStep: Bool {
        roomTutorialController.isLastStep
    }

    /// Indicates room detail tutorial overlay is currently active.
    private var isRoomTutorialActive: Bool {
        switch roomTutorialPhase {
        case .inactive:
            return false
        case .firstVisit, .replay:
            return roomTutorialController.isActive
        }
    }

    /// Blocking highlight overlay rendered above live room content.
    /// - Parameter anchors: Live anchor map collected from room descendants.
    @ViewBuilder
    private func roomTutorialOverlay(
        anchors: [TutorialHighlightTarget: [Anchor<CGRect>]]
    ) -> some View {
        if let overlayStep = currentRoomOverlayStep {
            TutorialCoachOverlay(
                step: overlayStep,
                isFirstStep: isRoomTutorialFirstStep,
                isLastStep: isRoomTutorialLastStep,
                anchors: anchors,
                floatingToolbarHighlightFrame: $roomTutorialFloatingHighlightFrame,
                onBack: showPreviousRoomTutorialStep,
                onNext: advanceRoomTutorialStep
            )
        }
    }

    /// Handles initial room load with tutorial-first flow for first entry scenarios.
    private func handleInitialRoomLoadFlow() async {
        let roomPreloadDecision = TurorialTrigger.resolveRoomPreloadDecision(
            overrideScenario: tutorialScenarioOverride,
            isUITesting: AppTesting.isUITesting,
            initialRoleSeed: vm.initialRoleSeed,
            isRoomHostScenarioCompleted: session.isTutorialScenarioCompleted(.roomHostFirstVisit),
            isRoomJoinerScenarioCompleted: session.isTutorialScenarioCompleted(.roomPersonalFirstVisit)
        )
        if case .start(let preloadScenario) = roomPreloadDecision {
            beginRoomTutorial(scenario: preloadScenario)
            return
        }
        if AppTesting.isUITesting {
            await vm.load(forceRefresh: isForceRefreshOnAppear)
            finalizePendingConfirmationQueueAutoOpen()
            return
        }

        await vm.load(forceRefresh: isForceRefreshOnAppear)

        let roomPostloadDecision = TurorialTrigger.resolveRoomPostloadDecision(
            role: vm.role,
            isRoomHostScenarioCompleted: session.isTutorialScenarioCompleted(.roomHostFirstVisit),
            isRoomJoinerScenarioCompleted: session.isTutorialScenarioCompleted(.roomPersonalFirstVisit)
        )
        if case .start(let postloadScenario) = roomPostloadDecision {
            beginRoomTutorial(scenario: postloadScenario)
            return
        }

        finalizePendingConfirmationQueueAutoOpen()
    }

    /// Opens confirmation queue once when push route requested auto-open behavior.
    private func finalizePendingConfirmationQueueAutoOpen() {
        if isPendingOpenConfirmationQueueOnAppear, vm.role == .attendee {
            isRaidConfirmationQueueSheetPresented = true
        }
        isPendingOpenConfirmationQueueOnAppear = false
    }

    /// Starts room interactive tutorial and applies fake tutorial room scene.
    /// - Parameter scenario: Target room tutorial scenario.
    private func beginRoomTutorial(scenario: TutorialScenario) {
        guard !isRoomTutorialActive else { return }
        roomTutorialPhase = tutorialScenarioOverride == nil ? .firstVisit(scenario) : .replay(scenario)
        guard let tutorialConfig = currentRoomTutorialScene,
              tutorialConfig.steps.isEmpty == false else {
            roomTutorialPhase = .inactive
            return
        }
        let overlaySteps = tutorialConfig.steps.map { tutorialStep in
            TutorialOverlayStep(
                highlightTarget: tutorialStep.highlightTarget,
                title: tutorialStep.title,
                message: tutorialStep.message
            )
        }
        guard roomTutorialController.begin(steps: overlaySteps) else {
            roomTutorialPhase = .inactive
            return
        }
        vm.loadRoomTutorialScene(for: scenario)
        session.beginFeatureTutorialPresentation()
        TutorialEventLogger.log(
            screen: "room_detail",
            scenario: scenario,
            event: .start,
            source: roomTutorialSourceLabel,
            stepIndex: roomTutorialController.stepIndex,
            stepCount: currentRoomTutorialScene?.steps.count
        )
    }

    /// Moves room tutorial to previous step when available.
    private func showPreviousRoomTutorialStep() {
        roomTutorialController.moveToPreviousStep()
        TutorialEventLogger.log(
            screen: "room_detail",
            scenario: activeRoomTutorialScenario,
            event: .back,
            source: roomTutorialSourceLabel,
            stepIndex: roomTutorialController.stepIndex,
            stepCount: currentRoomTutorialScene?.steps.count
        )
    }

    /// Advances room tutorial to next step or completes when on final step.
    private func advanceRoomTutorialStep() {
        if roomTutorialController.moveToNextStepOrFinish() {
            finishRoomTutorial()
            return
        }
        TutorialEventLogger.log(
            screen: "room_detail",
            scenario: activeRoomTutorialScenario,
            event: .next,
            source: roomTutorialSourceLabel,
            stepIndex: roomTutorialController.stepIndex,
            stepCount: currentRoomTutorialScene?.steps.count
        )
    }

    /// Completes room tutorial and restores normal room data flow.
    private func finishRoomTutorial() {
        let finishedScenario = activeRoomTutorialScenario
        let isReplayFlow: Bool
        switch roomTutorialPhase {
        case .replay:
            isReplayFlow = true
        case .inactive, .firstVisit:
            isReplayFlow = false
        }
        TutorialEventLogger.log(
            screen: "room_detail",
            scenario: finishedScenario,
            event: .finish,
            source: roomTutorialSourceLabel,
            stepIndex: roomTutorialController.stepIndex,
            stepCount: currentRoomTutorialScene?.steps.count
        )
        roomTutorialController.end()
        roomTutorialFloatingHighlightFrame = nil
        session.endFeatureTutorialPresentation()
        roomTutorialPhase = .inactive

        if isReplayFlow {
            onTutorialReplayFinished?()
            return
        }

        if let finishedScenario {
            session.markTutorialScenarioCompleted(finishedScenario)
        }
        Task {
            await vm.load(forceRefresh: true)
            finalizePendingConfirmationQueueAutoOpen()
        }
    }

    /// Active room tutorial scenario resolved from explicit phase.
    private var activeRoomTutorialScenario: TutorialScenario? {
        switch roomTutorialPhase {
        case .inactive:
            return nil
        case .firstVisit(let scenario), .replay(let scenario):
            return scenario
        }
    }

    /// Stable room tutorial source label used for structured logging.
    private var roomTutorialSourceLabel: String {
        switch roomTutorialPhase {
        case .replay:
            return "replay"
        case .inactive, .firstVisit:
            return "first_visit"
        }
    }

    @ViewBuilder
    private var messageBoxOverlay: some View {
        if showRaidThanksAlert {
            MessageBox(
                title: NSLocalizedString("room_msg_raid_thanks_title", comment: ""),
                message: String(
                    format: NSLocalizedString("room_msg_raid_thanks_message", comment: ""),
                    raidThanksHoney,
                    raidRemainingDepositHoney
                ),
                buttons: [
                    MessageBoxButton(
                        id: "room_raid_thanks_ok",
                        title: NSLocalizedString("common_ok", comment: "")
                    ) {
                        showRaidThanksAlert = false
                        if let room = vm.room,
                           let deposit = vm.currentUserDepositHoney(),
                           deposit < AppConfig.Mushroom.minimumRequiredDepositHoney {
                            showNextRoundAfterRating = true
                        }
                        showAttendeeRateHostAlert = true
                    }
                ]
            )
        } else if isShowingNoFaultSettlementAlert {
            MessageBox(
                title: NSLocalizedString("room_msg_settlement_no_fault_title", comment: ""),
                message: String(format: NSLocalizedString("room_msg_settlement_no_fault_message", comment: ""), noFaultSettlementHoney),
                buttons: [
                    MessageBoxButton(
                        id: "room_settlement_no_fault_ok",
                        title: NSLocalizedString("common_ok", comment: "")
                    ) {
                        isShowingNoFaultSettlementAlert = false
                    }
                ]
            )
        } else if showAttendeeRateHostAlert {
            MessageBox(
                title: String(format: NSLocalizedString("room_msg_rate_host_title", comment: ""), vm.room?.hostName ?? "Host"),
                message: "",
                buttons: [
                    MessageBoxButton(
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
                    MessageBoxButton(
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
                    MessageBoxButton(
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
                    MessageBoxButton(
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
            MessageBox(
                title: String(format: NSLocalizedString("room_msg_rate_attendee_title", comment: ""), hostRateAttendeeName),
                message: "",
                buttons: [
                    MessageBoxButton(
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
                    MessageBoxButton(
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
                    MessageBoxButton(
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
                    MessageBoxButton(
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
            MessageBox(
                title: NSLocalizedString("room_msg_next_round_title", comment: ""),
                message: NSLocalizedString("room_msg_next_round_message", comment: ""),
                buttons: [
                    MessageBoxButton(
                        id: "room_next_round_update_deposit",
                        title: NSLocalizedString("room_update_deposit", comment: "")
                    ) {
                        showNextRoundAlert = false
                        showDepositSheet = true
                    },
                    MessageBoxButton(
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
            MessageBox(
                title: NSLocalizedString("room_msg_join_confirm_title", comment: ""),
                message: String(format: NSLocalizedString("room_msg_join_confirm_message", comment: ""), joinDepositAmount),
                buttons: [
                    MessageBoxButton(
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
                                showJoinSuccessAlert = true
                            }
                        }
                    },
                    MessageBoxButton(
                        id: "room_join_confirm_cancel",
                        title: NSLocalizedString("common_cancel", comment: ""),
                        role: .cancel
                    ) {
                        showJoinConfirmAlert = false
                    }
                ]
            )
        } else if showNotEnoughHoneyAlert {
            MessageBox(
                title: NSLocalizedString("room_msg_not_enough_honey_title", comment: ""),
                message: String(format: NSLocalizedString("room_msg_not_enough_honey_message", comment: ""), session.honey),
                buttons: [
                    MessageBoxButton(
                        id: "room_not_enough_honey_ok",
                        title: NSLocalizedString("common_ok", comment: "")
                    ) {
                        showNotEnoughHoneyAlert = false
                    }
                ]
            )
        } else if showJoinSuccessAlert {
            MessageBox(
                title: NSLocalizedString("room_msg_join_success_title", comment: ""),
                message: NSLocalizedString("room_msg_join_success_message", comment: ""),
                buttons: [
                    MessageBoxButton(
                        id: "room_join_success_ok",
                        title: NSLocalizedString("common_ok", comment: "")
                    ) {
                        showJoinSuccessAlert = false
                    }
                ]
            )
        } else if vm.showJoinLimitAlert {
            MessageBox(
                title: NSLocalizedString("room_msg_join_limit_title", comment: ""),
                message: vm.joinLimitMessage,
                buttons: [
                    MessageBoxButton(
                        id: "room_join_limit_ok",
                        title: NSLocalizedString("common_ok", comment: "")
                    ) {
                        vm.showJoinLimitAlert = false
                    }
                ]
            )
        } else if showUpdateDepositSuccessAlert {
            MessageBox(
                title: NSLocalizedString("room_msg_update_deposit_success_title", comment: ""),
                message: String(format: NSLocalizedString("room_msg_update_deposit_success_message", comment: ""), updateDepositOldAmount, updateDepositNewAmount),
                buttons: [
                    MessageBoxButton(
                        id: "room_update_deposit_success_ok",
                        title: NSLocalizedString("common_ok", comment: "")
                    ) {
                        showUpdateDepositSuccessAlert = false
                    }
                ]
            )
        } else if showLeaveConfirmAlert {
            MessageBox(
                title: NSLocalizedString("room_msg_leave_confirm_title", comment: ""),
                message: String(format: NSLocalizedString("room_msg_leave_confirm_message", comment: ""), leaveRoomName),
                buttons: [
                    MessageBoxButton(
                        id: "room_leave_confirm_yes",
                        title: NSLocalizedString("common_yes", comment: ""),
                        role: .destructive
                    ) {
                        showLeaveConfirmAlert = false
                        Task {
                            await vm.leave()
                        }
                    },
                    MessageBoxButton(
                        id: "room_leave_confirm_cancel",
                        title: NSLocalizedString("common_cancel", comment: ""),
                        role: .cancel
                    ) {
                        showLeaveConfirmAlert = false
                    }
                ]
            )
        } else if showClaimConfirmAlert {
            MessageBox(
                title: NSLocalizedString("room_msg_claim_confirm_title", comment: ""),
                message: claimConfirmMessage(),
                buttons: [
                    MessageBoxButton(
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
                    MessageBoxButton(
                        id: "room_claim_confirm_cancel",
                        title: NSLocalizedString("common_cancel", comment: ""),
                        role: .cancel
                    ) {
                        showClaimConfirmAlert = false
                    }
                ]
            )
        } else if showClaimSentAlert {
            MessageBox(
                title: NSLocalizedString("room_msg_claim_sent_title", comment: ""),
                message: NSLocalizedString("room_msg_claim_sent_message", comment: ""),
                buttons: [
                    MessageBoxButton(
                        id: "room_claim_sent_ok",
                        title: NSLocalizedString("common_ok", comment: "")
                    ) {
                        showClaimSentAlert = false
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

    /// Host-visible raid history items sorted from latest confirmation to oldest confirmation.
    private var raidHistoryItemsLatestFirst: [RoomRaidHistoryItem] {
        guard let room = vm.room else { return [] }
        return room.raidConfirmationHistory
            .sorted(by: { lhs, rhs in
                lhs.requestedAt > rhs.requestedAt
            })
            .map { historyRecord in
                RoomRaidHistoryItem(
                    id: historyRecord.id,
                    requestedAt: historyRecord.requestedAt,
                    attendeeResults: historyRecord.attendeeResults.map { attendeeResult in
                        RoomRaidHistoryAttendeeResultItem(
                            id: attendeeResult.id,
                            attendeeName: attendeeResult.name,
                            status: attendeeResult.status
                        )
                    }
                )
            }
    }

    /// Queue items visible in attendee confirmation queue, sorted from latest to oldest.
    private var pendingRaidConfirmationQueueItems: [RoomRaidConfirmationQueueItem] {
        guard vm.pendingConfirmationForCurrentUser, let room = vm.room else { return [] }
        return vm.currentUserPendingConfirmationQueueLatestFirst()
            .map { pending in
                RoomRaidConfirmationQueueItem(
                    id: pending.id,
                    hostName: room.hostName,
                    requestedAt: pending.requestedAt
                )
            }
            .sorted(by: { lhs, rhs in
                lhs.requestedAt > rhs.requestedAt
            })
    }

    /// Pending attendee confirmation count used by toolbar badge.
    private var pendingRaidConfirmationCount: Int {
        pendingRaidConfirmationQueueItems.count
    }

    /// Toolbar icon with a red dot indicator when attendee has pending confirmations.
    @ViewBuilder
    private var raidConfirmationToolbarIcon: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "list.clipboard")
            if pendingRaidConfirmationCount > 0 {
                ProfileActionDot()
                    .offset(x: 6, y: -4)
            }
        }
        .accessibilityValue(
            Text(
                pendingRaidConfirmationCount > 0
                    ? "\(pendingRaidConfirmationCount)"
                    : "0"
            )
        )
    }

    /// Handles one attendee confirmation selection from the queue page.
    /// - Parameters:
    ///   - queueItem: Queue row that triggered this response.
    ///   - settlementOutcome: Selected settlement outcome submitted to backend.
    private func respondToRaidConfirmation(
        queueItem: RoomRaidConfirmationQueueItem,
        settlementOutcome: RaidSettlementOutcome
    ) async {
        guard isRaidConfirmationResponding == false else { return }
        isRaidConfirmationResponding = true
        defer { isRaidConfirmationResponding = false }

        switch settlementOutcome {
        case .joinedSuccess:
            let isConfirmed = await vm.respondToRaidConfirmation(confirmationId: queueItem.id, settlementOutcome: .joinedSuccess)
            if isConfirmed {
                raidThanksHoney = AppConfig.Mushroom.joinedSuccessRewardHoney
                raidRemainingDepositHoney = vm.currentUserDepositHoney() ?? 0
                showRaidThanksAlert = true
            }
        case .seatFullNoFault:
            let currentDeposit = vm.currentUserDepositHoney() ?? 0
            let isConfirmed = await vm.respondToRaidConfirmation(confirmationId: queueItem.id, settlementOutcome: .seatFullNoFault)
            if isConfirmed {
                noFaultSettlementHoney = min(currentDeposit, AppConfig.Mushroom.seatFullRewardHoney)
                isShowingNoFaultSettlementAlert = true
            }
        case .missedInvitation:
            _ = await vm.respondToRaidConfirmation(confirmationId: queueItem.id, settlementOutcome: .missedInvitation)
        }

        if pendingRaidConfirmationQueueItems.isEmpty == false,
           pendingRaidConfirmationQueueItems.contains(where: { $0.id == queueItem.id }) {
            isRaidConfirmationQueueSheetPresented = true
        }
    }
}

/// One attendee raid-confirmation queue entry rendered by the room confirmation page.
private struct RoomRaidConfirmationQueueItem: Identifiable, Equatable {
    /// Stable queue entry identifier.
    let id: String
    /// Host display name used in confirmation text.
    let hostName: String
    /// Most recent raid confirmation request timestamp.
    let requestedAt: Date
}

/// Attendee-facing queue page that lists pending room confirmation actions.
private struct RoomRaidConfirmationQueueView: View {
    /// Pending confirmation items that still need attendee responses.
    let queueItems: [RoomRaidConfirmationQueueItem]
    /// True while a confirmation response transaction is in flight.
    let isResponding: Bool
    /// Callback used to close this queue page.
    let onClose: () -> Void
    /// Pull-to-refresh callback for loading latest queue state.
    let onRefresh: () async -> Void
    /// Callback when attendee selects one settlement outcome.
    let onRespond: (RoomRaidConfirmationQueueItem, RaidSettlementOutcome) -> Void

    /// Main queue list layout.
    var body: some View {
        List {
            if queueItems.isEmpty {
                Text(LocalizedStringKey("room_confirmation_queue_empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(queueItems) { queueItem in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            String(
                                format: NSLocalizedString("room_confirmation_queue_item_title_format", comment: ""),
                                queueItem.hostName
                            )
                        )
                        .font(.headline)

                        Text(Optional(queueItem.requestedAt).relativeShortString())
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 8) {
                            Button {
                                onRespond(queueItem, .joinedSuccess)
                            } label: {
                                Text(LocalizedStringKey("room_msg_raid_confirm_joined_success_button"))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isResponding)
                            .accessibilityIdentifier("room_confirmation_joined_success_button_\(queueItem.id)")

                            Button {
                                onRespond(queueItem, .seatFullNoFault)
                            } label: {
                                Text(LocalizedStringKey("room_msg_raid_confirm_seat_full_button"))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isResponding)
                            .accessibilityIdentifier("room_confirmation_seat_full_button_\(queueItem.id)")

                            Button {
                                onRespond(queueItem, .missedInvitation)
                            } label: {
                                Text(LocalizedStringKey("room_msg_raid_confirm_missed_invite_button"))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isResponding)
                            .accessibilityIdentifier("room_confirmation_missed_invite_button_\(queueItem.id)")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(LocalizedStringKey("room_confirmation_queue_title"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(LocalizedStringKey("common_close")) {
                    onClose()
                }
                .accessibilityIdentifier("room_confirmation_queue_close_button")
            }
        }
        .refreshable {
            await onRefresh()
        }
    }
}

/// One host-visible raid history confirmation entry.
private struct RoomRaidHistoryItem: Identifiable, Equatable {
    /// Stable confirmation id.
    let id: String
    /// Host invitation request timestamp.
    let requestedAt: Date
    /// All non-host attendee status rows captured for this confirmation.
    let attendeeResults: [RoomRaidHistoryAttendeeResultItem]
}

/// One attendee response row inside host raid history.
private struct RoomRaidHistoryAttendeeResultItem: Identifiable, Equatable {
    /// Attendee uid.
    let id: String
    /// Attendee display name.
    let attendeeName: String
    /// Invitation response status shown in host history.
    let status: RoomRaidConfirmationAttendeeStatus
}

/// Host-facing read-only raid history page.
private struct RoomRaidHistoryView: View {
    /// Confirmation history entries sorted latest to oldest.
    let historyItems: [RoomRaidHistoryItem]
    /// Callback used to dismiss this sheet.
    let onClose: () -> Void
    /// Pull-to-refresh callback for reloading latest history.
    let onRefresh: () async -> Void

    /// Main history list composition.
    var body: some View {
        List {
            if historyItems.isEmpty {
                Text(LocalizedStringKey("room_raid_history_empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(historyItems) { historyItem in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Optional(historyItem.requestedAt).relativeShortString())
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        ForEach(historyItem.attendeeResults) { attendeeResult in
                            HStack(spacing: 10) {
                                Text(attendeeResult.attendeeName)
                                    .font(.headline)
                                    .lineLimit(1)
                                Spacer()
                                ColorfulTag(
                                    titleKey: attendeeResult.status.statusTitleKey,
                                    tone: attendeeResult.status.statusUrgency
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(LocalizedStringKey("room_raid_history_title"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(LocalizedStringKey("common_close")) {
                    onClose()
                }
                .accessibilityIdentifier("room_raid_history_close_button")
            }
        }
        .refreshable {
            await onRefresh()
        }
    }
}

extension RoomRaidConfirmationAttendeeStatus {
    /// Localized status label key for host raid history pill.
    fileprivate var statusTitleKey: LocalizedStringKey {
        switch self {
        case .confirming:
            return LocalizedStringKey("room_raid_history_status_confirming")
        case .joined:
            return LocalizedStringKey("room_raid_history_status_joined")
        case .seatFull:
            return LocalizedStringKey("room_raid_history_status_seat_full")
        case .noInvite:
            return LocalizedStringKey("room_raid_history_status_no_invite")
        }
    }

    /// Tag tone mapping for host raid-history status chips.
    fileprivate var statusUrgency: ColorfulTagTone {
        switch self {
        case .confirming, .seatFull:
            return .waiting
        case .joined:
            return .ready
        case .noInvite:
            return .rejected
        }
    }
}

private struct AttendeeRow: View {
    let attendee: RoomAttendee // Attendee model rendered by this row.
    let tutorialHighlightTarget: TutorialHighlightTarget? // Optional tutorial row-highlight target attached to this row container.
    let isHostAttendee: Bool // True when this attendee is the room host.
    let isHostViewing: Bool // True when the current user viewing this screen is host.
    let isAskingToJoin: Bool // True when this attendee is pending host join approval.
    let isPendingConfirmation: Bool // True when attendee has a pending raid confirmation.
    let onKick: () -> Void // Callback to kick this attendee from the room.
    let onApproveJoinApplication: () -> Void // Callback to approve join application for this attendee.
    let onRejectJoinApplication: () -> Void // Callback to reject join application for this attendee.
    let onCopyFriendCode: (String) -> Void // Callback to copy attendee friend code.

    /// True when this attendee row is the host-visible source of a join-request notification.
    private var isJoinRequestNotificationSource: Bool {
        isHostViewing && isAskingToJoin && !isHostAttendee
    }

    /// Localized status key displayed in attendee status badge.
    private var statusTitleKey: LocalizedStringKey {
        if isHostAttendee {
            return LocalizedStringKey("room_status_host")
        }
        if isAskingToJoin {
            return LocalizedStringKey("room_status_asking_to_join")
        }
        if isPendingConfirmation {
            return LocalizedStringKey("room_status_waiting_confirm")
        }
        if attendee.status == .notEnoughHoney {
            return LocalizedStringKey("room_status_not_enough_honey")
        }
        return LocalizedStringKey("room_status_ready")
    }

    /// Tag tone mapped from current attendee status.
    private var statusUrgency: ColorfulTagTone {
        if isHostAttendee {
            return .host
        }
        if isAskingToJoin || isPendingConfirmation {
            return .waiting
        }
        if attendee.status == .notEnoughHoney {
            return .rejected
        }
        return .ready
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if isJoinRequestNotificationSource {
                    ProfileActionDot()
                }

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
                ColorfulTag(
                    titleKey: statusTitleKey,
                    tone: statusUrgency
                )

                Spacer()

                if !isHostAttendee {
                    ColorfulTag(tone: .honey, font: .footnote.weight(.semibold)) {
                        HStack(spacing: 4) {
                            Image("HoneyIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                            Text(String(format: NSLocalizedString("room_deposit_honey_format", comment: ""), attendee.depositHoney))
                                .monospacedDigit()
                        }
                    }
                }

                ColorfulTag(tone: .star, font: .footnote.weight(.semibold)) {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                        Text("\(attendee.stars)")
                            .monospacedDigit()
                    }
                }

                if isHostViewing && !isHostAttendee && !isAskingToJoin {
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

            if isHostViewing, isAskingToJoin, !isHostAttendee {
                HStack(spacing: 10) {
                    Button {
                        onApproveJoinApplication()
                    } label: {
                        Text(LocalizedStringKey("room_join_application_accept"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(StatusBadgeLikeActionButtonStyle(tone: .ready))
                    .accessibilityIdentifier("room_join_application_accept_button_\(attendee.id)")

                    Button {
                        onRejectJoinApplication()
                    } label: {
                        Text(LocalizedStringKey("room_join_application_reject"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(StatusBadgeLikeActionButtonStyle(tone: .rejected))
                    .accessibilityIdentifier("room_join_application_reject_button_\(attendee.id)")
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .tutorialHighlightAnchor(tutorialHighlightTarget)
    }
}

/// Button style that mirrors `ColorfulTag` rounded label appearance for action chips.
private struct StatusBadgeLikeActionButtonStyle: ButtonStyle {
    /// Shared colorful-tag tone used by colorful tags and these action buttons.
    let tone: ColorfulTagTone

    /// Renders the button as a rounded badge-like action chip.
    func makeBody(configuration: Configuration) -> some View {
        ColorfulTag(
            tone: tone,
            horizontalPadding: 0,
            verticalPadding: 0,
            font: .caption.weight(.semibold)
        ) {
            configuration.label
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
