# Mushroom

## Related Files
- `mushroomHunter/Features/Mushroom/RoomBrowseView.swift`: mushroom room list UI and room entry points.
- `mushroomHunter/Features/Mushroom/RoomBrowseViewModel.swift`: browse state, filtering, and join flow orchestration.
- `mushroomHunter/Features/Mushroom/RoomFormView.swift`: host room create/edit UI and form validation.
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
- `mushroomHunter/User/NotificationInboxStore.swift`: shared Firestore-backed notification event history pagination, unread state, and deep-link route metadata.
- `functions/index.js`: server-side push triggers used by mushroom confirmation flows.

## Feature Coverage
- Main Mushroom tab icon uses SF Symbol `person.3.fill` to reflect group room coordination.
- Host can create and manage a room with title/location/description/fixed raid cost (no target mushroom selectors in create/edit UI).
- Browse search is opened from the top action bar as an inline search field above the room list (no dedicated sheet/alert).
- Mushroom browse includes a screen-level top-right bell icon that opens the shared notification inbox list.
- Notification inbox loads the latest 10 events first from `users/{uid}/events` and loads older pages while scrolling.
- Notification inbox rows show unread state with red dot + bold title/message text, and become read when tapped (or via `Read All` action).
- Tapping a room-related inbox row routes using existing push deep-link channels:
  - raid confirmation notifications open room and auto-present confirmation queue.
  - other room notifications open room detail.
- Mushroom browse search matches room title and location text (country/city).
- Mushroom browse search applies local filtering while typing; backend fetch (first page) is refreshed only when user taps `Search`.
- Mushroom browse now pins user-owned rooms above general browse results at all times:
  - `Joined` rooms are rendered at the top with a `Joined` ownership tag.
  - `Host` rooms are rendered at the top with a `Host` ownership tag.
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
- Room attendee list statuses now use the same rounded-rectangle urgency badge style as Profile status labels (`Host` blue, `Asking/Waiting` orange, `Rejected` red, `Ready` green).
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
  - Writes host-side notification history event (`room_created`) for mushroom-room creation.
- `recordHostRaidInviteEvent`
  - Trigger: update on `rooms/{roomId}` when `raidConfirmationHistory` receives a new head record.
  - Writes host-side notification history event (`raid_invited`) for each raid invitation cycle.
- `notifyHostJoinRequest`
  - Trigger: create on `rooms/{roomId}/attendees/{attendeeUid}` with `status = AskingToJoin`
  - Push target: host (`rooms/{roomId}.hostFcmToken` first, with `users/{hostUid}.fcmToken` fallback)
  - Payload data: `type=room_join_request`, `roomId`, `room_id`, `attendeeUid`, `eventId`
  - Also writes join-request history events for both joiner and host.
- `notifyJoinApplicantAccepted`
  - Trigger: attendee `status` transitions `AskingToJoin -> Ready`
  - Push target: join applicant (`rooms/{roomId}/attendees/{attendeeUid}.fcmToken` first, with `users/{attendeeUid}.fcmToken` fallback)
  - Payload data: `type=room_join_request_accepted`, `roomId`, `room_id`, `eventId`
  - Also writes acceptance history events for both joiner and host.
- `notifyJoinApplicantRejected`
  - Trigger: delete on `rooms/{roomId}/attendees/{attendeeUid}` where previous `status = AskingToJoin`
  - Push target: join applicant (`rooms/{roomId}/attendees/{attendeeUid}.fcmToken` snapshot first, with `users/{attendeeUid}.fcmToken` fallback)
  - Payload data: `type=room_join_request_rejected`, `roomId`, `room_id`, `eventId`
  - Also writes rejection history events for both joiner and host.
- `sendRaidConfirmationPush`
  - Trigger: update on `rooms/{roomId}/attendees/{attendeeUid}`
  - Sends only when attendee status transitions into `WaitingConfirmation`
  - Push target: `rooms/{roomId}/attendees/{attendeeUid}.fcmToken` first, with `users/{attendeeUid}.fcmToken` fallback
  - Payload data: `type=raid_confirmation`, `roomId`, `room_id`, `eventId`
  - Also writes attendee-side history event (`raid_confirmation`).
