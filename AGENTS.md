# AGENT Instructions for HoneyHub

This AGENTS.md is a very important document and you HAVE to maintain it.
After **any code changes**, You have to come back to AGENTS.md to check if you need to update it

## Overview
HoneyHub (bundle `com.kenyu.mushroomHunter`) is an iOS app for Pikmin Bloom players to coordinate mushroom raids and trade/market postcards.
Core flows:
- Browse open mushroom rooms, see target details, join with a honey deposit, and coordinate via room details.
- Host a room with target color/attribute/size, manage attendees, and close or finish a raid.
- Hosts can open a share sheet in room details to show a QR code and share a room invite link (`honeyhub://room/{roomId}`) for installed-app users.
- Maintain a user profile (display name, friend code, stars/reputation).
- Browse/search postcards and upload postcard images to Firebase Storage.
- Postcard register success dismisses the sheet and refreshes browse; postcard browse/detail pull-to-refresh fetch latest Firestore data.
- Seller can open a shipping sheet from postcard detail, see waiting buyers, and mark each order as sent.
- After buyer places an order, seller receives a push to process shipping in postcard detail.
- After seller marks shipped, buyer receives a push and can confirm receipt in postcard detail:
  - Buyer taps "Yes" to complete transaction and transfer held honey to seller.
  - Buyer taps "No" to keep honey on hold and continue waiting.
- Postcard register form uses left-label/right-input rows, and country selection uses a dropdown list (same country source as room create).
- In postcard register, tapping the snapshot area opens photo picker (no separate photo button); default country is Taiwan.
- Postcard register detail text is capped at 100 characters.


## Always Build/Install/Run After Code Changes
- After **any code change**, you must build, install, and launch the app on my connected iPhone unless I explicitly say “skip build”.
- If the build or install fails, read the error message and try to resolve yourself

### Current device and bundle
- Device (CoreDevice UUID): `664E44A2-57C7-5319-B871-EB1D380FBC1B` (Ken’s iPhone)
- Bundle ID: `com.kenyu.mushroomHunter`
- Project: `/Users/ken/Desktop/mushroomHunter/mushroomHunter.xcodeproj`
- Scheme: `HoneyHub`

### Required commands (in order)
```bash
xcodebuild -project /Users/ken/Desktop/mushroomHunter/mushroomHunter.xcodeproj \
  -scheme HoneyHub -configuration Debug \
  -destination "id=00008150-00021D26028A401C" build

# find .app (DerivedData can change)
APP_PATH=$(ls -dt /Users/ken/Library/Developer/Xcode/DerivedData/mushroomHunter-*/Build/Products/Debug-iphoneos/HoneyHub.app | head -n 1)

xcrun devicectl device install app --device 664E44A2-57C7-5319-B871-EB1D380FBC1B "$APP_PATH"
xcrun devicectl device process launch --device 664E44A2-57C7-5319-B871-EB1D380FBC1B com.kenyu.mushroomHunter
```

## General Expectations
- Prefer `rg` for searches if available; otherwise fall back to `grep`.
- Keep changes minimal and focused; don’t reformat unrelated code.
- If behavior changes, mention what to test in the app.

## Automated Testing
- UI test target: `HoneyHubUITests`.
- Local UI test command:
```bash
xcodebuild -project /Users/ken/Desktop/mushroomHunter/mushroomHunter.xcodeproj \
  -scheme HoneyHub \
  -destination "platform=iOS Simulator,name=iPhone 17,OS=26.1" \
  -maximum-parallel-testing-workers 1 \
  test
```
- CI workflow file: `/Users/ken/Desktop/mushroomHunter/.github/workflows/ios-ui-tests.yml`.
- UI tests launch app with `--ui-testing --mock-rooms` so tests do not depend on live Firebase data.

## Backend
We use Firebase for auth, Firestore for data, and Firebase Storage for postcard images.

### Firestore data structure

