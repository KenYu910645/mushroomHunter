# Mushroom

## Related Files
- `mushroomHunter/Features/Mushroom/RoomBrowseView.swift`: mushroom room list UI and room entry points.
- `mushroomHunter/Features/Mushroom/RoomBrowseViewModel.swift`: browse state, filtering, join flow orchestration, and local fake Mushroom tutorial dataset seeding.
- `mushroomHunter/Features/Mushroom/RoomCreateEditView.swift`: host room create/edit UI and form validation.
- `mushroomHunter/Features/Mushroom/RoomView.swift`: room details UI, attendee actions, finish flow, invite share sheet, and first-entry room personal/host interactive tutorials.
- `mushroomHunter/Features/Mushroom/RoomView.swift`: includes room-specific invite sheet wrapper used by room view.
- `mushroomHunter/Features/Shared/InviteShareSheet.swift`: shared invite QR sheet component used by room and postcard screens.
- `mushroomHunter/Features/Mushroom/RoomViewModel.swift`: room details state, role/join gating logic, action orchestration, and fake room tutorial scene seeding.
- `mushroomHunter/Features/Mushroom/RoomDomainModels.swift`: room/attendee data models and status enums.
- `mushroomHunter/Features/Shared/TopActionBar.swift`: shared honey/search/create header used by browse screens (stars hidden on mushroom browse).
- `mushroomHunter/Features/EventInbox/EventInboxView.swift`: shared in-app notification inbox list opened from mushroom/postcard top-right bell actions.
- `mushroomHunter/Features/DailyReward/DailyRewardView.swift`: shared DailyReward month sheet opened from the Mushroom tab top-right calendar icon.
- `mushroomHunter/Features/DailyReward/DailyRewardToolbarActions.swift`: shared calendar + bell toolbar actions used by the Mushroom tab.
- `mushroomHunter/Features/Shared/SmartTextField.swift`: shared auto-select text field wrapper used by host/profile/profile-create forms.
- `mushroomHunter/Features/Shared/SmartTextEditor.swift`: shared auto-select text editor wrapper used by host description input.
- `mushroomHunter/Features/Shared/KeyboardDismissBridge.swift`: shared UIKit bridge that dismisses keyboard on outside taps without collapsing during scroll.
- `mushroomHunter/Features/Shared/MessageBox.swift`: shared custom confirmation/error dialog used across mushroom room screens.
- `mushroomHunter/Features/Shared/ColorfulTag.swift`: shared colorful tag + red action-dot UI primitives used by room/postcard status rows.
- `mushroomHunter/Services/Firebase/RoomBrowseRepo.swift`: Firestore reads for browsing open rooms.
- `mushroomHunter/Services/Firebase/ProfileListRepo.swift`: Firestore joined/hosted room summary reads used to pin user-owned rooms on browse top.
- `mushroomHunter/Services/Firebase/RoomFormRepo.swift`: Firestore writes for host room lifecycle (create/update/close).
- `mushroomHunter/Services/Firebase/RoomRepo.swift`: Firestore reads for a single room and attendee list.
- `mushroomHunter/Services/Firebase/RoomActionsRepo.swift`: Firestore transactions for join/leave/deposit/raid confirmation/rating.
- `mushroomHunter/Utilities/RoomInviteLink.swift`: deep link generation/parsing for `honeyhub://room/{roomId}`.
- `mushroomHunter/Utilities/CountryLocalization.swift`: shared locale-aware country + room-location display resolver used by mushroom/postcard labels.
- `mushroomHunter/Utilities/AppConfig.swift`: centralized owner-managed mushroom settings (attribute lists, fixed raid defaults, room limits, query limits).
- `mushroomHunter/Features/Mushroom/RoomCache.swift`: shared Mushroom payload cache utility + cross-feature cache dirty-bit store.
- `mushroomHunter/Utilities/FriendCode.swift`: shared friend-code sanitizing/formatting/validation utility used across profile, room, and postcard flows.
- `mushroomHunter/Features/EventInbox/EventInboxStore.swift`: shared Firestore-backed notification event history pagination, Action/Record state handling, and deep-link route metadata.
- `functions/index.js`: server-side push triggers used by mushroom confirmation flows.