- `notifyHostRaidConfirmationResult`
  - Trigger: update on `rooms/{roomId}/attendees/{attendeeUid}`
  - Sends only when status transitions from `WaitingConfirmation` to `Ready` or `Rejected`
  - Host resolved from cached `rooms/{roomId}.hostUid` first, with attendee query fallback where `status=Host`
  - Push target: `rooms/{roomId}.hostFcmToken` first, with `users/{hostUid}.fcmToken` fallback
  - Payload data:
    - joined success: `type=raid_confirmation_accepted`
    - seat full no-fault: `type=raid_confirmation_seat_full`
    - missed invitation: `type=raid_confirmation_missed_invite`
    - rejected: `type=raid_confirmation_rejected`
  - Also writes history events for both host and attendee.
- `notifyMushroomStarReceived`
  - Trigger: update on `rooms/{roomId}/attendees/{attendeeUid}`
  - Sends when rating flags transition:
    - `attendeeRatedHost: false -> true` (host receives stars)
    - `hostRatedAttendee: false -> true` (attendee receives stars)
  - Payload data: `type=room_star_received`, `roomId`, `room_id`, `fromUid`, `toUid`, `stars`
  - Also writes history events for both giver (`room_star_given`) and receiver (`room_star_received`).
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
- `status` (String): attendee state. Current values are `Host`, `AskingToJoin`, `Ready`, `WaitingConfirmation`, `Rejected`.
- `pendingConfirmationRequests` (Map<String, Timestamp>, optional): pending confirmation queue keyed by confirmation id. Each key/value pair is one unprocessed confirmation request timestamp for joiner queue rendering and response.
- `lastSettlementOutcome` (String, optional): latest escrow settlement result (`JoinedSuccess`, `SeatFullNoFault`, `MissedInvitation`).
- `lastSettlementHoney` (Int, optional): latest settled honey amount moved from attendee escrow to host for that settlement.
- `attendeeRatedHost` (Bool, optional): whether attendee already rated host for the latest confirmation cycle. Reset to `false` when host sends a new confirmation request.
- `attendeeRatedHostStars` (Int, optional): attendee-selected star count (1...3) used for host star-received push copy.
- `hostRatedAttendee` (Bool, optional): whether host already rated attendee for the latest confirmation cycle. Reset to `false` when host sends a new confirmation request.
- `hostRatedAttendeeStars` (Int, optional): host-selected star count (1...3) used for attendee star-received push copy.
- `needsHostRating` (Bool, optional): set to `true` when attendee accepts confirmation (host receives honey) so host can rate attendee; set back to `false` after host submits stars.




# HoneyHub Raid Confirmation Flow Guide

This document explains the current confirmation flow between host and attendees in HoneyHub.

## Scope
This guide focuses on:
- Room join/deposit lifecycle
- Host raid confirmation request flow
- Attendee accept/reject flow
- Push notification triggers and routing
- Reputation (stars) flow after confirmation

## Source Of Truth
Main implementation files:
- `/Users/ken/Desktop/mushroomHunter/mushroomHunter/Services/Firebase/RoomActionsRepo.swift`
- `/Users/ken/Desktop/mushroomHunter/mushroomHunter/Features/Mushroom/RoomViewModel.swift`
- `/Users/ken/Desktop/mushroomHunter/mushroomHunter/Features/Mushroom/RoomView.swift`
- `/Users/ken/Desktop/mushroomHunter/functions/index.js`
- `/Users/ken/Desktop/mushroomHunter/mushroomHunter/User/UserSessionStore.swift`
- `/Users/ken/Desktop/mushroomHunter/mushroomHunter/User/UserAuth.swift`
- `/Users/ken/Desktop/mushroomHunter/mushroomHunter/User/UserProfile.swift`
- `/Users/ken/Desktop/mushroomHunter/mushroomHunter/User/UserWallet.swift`
- `/Users/ken/Desktop/mushroomHunter/mushroomHunter/App/HoneyHubApp.swift`
- `/Users/ken/Desktop/mushroomHunter/mushroomHunter/App/ContentView.swift`

## State Model
Attendee status values (`rooms/{roomId}/attendees/{uid}.status`):
- `Host`: room owner row in attendees subcollection
- `AskingToJoin`: join application pending host moderation
- `Ready`: normal active state (joined, not waiting)
- `WaitingConfirmation`: attendee has at least one unprocessed confirmation request in queue
- `Rejected`: attendee rejected host claim

Rating flags on attendee document:
- `attendeeRatedHost` (Bool): attendee already rated host in current confirmation cycle
- `hostRatedAttendee` (Bool): host already rated attendee in current confirmation cycle
- `needsHostRating` (Bool): set `true` only after attendee accepts confirmation

