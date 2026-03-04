# Mushroom

## Related Files
- `mushroomHunter/Features/Mushroom/RoomBrowseView.swift`: mushroom room list UI and room entry points.
- `mushroomHunter/Features/Mushroom/RoomBrowseViewModel.swift`: browse state, filtering, and join flow orchestration.
- `mushroomHunter/Features/Mushroom/RoomCreateEditView.swift`: host room create/edit UI and form validation.
- `mushroomHunter/Features/Mushroom/RoomView.swift`: room details UI, attendee actions, finish flow, invite share sheet.
- `mushroomHunter/Features/Mushroom/RoomView.swift`: includes room-specific invite sheet wrapper used by room view.
- `mushroomHunter/Features/Shared/InviteShareSheet.swift`: shared invite QR sheet component used by room and postcard screens.
- `mushroomHunter/Features/Mushroom/RoomViewModel.swift`: room details state, role/join gating logic, and action orchestration.
- `mushroomHunter/Features/Mushroom/RoomDomainModels.swift`: room/attendee data models and status enums.
- `mushroomHunter/Features/Shared/BrowseViewTopActionBar.swift`: shared honey/search/create header used by browse screens (stars hidden on mushroom browse).
- `mushroomHunter/Features/Shared/NotificationInboxView.swift`: shared in-app notification inbox list opened from mushroom/postcard top-right bell actions.
- `mushroomHunter/Features/Shared/SelectAllTextField.swift`: shared auto-select text field wrapper used by host/profile/profile-create forms.
- `mushroomHunter/Features/Shared/SelectAllTextEditor.swift`: shared auto-select text editor wrapper used by host description input.
- `mushroomHunter/Features/Shared/OutsideTapKeyboardDismissBridge.swift`: shared UIKit bridge that dismisses keyboard on outside taps without collapsing during scroll.
- `mushroomHunter/Features/Shared/HoneyMessageBox.swift`: shared custom confirmation/error dialog used across mushroom room screens.
- `mushroomHunter/Features/Shared/ProfileStatusBadge.swift`: shared urgency badge + red action-dot UI primitives used by room/postcard status rows.
- `mushroomHunter/Services/Firebase/RoomBrowseRepo.swift`: Firestore reads for browsing open rooms.
- `mushroomHunter/Services/Firebase/ProfileListRepo.swift`: Firestore joined/hosted room summary reads used to pin user-owned rooms on browse top.
- `mushroomHunter/Services/Firebase/RoomFormRepo.swift`: Firestore writes for host room lifecycle (create/update/close).
- `mushroomHunter/Services/Firebase/RoomRepo.swift`: Firestore reads for a single room and attendee list.
- `mushroomHunter/Services/Firebase/RoomActionsRepo.swift`: Firestore transactions for join/leave/deposit/raid confirmation/rating.
- `mushroomHunter/Utilities/RoomInviteLink.swift`: deep link generation/parsing for `honeyhub://room/{roomId}`.
- `mushroomHunter/Utilities/CountryLocalization.swift`: shared locale-aware country + room-location display resolver used by mushroom/postcard labels.
- `mushroomHunter/Utilities/AppConfig.swift`: centralized owner-managed mushroom settings (attribute lists, fixed raid defaults, room limits, query limits).
- `mushroomHunter/Utilities/AppDataCache.swift`: shared app-level memory+disk Codable cache used by mushroom browse/detail stale-first loading.
- `mushroomHunter/Utilities/FriendCode.swift`: shared friend-code sanitizing/formatting/validation utility used across profile, room, and postcard flows.
- `mushroomHunter/User/NotificationInboxStore.swift`: shared Firestore-backed notification event history pagination, Action/Record state handling, and deep-link route metadata.
- `functions/index.js`: server-side push triggers used by mushroom confirmation flows.

## Feature Coverage
- Main Mushroom tab icon uses SF Symbol `person.3.fill` to reflect group room coordination.
- Host can create and manage a room with title/location/description/fixed raid cost (no target mushroom selectors in create/edit UI).
- Browse search is opened from the top action bar as an inline search field above the room list (no dedicated sheet/alert).
- Mushroom browse includes a screen-level top-right bell icon that opens the shared notification inbox list.
- Notification inbox loads the latest 10 events first from `users/{uid}/events` and loads older pages while scrolling.
- Notification inbox rows now separate Action vs Record semantics:
  - Action events render with red dot + bold text while unresolved.
  - Record events render as normal history rows.
  - Tapping a row only routes for Action events; Record rows do not open routes.
