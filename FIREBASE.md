# Firebase

## Firebase Effeiciency

This document explains how HoneyHub interacts with Firebase, and what UI actions trigger Firestore/Storage/Functions read-write activity.

## Current Firestore Database Rule
```js
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

## Current Firebase Storage Rule
```js
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read, write: if true;
    }
  }
}
```

## Stack Overview
- Authentication: Firebase Auth (Apple/Google)
- Database: Cloud Firestore
- File Storage: Firebase Storage (postcard images)
- Server events: Firebase Cloud Functions (push/email)

## Cost Model Quick Reminder
- Firestore cost is mainly from:
  - document reads
  - document writes
  - document deletes
- Storage cost is mainly from:
  - stored GB-month
  - download/egress bandwidth
  - upload/download operations
- Cloud Functions cost is from:
  - invocation count
  - compute/runtime
  - network and dependent service calls

## Core Data Collections
- `users/{uid}`: profile, wallet, limits, push token
- `users/{uid}/events/{eventId}`: per-user event history (Action/Record state via `isActionEvent`/`isResolved`, route metadata, newest-first paging)
- `rooms/{roomId}`: mushroom room header data
- `rooms/{roomId}/attendees/{uid}`: room membership and state
- `postcards/{postcardId}`: postcard listing data
- `postcardOrders/{orderId}`: postcard order lifecycle
- `feedbackSubmissions/{feedbackId}`: feedback payloads
- Storage path `postcards/{ownerId}/{filename}.jpg`: full and thumbnail postcard images

## UI Operation -> Firebase R/W

### App Launch, Sign-in, Session
- Open app while signed in:
  - Firestore read: `users/{uid}` to refresh local session/profile/wallet.
- Receive/refresh FCM token:
  - Firestore write: `users/{uid}.fcmToken` (guarded; skip write if unchanged in-session).
  - Firestore writes: hosted room snapshots (`rooms.hostFcmToken`, host attendee `fcmToken`) to reduce later function reads.
- Sign in (Apple/Google):
  - Auth operation only, then profile sync may write `users/{uid}` defaults.

### Profile Tab
- Open profile tab:
  - Uses app-level cache first for hosted/joined/on-shelf/ordered lists.
  - Firestore queries run when cache is missing or when user pull-to-refreshes.
- Profile/app-icon actionable badge refresh:
  - Joined rooms query for attendee statuses (`collectionGroup(attendees)` by `uid`).
  - Hosted rooms query (`rooms where hostUid == uid`), then per-room attendee query:
    - `rooms/{roomId}/attendees where status == AskingToJoin` (count pending join applications).
  - Seller pending-order query:
    - `postcardOrders where sellerId == uid and status in [SellerConfirmPending, AwaitingShipping, AwaitingSellerSend]`.
  - Buyer pending-receive query:
    - `postcardOrders where buyerId == uid and status in [Shipped, InTransit, AwaitingBuyerDecision]`.
- On-shelf postcard status badges:
  - Firestore query: `postcardOrders where sellerId == uid and status in [SellerConfirmPending, AwaitingShipping, AwaitingSellerSend]` to flag listings with unprocessed seller queue items as `Order Received`.
- Hosted rooms list:
  - Primary query: `rooms where hostUid == uid`.
  - Legacy fallback query only when needed.
- Joined rooms list:
  - Primary query: `collectionGroup(attendees) where uid == current uid` + status filters.
  - Legacy fallback only when primary docs are insufficient.
- Save profile (name/friend code):
  - Firestore write: `users/{uid}` (guarded by changed fields).
  - Firestore batch writes: host attendee snapshot fields across active hosted rooms.
  - Cloud Function write: `users/{uid}/events/{eventId}` for display-name/friend-code update history.

### Notification Inbox (Bell)
- Open inbox from Mushroom/Postcard top-right bell:
  - Firestore query read: first page `users/{uid}/events order by createdAt desc limit 10`.
- Scroll near list bottom:
  - Firestore paged query read using cursor (`startAfter`) for older history.
- Tap one event row:
  - Action event row opens action route; resolution is handled by business-flow updates.
  - Record event row does not route.
- Inbox has no `Read All` action.
- Event text storage:
  - Cloud Functions write localized snapshot `title` + `message` into each event doc at creation time.
  - iOS inbox reads stored `title`/`message` first, with `event_type_*` fallback for legacy rows.

### Mushroom Tab

#### Browse rooms
- Enter Mushroom browse:
  - Uses app-level cache first for browse list.
  - Firestore query runs when cache is missing.
- Pull-to-refresh:
  - Firestore query read on `rooms` list, then cache overwrite.
- Search submit:
  - Forces Firestore query read on `rooms` list before applying local text filter.

#### Open room detail
- Tap a room:
  - Uses app-level cache first for room header + attendee list.
  - Firestore reads run when cache is missing.
- Pull-to-refresh:
  - Firestore read: `rooms/{roomId}`
  - Firestore query read: `rooms/{roomId}/attendees`

#### Join room
- Tap Join:
  - Firestore read: `users/{uid}` for limit and wallet info.
  - Firestore query read: active joined-room count via `collectionGroup(attendees)`.
  - Legacy fallback query only when required.
  - Firestore transaction writes:
    - create attendee doc
      - initial `status: AskingToJoin`
      - `joinGreetingMessage`
    - decrement user honey
    - increment room joinedCount
  - Cloud Function write: `users/{uid}/events/{eventId}` for honey balance delta history.

#### Host approve/reject join application
- Host opens room attendee row menu (`...`) for pending applicant (`AskingToJoin`):
  - Accept:
    - Firestore transaction writes attendee `status: Ready`.
  - Reject:
    - Firestore transaction deletes attendee doc.
    - Decrements `rooms.joinedCount`.
    - Refunds full attendee deposit to `users/{attendeeUid}.honey`.

#### Update deposit
- Tap update deposit:
  - Firestore transaction reads attendee+room+user docs
  - Firestore transaction writes attendee deposit and user honey delta
  - Cloud Function write: `users/{uid}/events/{eventId}` for honey balance delta history.

#### Leave room / Kick attendee / Close room
- Host or attendee action:
  - Firestore transaction reads required docs
  - Firestore writes attendee/room/user fields and status transitions
  - Room close removes room + attendees (delete operations)
  - Cloud Function write: `users/{uid}/events/{eventId}` for honey balance delta history when applicable.

#### Finish raid / confirmation flows
- Host taps raid done:
  - Firestore transaction writes all non-host attendee statuses to `WaitingConfirmation` and room timestamps
  - Triggers Cloud Function push flow
- Attendee submits escrow settlement:
  - `JoinedSuccess`: full raid cost transferred to host, attendee escrow deducts full cost.
  - `SeatFullNoFault`: small effort fee transferred to host, attendee escrow deducts only effort fee.
  - `MissedInvitation`: no honey transfer.
  - Firestore transaction writes status/deposit/honey/rating flags and settlement snapshot fields.
  - Triggers Cloud Function push flow
  - Cloud Function write: `users/{uid}/events/{eventId}` for host/attendee honey balance delta history.
- Host/attendee rating:
  - Firestore transaction updates user stars + attendee flags

### Postcard Tab

#### Browse list
- Enter Postcard tab / pull-to-refresh:
  - Firestore query read: first page of `postcards` ordered by `createdAt desc`.
  - Current page size is `AppConfig.Postcard.browseListFetchLimit = 20`.

#### Load more (pagination)
- Tap `Load more` button:
  - Firestore query read: next page using cursor (`start(afterDocument:)`).
  - Each tap = one additional query page.

#### Search
- Typing text:
  - Local filtering only (no immediate backend call).
- Press search/submit:
  - Firestore query read: `postcards where searchTokens arrayContains token` + pagination.
- Tap load more during search:
  - Another paged search query read.

#### Open postcard detail
- Tap listing card:
  - Firestore read: `postcards/{postcardId}` (refresh in detail).
  - If buyer: one Firestore query for latest active order (`status in [...]`, ordered by `createdAt desc`, `limit(1)`).

#### Create postcard listing (includes image upload)
- In register form submit:
  - Storage upload write: full image JPEG.
  - Storage upload write: thumbnail JPEG (default 256x256, compressed).
  - Storage reads: `downloadURL` for both uploads.
  - Firestore write: create `postcards/{postcardId}` with `imageUrl` + `thumbnailUrl`.
  - On failure after upload: best-effort Storage delete cleanup of newly uploaded blobs.

#### Edit postcard listing
- Save without image replacement:
  - Firestore write: update listing fields only.
- Save with image replacement:
  - Storage upload full + thumbnail
  - Firestore write listing with new URLs
  - Best-effort Storage delete of old full/thumbnail objects
  - Rollback cleanup for newly uploaded files if write fails

#### Delete postcard listing
- Tap delete listing:
  - Firestore read: existing listing to get image URLs
  - Firestore delete: listing doc
  - Storage deletes: full image + thumbnail (best effort)

#### Buy postcard
- Tap buy:
  - Firestore query read: checks active order for `(buyerId, postcardId)` in status set `[AwaitingShipping, Shipped]` (plus legacy aliases).
  - Firestore transaction reads postcard + buyer user docs
  - Firestore writes:
    - decrement listing stock
    - decrement buyer honey
    - create `postcardOrders/{orderId}`
  - Order document snapshots seller/buyer metadata including push tokens for function efficiency.
  - Cloud Function write: `users/{uid}/events/{eventId}` for buyer honey balance delta history.

#### Seller shipping queue
- Open shipping sheet:
  - Firestore query read: `postcardOrders` filtered by seller+postcard+pending statuses (`AwaitingShipping`, plus legacy aliases).
  - Friend-code fallback users query only for legacy orders missing snapshot values.
- Seller reject:
  - Firestore transaction write:
    - reject -> `status: Rejected` + buyer refund + stock restore
  - Cloud Function write: `users/{uid}/events/{eventId}` for buyer honey refund history.
- Mark sent:
  - Firestore transaction write: order status/timeouts -> `Shipped`.

#### Buyer receive flow
- Confirm received:
  - Firestore transaction reads order + seller user
  - Firestore writes seller honey and order completion state
  - Cloud Function write: `users/{uid}/events/{eventId}` for seller honey balance delta history.
- Auto-complete fallback:
  - Cloud Scheduler function sweeps `Shipped` orders past `buyerConfirmDeadlineAt`
  - Firestore transaction writes seller honey and order status -> `CompletedAuto`
  - Cloud Function write: `users/{uid}/events/{eventId}` for seller honey balance delta history.

### Feedback
- Submit feedback from profile:
  - Firestore write: `feedbackSubmissions/{feedbackId}`
  - Cloud Function trigger sends email (SMTP path)

## Cloud Functions Interaction Summary

### Mushroom push functions
- `recordRoomCreatedEvent`
  - Trigger: room create.
  - Writes host-side `users/{uid}/events/{eventId}` history event (`ROOM_CREATED_HOST`).
- `recordHostRaidInviteEvent`
  - Trigger: room update when `raidConfirmationHistory` prepends a new record.
  - Writes host-side history event (`RAID_INVITED_HOST`).
- `notifyHostJoinRequest`
  - Trigger: attendee document created with status `AskingToJoin`.
  - Sends join-request push to host.
  - Writes history events for both host and joiner.
  - Resolves host from `rooms.hostUid` first.
  - Uses room snapshot token first (`rooms.hostFcmToken`), user fallback.
- `handleRoomAttendeeUpdatedEvents`
  - Trigger: update on `rooms/{roomId}/attendees/{attendeeUid}`.
  - Single routed handler for attendee update events:
    - attendee enters `WaitingConfirmation`,
    - applicant `AskingToJoin -> Ready`,
    - confirmation result `WaitingConfirmation -> Ready`,
    - star-rating flag transitions.
  - Sends corresponding push notifications and writes corresponding history events for each routed event type.
- `notifyJoinApplicantRejected`
  - Trigger: attendee document deleted when previous status is `AskingToJoin`.
  - Sends rejection push to applicant.
  - Writes history events for both host and joiner.
  - Uses attendee snapshot token first (`attendees/{uid}.fcmToken`), user fallback.

### Postcard push functions
- `recordPostcardCreatedEvent`
  - Trigger: postcard create.
  - Writes seller-side history event (`POSTCARD_CREATED_SELLER`).
- `sendPostcardOrderCreatedPush`
  - Trigger: order created in `AwaitingShipping`
  - Uses `postcardOrders.sellerFcmToken` first, user fallback.
  - Writes history events for both seller (`POSTCARD_ORDER_SELLER`) and buyer (`POSTCARD_ORDER_BUYER`).
- `handlePostcardOrderUpdatedEvents`
  - Trigger: update on `postcardOrders/{orderId}`.
  - Single routed handler for order status transitions:
    - order -> `Shipped`,
    - order -> `Rejected`,
    - order -> `Completed` or `CompletedAuto`.
  - Uses `postcardOrders` snapshot token first, user fallback.
  - Sends corresponding push and writes corresponding history events for each routed event type.
- `processPostcardOrderTimeouts`
  - Trigger: scheduler every 15 minutes
  - Handles seller no-ship timeout and buyer auto-complete.

### User profile event function
- `recordUserProfileAndWalletEvents`
  - Trigger: update on `users/{uid}`.
  - Writes event-history entries in `users/{uid}/events/{eventId}` when:
    - `displayName` changes,
    - `friendCode` changes.

This token-snapshot-first approach reduces repeated `users/{uid}` reads in hot notification paths.
Push notifications (mushroom + postcard) now use the same server-side localized snapshot text as event history (`title`/`message`) so push copy and inbox copy stay identical for each created event.

## Image Download Behavior (Important for Cost)
- Browse card uses `thumbnailUrl` first, then falls back to `imageUrl` if thumbnail missing.
- Detail screen uses full `imageUrl`.
- Postcard image UI now uses cache-first local image loading (`memory -> disk -> network`) for browse thumbnails, detail hero image, and form preview fallback images.
- Bigger user base + more browsing mainly increases Storage download bandwidth cost.
- Pagination (20 per page) limits one-time burst download compared with loading 50+ cards at once.

## Current Efficiency Patterns Already in Place
- Cursor pagination for postcard browse/search.
- Thumbnail pipeline (`256x256` default, compressed) for browse images.
- App-level postcard image cache (memory+disk) with cache-first image rendering to reduce repeated Firebase Storage egress.
- App-level mushroom/profile list caches (memory+disk) with stale-first rendering and explicit refresh on pull-to-refresh/state-changing actions.
- Conditional legacy fallback queries (only when primary query is insufficient).
- Snapshot fields (`sellerFriendCode`, `hostUid`, push token snapshots) to avoid extra reads.
- Write guards for token/profile sync paths to avoid duplicate writes.

## App-Level Data Cache Scope

This section documents app-level cache behavior for Postcard, Mushroom, and Profile views.

### Cache storage scope
- Cache type: app-level memory + disk cache (persisted across view transitions; disk survives app restarts until evicted/overwritten).
- Cache granularity:
  - Postcard: image URL cache (`thumbnailUrl` / `imageUrl`) for postcard browse/detail/form previews.
  - Mushroom browse: one cached room-list payload for browse page.
  - Mushroom room detail: one cached payload per `roomId` (room header + attendees list).
  - Profile: one cached payload per user (`authUid`) for hosted rooms, joined rooms, hosted pending-join counts, on-shelf postcards, ordered postcards, and pending seller-order badge counts.

### Cache hit / miss behavior
- Postcard image cache:
  - Hit: memory or disk has image bytes for the URL; UI renders without Firebase Storage fetch.
  - Miss: no cached bytes (or expired/evicted); network fetch runs, then cache is filled.
- Mushroom browse data cache:
  - Hit: cached browse list exists; entering Mushroom tab uses cached list immediately (no immediate Firestore read).
  - Miss: no cached list; entering Mushroom tab queries Firestore and writes returned list into cache.
- Mushroom room detail cache:
  - Hit: cached room payload exists for that `roomId`; opening room uses cached header/attendees immediately.
  - Miss: no cached payload for that `roomId`; opening room queries Firestore (`rooms/{roomId}` + `attendees`) and caches result.
- Profile list cache:
  - Hit: cached profile payload exists for current user; opening Profile uses cached sections immediately.
  - Miss: no cached payload for current user; Profile queries Firestore lists and caches results.

### Forced update triggers (refresh from Firebase)
- User pull-to-refresh (upscroll) always forces backend refresh:
  - Mushroom browse list (`rooms` query).
  - Mushroom room detail (`rooms/{roomId}` + attendees query).
  - Profile lists (hosted/joined/on-shelf/ordered + hosted pending-join counts + seller pending-order counts).
- Mushroom browse search submit forces backend refresh before applying local text filtering.
- Mushroom room state-changing actions force backend refresh and cache overwrite, including:
  - join / leave / update deposit
  - approve / reject join application
  - kick attendee
  - finish raid
  - attendee confirmation responses
  - host/attendee rating actions
- Profile hosted-room close callback forces hosted-room refresh to keep profile host list consistent after room lifecycle changes.

### Practical behavior summary
- Default navigation is stale-first (cache-first) for faster UX and fewer reads.
- Pull-to-refresh (user upscroll) is the explicit "get latest from Firebase now" action.
- Mutating actions refresh and overwrite cache so post-action UI state is backend-consistent.

## When Cost Usually Spikes
- Heavy browse traffic with many image impressions (Storage egress).
- Repeated opens/refreshes of detail pages using full-size image URLs.
- Very high-frequency writes in chatty update paths without guards.
- Legacy data requiring fallback query paths repeatedly.

## Operational Suggestions
- Keep thumbnail size/compression tuned in `AppConfig.Postcard` based on visual quality vs bandwidth.
- Keep image cache limits tuned in `AppConfig.Postcard` (`imageMemoryCacheEntryLimit`, `imageDiskCacheMaxBytes`, `imageDiskCachePruneTargetRatio`, `imageDiskCacheMaxAgeSeconds`) to balance instant reloads vs local storage use.
- Keep browse page size conservative (currently 20).
- Periodically backfill missing snapshot fields (`thumbnailUrl`, token snapshots) to reduce fallback reads.
- Track Firebase usage dashboard by product area:
  - Firestore reads/writes by path
  - Storage egress by object prefix (`postcards/`)
  - Function invocation and execution time