## End-To-End Flowchart
```mermaid
flowchart TD
    A[Attendee joins with deposit + greeting] --> B[attendee.status = AskingToJoin]
    B --> C[Host approves or rejects application]
    C -->|Approve| D[attendee.status = Ready]
    C -->|Reject| E[attendee removed + full deposit refund]
    D --> F[Host taps Mushroom Raid Done]
    F --> G[Eligible attendees append pending request and remain/become WaitingConfirmation]
    G --> H[Cloud Function: sendRaidConfirmationPush]
    H --> I[Attendee submits escrow settlement]
    I -->|JoinedSuccess| J[host +fixedRaidCost; attendee deposit -fixedRaidCost; needsHostRating=true]
    I -->|SeatFullNoFault| K[host +effortFee; attendee deposit -effortFee]
    I -->|MissedInvitation| L[no honey transfer; attendee -> Ready]
```

## Detailed Lifecycle
### 1. Join Room And Deposit Lock
When attendee joins:
- Check max joined-room limit (`users.maxJoinRoom`)
- Check room capacity (`joinedCount < maxPlayers`)
- Require `initialDepositHoney >= fixedRaidCost`
- Deduct deposit from `users/{uid}.honey`
- Create attendee row with:
  - `status = AskingToJoin`
  - `depositHoney = initialDepositHoney`
  - `joinGreetingMessage = joiner input`
- Increment `rooms.joinedCount`

Host moderation:
- Host can approve application from inline `Accept` button (shown under joiner message):
  - `status = Ready`
- Host can reject application from inline `Reject` button (shown under joiner message):
  - attendee row removed
  - `rooms.joinedCount - 1`
  - full deposit refunded to joiner wallet

Important behavior:
- Deposit is locked while attendee remains in room
- Leaving or being kicked refunds remaining deposit

### 2. Host Starts Confirmation Cycle
Host opens Room Details and uses `Mushroom Raid Done`:
- Client auto-targets all eligible non-host attendees in room (`depositHoney >= fixedRaidCost`, excluding `AskingToJoin`)
- Client also sends all non-host attendee ids so backend can create a full-room history snapshot.
- `finishRaid(...)` updates each targeted attendee:
  - append one entry into `pendingConfirmationRequests` using one shared confirmation id for this cycle
  - `status = WaitingConfirmation`
  - `attendeeRatedHost = false`
  - `hostRatedAttendee = false`
  - `needsHostRating = false`
- Room updates:
  - `lastSuccessfulRaidAt = now`
  - prepend one `raidConfirmationHistory` entry:
    - invited attendees start as `Confirming`
    - non-invited attendees in that room snapshot are marked `NoInvite`
  - `updatedAt = now`

### 3. Push To Attendee (Request)
Cloud Function `sendRaidConfirmationPush` triggers on attendee doc update:
- Sends push only when status transitions into `WaitingConfirmation`
- Target token: `rooms/{roomId}/attendees/{attendeeUid}.fcmToken` (fallback `users/{attendeeUid}.fcmToken`)
- Payload data includes: `type=raid_confirmation`, `roomId`, `room_id`

### 4. Attendee Escrow Settlement
When current attendee has pending confirmations, Room Details exposes a top-right confirmation queue icon. Tapping it opens the attendee confirmation queue page for that room.

If attendee chooses `JoinedSuccess`:
- Transaction moves honey:
  - Host user honey `+ fixedRaidCost`
  - Attendee `depositHoney - fixedRaidCost`
- Attendee status set:
  - remove selected confirmation id from `pendingConfirmationRequests`
  - `status = WaitingConfirmation` if queue still has pending entries, otherwise `Ready`
  - `needsHostRating = true`
- Room history update:
  - matching `raidConfirmationHistory[id == confirmationId].attendeeResults[uid == attendeeUid].status = Joined`

If attendee chooses `SeatFullNoFault`:
- Transaction moves small effort fee:
  - Host user honey `+ noFaultEffortFee`
  - Attendee `depositHoney - noFaultEffortFee`
- Attendee status set:
  - remove selected confirmation id from `pendingConfirmationRequests`
  - `status = WaitingConfirmation` if queue still has pending entries, otherwise `Ready`
  - `needsHostRating = false`
- Room history update:
  - matching `raidConfirmationHistory[id == confirmationId].attendeeResults[uid == attendeeUid].status = SeatFull`

If attendee chooses `MissedInvitation`:
- No honey transfer
- Attendee status set:
  - remove selected confirmation id from `pendingConfirmationRequests`
  - `status = WaitingConfirmation` if queue still has pending entries, otherwise `Ready`
  - `needsHostRating = false`