- Tapping a room-related inbox row routes using existing push deep-link channels:
  - raid confirmation notifications open room and auto-present confirmation queue.
  - other room notifications open room detail.
- Mushroom browse search matches room title and location text (country/city).
- Mushroom browse search applies local filtering while typing; backend fetch (first page) is refreshed only when user taps `Search`.
- Mushroom browse now pins user-owned rooms above general browse results at all times, ordered as `Host` -> `Joined` -> other browse rooms:
  - `Host` rooms are rendered first at the top with a `Host` ownership tag.
  - `Joined` rooms are rendered after host rooms with a `Joined` ownership tag.
  - Ownership tags are rendered on the same row as location info, aligned at each room slot's right side.
  - Pinned rows are deduplicated from the general browse list to keep ownership context clear.
  - Pinned rows still follow the same availability/search filters, so unmatched rows are hidden while typing a query.
- Mushroom browse priority uses a score model (after local text/availability filters):
  - Score reward: `hostStars * AppConfig.Mushroom.browsePriorityHostStarWeight`.
  - Score penalty: `dormantHoursBeyondThreshold * AppConfig.Mushroom.browsePriorityDormantHourPenalty`.
  - Dormant hours are measured from `lastSuccessfulRaidAt` (fallback `createdAt` when never raided).
  - No dormancy penalty is applied until elapsed time exceeds `AppConfig.Mushroom.browsePriorityDormantThresholdHours` (default 48h).
- Mushroom browse list now uses app-level stale-first cache:
  - Entering Mushroom tab reads cached browse list first, then immediately refreshes from Firestore and overwrites cache.
  - Browse fetch uses server-first query (with local/default fallback only on server failure) so attendee count (`joinedCount`) is aligned with room detail more consistently.
  - Pull-to-refresh forces latest Firestore query and overwrites cache.
  - Tapping keyboard search submit forces latest Firestore query before applying local filter.
- Inline search field includes an `x` clear button; tapping `x` clears query and collapses the search field. Keyboard submit uses `Search` and triggers backend search. Top-bar search icon toggles field show/hide.
- Mushroom browse uses `ScrollView + LazyVStack` (same pattern as Postcard browse), so the top action bar (honey/search/create) moves with page scroll and matches postcard visual style.
- UI-test mode (`--ui-testing --mock-rooms`) routes host submit flow through mock success without Firestore writes.
- Host create/edit description is prefilled with localized default `host_default_description` (`Welcome! Let's play!`) when empty.
- Owner config `AppConfig.Mushroom.isRaidPaymentAdjustmentEnabled` controls whether host room form shows the raid payment adjustment option:
  - `false`: adjustment UI is hidden in room form and create flow uses fixed payment `10` honey (`AppConfig.Mushroom.disabledRaidPaymentHoney`).
  - `true`: host can adjust payment via stepper from min value to `AppConfig.Mushroom.enabledRaidPaymentMaxHoney` (currently `10`).
- Host create/edit form now dismisses keyboard on outside taps (without collapsing during scroll), on keyboard `Enter`/`Done`, and before submit, and auto-scrolls the focused input above keyboard overlap.
- Host location parser now recognizes both current-locale and English country names (plus ISO country codes), so existing room/postcard location values still map correctly after language changes.
- Room browse/detail location labels now localize the country segment to the viewer locale while preserving stored city text (including legacy English country values).
- Host can manage attendees (kick, close room, finish raid/claim cycle).
- Join request workflow:
  - Joiner enters deposit + greeting message.
  - Join request creates attendee with status `AskingToJoin` and occupies a room slot immediately.
  - Host can approve/reject from two inline buttons shown under the joiner greeting message (`Accept` on left in green, `Reject` on right in red).
  - Attendee row `...` menu is used for non-join-request host actions like `Kick`.
  - Rejected application removes attendee and refunds full deposit.
- Host `Mushroom Raid Done` now sends escrow settlement requests to all eligible non-host joiners in the room (instead of manually selecting attendees), including attendees who already have unresolved pending confirmations.
- Joining from room details now requires both:
  - deposit amount
  - attendee greeting message (required, max 100 chars)
