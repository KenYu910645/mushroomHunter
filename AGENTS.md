# AGENT Instructions for HoneyHub

`AGENTS.md` is the root operating guide for this repository. Keep it accurate.
If any workflow, command, architecture detail, or linked documentation changes, update this file in the same task.

## Project Overview
HoneyHub (bundle id `com.kenyu.mushroomHunter`) is an iOS app for Pikmin Bloom players to:
- Coordinate mushroom raids.
- Trade postcards in a buyer/seller marketplace.

Main app flow after sign-in:
1. Mushroom tab
2. Postcard tab
3. Profile tab

If signed out, users see the sign-in flow. First-time users must complete profile creation, then receive a one-time swipe tutorial (Mushroom -> Postcard -> Profile) with screenshot annotations (circle/arrow/text) rendered in-app.

## Documentation Map (Must Keep In Sync)
Use and maintain these files when related code changes:
- `AGENTS.md`: execution workflow, build/run rules, repo-level constraints.
- `EVENTS.md`: consolidated event-history model, event type catalog, push event routing types, and Firestore `users/{uid}/events` field reference.
- `FIREBASE.md`: Firebase architecture, operational notes, and the current Firestore database rule.
- `CACHE.md`: single source of truth for app-level cache architecture, scope, keys, and refresh/invalidation behavior.
- `MUSHROOM.md`: mushroom room lifecycle, attendee states, room invite/share flow.
- `POSTCARD.md`: postcard marketplace, listing/order lifecycle, shipping/receipt behavior.
- `PROFILE.md`: profile editing, settings, feedback/about, profile-owned content views.
- `SIGNIN.md`: authentication and first-time onboarding/profile-completion behavior.
- `TESTCASE.md`: UI test case inventory and covered end-to-end flow scope.

Rule: any code change that affects behavior must update the relevant markdown file(s) above.

## Firestore Rule Sync Policy
- `FIREBASE.md` must always contain the latest "Current Firestore Database Rule" section that mirrors the deployed Firestore rules.
- If implementation work requires a Firestore rule change, notify Ken in the handoff that deployed rules must be synced.
- If you directly update the rule block in `FIREBASE.md`, explicitly notify Ken to sync Firebase console/deployed rules to match the document.

## Firestore Index Sync Policy
- If implementation introduces a new Firestore query pattern (new `where`/`orderBy` combinations, new `in` filters, or new timeout/status sweep queries), verify whether a composite index is required.
- Update `FIREBASE.md` query documentation when query patterns change.
- In handoff, explicitly remind Ken to create/update Firebase Firestore indexes when needed and call out which query paths require them.

## Firebase Storage Rule Sync Policy
- `FIREBASE.md` must always contain the latest "Current Firebase Storage Rule" section that mirrors the deployed Firebase Storage rules.
- If implementation work requires a Firebase Storage rule change, notify Ken in the handoff that deployed rules must be synced.
- If you directly update the storage rule block in `FIREBASE.md`, explicitly notify Ken to sync Firebase console/deployed rules to match the document.

## File Structure By Feature
This is the source-of-truth feature map. Keep it updated whenever files are added/moved.

