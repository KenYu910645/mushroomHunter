# Firebase

## Firebase Effeiciency

This document explains how HoneyHub interacts with Firebase, and what UI actions trigger Firestore and Storage read-write activity.

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
- Event-history and push routing details: `EVENTS.md`
- Cache behavior source of truth: `CACHE.md`

## Cost Model Quick Reminder
- Firestore cost is mainly from:
  - document reads
  - document writes
  - document deletes
- Storage cost is mainly from:
  - stored GB-month
  - download/egress bandwidth
  - upload/download operations

## Core Data Collections
- `users/{uid}`: profile, wallet, limits, push token, premium entitlement
- `users/{uid}/events/{eventId}`: per-user event history (Action/Record state via `isActionEvent`/`isResolved`, route metadata, newest-first paging)
- `rooms/{roomId}`: mushroom room header data
- `rooms/{roomId}/attendees/{uid}`: room membership and state
- `roomRatingTasks/{taskId}`: durable mushroom room rating tasks while the room remains open
- `postcards/{postcardId}`: postcard listing data
- `postcardOrders/{orderId}`: postcard order lifecycle
- `feedbackSubmissions/{feedbackId}`: feedback payloads
- Storage path `postcards/{ownerId}/{filename}.jpg`: full and thumbnail postcard images

## UI Operation -> Firebase R/W

### App Launch, Sign-in, Session
- Open app while signed in:
  - Firestore read: `users/{uid}` to refresh local session/profile/wallet.
  - Firestore snapshot listener on `users/{uid}` keeps local stars/honey/profile fields synchronized with backend transaction writes while the session stays signed in.
- Receive/refresh FCM token:
  - Firestore write: `users/{uid}.fcmToken` (guarded; skip write if unchanged in-session).
  - Firestore writes: hosted room snapshots (`rooms.hostFcmToken`, host attendee `fcmToken`) to reduce later function reads.
- Sign in (Apple/Google):
  - Auth operation only, then profile sync fills any missing `users/{uid}` defaults without overwriting existing `stars`/`honey` counters.
  - This missing-field repair also covers partial docs created earlier by token/bootstrap writes, so new users still receive a complete wallet/profile document with `honey`, `stars`, limits, premium flags, locale, and timestamps.

### Profile Tab
- Open profile tab:
  - Profile screen reads session identity values (display name/friend code/honey/stars).
  - Premium membership sheet loads StoreKit product metadata locally, then syncs verified entitlement state to `users/{uid}` through `syncPremiumSubscription`.
  - Shared calendar icon opens the DailyReward sheet and loads current-month reward state from `users/{uid}.dailyReward`.
- App icon badge refresh:
  - Firestore query read: `users/{uid}/events where isActionEvent == true and isResolved == false`.
  - Client excludes `DAILY_REWARD_REMINDER` from that unresolved action count and then adds `1` when `users/{uid}.dailyReward.lastClaimedDayKey` is not today's Taipei day key.
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
  - Event history write behavior is documented in `EVENTS.md`.
- Sync premium subscription:
  - Callable Function: `syncPremiumSubscription`
  - Firestore write on `users/{uid}`:
    - update `isPremium`
    - update `premiumSource`
    - update `premiumProductId`
    - update `premiumExpirationAt`
    - update `premiumLastVerifiedAt`
    - update effective `maxHostRoom`
    - update effective `maxJoinRoom`
    - update `updatedAt`

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
  - Server event pipeline writes localized snapshot `title` + `message` into each event doc at creation time.
  - iOS inbox reads stored `title`/`message` first, with `event_type_*` fallback for legacy rows.

### DailyReward Calendar
- Open DailyReward sheet from Mushroom/Postcard/Profile toolbar:
  - Firestore read: `users/{uid}` to load `dailyReward.monthKey`, `dailyReward.claimedDays`, and wallet snapshot fallback.
  - Shared calendar icon shows a red dot when `dailyReward.lastClaimedDayKey` does not match today's Taipei day key.
- Claim today's reward:
  - Callable Function: `claimDailyHoneyReward`
  - Firestore transaction write on `users/{uid}`:
    - increment `honey` by `10` for free users or `30` for active premium users
    - update `dailyReward.monthKey`
    - update `dailyReward.claimedDays`
    - update `dailyReward.lastClaimedDayKey`
    - update `dailyReward.lastClaimedAt`
    - update `dailyReward.updatedAt`
    - update `updatedAt`
  - Firestore write: create `users/{uid}/events/{eventId}` with type `HONEY_REWARD`
  - Firestore batch write: resolve unresolved `DAILY_REWARD_REMINDER` events for that user
  - No push notification is sent for DailyReward claims.
- Scheduled reminder at 12:00 PM Asia/Taipei:
  - Scheduled Function: `sendDailyRewardReminders`
  - Firestore paged read: `users`
  - Firestore event write: create `users/{uid}/events/{eventId}` with type `DAILY_REWARD_REMINDER` when today's reward is still unclaimed
  - Push: sends snapshot-title/body APNs that route user into the shared DailyReward sheet

### Mushroom Tab

#### Browse rooms
- Enter Mushroom browse:
  - Firestore query read on `rooms` list.
  - Firestore query reads on `users` (by `hostUid` chunks) to resolve latest host stars for browse-priority scoring.
  - See `CACHE.md` for cache-hit/miss and refresh trigger behavior.
- Pull-to-refresh:
  - Firestore query read on `rooms` list.
  - Firestore query reads on `users` (by `hostUid` chunks) to resolve latest host stars for browse-priority scoring.
- Search submit:
  - Forces Firestore query read on `rooms` list before applying local text filter.
  - Forces Firestore query reads on `users` (by `hostUid` chunks) to resolve latest host stars for browse-priority scoring.