- Join sheet pre-fills a localized default greeting and blocks submit when greeting is empty.
- Join confirmation alert now includes both `Sure` and `Cancel` actions.
- Join confirmation message is generic and no longer includes room title text.
- Top-up honey sheet leave button now shows a footer hint that leaving returns unspent deposit.
- UI-test mode supports room deep-link routing via launch arg `--ui-open-room {roomId}` for deterministic room-entry automation.
- In UI-test mock mode, attendee leave can execute directly from the bottom action dock (and from edit-bid sheet) without confirmation alert to reduce automation flakiness.
- In UI-test mock mode, room role/deposit checks fall back to fixture user id (`ui-test-user`) when session auth uid is not yet populated.
- UI-test mock mode supports forcing fixture room attendee state at launch with `--mock-room-joined`.
- Host reject-resolution alert behavior:
  - `Resend`: appends a new pending confirmation request and keeps attendee in `WaitingConfirmation`.
  - `Give Up`: sets attendee status back to `Ready`.
- Room confirmation/error feedback uses shared patterns:
  - attendee raid settlement now uses a dedicated queue page opened from a top-right toolbar icon in room details.
  - join/leave/claim/rating and other confirmations still use shared `HoneyMessageBox` for consistent action layout.
- Host raid confirmation prompt uses a generic confirmation message without attendee-name list text.
- Joiner room details now shows a top-right confirmation-queue icon with a red dot when there are pending room confirmations.
- Joiner confirmation queue page shows all unprocessed confirmations for the current room and renders newest-first ordering.
- Tapping a raid-confirmation push notification now opens the related room and auto-presents the joiner confirmation queue page directly.
- Room opened from push now forces a server refresh on first load so latest confirmation state appears immediately.
- Push routing now opens Mushroom tab and pushes the normal Room page inside the tab navigation stack (non-sheet flow).
- Joiner confirmation queue row content is compact:
  - host invitation sentence.
  - relative elapsed text only (`Xm ago` / `Xh ago`), with no extra prefix and no room-title line.
- Host room details now shows a top-right `Raid History` icon (`list.clipboard`), matching joiner confirmation-list icon style.
- Host room details top-right host-action order is `Share -> Raid History -> Edit`.
- Joined-room (attendee) top-right action order is `Confirmation Queue (clipboard) -> Edit Deposit (pencil)`.
- Host raid history page is read-only and lists confirmation records from latest to oldest.
- Each host history record shows all non-host attendees in the room snapshot with rounded status pills:
  - `Confirming` (yellow)
  - `Joined` (green)
  - `Seat full` (yellow)
  - `No invite` (red)
- Each queue row provides the same three settlement actions used previously in the attendee confirmation message box:
  - `Yes, I joined the mushroom`
  - `Yes, but the mushroom is full`
  - `No, I didn't see invitation`
- Honey-tokenized message text in shared `HoneyMessageBox` renders `HoneyIcon` as true inline text content, so long localized sentences wrap naturally without pushing the icon to the trailing edge.
- Inline HoneyIcon size used in message-box tokenized text is owner-tunable via `AppConfig.SharedUI.honeyMessageIconSize`.
- Host room form minimum-payment row now token-renders `host_min_bid_label` so `{honey_icon}` displays as inline `HoneyIcon` instead of raw text.
- Room details includes invite share tools for host:
  - QR code sheet.
  - Share/copy room invite link using deep link format `honeyhub://room/{roomId}`.
- Room details copy-feedback toast (`Copied to clipboard`) now uses the same visual style and timing as postcard screens to keep cross-feature behavior consistent.
- Room header no longer shows `Last Successful Raid`; header now focuses on title, attendee count, location, and description.
- Room attendee list statuses now use the same rounded-rectangle urgency badge style as Profile status labels (`Host` blue, `Asking/Waiting` orange, `Ready` green).
- Room attendee star display now uses a yellow rounded badge with star icon to improve readability.
- Room attendee deposit honey display now uses a rounded orange HoneyIcon badge style to match the star badge treatment.
- In Room details, host-visible `AskingToJoin` attendee rows now show a tiny red dot before the attendee name to identify the notification source quickly.
- Room details now uses app-level stale-first cache for room header + attendee data:
  - Opening room shows cached payload first.
  - Pull-to-refresh forces latest `rooms/{roomId}` + `attendees` query and overwrites cache.
  - Room state-changing actions (join/leave/deposit update/kick/approve/reject/finish/confirm/rating) force latest backend reload and refresh cache.
- Room detail toolbar role now accepts a browse-seeded initial role (`host`/`attendee`) before async detail fetch completes, so top-right host/joined action buttons no longer pop in late after first render.
- Room detail top-right buttons now follow postcard-style slot rendering: host/attendee icon slots are shown immediately from role state, and actions that require loaded room payload stay disabled until room data is ready.
- Room detail view hides the navigation title so content starts directly with room snapshot/details.

