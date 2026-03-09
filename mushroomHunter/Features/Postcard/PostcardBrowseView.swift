//
//  PostcardBrowseView.swift
//  mushroomHunter
//
//  Purpose:
//  - Hosts the postcard tab browse flow with search, register sheet, and listing grid.
//
import SwiftUI

/// Push/deep-link route consumed by Postcard browse navigation stack.
struct PostcardBrowsePushRoute: Identifiable, Hashable {
    /// Unique id so repeated route payloads can still navigate.
    let id: UUID = UUID()
    /// Target postcard listing id to open.
    let postcardId: String
    /// Indicates destination should auto-open order context.
    let isOpeningOrderPage: Bool
    /// Indicates destination should force backend refresh on first load.
    let isForceRefresh: Bool
}

// MARK: - Browse

/// Root postcard browse screen used by the Postcard tab.
struct PostcardBrowseView: View {
    /// Optional postcard tutorial override used by replay entry points.
    private let tutorialScenarioOverride: TutorialScenario?
    /// Optional callback fired when replayed postcard tutorial flow finishes.
    private let onTutorialReplayFinished: (() -> Void)?
    /// Shared session state used for wallet values and profile refresh.
    @EnvironmentObject private var session: UserSessionStore
    /// Shared notification inbox state used by the top-right bell button.
    @EnvironmentObject private var notificationInbox: EventInboxStore
    /// Browse view model that loads and filters postcard listings.
    @StateObject private var vm = PostcardBrowseViewModel()
    /// Controls presentation of the search alert.
    @State private var isSearchFieldVisible: Bool = false
    /// Controls presentation of the postcard register sheet.
    @State private var isRegisterSheetPresented: Bool = false
    /// Controls presentation of the notification inbox sheet.
    @State private var isNotificationInboxPresented: Bool = false
    /// Refresh trigger incremented after creating a postcard.
    @State private var browseDataRefreshToken: Int = 0
    /// Current color scheme used for theme background rendering.
    @Environment(\.colorScheme) private var scheme
    /// Controls keyboard focus for inline search field.
    @FocusState private var isSearchFieldFocused: Bool
    /// Debounce task used to delay backend search until typing pauses.
    @State private var querySearchDebounceTask: Task<Void, Never>? = nil
    /// Shared tutorial step controller for postcard browse coach marks.
    @StateObject private var postcardBrowseTutorial = TutorialStepController()
    /// Pending push route provided by app-level notification router.
    @Binding private var pendingPushRoute: PostcardBrowsePushRoute?
    /// Active push route currently pushed in postcard navigation stack.
    @State private var activePushRoute: PostcardBrowsePushRoute? = nil
    /// Spacing used between postcard grid columns.
    private let cardColumnSpacing: CGFloat = 8

    init( // Initializes this type.
        pendingPushRoute: Binding<PostcardBrowsePushRoute?> = .constant(nil),
        tutorialScenarioOverride: TutorialScenario? = nil,
        onTutorialReplayFinished: (() -> Void)? = nil
    ) {
        self.tutorialScenarioOverride = tutorialScenarioOverride
        self.onTutorialReplayFinished = onTutorialReplayFinished
        _pendingPushRoute = pendingPushRoute
    }

