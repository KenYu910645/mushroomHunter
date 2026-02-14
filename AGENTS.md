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

If signed out, users see the sign-in flow. First-time users must complete profile creation.

## Documentation Map (Must Keep In Sync)
Use and maintain these files when related code changes:
- `AGENTS.md`: execution workflow, build/run rules, repo-level constraints.
- `MUSHROOM.md`: mushroom room lifecycle, attendee states, room invite/share flow.
- `POSTCARD.md`: postcard marketplace, listing/order lifecycle, shipping/receipt behavior.
- `PROFILE.md`: profile editing, settings, feedback/about, profile-owned content views.
- `SIGNIN.md`: authentication and first-time onboarding/profile-completion behavior.

Rule: any code change that affects behavior must update the relevant markdown file(s) above.

## File Structure By Feature
This is the source-of-truth feature map. Keep it updated whenever files are added/moved.

### MUSHROOM (`MUSHROOM.md`)
- `mushroomHunter/Features/Mushroom/BrowseView.swift`
- `mushroomHunter/Features/Mushroom/HostView.swift`
- `mushroomHunter/Features/Mushroom/RoomDetailsView.swift`
- `mushroomHunter/Features/Mushroom/RoomDetailsSubViews.swift`
- `mushroomHunter/Features/Mushroom/RoomDetailsViewModel.swift`
- `mushroomHunter/Features/Mushroom/RoomDetailsModels.swift`
- `mushroomHunter/Services/Firebase/FirebaseBrowseRepository.swift`
- `mushroomHunter/Services/Firebase/FirebaseHostRepository.swift`
- `mushroomHunter/Services/Firebase/FirebaseRoomDetailsRepository.swift`
- `mushroomHunter/Services/Firebase/FirebaseRoomActionsRepository.swift`
- `mushroomHunter/Utilities/RoomInviteLink.swift`
- Cloud Functions in `functions/index.js`:
  - `sendRaidConfirmationPush`
  - `notifyHostRaidConfirmationResult`

### POSTCARD (`POSTCARD.md`)
- `mushroomHunter/Features/Postcard/PostcardTabView.swift`
- `mushroomHunter/Features/Postcard/PostcardBrowseViewModel.swift`
- `mushroomHunter/Features/Postcard/PostcardModels.swift`
- `mushroomHunter/Services/Firebase/FirebasePostcardRepository.swift`
- `mushroomHunter/Services/Firebase/FirebasePostcardImageUploader.swift`
- `mushroomHunter/Utilities/SearchTokens.swift`
- Cloud Functions in `functions/index.js`:
  - `sendPostcardOrderCreatedPush`
  - `sendPostcardShippedPush`
  - `notifySellerPostcardCompleted`

### PROFILE (`PROFILE.md`)
- `mushroomHunter/Features/Profile/ProfileView.swift`
- `mushroomHunter/Services/Firebase/FirebaseProfileHostRepository.swift`
- `mushroomHunter/Session/SessionStore.swift` (profile fields, user sync, honey/stars sync)
- Cloud Functions in `functions/index.js`:
  - `sendFeedbackNotificationEmail`

### SIGNIN (`SIGNIN.md`)
- `mushroomHunter/Features/Profile/LoginView.swift`
- `mushroomHunter/Features/Profile/CreateProfileView.swift`
- `mushroomHunter/Session/SessionStore.swift` (Apple/Google auth + profile completion)
- `mushroomHunter/App/ContentView.swift` (auth/profile-complete routing)
- `mushroomHunter/App/mushroomHunterApp.swift` (URL routing bootstrap)

## Backend
- Auth: Firebase Authentication (Apple + Google)
- Data: Firestore
- Media: Firebase Storage (postcard images)
- Server-side notifications/email: Firebase Cloud Functions (`functions/index.js`)

## Always Build/Install/Run After Code Changes
After any code change, you must build, install, and launch on Ken's connected iPhone unless explicitly told to "skip build".
If build/install/launch fails, read errors and fix before handing off.

### Current device and bundle
- Device (CoreDevice UUID): `664E44A2-57C7-5319-B871-EB1D380FBC1B` (Ken's iPhone)
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

xcrun devicectl device install app --device 664E44A2-57C7-5319-B871-EB1D380FBC1B "$APP_PATH"
xcrun devicectl device process launch --device 664E44A2-57C7-5319-B871-EB1D380FBC1B com.kenyu.mushroomHunter
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
- If behavior changes, include app test guidance in handoff.

## Automated Testing
- UI test target: `HoneyHubUITests`
- Local UI test command:
```bash
xcodebuild -project /Users/ken/Desktop/mushroomHunter/mushroomHunter.xcodeproj \
  -scheme HoneyHub \
  -destination "platform=iOS Simulator,name=iPhone 17,OS=26.1" \
  -maximum-parallel-testing-workers 1 \
  test
```
- CI workflow: `/Users/ken/Desktop/mushroomHunter/.github/workflows/ios-ui-tests.yml`
- UI tests launch app with `--ui-testing --mock-rooms` (no live Firebase dependency).