#### `users/{uid}`
User profile and limits. Created/merged in `SessionStore.ensureUserProfile()` and by room actions when a user joins/leaves without a prior profile.
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
- `targetColor` (String): target mushroom color. Set on create/update. edi
- `targetAttribute` (String): target mushroom attribute/type. Set on create/update.
- `targetSize` (String): target size. Set on create/update.
- `location` (String): short location label. Set on create/update. Typically, consist of country, city
- `description` (String): description. Set on create/update.
- `fixedRaidCost` (Int): minimum honey deposit for joining. Set on create/update.
- `maxPlayers` (Int): max attendees (default 10). Set on create.
- `joinedCount` (Int): number of active attendees. Incremented on join, decremented on leave/kick/close. Host is counted as an attendee.
- `createdAt` (Timestamp): set on create.
- `updatedAt` (Timestamp): updated on any room or attendee change.
- `lastSuccessfulRaidAt` (Timestamp, optional): set when host finishes a raid.
- `expiresAt` (Timestamp, optional/future): not currently written by client; reserved.
Notes:
- Host identity and info are stored in `attendees/{uid}` with `status = Host` (the host is just an attendee).

#### `rooms/{roomId}/attendees/{uid}`
Attendee entries for a room. Written in join/leave/deposit flows.
Fields:
- `name` (String): attendee display name. Set on join.
- `friendCode` (String): attendee friend code. Set on join.
- `stars` (Int): attendee stars. Set on join.
- `depositHoney` (Int): current deposit. Set on join; updated on deposit change and raid settlement.
- `joinedAt` (Timestamp): set on join.
- `updatedAt` (Timestamp): updated on deposit changes and raid settlement.
- `status` (String): attendee state. Current values are `Host`, `Ready`, `WaitingConfirmation`, `Rejected`.
- `attendeeRatedHost` (Bool, optional): whether attendee already rated host for the latest confirmation cycle. Reset to `false` when host sends a new confirmation request.
- `hostRatedAttendee` (Bool, optional): whether host already rated attendee for the latest confirmation cycle. Reset to `false` when host sends a new confirmation request.
- `needsHostRating` (Bool, optional): set to `true` when attendee accepts confirmation (host receives honey) so host can rate attendee; set back to `false` after host submits stars.

#### `postcards/{postcardId}`
Postcard marketplace listings. Client reads for browse, creates from Postcard Register, and seller can edit/delete from Postcard Detail.
Fields:
- `title` (String): listing title.
- `priceHoney` (Int): price per postcard.
- `sellerId` (String): seller uid for ownership checks.
- `sellerName` (String): seller display name.
- `stock` (Int): available quantity.
- `imageUrl` (String, optional): public URL of postcard image.
- `location` (Map): `{ country, province, detail }` strings.
- `searchTokens` ([String]): normalized tokens for search.
- `createdAt` (Timestamp): listing creation time.
- `updatedAt` (Timestamp): last listing update time.
Notes:
- Register flow uploads image to Firebase Storage first, then writes listing doc with returned `imageUrl`.
- `searchTokens` are generated by `SearchTokenBuilder` from title + seller name + location fields for search.
- Client UI input caps: `title` max `20` chars, `location.province` max `20` chars, `location.detail` max `100` chars.
- Postcard detail view behavior:
  - Seller (`auth.uid == sellerId`) sees edit toolbar action and can update listing fields or delete listing.
  - Non-seller sees buy action button only.
  - On buy, client runs Firestore transaction: decrements `stock` and deducts buyer `users/{uid}.honey` atomically.
  - Postcard create/edit form clamps numeric input to avoid integer overflow (`priceHoney` max `1,000,000,000`; `stock` max `1,000,000`).

#### `postcardOrders/{orderId}`
Postcard transaction documents created when buyer confirms purchase.
Fields:
- `postcardId` (String): source listing id.
- `postcardTitle` (String): snapshot title at purchase time.
- `postcardImageUrl` (String): snapshot image URL at purchase time.
- `location` (Map): snapshot `{ country, province, detail }`.
- `status` (String): current transaction state. Starts as `AwaitingSellerSend`.
- `buyerId` (String): buyer uid.
- `buyerName` (String): buyer display name snapshot.
- `sellerId` (String): seller uid.
- `sellerName` (String): seller display name snapshot.
- `priceHoney` (Int): listing price at purchase.
- `holdHoney` (Int): honey held for escrow (equal to `priceHoney` in MVP).
- `sellerReminderAt` (Timestamp): next seller reminder time.
- `sellerDeadlineAt` (Timestamp): current seller deadline.
- `buyerReminderAt` (Timestamp): default buyer reminder anchor.
- `buyerAutoCompleteAt` (Timestamp): default buyer auto-complete deadline anchor.
- `sentAt` (Timestamp, optional): set when seller marks postcard sent.
- `completedAt` (Timestamp, optional): set when buyer confirms receipt and transaction completes.
- `timeouts` (Map): hour-based parameters written to each order:
  - `sellerSendReminderHours`
  - `sellerSendDeadlineHours`
  - `buyerReceiveReminderHours`
  - `buyerAutoCompleteHours`