### MUSHROOM (`MUSHROOM.md`)
- `mushroomHunter/Features/Mushroom/RoomBrowseView.swift`
- `mushroomHunter/Features/Mushroom/RoomBrowseViewModel.swift`
- `mushroomHunter/Features/Mushroom/RoomCreateEditView.swift`
- `mushroomHunter/Features/Mushroom/RoomView.swift`
- `mushroomHunter/Features/Mushroom/RoomView.swift` (contains room-specific invite sheet wrapper for room flow)
- `mushroomHunter/Features/Shared/InviteShareSheet.swift` (shared invite QR sheet used by room/postcard)
- `mushroomHunter/Features/Mushroom/RoomViewModel.swift`
- `mushroomHunter/Features/Mushroom/RoomDomainModels.swift`
- `mushroomHunter/Features/Shared/TopActionBar.swift` (shared browse header with honey/search/create actions)
- `mushroomHunter/Features/EventInbox/EventInboxView.swift` (shared in-app notification inbox list opened from top-right bell actions)
- `mushroomHunter/Features/Shared/SmartTextField.swift` (shared auto-select text field wrapper used by host/profile/profile-create forms)
- `mushroomHunter/Features/Shared/SmartTextEditor.swift` (shared auto-select text editor wrapper used by multiline inputs)
- `mushroomHunter/Features/Shared/KeyboardDismissBridge.swift` (shared UIKit bridge for dismissing keyboard on outside taps without scroll interference)
- `mushroomHunter/Features/Shared/MessageBox.swift` (shared custom confirmation/error dialog used across room flows)
- `mushroomHunter/Features/Shared/ColorfulTag.swift` (shared colorful tag + red action-dot primitives used by room/postcard status rows)
- `mushroomHunter/Services/Firebase/RoomBrowseRepo.swift`
- `mushroomHunter/Services/Firebase/ProfileListRepo.swift` (joined/hosted room summary source used to pin user-owned rooms at the top of browse)
- `mushroomHunter/Services/Firebase/RoomFormRepo.swift`
- `mushroomHunter/Services/Firebase/RoomRepo.swift`
- `mushroomHunter/Services/Firebase/RoomActionsRepo.swift`
- `mushroomHunter/Utilities/RoomInviteLink.swift`
- `mushroomHunter/Utilities/AppConfig.swift` (owner-managed mushroom defaults, limits, and option sets)
- `mushroomHunter/Utilities/AppDataCache.swift` (shared app-level Codable payload cache utility)
- `mushroomHunter/Utilities/CountryLocalization.swift` (shared locale-aware country + room-location display resolver used by mushroom/postcard views/forms)
- `mushroomHunter/Utilities/FriendCode.swift` (shared friend-code sanitize/validate/format utility used by profile/room/postcard)
- `mushroomHunter/Features/EventInbox/EventInboxStore.swift` (shared Firestore-backed notification event history pagination, unread state, and deep-link route metadata)
- Cloud Functions in `functions/index.js`:
  - `recordRoomCreatedEvent`
  - `recordRoomClosedEvent`
  - `recordHostRaidInviteEvent`
  - `notifyHostJoinRequest`
  - `handleRoomAttendeeUpdatedEvents`
  - `notifyJoinApplicantRejected`

### POSTCARD (`POSTCARD.md`)
- `mushroomHunter/Features/Postcard/PostcardBrowseView.swift`
- `mushroomHunter/Features/Postcard/PostcardView.swift`
- `mushroomHunter/Features/Postcard/PostcardOrdersView.swift`
- `mushroomHunter/Features/Postcard/PostcardCreateEditView.swift`
- `mushroomHunter/Features/Postcard/PostcardBrowseViewModel.swift`
- `mushroomHunter/Features/Postcard/PostcardDomainModel.swift`
- `mushroomHunter/App/HoneyHubApp.swift` (postcard invite deep-link routing)
- `mushroomHunter/App/ContentView.swift` (postcard invite deep-link presentation)
- `mushroomHunter/Features/Shared/TopActionBar.swift` (shared browse header with honey/search/create actions)
- `mushroomHunter/Features/EventInbox/EventInboxView.swift` (shared in-app notification inbox list opened from top-right bell actions)
- `mushroomHunter/Features/Shared/SmartTextField.swift` (shared auto-select text field wrapper used by postcard/profile/mushroom forms)
- `mushroomHunter/Features/Shared/SmartTextEditor.swift` (shared auto-select text editor wrapper used by postcard description fields)
- `mushroomHunter/Features/Shared/KeyboardDismissBridge.swift` (shared UIKit bridge for dismissing keyboard on outside taps without scroll interference)
- `mushroomHunter/Features/Shared/InviteShareSheet.swift` (shared invite QR sheet used by postcard seller share flow)
- `mushroomHunter/Features/Shared/MessageBox.swift` (shared custom confirmation/error dialog used across postcard flows)
- `mushroomHunter/Features/Shared/ColorfulTag.swift` (shared colorful tag + red action-dot primitives used by room/postcard status rows)
- `mushroomHunter/Features/Postcard/PostcardImageCache.swift` (shared postcard image rendering component)
- `mushroomHunter/Services/Firebase/PostcardRepo.swift` (browse/recent paging plus on-shelf/ordered queries used to pin user-owned postcards at the top of browse)
- `mushroomHunter/Services/Firebase/PostcardImageUploader.swift`
- `mushroomHunter/Utilities/RoomInviteLink.swift` (postcard invite link generation/parsing)
- `mushroomHunter/Utilities/SearchTokens.swift`
- `mushroomHunter/Utilities/AppConfig.swift` (owner-managed postcard caps, list limits, and timeout windows)
- `mushroomHunter/Utilities/CountryLocalization.swift` (shared locale-aware country + room-location display resolver used by mushroom/postcard views/forms)
- `mushroomHunter/Utilities/FriendCode.swift` (shared friend-code sanitize/validate/format utility used by profile/room/postcard)
- `mushroomHunter/Features/EventInbox/EventInboxStore.swift` (shared Firestore-backed notification event history pagination, unread state, and deep-link route metadata)
- Cloud Functions in `functions/index.js`:
  - `recordPostcardCreatedEvent`
  - `recordPostcardClosedEvent`
  - `sendPostcardOrderCreatedPush`
  - `handlePostcardOrderUpdatedEvents`