    /// Main postcard browse UI tree.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let err = vm.errorMessage {
                        Text(err)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }

                    headerBar

                    if isSearchFieldVisible {
                        HStack(spacing: 8) {
                            TextField(LocalizedStringKey("postcard_search_placeholder"), text: $vm.query)
                                .focused($isSearchFieldFocused)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .submitLabel(.search)
                                .onSubmit {
                                    querySearchDebounceTask?.cancel()
                                    Task { await vm.performConfirmedSearch(session: session) }
                                }

                            Spacer(minLength: 0)

                            Button {
                                isSearchFieldFocused = false
                                isSearchFieldVisible = false
                                Task { await vm.clearConfirmedSearch(session: session) }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("postcard_search_clear_button")
                            .accessibilityLabel(LocalizedStringKey("postcard_search_clear_accessibility"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .padding(.horizontal)
                    }

                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(vm.filteredListings) { listing in
                            let ownershipTag = vm.ownershipTag(for: listing.id)
                            let isPinnedTutorialListing = postcardBrowseTutorial.isActive && ownershipTag != nil
                            let isGeneralTutorialListing = postcardBrowseTutorial.isActive && ownershipTag == nil
                            NavigationLink {
                                PostcardView(
                                    listing: listing,
                                    onListingDeleted: handleDeletedListing
                                )
                            } label: {
                                PostcardCardView(
                                    listing: listing,
                                    ownershipTag: ownershipTag
                                )
                            }
                            .tutorialHighlightAnchor(
                                isPinnedTutorialListing
                                    ? .postcardBrowsePinnedOwnershipArea
                                    : (isGeneralTutorialListing ? .postcardBrowseGeneralListingsArea : nil)
                            )
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .buttonStyle(.plain)
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("postcard_link_\(listing.id)")
                        }
                    }
                    .padding(.horizontal)

                    if !vm.listings.isEmpty {
                        if vm.isLoadingNextPage {
                            ProgressView("Loading more postcards…")
                                .padding(.top, 8)
                        } else if vm.isHasMorePages {
                            Button {
                                Task { await vm.loadNextPage() }
                            } label: {
                                Text("Load more")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .padding(.horizontal)
                            .padding(.top, 4)
                        }
                    }

                    if vm.filteredListings.isEmpty && !vm.isLoading {
                        ContentUnavailableView(
                            LocalizedStringKey("postcard_empty_title"),
                            systemImage: "magnifyingglass",
                            description: Text(LocalizedStringKey("postcard_empty_description"))
                        )
                        .padding(.top, 24)
                    }
                }
                .padding(.vertical, 8)
            }
            .refreshable {
                guard !postcardBrowseTutorial.isActive else { return }
                await vm.refresh(session: session)
            }
            .navigationTitle(LocalizedStringKey("postcard_title"))
            .navigationDestination(item: $activePushRoute) { route in
                PostcardBrowseDestinationView(route: route)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        guard !postcardBrowseTutorial.isActive else { return }
                        Task { @MainActor in
                            await notificationInbox.refreshFromServer()
                            isNotificationInboxPresented = true
                        }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                            if notificationInbox.unreadCount > 0 {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -3)
                            }
                        }
                    }
                    .accessibilityLabel(LocalizedStringKey("postcard_notification_accessibility"))
                    .accessibilityIdentifier("postcard_notification_button")
                }
            }
            .background(Theme.backgroundGradient(for: scheme))
            .allowsHitTesting(!postcardBrowseTutorial.isActive)
            .overlay {
                if vm.isLoading && vm.filteredListings.isEmpty {
                    ProgressView("Loading postcards…")
                }
            }
            .overlay {
                if postcardBrowseTutorial.isActive {
                    Color.clear
                }
            }
            .overlayPreferenceValue(TutorialHighlightAnchorPreferenceKey.self) { anchors in
                if postcardBrowseTutorial.isActive {
                    postcardBrowseTutorialOverlay(anchors: anchors)
                }
            }
        }
        .sheet(isPresented: $isRegisterSheetPresented) {
            NavigationStack {
                PostcardCreateEditView(onSubmitted: {
                    isRegisterSheetPresented = false
                    Task {
                        await CacheDirtyBitStore.shared.markPostcardBrowseDirty()
                    }
                    browseDataRefreshToken += 1
                })
                .navigationTitle(LocalizedStringKey("postcard_register_title"))
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            isRegisterSheetPresented = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isNotificationInboxPresented) {
            EventInboxView { route in
                routeEventInboxItem(route)
            }
            .environmentObject(notificationInbox)
        }
        .onChange(of: vm.selectedCountry) { _, _ in
            vm.normalizeProvinceSelection()
        }
        .onAppear {
            /// Start tutorial flow immediately so step anchors are available from the first rendered tutorial frame.
            startPostcardBrowseTutorialIfNeeded()
            if !AppTesting.isUITesting {
                /// Refresh profile/honey in parallel without blocking tutorial startup.
                Task { await session.refreshProfileFromBackend() }
            }
        }
        .onChange(of: pendingPushRoute) { _, route in
            guard let route else { return }
            activePushRoute = route
            pendingPushRoute = nil
        }
        .onChange(of: vm.query) { _, latestQuery in
            schedulePostcardSearch(for: latestQuery)
        }
        .onDisappear {
            if postcardBrowseTutorial.isActive {
                TutorialEventLogger.log(
                    screen: "postcard_browse",
                    scenario: .postcardBrowseFirstVisit,
                    event: .cancel,
                    source: tutorialSourceLabel,
                    stepIndex: postcardBrowseTutorial.stepIndex,
                    stepCount: postcardBrowseOverlaySteps.count
                )
                postcardBrowseTutorial.end()
                session.endFeatureTutorialPresentation()
            }
            querySearchDebounceTask?.cancel()
            querySearchDebounceTask = nil
        }
        .task(id: browseDataRefreshToken) {
            guard !postcardBrowseTutorial.isActive else { return }
            await vm.refresh(session: session)
        }
    }

    /// Grid layout used by postcard cards.
    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: cardColumnSpacing, alignment: .top),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: cardColumnSpacing, alignment: .top)
        ]
    }

    /// Shared top action bar for honey amount, search, and create actions.
    private var headerBar: some View {
        TopActionBar(
            honey: session.honey,
            stars: session.stars,
            onSearch: {
                isSearchFieldVisible.toggle()
                if isSearchFieldVisible {
                    isSearchFieldFocused = true
                } else {
                    isSearchFieldFocused = false
                }
            },
            onCreate: { isRegisterSheetPresented = true },
            searchAccessibilityLabel: "postcard_search_accessibility",
            createAccessibilityLabel: "postcard_register_accessibility",
            searchButtonIdentifier: "postcard_search_button",
            createButtonIdentifier: "postcard_create_button",
            isStarsVisible: false,
            tutorialBarTarget: nil,
            tutorialHoneyTarget: postcardBrowseTutorial.isActive ? .postcardBrowseHoneyTag : nil,
            tutorialSearchButtonTarget: postcardBrowseTutorial.isActive ? .postcardBrowseSearchButton : nil,
            tutorialCreateButtonTarget: postcardBrowseTutorial.isActive ? .postcardBrowseCreateButton : nil
        )
        .padding(.horizontal)
    }

    /// Triggers debounced backend search while user types in postcard search field.
    /// - Parameter latestQuery: Latest raw query text from inline search field.
    private func schedulePostcardSearch(for latestQuery: String) {
        guard !postcardBrowseTutorial.isActive else { return }
        querySearchDebounceTask?.cancel()

        let trimmedQuery = latestQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            querySearchDebounceTask = Task {
                await vm.clearConfirmedSearch(session: session)
            }
            return
        }

        querySearchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard Task.isCancelled == false else { return }
            await vm.performConfirmedSearch(session: session)
        }
    }

    /// Routes a tapped notification inbox row into existing app-level deep-link channels.
    /// - Parameter route: Inbox route metadata attached to the tapped row.
    private func routeEventInboxItem(_ route: EventInboxRoute) {
        switch route.kind {
        case .room:
            guard let roomId = route.roomId, roomId.isEmpty == false else { return }
            if route.isOpeningConfirmationQueue {
                NotificationCenter.default.post(name: .didOpenRoomConfirmationFromPush, object: roomId)
            } else {
                NotificationCenter.default.post(name: .didOpenRoomFromPush, object: roomId)
            }
        case .postcard:
            guard let postcardId = route.postcardId, postcardId.isEmpty == false else { return }
            if route.isOpeningOrderPage {
                NotificationCenter.default.post(
                    name: .didOpenPostcardOrderFromPush,
                    object: [
                        "postcardId": postcardId,
                        "orderId": route.orderId ?? ""
                    ]
                )
            } else {
                NotificationCenter.default.post(name: .didOpenPostcardFromLink, object: postcardId)
            }
        case .none:
            break
        }
    }

    /// Applies immediate local removal for one deleted listing id and schedules a backend sync refresh.
    /// - Parameter postcardId: Listing id confirmed deleted from detail edit flow.
    private func handleDeletedListing(_ postcardId: String) {
        vm.markListingDeletedLocally(postcardId: postcardId)
        Task {
            await CacheDirtyBitStore.shared.markPostcardBrowseDirty()
            await CacheDirtyBitStore.shared.markPostcardDetailDirty(postcardId: postcardId)
        }
        browseDataRefreshToken += 1
    }

    /// Current postcard browse tutorial scenario.
    private var postcardBrowseTutorialScenario: TutorialConfig.PostcardBrowse.Scenario {
        TutorialConfig.PostcardBrowse.scenario
    }

    /// Shared overlay steps converted from postcard browse tutorial config.
    private var postcardBrowseOverlaySteps: [TutorialOverlayStep] {
        postcardBrowseTutorialScenario.steps.map { step in
            TutorialOverlayStep(
                highlightTarget: step.highlightTarget,
                title: step.title,
                message: step.message
            )
        }
    }

    /// Blocking highlight overlay rendered above live postcard browse content.
    /// - Parameter anchors: Live anchor map collected from browse descendants.
    @ViewBuilder
    private func postcardBrowseTutorialOverlay(
        anchors: [TutorialHighlightTarget: [Anchor<CGRect>]]
    ) -> some View {
        if let currentStep = postcardBrowseTutorial.currentStep {
            TutorialCoachOverlay(
                step: currentStep,
                isFirstStep: postcardBrowseTutorial.isFirstStep,
                isLastStep: postcardBrowseTutorial.isLastStep,
                anchors: anchors,
                onBack: showPreviousPostcardBrowseTutorialStep,
                onNext: advancePostcardBrowseTutorialStep
            )
        }
    }

    /// Starts postcard browse tutorial when needed, otherwise loads normal backend data.
    private func startPostcardBrowseTutorialIfNeeded() {
        if tutorialScenarioOverride == .postcardBrowseFirstVisit {
            beginPostcardBrowseTutorial()
            return
        }

        if AppTesting.isUITesting || session.isTutorialScenarioCompleted(.postcardBrowseFirstVisit) {
            Task { await vm.loadOnAppear(session: session) }
            return
        }

        beginPostcardBrowseTutorial()
    }

    /// Begins postcard browse tutorial mode and seeds fake local listings.
    private func beginPostcardBrowseTutorial() {
        guard postcardBrowseTutorial.begin(steps: postcardBrowseOverlaySteps) else { return }
        vm.loadPostcardBrowseTutorialScene()
        session.beginFeatureTutorialPresentation()
        TutorialEventLogger.log(
            screen: "postcard_browse",
            scenario: .postcardBrowseFirstVisit,
            event: .start,
            source: tutorialSourceLabel,
            stepIndex: postcardBrowseTutorial.stepIndex,
            stepCount: postcardBrowseOverlaySteps.count
        )
    }

    /// Shows previous tutorial step when current step is not first.
    private func showPreviousPostcardBrowseTutorialStep() {
        postcardBrowseTutorial.moveToPreviousStep()
        TutorialEventLogger.log(
            screen: "postcard_browse",
            scenario: .postcardBrowseFirstVisit,
            event: .back,
            source: tutorialSourceLabel,
            stepIndex: postcardBrowseTutorial.stepIndex,
            stepCount: postcardBrowseOverlaySteps.count
        )
    }

    /// Advances to next tutorial step or exits tutorial when final step is completed.
    private func advancePostcardBrowseTutorialStep() {
        let isFinishing = postcardBrowseTutorial.moveToNextStepOrFinish()
        if isFinishing {
            finishPostcardBrowseTutorial()
        } else {
            TutorialEventLogger.log(
                screen: "postcard_browse",
                scenario: .postcardBrowseFirstVisit,
                event: .next,
                source: tutorialSourceLabel,
                stepIndex: postcardBrowseTutorial.stepIndex,
                stepCount: postcardBrowseOverlaySteps.count
            )
        }
    }

    /// Completes tutorial and restores normal postcard browse data flow.
    private func finishPostcardBrowseTutorial() {
        TutorialEventLogger.log(
            screen: "postcard_browse",
            scenario: .postcardBrowseFirstVisit,
            event: .finish,
            source: tutorialSourceLabel,
            stepIndex: postcardBrowseTutorial.stepIndex,
            stepCount: postcardBrowseOverlaySteps.count
        )
        postcardBrowseTutorial.end()
        session.endFeatureTutorialPresentation()

        if tutorialScenarioOverride == .postcardBrowseFirstVisit {
            onTutorialReplayFinished?()
            return
        }

        session.markTutorialScenarioCompleted(.postcardBrowseFirstVisit)
        Task { await vm.refresh(session: session) }
    }

    /// Stable tutorial source label used for structured logging.
    private var tutorialSourceLabel: String {
        tutorialScenarioOverride == nil ? "first_visit" : "replay"
    }

}