## Cloud Functions (Mushroom Use Cases)
- `recordRoomCreatedEvent`
  - Trigger: create on `rooms/{roomId}`
  - Writes host-side notification history event (`ROOM_CREATED`) for mushroom-room creation.
- `recordHostRaidInviteEvent`
  - Trigger: update on `rooms/{roomId}` when `raidConfirmationHistory` receives a new head record.
  - Writes host-side notification history event (`RAID_INVITED`) for each raid invitation cycle.
- `notifyHostJoinRequest`
  - Trigger: create on `rooms/{roomId}/attendees/{attendeeUid}` with `status = AskingToJoin`
  - Push target: host (`rooms/{roomId}.hostFcmToken` first, with `users/{hostUid}.fcmToken` fallback)
  - Payload data: `type=room_join_request`, `roomId`, `room_id`, `attendeeUid`, `eventId`
  - Also writes join-request history events for both joiner and host.
- `handleRoomAttendeeUpdatedEvents`
  - Trigger: update on `rooms/{roomId}/attendees/{attendeeUid}`.
  - This single update trigger routes internally by transition and now covers:
    - attendee enters `WaitingConfirmation` (old `sendRaidConfirmationPush` behavior),
    - join applicant `AskingToJoin -> Ready` (old `notifyJoinApplicantAccepted` behavior),
    - confirmation result `WaitingConfirmation -> Ready` (old `notifyHostRaidConfirmationResult` behavior),
    - rating flag transitions (old `notifyMushroomStarReceived` behavior).
  - Push and event-history payload behavior for each routed event remains unchanged.
- `notifyJoinApplicantRejected`
  - Trigger: delete on `rooms/{roomId}/attendees/{attendeeUid}` where previous `status = AskingToJoin`
  - Push target: join applicant (`rooms/{roomId}/attendees/{attendeeUid}.fcmToken` snapshot first, with `users/{attendeeUid}.fcmToken` fallback)
  - Payload data: `type=room_join_request_rejected`, `roomId`, `room_id`, `eventId`
  - Also writes rejection history events for both joiner and host.
- Routed behavior details inside `handleRoomAttendeeUpdatedEvents`:
  - `RAID_CONFIRM`: sends attendee push (`type=raid_confirmation`) and writes attendee-side action event.
  - `JOIN_REQUEST_ACCEPTED`: sends applicant push and writes acceptance history events for applicant + host.
  - `REPLY_HOST`: sends host push with outcome-specific payload type and writes host + attendee history events.
  - `STAR_RECEIVED`: sends receiver push and writes receiver history event (with mirrored sender-side history where applicable).
- Mushroom push notification copy is delivered via APNs localization keys in app `Localizable.strings` (no hardcoded-only message text in Cloud Functions).


### Confirmation stars flow
- Attendee settlement flow now has three outcomes after host taps `Mushroom Raid Done`:
  - `Yes, joined success`: host gets full payment (`fixedRaidCost`), attendee deposit deducts full payment, attendee can rate host.
  - `No, seat full (no-fault race)`: host gets small effort fee (`AppConfig.Mushroom.noFaultEffortFee`), attendee deposit deducts only that effort fee.
  - `No, I didn't see invitation`: no honey transfer, treated as host-not-invited outcome.
- Star-selection buttons in rating message boxes use neutral bordered style (non-prominent) to reduce visual glare.
- Attendee rating is available only for `joined success` settlement.
- Host flow: when attendee accepts confirmation, attendee doc is marked `needsHostRating = true`; host can then give that attendee `1`, `2`, or `3` stars.
- Stars updates write to `users/{uid}.stars` and also refresh room attendee stars in the active room so Room Details reflects new totals immediately.
- Firestore transaction rule reminder: in room raid settlement transactions, read all attendee docs before applying any writes to avoid "all reads must occur before writes" transaction failures.


### Firestore data structure

#### `users/{uid}`
User profile and limits. Created/merged in `UserSessionStore.ensureUserProfile()` and by room actions when a user joins/leaves without a prior profile.
Fields:
- `displayName` (String): user’s in-app name. Updated when profile is saved or synced.
- `friendCode` (String): 12-digit friend code. Updated when profile is saved or synced.
- `stars` (Int): reputation/stars. Updated from profile settings.
- `honey` (Int): currency balance. Updated on join/leave/deposit changes and raid settlement.
- `maxHostRoom` (Int): limit of open rooms a user can host. Defaults to 1, synced on profile refresh.
- `maxJoinRoom` (Int): limit of open rooms a user can join. Defaults to 3, synced on profile refresh.
- `profileComplete` (Bool): computed from displayName + friendCode, synced on profile updates. profileComplete will be false at first, and after user field in displayName and friendCode and click on the create profile button. This variable will be set to true and never set back to false again.
- `fcmToken` (String, optional): device push token. Updated when token is received/refreshed. Each device/app install gets its own token and it can change over time.
- `createdAt` (Timestamp): set on first profile creation.
- `updatedAt` (Timestamp): last time the user data is updated. updated on any profile or balance change.