### PROFILE (`PROFILE.md`)
- `mushroomHunter/Features/Profile/ProfileView.swift`
- `mushroomHunter/Features/Profile/ProfileCreateEditView.swift` (shared create/edit profile form presented from onboarding and profile edit sheet)
- `mushroomHunter/Features/Profile/ProfileViewModel.swift` (profile tab badge aggregation + background refresh for room/postcard actionable counts)
- `mushroomHunter/Features/Profile/FeedbackView.swift` (feedback compose view + submission payload model)
- `mushroomHunter/Features/Profile/AboutView.swift` (about page contact information view)
- `mushroomHunter/Features/EventInbox/EventInboxView.swift` (shared in-app notification inbox sheet opened from the profile top-right bell action)
- `mushroomHunter/Features/EventInbox/EventInboxStore.swift` (shared Firestore-backed notification event history pagination, unread state, and deep-link route metadata)
- `mushroomHunter/Features/Shared/SmartTextField.swift` (shared auto-select text field wrapper used by profile edit/create)
- `mushroomHunter/Features/Shared/SmartTextEditor.swift` (shared auto-select text editor wrapper used by profile feedback message)
- `mushroomHunter/Features/Shared/KeyboardDismissBridge.swift` (shared UIKit bridge for dismissing keyboard on outside taps without scroll interference)
- `mushroomHunter/Features/Shared/MessageBox.swift` (shared custom confirmation/error dialog used across profile flows)
- `mushroomHunter/Services/Firebase/ProfileListRepo.swift`
- `mushroomHunter/Services/Firebase/FeedbackRepo.swift`
- `mushroomHunter/User/UserSessionStore.swift` (shared user session state container + local persistence helpers)
- `mushroomHunter/User/UserAuth.swift` (auth lifecycle and sign-in/sign-out flows)
- `mushroomHunter/User/UserProfile.swift` (profile fields, user sync, token sync)
- `mushroomHunter/Utilities/AppConfig.swift` (owner-managed profile validation and shared limits)
- `mushroomHunter/Utilities/AppDataCache.swift` (shared app-level Codable payload cache utility)
- `mushroomHunter/Utilities/FriendCode.swift` (shared friend-code sanitize/validate/format utility used by profile form and display)
- Cloud Functions in `functions/index.js`:
  - `sendFeedbackNotificationEmail`
  - `recordUserProfileAndWalletEvents` (records user-level event history for honey balance deltas and profile name/friend-code updates)

### SIGNIN (`SIGNIN.md`)
- `mushroomHunter/Features/Profile/LoginView.swift`
- `mushroomHunter/Features/Profile/ProfileCreateEditView.swift` (shared create/edit profile form, signin flow uses create mode)
- `mushroomHunter/Features/Profile/TutorialView.swift` (one-time swipe tutorial presented after first successful profile creation)
- `mushroomHunter/Features/Shared/SmartTextField.swift` (shared auto-select text field wrapper used in create-profile form)
- `mushroomHunter/Features/Shared/SmartTextEditor.swift` (shared auto-select text editor wrapper for multiline form inputs)
- `mushroomHunter/Features/Shared/KeyboardDismissBridge.swift` (shared UIKit bridge for dismissing keyboard on outside taps without scroll interference)
- `mushroomHunter/Features/Shared/MessageBox.swift` (shared custom confirmation/error dialog used by profile create/edit validation)
- `mushroomHunter/User/UserSessionStore.swift` (main session state container)
- `mushroomHunter/User/UserAuth.swift` (Apple/Google auth + auth state handling)
- `mushroomHunter/User/UserProfile.swift` (profile completion persistence/sync)
- `mushroomHunter/App/ContentView.swift` (auth/profile-complete routing)
- `mushroomHunter/App/HoneyHubApp.swift` (URL routing bootstrap)
- `mushroomHunter/Utilities/FriendCode.swift` (shared friend-code sanitize/validate/format utility used by profile create flow)