#### Open room detail
- Tap a room:
  - Firestore read/query for room header + attendee list.
  - Firestore attendee snapshot listener stays attached while the room page remains open so attendee stars/status changes from other devices refresh in place.
  - See `CACHE.md` for cache-hit/miss and refresh trigger behavior.
- Pull-to-refresh:
  - Firestore read: `rooms/{roomId}`
  - Firestore query read: `rooms/{roomId}/attendees`
  - Firestore query reads on `users` (by attendee uid chunks) to override attendee-row `stars` with the latest profile star counts during forced refresh.

#### Join room
- Tap Join:
  - Firestore read: `users/{uid}` for limit and wallet info.
  - Effective joined-room limit uses premium entitlement when `isPremium == true` and `premiumExpirationAt` is still in the future.
  - Firestore query read: active joined-room count via `collectionGroup(attendees)`.
  - Legacy fallback query only when required.
  - Firestore transaction writes:
    - create attendee doc
      - initial `status: AskingToJoin`
      - `joinGreetingMessage`
    - decrement user honey
    - increment room joinedCount

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

#### Leave room / Kick attendee / Close room
- Host or attendee action:
  - Firestore transaction reads required docs
  - Firestore writes attendee/room/user fields and status transitions
  - Room close removes room + attendees (delete operations)

#### Finish raid / confirmation flows
- Host taps raid done:
  - Firestore transaction writes all non-host attendee statuses to `WaitingConfirmation` and room timestamps
- Attendee submits escrow settlement:
  - `JoinedSuccess`: global joined-success reward (`AppConfig.Mushroom.joinedSuccessRewardHoney`, default `10`) transferred to host, attendee escrow deducts the same amount.
  - `SeatFullNoFault`: global seat-full reward (`AppConfig.Mushroom.seatFullRewardHoney`, default `2`) transferred to host, attendee escrow deducts only that amount.
  - `MissedInvitation`: no honey transfer.
  - Firestore transaction writes status/deposit/honey/settlement snapshot fields and creates two `roomRatingTasks` docs.
- Host/attendee rating:
  - Firestore transaction updates user stars, best-effort updates active room attendee stars, and resolves the matching `roomRatingTasks` doc as `Rated` or `Skipped`.
  - Cloud Function trigger `handleRoomRatingTaskUpdatedEvents` watches `roomRatingTasks/{taskId}` transitions into `Rated` and emits receiver-side `STAR_RECEIVED` inbox rows plus push notifications.
  - Room close marks pending `roomRatingTasks` docs for that room as `Closed`.

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

#### Seller shipping queue
- Open shipping sheet:
  - Firestore query read: `postcardOrders` filtered by seller+postcard+pending statuses (`AwaitingShipping`, plus legacy aliases).
  - Friend-code fallback users query only for legacy orders missing snapshot values.
  - Seller pending postcard-rating query: `postcardOrders where sellerId == uid and postcardId == postcardId and isSellerRatingRequired == true limit 20`, then the app renders all pending seller-rating rows in the sheet.
- Seller reject:
  - Firestore transaction write:
    - reject -> `status: Rejected` + buyer refund + stock restore
- Mark sent:
  - Firestore transaction write: order status/timeouts -> `Shipped`.

#### Buyer receive flow
- Confirm received:
  - Firestore transaction reads order + seller user
  - Firestore writes seller honey, order completion state, both postcard rating-required flags, and resets both postcard rating-dismissed flags
  - Buyer pending postcard-rating query: `postcardOrders where buyerId == uid and postcardId == postcardId and isBuyerRatingRequired == true limit 10`, then the app chooses the latest `completedAt` locally for the inline buyer rating card.
- Auto-complete fallback:
  - Scheduled backend sweep processes `Shipped` orders past `buyerConfirmDeadlineAt`
  - Firestore transaction writes seller honey and order status -> `CompletedAuto`

## Firestore Index Notes
- Postcard pending-rating lookups now avoid the `completedAt desc` composite-index dependency by reading a small equality-filtered result set and choosing the latest `completedAt` in-app.

### Feedback
- Submit feedback from profile:
  - Firestore write: `feedbackSubmissions/{feedbackId}`
  - Server email delivery behavior is documented in `EVENTS.md`.

## Image Download Behavior (Important for Cost)
- Browse card uses `thumbnailUrl` first, then falls back to `imageUrl` if thumbnail missing.
- Detail screen uses full `imageUrl`.
- Bigger user base + more browsing mainly increases Storage download bandwidth cost.
- Pagination (20 per page) limits one-time burst download compared with loading 50+ cards at once.

## Current Efficiency Patterns Already in Place
- Cursor pagination for postcard browse/search.
- Thumbnail pipeline (`256x256` default, compressed) for browse images.
- Conditional legacy fallback queries (only when primary query is insufficient).
- Snapshot fields (`sellerFriendCode`, `hostUid`, push token snapshots) to avoid extra reads.
- Write guards for token/profile sync paths to avoid duplicate writes.
- Cache behavior details are centralized in `CACHE.md`.

## When Cost Usually Spikes
- Heavy browse traffic with many image impressions (Storage egress).
- Repeated opens/refreshes of detail pages using full-size image URLs.
- Very high-frequency writes in chatty update paths without guards.
- Legacy data requiring fallback query paths repeatedly.

## Operational Suggestions
- Keep thumbnail size/compression tuned in `AppConfig.Postcard` based on visual quality vs bandwidth.
- Keep browse page size conservative (currently 20).
- Periodically backfill missing snapshot fields (`thumbnailUrl`, token snapshots) to reduce fallback reads.
- Track Firebase usage dashboard by product area:
  - Firestore reads/writes by path
  - Storage egress by object prefix (`postcards/`)
