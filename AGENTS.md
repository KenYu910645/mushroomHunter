# AGENT Instructions for HoneyHub

This AGENTS.md is a very important document and you HAVE to maintain it.
After **any code changes**, You have to come back to AGENTS.md to check if you need to update it

## Overview
HoneyHub (bundle `com.kenyu.mushroomHunter`) is an iOS app for Pikmin Bloom players to coordinate mushroom raids and trade/market postcards.
Core flows:
- Browse open mushroom rooms, see target details, join with a honey deposit, and coordinate via room details.
- Host a room with target color/attribute/size, manage attendees, and close or finish a raid.
- Maintain a user profile (display name, friend code, stars/reputation).
- Browse/search postcards and upload postcard images to Firebase Storage.


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
APP_PATH=$(ls -d /Users/ken/Library/Developer/Xcode/DerivedData/mushroomHunter-*/Build/Products/Debug-iphoneos/HoneyHub.app | head -n 1)

xcrun devicectl device install app --device 664E44A2-57C7-5319-B871-EB1D380FBC1B "$APP_PATH"
xcrun devicectl device process launch --device 664E44A2-57C7-5319-B871-EB1D380FBC1B com.kenyu.mushroomHunter
```

## General Expectations
- Prefer `rg` for searches if available; otherwise fall back to `grep`.
- Keep changes minimal and focused; don’t reformat unrelated code.
- If behavior changes, mention what to test in the app.

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

#### `postcards/{postcardId}`
Postcard marketplace listings. (Client currently reads; create/update may be done by admin tools or future UI.)
Fields:
- `title` (String): listing title.
- `priceHoney` (Int): price per postcard.
- `sellerName` (String): seller display name.
- `stock` (Int): available quantity.
- `imageUrl` (String, optional): public URL of postcard image.
- `location` (Map): `{ country, province, detail }` strings.
- `searchTokens` ([String]): normalized tokens for search.
- `createdAt` (Timestamp): listing creation time.

### Firebase Storage
- Path: `postcards/{ownerId}/{uuid}.jpg` where `ownerId` is the uploader uid or `anonymous`.
- Image is uploaded with `image/jpeg` metadata and the download URL is stored in `postcards.imageUrl`.