#### `rooms/{roomId}`
Mushroom rooms hosted by a player. We delete the room doc when the host closes it, so Firestore only stores active rooms.
Fields:
- `title` (String): room title. Set on create; updated on edit.
- `hostUid` (String): cached host uid used by backend push flows to avoid attendee host lookups.
- `hostFcmToken` (String, optional): cached host push token used by backend push flows before user lookup fallback.
- `location` (String): short location label. Set on create/update. Typically, consist of country, city
- `description` (String): description. Set on create/update.
- `fixedRaidCost` (Int): minimum honey deposit for joining. Set on create/update.
- `hostName` (String): host display name snapshot for quick browse rendering/search.
- `hostStars` (Int): host stars snapshot for quick browse rendering/search.
- `maxPlayers` (Int): max attendees (default 10). Set on create.
- `joinedCount` (Int): number of active attendees. Incremented on join, decremented on leave/kick/close. Host is counted as an attendee.
- `createdAt` (Timestamp): set on create.
- `updatedAt` (Timestamp): updated on any room or attendee change.
- `lastSuccessfulRaidAt` (Timestamp, optional): set when host finishes a raid.
- `raidConfirmationHistory` (Array<Map>, optional): host read-only confirmation history records sorted latest-first. Each record stores:
  - `id` (String): shared confirmation id for that cycle.
  - `requestedAt` (Timestamp): host request time.
  - `attendeeResults` (Array<Map>): non-host attendee snapshot list with:
    - `uid` (String)
    - `name` (String)
    - `status` (String): `Confirming` / `Joined` / `SeatFull` / `NoInvite`
- `expiresAt` (Timestamp, optional/future): not currently written by client; reserved.
Notes:
- Host identity and info are stored in `attendees/{uid}` with `status = Host` (the host is just an attendee).
- Legacy rooms may still include `targetColor`/`targetAttribute`/`targetSize`, but create/edit no longer writes or edits those fields.
- Host-room limit checks query `rooms.hostUid`.
- Join-room limit checks query attendee docs by `uid + active status` without per-room read fan-out.

#### `rooms/{roomId}/attendees/{uid}`
Attendee entries for a room. Written in join/leave/deposit flows.
Fields:
- `name` (String): attendee display name. Set on join.
- `uid` (String): attendee uid snapshot used by collection-group membership checks.
- `friendCode` (String): attendee friend code. Set on join.
- `fcmToken` (String, optional): attendee push token snapshot used by backend push flows before user lookup fallback.
- `stars` (Int): attendee stars. Set on join.
- `depositHoney` (Int): current deposit. Set on join; updated on deposit change and raid settlement.
- `joinGreetingMessage` (String): attendee greeting captured when joining. Required by join flow.
- `joinedAt` (Timestamp): set on join.
- `updatedAt` (Timestamp): updated on deposit changes and raid settlement.
- `status` (String): attendee state. Current values are `Host`, `AskingToJoin`, `Ready`, `WaitingConfirmation`.
- `pendingConfirmationRequests` (Map<String, Timestamp>, optional): pending confirmation queue keyed by confirmation id. Each key/value pair is one unprocessed confirmation request timestamp for joiner queue rendering and response.
- `lastSettlementOutcome` (String, optional): latest escrow settlement result (`JoinedSuccess`, `SeatFullNoFault`, `MissedInvitation`).
- `lastSettlementHoney` (Int, optional): latest settled honey amount moved from attendee escrow to host for that settlement.
- `attendeeRatedHost` (Bool, optional): whether attendee already rated host for the latest confirmation cycle. Reset to `false` when host sends a new confirmation request.
- `attendeeRatedHostStars` (Int, optional): attendee-selected star count (1...3) used for host star-received push copy.
- `hostRatedAttendee` (Bool, optional): whether host already rated attendee for the latest confirmation cycle. Reset to `false` when host sends a new confirmation request.
- `hostRatedAttendeeStars` (Int, optional): host-selected star count (1...3) used for attendee star-received push copy.
- `needsHostRating` (Bool, optional): set to `true` when attendee accepts confirmation (host receives honey) so host can rate attendee; set back to `false` after host submits stars.