- Room history update:
  - matching `raidConfirmationHistory[id == confirmationId].attendeeResults[uid == attendeeUid].status = NoInvite`

### 5. Push To Host (Result)
Cloud Function `notifyHostRaidConfirmationResult` triggers when status transitions:
- `WaitingConfirmation -> Ready` with `JoinedSuccess`: send full-payment accepted message.
- `WaitingConfirmation -> Ready` with `SeatFullNoFault`: send no-fault seat-full effort-fee message.
- `WaitingConfirmation -> Ready` with `MissedInvitation`: send missed-invitation (no honey moved) message.
- Host is resolved by attendee row where `status = Host`
- Host token from `rooms/{roomId}.hostFcmToken` (fallback `users/{hostUid}.fcmToken`)

### 6. Resolve Rejected Case
Host sees rejected state in attendee row and can tap `Resolve`:
- `resolveRejectedConfirmation(...)` sets:
  - `status = Ready`
  - `needsHostRating = false`
- This does not transfer honey

### 7. Reputation (Stars) Flow
Attendee rates host:
- Allowed only when attendee status is `Ready`
- Blocked if `attendeeRatedHost == true`
- On success:
  - `users/{hostUid}.stars += 1..3`
  - Host attendee row stars updated in-room
  - `attendeeRatedHost = true`
  - `attendeeRatedHostStars = 1..3`

Host rates attendee:
- Allowed only if caller is host and attendee:
  - `status == Ready`
  - `needsHostRating == true`
  - `hostRatedAttendee == false`
- On success:
  - `users/{attendeeUid}.stars += 1..3`
  - attendee row `stars` updated in-room
  - `hostRatedAttendee = true`
  - `hostRatedAttendeeStars = 1..3`
  - `needsHostRating = false`

## Push Routing In App
Push/deeplink routing path:
1. iOS receives push (`roomId` or `room_id` in payload)
2. App posts `Notification.Name.didOpenRoomFromPush`
3. `ContentView` opens a `NavigationStack` sheet containing `RoomView` for that room (so room toolbar actions are available for host/attendee roles)
4. `RoomViewModel.load()` fetches attendee statuses and recomputes pending states

## Data Mutation Map (Quick Reference)
- `joinRoom(...)`
  - attendee: create `AskingToJoin` + deposit + greeting
  - user: minus deposit honey
  - room: `joinedCount +1`
- `finishRaid(...)`
  - all eligible non-host attendees: append pending request in `pendingConfirmationRequests`, set/keep `WaitingConfirmation`, reset rating flags
  - room: `lastSuccessfulRaidAt`, prepend one `raidConfirmationHistory` record
- `respondToRaidConfirmation(JoinedSuccess)`
  - host user: plus raid cost honey
  - attendee row: minus deposit, `Ready`, `needsHostRating=true`
  - room history attendee result: `Joined`
- `respondToRaidConfirmation(SeatFullNoFault)`
  - host user: plus no-fault effort fee honey
  - attendee row: minus effort fee, `Ready`, `needsHostRating=false`
  - room history attendee result: `SeatFull`
- `respondToRaidConfirmation(MissedInvitation)`
  - no honey movement
  - attendee row: `Ready`, `needsHostRating=false`
  - room history attendee result: `NoInvite`
- `resolveRejectedConfirmation(...)`
  - attendee row: `Ready`
- `rateHostAfterConfirmation(...)`
  - host user stars increment
  - host attendee row stars refresh
  - attendee row `attendeeRatedHost=true`, `attendeeRatedHostStars=1..3`
- `rateAttendeeAfterConfirmation(...)`
  - attendee user stars increment
  - attendee row stars refresh
  - attendee row `hostRatedAttendee=true`, `hostRatedAttendeeStars=1..3`, `needsHostRating=false`

## Why This Feels Complex
Current complexity comes from a mixed set of responsibilities in one room flow:
- Financial escrow (`depositHoney`, `users.honey`)
- Attendance lifecycle (`AskingToJoin/Ready/WaitingConfirmation/Rejected`)
- Asynchronous signaling (push in both directions)
- Two-sided reputation flow with separate one-time flags

This is logically correct, but requires many state flags to avoid duplicate transfers/ratings.

## Suggested Mental Model For Team Members
Use these two layers when debugging:
1. Payment/confirmation layer:
- `status` + `depositHoney` + host `users.honey`
2. Reputation layer:
- `attendeeRatedHost` + `hostRatedAttendee` + `needsHostRating`

If a bug appears, first identify which layer is failing, then inspect only that layer's flags and writes.