## Feature Coverage
### 1) Navigation and Entry
- Mushroom tab icon uses SF Symbol `person.3.fill`.
- Browse header uses shared top action bar (`honey/search/create`) and scrolls with content (`ScrollView + LazyVStack`).
- Browse has top-right calendar to open the shared DailyReward sheet.
- Browse has top-right bell to open shared notification inbox.
- Push/deep-link routing opens Mushroom tab and pushes the standard room detail page (not a sheet).
- First time entering Mushroom browse runs tutorial mode on the real browse page (same layout/styles as production), seeds local fake listings, blocks interactions with highlight steps, then loads real Firebase listings after completion.
- First time entering room detail in personal/host view runs in-place tutorial mode on the real room page, loads fake room scene from `TutorialConfig`, blocks interactions, then restores real Firebase room payload after completion.

### 2) Browse and Search
- Search UI is inline (not sheet/alert), with toggle, clear `x`, keyboard `Search`, and hide-to-clear behavior.
- Local filtering matches room `title` and `location` (stored + localized country label).
- Backend room fetch refreshes only on explicit `Search`, pull-to-refresh, or forced refresh.
- Browse tab re-entry and pull-to-refresh now use the same canonical full-refresh flow.
- Explicit browse refresh is server-authoritative for both the main open-room list and pinned hosted/joined rows; cache is only used as an empty-state bootstrap before that refresh runs.
- The Mushroom browse pull-to-refresh closure now hands the actual reload to an app-owned async task so SwiftUI `.refreshable` cancellation cannot abort the backend refresh mid-gesture.
- Each browse room row uses the full visible row area as the navigation hit target instead of limiting taps to text/icon subviews.
- Browse priority score:
- Reward: `hostStars * AppConfig.Mushroom.browsePriorityHostStarWeight`.
- Penalty: `dormantHoursBeyondThreshold * AppConfig.Mushroom.browsePriorityDormantHourPenalty`.
- Dormancy reference: `lastSuccessfulRaidAt` fallback to `createdAt`; no penalty before threshold hours.
- User-owned rooms are always pinned and tagged in this order: `Host` -> `Joined` -> other rooms.
- Pinned rows are deduplicated from general rows and still obey current search/availability filters.
- Browse attendee count always renders SF Symbol `person.fill` with localized numeric count text (`%d/%d`) so locale translation does not replace the icon.

### 3) Host Room Form (Create/Edit)
- Host form manages room `title`, `location`, and `description` only (no target mushroom selectors and no host-editable honey reward control).
- Description defaults to localized `host_default_description` when empty.
- Raid rewards are owner-tuned globally in `AppConfig.Mushroom.joinedSuccessRewardHoney` and `AppConfig.Mushroom.seatFullRewardHoney`.
- The minimum attendee deposit is controlled globally by `AppConfig.Mushroom.minimumRequiredDepositHoney`.
- Form supports outside-tap/keyboard dismiss and focused input auto-scroll above keyboard overlap.
- Closing create sheet (manual close or success) triggers forced browse refresh.
- Location parsing supports current-locale country names, English names, and ISO codes.
- Location display localizes country while preserving city text.
- Host room-limit error message uses localized format text with injected max-room count.

### 4) Membership and Room Actions
- Join requires deposit + greeting message (required, max 100 chars); join sheet pre-fills localized default greeting.
- When the available deposit is fixed to a single valid value (for example user honey is exactly the minimum required 10), Room Details hides the slider and keeps that fixed amount instead of constructing a zero-width slider range.
- Join confirmation dialog includes `Sure` + `Cancel`, and uses generic wording (no room title).
- Join request creates attendee with `AskingToJoin` and immediately occupies a seat.
- Host approves/rejects join requests from inline buttons under join greeting (`Accept` left, `Reject` right).
- Host uses attendee `...` menu for non-request actions (for example `Kick`).
- Reject refunds full attendee deposit and removes attendee row.
- Kick refunds the kicked attendee's full deposited honey, removes the attendee row, and writes host/attendee record events into both inboxes.
- Host actions include `Kick`, `Close room`, and raid finish cycle.
- Leave flow UI shows hint that unspent deposit is returned.

### 5) Raid Confirmation and History
- Host `Mushroom Raid Done` sends settlement requests to all eligible non-host attendees, including attendees with unresolved requests.
- Joiner has confirmation queue icon with red dot when pending requests exist.
- Queue shows all unprocessed confirmations newest-first.
- Queue row content is compact: host invitation text + localized relative elapsed time (`0m ago` / `0分鐘前`).
- Each queue row supports 3 settlement actions:
- `Yes, I joined the mushroom`
- `Yes, but the mushroom is full`
- `No, I didn't see invitation`
- Host can resend by running `Mushroom Raid Done` again for the same attendee(s); each resend appends a new pending confirmation request and sends a fresh attendee action push/event even if the attendee is already in `WaitingConfirmation`.
- Host has read-only raid history page (`list.clipboard`) showing latest-first confirmation records.
- Host raid-history clipboard now also includes a `Pending Ratings` section for unresolved host -> attendee rating tasks.
- Pending rating rows use localized copy and the same star-icon labels (`⭐`, `⭐⭐`, `⭐⭐⭐`) previously used by room message boxes.
- Host history attendee status pills: `Confirming` (yellow), `Joined` (green), `Seat full` (yellow), `No invite` (red).
- Tapping raid-confirmation push opens room and auto-presents confirmation queue.
- Room opened from push forces first-load server refresh for latest confirmation state.
- Attendee confirmation clipboard now also includes a `Pending Ratings` section for unresolved attendee -> host rating tasks.