/// Postcard push destination loader that opens normal postcard detail route in-stack.
private struct PostcardBrowseDestinationView: View {
    /// Route payload to resolve postcard detail destination.
    let route: PostcardBrowsePushRoute
    /// Loaded postcard listing document.
    @State private var listing: PostcardListing? = nil
    /// Indicates listing fetch is in progress.
    @State private var isLoading: Bool = false
    /// Repository used to load listing by id.
    private let repo = FbPostcardRepo()

    var body: some View {
        Group {
            if let listing {
                PostcardView(
                    listing: listing,
                    onListingDeleted: nil,
                    isOpeningOrderPageOnAppear: route.isOpeningOrderPage,
                    isForceRefreshOnAppear: route.isForceRefresh
                )
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    LocalizedStringKey("postcard_link_unavailable_title"),
                    systemImage: "qrcode",
                    description: Text(LocalizedStringKey("postcard_link_unavailable_message"))
                )
            }
        }
        .task {
            await loadPostcard()
        }
    }

    /// Loads the route postcard id from backend (or fixtures in UI-test mode).
    private func loadPostcard() async {
        guard !route.postcardId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if AppTesting.useMockPostcards {
            if route.postcardId == AppTesting.fixturePostcardId {
                listing = AppTesting.fixturePostcardListing()
            } else if route.postcardId == AppTesting.fixtureOwnedPostcardListing().id {
                listing = AppTesting.fixtureOwnedPostcardListing()
            }
            return
        }
        isLoading = true
        defer { isLoading = false }
        listing = try? await repo.fetchPostcard(postcardId: route.postcardId)
    }
}

