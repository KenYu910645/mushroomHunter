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
  - Firestore queries for profile-owned rooms/listings/orders depending on sections shown.
- Hosted rooms list:
  - Primary query: `rooms where hostUid == uid`.
  - Legacy fallback query only when needed.
- Joined rooms list:
  - Primary query: `collectionGroup(attendees) where uid == current uid` + status filters.
  - Legacy fallback only when primary docs are insufficient.
- Save profile (name/friend code):
  - Firestore write: `users/{uid}` (guarded by changed fields).
  - Firestore batch writes: host attendee snapshot fields across active hosted rooms.

### Mushroom Tab

#### Browse rooms
- Enter Mushroom browse / pull-to-refresh:
  - Firestore query read on `rooms` list.

#### Open room detail
- Tap a room:
  - Firestore read: `rooms/{roomId}`
  - Firestore query read: `rooms/{roomId}/attendees`

#### Join room
- Tap Join:
  - Firestore read: `users/{uid}` for limit and wallet info.
  - Firestore query read: active joined-room count via `collectionGroup(attendees)`.
  - Legacy fallback query only when required.
  - Firestore transaction writes:
    - create attendee doc
    - decrement user honey
    - increment room joinedCount

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
  - Firestore transaction writes attendee statuses to `WaitingConfirmation` and room timestamps
  - Triggers Cloud Function push flow
- Attendee accepts/rejects:
  - Firestore transaction writes status/deposit/honey/rating flags
  - Triggers Cloud Function push flow
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
  - Firestore transaction reads postcard + buyer user docs
  - Firestore writes:
    - decrement listing stock
    - decrement buyer honey
    - create `postcardOrders/{orderId}`
  - Order document snapshots seller/buyer metadata including push tokens for function efficiency.

#### Seller shipping queue
- Open shipping sheet:
  - Firestore query read: `postcardOrders` filtered by seller+postcard+awaiting send.
  - Friend-code fallback users query only for legacy orders missing snapshot values.
- Mark sent:
  - Firestore transaction write: order status/timeouts -> `InTransit`.

#### Buyer receive flow
- Confirm received:
  - Firestore transaction reads order + seller user
  - Firestore writes seller honey and order completion state
- Mark not received:
  - Firestore transaction writes order status/timestamps (no honey transfer)

### Feedback
- Submit feedback from profile:
  - Firestore write: `feedbackSubmissions/{feedbackId}`
  - Cloud Function trigger sends email (SMTP path)

## Cloud Functions Interaction Summary

### Mushroom push functions
- `sendRaidConfirmationPush`
  - Trigger: attendee status -> `WaitingConfirmation`
  - Uses attendee snapshot token first (`attendees/{uid}.fcmToken`), user lookup fallback.
- `notifyHostRaidConfirmationResult`
  - Trigger: `WaitingConfirmation -> Ready/Rejected`
  - Resolves host from `rooms.hostUid` first.
  - Uses room snapshot token first (`rooms.hostFcmToken`), user lookup fallback.

### Postcard push functions
- `sendPostcardOrderCreatedPush`
  - Trigger: order created in `AwaitingSellerSend`
  - Uses `postcardOrders.sellerFcmToken` first, user fallback.
- `sendPostcardShippedPush`
  - Trigger: order status -> `InTransit`
  - Uses `postcardOrders.buyerFcmToken` first, user fallback.
- `notifySellerPostcardCompleted`
  - Trigger: order status -> `Completed`
  - Uses `postcardOrders.sellerFcmToken` first, user fallback.

This token-snapshot-first approach reduces repeated `users/{uid}` reads in hot notification paths.

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
  - Function invocation and execution time