- `createdAt` (Timestamp): order creation time.
- `updatedAt` (Timestamp): latest order update time.
Notes:
- Seller shipping action transitions status from `AwaitingSellerSend` -> `InTransit` and updates `sentAt`, `buyerReminderAt`, and `buyerAutoCompleteAt`.
- Buyer "not received yet" keeps honey on hold and sets status to `AwaitingBuyerDecision`.
- Buyer confirmation transitions status to `Completed` and transfers `holdHoney` to seller `users/{sellerId}.honey`.

### Firebase Storage
- Path: `postcards/{ownerId}/{uuid}.jpg` where `ownerId` is the authenticated uploader uid.
- Image is uploaded with `image/jpeg` metadata and the download URL is stored in `postcards.imageUrl`.
- Client-side upload preprocessing crops postcard snapshots to fixed pixel rect `(x:20, y:20) -> (x:665, y:655)` before JPEG encoding/upload.
- If the selected source image cannot safely contain that crop rect, client shows an error and skips upload.

### Cloud Functions (Push Notifications)
- Function: `sendRaidConfirmationPush` in `functions/index.js`.
- Trigger: Firestore document update on `rooms/{roomId}/attendees/{attendeeUid}`.
- Condition: send only when attendee `status` transitions into `WaitingConfirmation` (not on repeated updates while already `WaitingConfirmation`).
- Target token source: `users/{attendeeUid}.fcmToken`.
- Payload includes:
  - Notification title/body for immediate phone alert.
  - Data keys `type = raid_confirmation`, `roomId`, and `room_id` for app routing.
- Function: `notifyHostRaidConfirmationResult` in `functions/index.js`.
- Trigger: Firestore document update on `rooms/{roomId}/attendees/{attendeeUid}`.
- Condition: send only when attendee `status` transitions from `WaitingConfirmation` to either:
  - `Ready` (attendee accepted confirmation): push host that attendee confirmed and host earned `fixedRaidCost` honey.
  - `Rejected` (attendee rejected confirmation): push host to resolve the issue in room details.
- Host resolution:
  - Find host uid from `rooms/{roomId}/attendees` where `status = Host`.
  - Read host token from `users/{hostUid}.fcmToken`.
- Payload includes room routing keys `roomId` and `room_id`, and type:
  - `raid_confirmation_accepted`
  - `raid_confirmation_rejected`
- Function: `sendPostcardShippedPush` in `functions/index.js`.
- Trigger: Firestore document update on `postcardOrders/{orderId}`.
- Condition: send only when order `status` transitions into `InTransit`.
- Target token source: `users/{buyerId}.fcmToken`.
- Payload includes:
  - Notification title/body that seller marked postcard as sent.
  - Data keys `type = postcard_shipped`, `orderId`, and `postcardId`.
- Function: `sendPostcardOrderCreatedPush` in `functions/index.js`.
- Trigger: Firestore document create on `postcardOrders/{orderId}`.
- Condition: send when new order status is `AwaitingSellerSend`.
- Target token source: `users/{sellerId}.fcmToken`.
- Payload includes:
  - Notification title/body to open postcard detail and process shipping.
  - Data keys `type = postcard_order_created`, `orderId`, and `postcardId`.
- Function: `notifySellerPostcardCompleted` in `functions/index.js`.
- Trigger: Firestore document update on `postcardOrders/{orderId}`.
- Condition: send when order `status` transitions into `Completed`.
- Target token source: `users/{sellerId}.fcmToken`.
- Payload includes:
  - Notification title/body that buyer confirmed receipt and honey transfer completed.
  - Data keys `type = postcard_order_completed`, `orderId`, `postcardId`, and `honey`.

### Confirmation stars flow
- Attendee flow: after attendee accepts raid confirmation and pays host (`depositHoney -= fixedRaidCost`, host `honey += fixedRaidCost`), attendee can give host `1`, `2`, or `3` stars.
- Host flow: when attendee accepts confirmation, attendee doc is marked `needsHostRating = true`; host can then give that attendee `1`, `2`, or `3` stars.
- Stars updates write to `users/{uid}.stars` and also refresh room attendee stars in the active room so Room Details reflects new totals immediately.
- Firestore transaction rule reminder: in room raid settlement transactions, read all attendee docs before applying any writes to avoid "all reads must occur before writes" transaction failures.