## Backend
- Auth: Firebase Authentication (Apple + Google)
- Data: Firestore
- Media: Firebase Storage (postcard images)
- Server-side notifications/email: Firebase Cloud Functions (`functions/index.js`)

## Always Build/Install/Run After Code Changes
After any code change, you must build, install, and launch on both connected iPhones (Ken's iPhone and Doris's phone) unless explicitly told to "skip build".
If build/install/launch fails, read errors and fix before handing off.

### Current device and bundle
- Ken's iPhone (CoreDevice UUID): `664E44A2-57C7-5319-B871-EB1D380FBC1B`
- Doris's phone (CoreDevice UUID): `A87D1488-6006-5E4F-9332-A8E6205A4373`
- Build destination device id: `00008150-00021D26028A401C`
- Bundle ID: `com.kenyu.mushroomHunter`
- Project: `/Users/ken/Desktop/mushroomHunter/mushroomHunter.xcodeproj`
- Scheme: `HoneyHub`

### Required commands (in order)
```bash
xcodebuild -project /Users/ken/Desktop/mushroomHunter/mushroomHunter.xcodeproj \
  -scheme HoneyHub -configuration Debug \
  -destination "id=00008150-00021D26028A401C" build

APP_PATH=$(ls -dt /Users/ken/Library/Developer/Xcode/DerivedData/mushroomHunter-*/Build/Products/Debug-iphoneos/HoneyHub.app | head -n 1)

(
  xcrun devicectl device install app --device 664E44A2-57C7-5319-B871-EB1D380FBC1B "$APP_PATH" &&
  xcrun devicectl device process launch --device 664E44A2-57C7-5319-B871-EB1D380FBC1B com.kenyu.mushroomHunter
) &
(
  xcrun devicectl device install app --device A87D1488-6006-5E4F-9332-A8E6205A4373 "$APP_PATH" &&
  xcrun devicectl device process launch --device A87D1488-6006-5E4F-9332-A8E6205A4373 com.kenyu.mushroomHunter
) &
wait
```

## Push To GitHub Workflow
When user says "push to github", do:
1. Stage only files related to this task.
2. Commit with `--signoff`.
3. Push to remote.

Commit message format:
```text
[FIX] <Commit Title>

1. Detail of the changes...
2. Detail of the changes...
3. Detail of the changes...

[Test] Build pass

<optional extra notes>
```

## General Expectations
- Prefer `rg` for search.
- Keep changes minimal and focused.
- Do not reformat unrelated files.
- For two-button UI actions, place the proceed/action button on the left and the cancel button on the right.
- If behavior changes, include app test guidance in handoff.
- After you understand the requirement, please scan through the code first, to check whehther these is code can be re-use(leverage exist function/struct/... etc) to help you write code.
- All files need to contain header comment
- All function/strcture/variable need to have comment
- All comments must be meaningful and explain intent/purpose; placeholder comments are forbidden.
- Do not use generic placeholders such as `// State or dependency property.` or similar non-informative comments.
- All boolean variables naming need to start with "is"

## Automated Testing
- UI test target: `HoneyHubUITests`
- Trigger phrase:
  - If user says `run UT`, run the full UI test suite.
  - Default execution must target Ken's iPhone first (`id=00008150-00021D26028A401C`).
  - If the target iPhone is unavailable (not connected/locked/untrusted), fall back to simulator and report that fallback in the handoff.
- Local UI test command:
```bash
xcodebuild -project /Users/ken/Desktop/mushroomHunter/mushroomHunter.xcodeproj \
  -scheme HoneyHub \
  -destination "platform=iOS Simulator,name=iPhone 17,OS=26.1" \
  -maximum-parallel-testing-workers 1 \
  test
```
- Target iPhone UI test command:
```bash
xcodebuild -project /Users/ken/Desktop/mushroomHunter/mushroomHunter.xcodeproj \
  -scheme HoneyHub \
  -destination "id=00008150-00021D26028A401C" \
  -maximum-parallel-testing-workers 1 \
  test
```
- CI workflow: `/Users/ken/Desktop/mushroomHunter/.github/workflows/ios-ui-tests.yml`
- UI tests launch app with `--ui-testing --mock-rooms --mock-postcards` (no live Firebase dependency).
- UI tests can optionally force deep-link entry with:
  - `--ui-open-room {roomId}`
  - `--ui-open-postcard {postcardId}`
- UI tests can optionally launch a fixture room in joined-attendee state with:
  - `--mock-room-joined`
- Test case documentation: `/Users/ken/Desktop/mushroomHunter/TESTCASE.md`