### 6) Room Detail UI
- Room header focuses on title, attendee count, location, and description (no last-raid line in header).
- Room header attendee count always renders SF Symbol `person.fill` with localized numeric count text (`%d/%d`) across all languages.
- Top-right action order:
- Host: `Share -> Raid History -> Edit`.
- Joined attendee: `Confirmation Queue -> Edit Deposit`.
- Host clipboard icon shows a red dot when host-side room rating tasks are pending.
- Attendee clipboard icon shows a red dot when either confirmation responses or attendee-side room rating tasks are pending.
- Role-seeded toolbar supports early host/attendee action slot rendering before room payload finishes loading.
- Action buttons that depend on room payload stay disabled until detail data is ready.
- Host-visible `AskingToJoin` attendee name includes small red dot marker.
- Attendee status tags use shared colorful mapping: `Host` blue, `Asking/Waiting` yellow, `Ready` green, `Not Enough Honey` red.
- Star and deposit badges use rounded visual styles (yellow star badge, orange honey badge).
- Room detail attendee area now uses stacked per-attendee cards (no standalone attendee-title block), and this same card structure is reused by tutorial mode.
- Room detail no longer renders a standalone `成員清單`/attendee-list title row; each attendee card is rendered as a peer section under room header.
- Detail page hides navigation title so content starts directly with room snapshot.

### 7) Notification Inbox Behavior
- Inbox fetches `users/{uid}/events` newest-first, first page size 10, and paginates on scroll.
- Rows separate Action vs Record semantics:
- Action rows: unresolved-and-unread rows show red dot + bold text, tapping the row marks it as read and removes the emphasis even before the action is fully resolved.
- Record rows: normal text, no route action.
- Room-related action routing:
- Raid confirmation route opens room + queue.
- Other room events open room detail.

### 8) Shared UI and Invite Tools
- Host room detail includes invite tools: QR sheet and share/copy deep link `honeyhub://room/{roomId}`.
- Copy toast style/timing matches postcard behavior.
- Shared `MessageBox` supports inline `{honey_icon}` token rendering with natural text wrapping.
- Shared `MessageBox` centers its message text content.
- Inline message-box honey icon size is configurable via `AppConfig.SharedUI.honeyMessageIconSize`.
- Host minimum-payment row also token-renders `{honey_icon}` as inline icon.

### 9) UI-Test Support
- `--ui-testing --mock-rooms` routes host submit via mock success without Firestore writes.
- `--ui-open-room {roomId}` supports deterministic room deep-link entry.
- `--mock-room-joined` forces fixture joined-attendee state.
- Mock-mode leave can bypass confirmation dialogs to reduce UI-test flakiness.
- Mock-mode role/deposit checks use fixture uid (`ui-test-user`) if auth uid is not ready.

### 10) Cache and Refresh
- Cache behavior and invalidation rules are defined only in `CACHE.md`.
- Mushroom browse/detail now checks dirty bits before reusing cache; dirty state forces backend refresh and is cleared only after successful fetch.

### Confirmation stars flow
- Attendee settlement flow now has three outcomes after host taps `Mushroom Raid Done`:
  - `Yes, joined success`: host gets the global joined-success reward (`AppConfig.Mushroom.joinedSuccessRewardHoney`, default `10`), attendee deposit deducts that amount, attendee can rate host.
  - `No, seat full (no-fault race)`: host gets the global seat-full reward (`AppConfig.Mushroom.seatFullRewardHoney`, default `2`), attendee deposit deducts only that amount.
  - `No, I didn't see invitation`: no honey transfer, treated as host-not-invited outcome.
- Host create/edit no longer exposes any raid-cost or honey-reward control; mushroom reward policy is owner-tuned only in `AppConfig.swift`.
- Popup rating message boxes are removed from mushroom room flows.
- Every resolved confirmation now creates two room rating tasks while the room remains open:
  - attendee -> host
  - host -> attendee