/// Card tile shown for each postcard listing in the browse grid.
private struct PostcardCardView: View {
    /// Listing displayed by this card.
    let listing: PostcardListing
    /// Optional ownership marker for pinned user-owned postcard slots.
    let ownershipTag: PostcardBrowseViewModel.OwnershipTag?
    /// Current color scheme used for card background styling.
    @Environment(\.colorScheme) private var scheme
    /// Fixed aspect ratio used for postcard thumbnail area.
    private let imageAspectRatio: CGFloat = 1.0

    /// Card content for a single postcard listing.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .aspectRatio(imageAspectRatio, contentMode: .fit)

                if let urlString = listing.thumbnailUrl ?? listing.imageUrl, let url = URL(string: urlString) {
                    CachedPostcardImageView(
                        imageURL: url,
                        fallbackSystemImageName: "photo",
                        fallbackIconFont: .title
                    )
                    .aspectRatio(imageAspectRatio, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else if let tutorialAssetName = TutorialConfig.tutorialPostcardSnapshotAssetName(for: listing.id) {
                    TutorialPostcardSnapshotImageView(
                        assetName: tutorialAssetName,
                        fallbackSystemImageName: "photo",
                        fallbackIconFont: .title
                    )
                        .aspectRatio(imageAspectRatio, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }

                // Keep price visible on top of the postcard snapshot in the browse card.
                ColorfulTag(
                    tone: .honey,
                    horizontalPadding: 8,
                    verticalPadding: 4,
                    font: .caption.weight(.semibold),
                    isSolidBackground: true,
                    customBackgroundColor: .accentColor
                ) {
                    HStack(spacing: 4) {
                        Image("HoneyIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                        Text("\(listing.priceHoney)")
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let ownershipTag {
                    PostcardOwnershipTagChip(titleKey: ownershipTag.titleKey)
                }
            }
            .frame(maxWidth: .infinity)

            Text(listing.title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .truncationMode(.tail)

            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                Text(listing.location.shortLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.cardBackground(for: scheme))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Ownership chip shown on pinned postcard browse cards.
private struct PostcardOwnershipTagChip: View {
    /// Localized ownership label rendered by this chip.
    let titleKey: LocalizedStringKey

    /// Tag chip UI used for on-shelf/ordered markers.
    var body: some View {
        ColorfulTag(
            titleKey: titleKey,
            tone: .ownership,
            horizontalPadding: 8,
            verticalPadding: 4,
            font: .caption2.weight(.semibold)
        )
    }
}