- Both tasks live in the existing clipboard surfaces and remain available regardless of later attendee status changes.
- Host rates attendees from the host `Raid History` clipboard sheet.
- Attendee rates host from the attendee `Confirmation Queue` clipboard sheet.
- `Skip` permanently closes that specific room rating task.
- Closing the room marks unresolved room rating tasks as closed and removes any remaining rating opportunity.
- After a confirmation settles and the attendee no longer has any pending confirmation requests, attendee `status` becomes `NotEnoughHoney` when remaining `depositHoney` is below `AppConfig.Mushroom.minimumRequiredDepositHoney`; otherwise it returns to `Ready`.
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
- `isProfileComplete` (Bool): computed from displayName + friendCode, synced on profile updates. `false` for first-time users, then set to `true` after successful profile creation and not reverted to `false`.
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
- `fixedRaidCost` (Int): legacy compatibility field written as the global joined-success reward on create/update. Active runtime validation and settlement now use `AppConfig.Mushroom.minimumRequiredDepositHoney`, `joinedSuccessRewardHoney`, and `seatFullRewardHoney` instead of trusting stored room values.
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
- Browse no longer searches host display name from room docs.
- Browse host-star priority is resolved from `users/{hostUid}.stars` (room-level `hostStars` is treated as legacy fallback only).
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
- `status` (String): attendee state. Current values are `Host`, `AskingToJoin`, `Ready`, `NotEnoughHoney`, `WaitingConfirmation`.
- `pendingConfirmationRequests` (Map<String, Timestamp>, optional): pending confirmation queue keyed by confirmation id. Each key/value pair is one unprocessed confirmation request timestamp for joiner queue rendering and response.
- `lastSettlementOutcome` (String, optional): latest escrow settlement result (`JoinedSuccess`, `SeatFullNoFault`, `MissedInvitation`).
- `lastSettlementHoney` (Int, optional): latest settled honey amount moved from attendee escrow to host for that settlement.
- `isAttendeeRatedHost` (Bool, optional): whether attendee already rated host for the latest confirmation cycle. Reset to `false` when host sends a new confirmation request.
- `attendeeRatedHostStars` (Int, optional): attendee-selected star count (1...3) used for host star-received push copy.
- `isHostRatedAttendee` (Bool, optional): whether host already rated attendee for the latest confirmation cycle. Reset to `false` when host sends a new confirmation request.
- `hostRatedAttendeeStars` (Int, optional): host-selected star count (1...3) used for attendee star-received push copy.
- `isHostRatingRequired` (Bool, optional): set to `true` when attendee accepts confirmation (host receives honey) so host can rate attendee; set back to `false` after host submits stars.

Compatibility notes:
- Legacy attendee docs may still contain `attendeeRatedHost`, `hostRatedAttendee`, and `needsHostRating`.
- Legacy user docs may still contain `profileComplete`.

#### `roomRatingTasks/{taskId}`
Durable room rating tasks that power the host/attendee clipboard surfaces while the room remains open.
Fields:
- `roomId` (String): parent room id.
- `roomTitle` (String): room title snapshot for clipboard display fallback.
- `confirmationId` (String): confirmation cycle that created the task.
- `requestedAt` (Timestamp): source confirmation timestamp used for newest-first ordering.
- `raterUid` (String): uid who can act on the task.
- `rateeUid` (String): uid who will receive stars.
- `counterpartName` (String): display name shown in the clipboard row.
- `direction` (String): `AttendeeToHost` or `HostToAttendee`.
- `settlementOutcome` (String): `JoinedSuccess`, `SeatFullNoFault`, or `MissedInvitation`.
- `status` (String): `Pending`, `Rated`, `Skipped`, or `Closed`.
- `stars` (Int, optional): submitted star value when `status == Rated`.
- `resolvedAt` (Timestamp, optional): when the task was rated, skipped, or closed.
- `updatedAt` (Timestamp): latest task mutation time.

#### `rooms/{roomId}/kickEvents/{kickEventId}`
Server-side kick marker documents written only by host kick transactions so backend event production can distinguish kick from leave or room close.
Fields:
- `hostUid` (String): host who kicked the attendee.
- `attendeeUid` (String): removed attendee uid.
- `attendeeName` (String): attendee display-name snapshot for inbox copy.
- `roomId` (String): kicked room id snapshot.
- `roomTitle` (String): room title snapshot for inbox copy.
- `refundedHoney` (Int): full deposit honey returned to the attendee.
- `createdAt` (Timestamp): kick marker creation time.
