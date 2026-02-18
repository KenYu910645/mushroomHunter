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
- `mushroomHunter/Features/Mushroom/RoomBrowseView.swift`
- `mushroomHunter/Features/Mushroom/RoomBrowseViewModel.swift`
- `mushroomHunter/Features/Mushroom/RoomFormView.swift`
- `mushroomHunter/Features/Mushroom/RoomView.swift`
- `mushroomHunter/Features/Mushroom/RoomView.swift` (contains room-specific invite sheet wrapper for room flow)
- `mushroomHunter/Features/Shared/InviteShareSheet.swift` (shared invite QR sheet used by room/postcard)
- `mushroomHunter/Features/Mushroom/RoomViewModel.swift`
- `mushroomHunter/Features/Mushroom/RoomDomainModels.swift`
- `mushroomHunter/Features/Shared/BrowseViewTopActionBar.swift` (shared browse header with honey/search/create actions)
- `mushroomHunter/Features/Shared/SelectAllTextField.swift` (shared auto-select text field wrapper used by host/profile/profile-create forms)
- `mushroomHunter/Features/Shared/SelectAllTextEditor.swift` (shared auto-select text editor wrapper used by multiline inputs)
- `mushroomHunter/Services/Firebase/RoomBrowseRepo.swift`
- `mushroomHunter/Services/Firebase/RoomFormRepo.swift`
- `mushroomHunter/Services/Firebase/RoomRepo.swift`
- `mushroomHunter/Services/Firebase/RoomActionsRepo.swift`
- `mushroomHunter/Utilities/RoomInviteLink.swift`
- `mushroomHunter/Utilities/AppConfig.swift` (owner-managed mushroom defaults, limits, and option sets)
- `mushroomHunter/Utilities/FriendCode.swift` (shared friend-code sanitize/validate/format utility used by profile/room/postcard)
- Cloud Functions in `functions/index.js`:
  - `sendRaidConfirmationPush`
  - `notifyHostRaidConfirmationResult`

### POSTCARD (`POSTCARD.md`)
- `mushroomHunter/Features/Postcard/PostcardBrowseView.swift`
- `mushroomHunter/Features/Postcard/PostcardView.swift`
- `mushroomHunter/Features/Postcard/PostcardShippingView.swift`
- `mushroomHunter/Features/Postcard/PostcardFormView.swift`
- `mushroomHunter/Features/Postcard/PostcardBrowseViewModel.swift`
- `mushroomHunter/Features/Postcard/PostcardDomainModel.swift`
- `mushroomHunter/App/mushroomHunterApp.swift` (postcard invite deep-link routing)
- `mushroomHunter/App/ContentView.swift` (postcard invite deep-link presentation)
- `mushroomHunter/Features/Shared/BrowseViewTopActionBar.swift` (shared browse header with honey/search/create actions)
- `mushroomHunter/Features/Shared/SelectAllTextField.swift` (shared auto-select text field wrapper used by postcard/profile/mushroom forms)
- `mushroomHunter/Features/Shared/SelectAllTextEditor.swift` (shared auto-select text editor wrapper used by postcard description fields)
- `mushroomHunter/Features/Shared/InviteShareSheet.swift` (shared invite QR sheet used by postcard seller share flow)
- `mushroomHunter/Services/Firebase/PostcardRepo.swift`
- `mushroomHunter/Services/Firebase/PostcardImageUploader.swift`
- `mushroomHunter/Utilities/RoomInviteLink.swift` (postcard invite link generation/parsing)
- `mushroomHunter/Utilities/SearchTokens.swift`
- `mushroomHunter/Utilities/AppConfig.swift` (owner-managed postcard caps, list limits, and timeout windows)
- `mushroomHunter/Utilities/FriendCode.swift` (shared friend-code sanitize/validate/format utility used by profile/room/postcard)
- Cloud Functions in `functions/index.js`:
  - `sendPostcardOrderCreatedPush`
  - `sendPostcardShippedPush`
  - `notifySellerPostcardCompleted`

### PROFILE (`PROFILE.md`)
- `mushroomHunter/Features/Profile/ProfileView.swift`
- `mushroomHunter/Features/Profile/ProfileFormView.swift` (shared create/edit profile form presented from onboarding and profile edit sheet)
- `mushroomHunter/Features/Profile/ProfileViewModel.swift` (profile tab room/postcard list loading and error state orchestration)
- `mushroomHunter/Features/Profile/ProfileMushroom.swift` (joined/hosted mushroom section views extracted from profile)
- `mushroomHunter/Features/Profile/ProfilePostcard.swift` (on-shelf/ordered postcard section views extracted from profile)
- `mushroomHunter/Features/Profile/ProfileSectionStateView.swift` (shared loading/error/empty/content renderer for profile list sections)
- `mushroomHunter/Features/Profile/FeedbackView.swift` (feedback compose view + submission payload model)
- `mushroomHunter/Features/Profile/AboutView.swift` (about page contact information view)
- `mushroomHunter/Features/Shared/SelectAllTextField.swift` (shared auto-select text field wrapper used by profile edit/create)
- `mushroomHunter/Features/Shared/SelectAllTextEditor.swift` (shared auto-select text editor wrapper used by profile feedback message)
- `mushroomHunter/Services/Firebase/ProfileListRepo.swift`
- `mushroomHunter/Services/Firebase/FeedbackRepo.swift`
- `mushroomHunter/User/UserSessionStore.swift` (shared user session state container + local persistence helpers)
- `mushroomHunter/User/UserAuth.swift` (auth lifecycle and sign-in/sign-out flows)
- `mushroomHunter/User/UserProfile.swift` (profile fields, user sync, token sync)
- `mushroomHunter/User/UserWallet.swift` (honey/stars state helpers)
- `mushroomHunter/Utilities/AppConfig.swift` (owner-managed profile validation and shared limits)
- `mushroomHunter/Utilities/FriendCode.swift` (shared friend-code sanitize/validate/format utility used by profile form and display)
- Cloud Functions in `functions/index.js`:
  - `sendFeedbackNotificationEmail`

### SIGNIN (`SIGNIN.md`)
- `mushroomHunter/Features/Profile/LoginView.swift`
- `mushroomHunter/Features/Profile/ProfileFormView.swift` (shared create/edit profile form, signin flow uses create mode)
- `mushroomHunter/Features/Shared/SelectAllTextField.swift` (shared auto-select text field wrapper used in create-profile form)
- `mushroomHunter/Features/Shared/SelectAllTextEditor.swift` (shared auto-select text editor wrapper for multiline form inputs)
- `mushroomHunter/User/UserSessionStore.swift` (main session state container)
- `mushroomHunter/User/UserAuth.swift` (Apple/Google auth + auth state handling)
- `mushroomHunter/User/UserProfile.swift` (profile completion persistence/sync)
- `mushroomHunter/App/ContentView.swift` (auth/profile-complete routing)
- `mushroomHunter/App/mushroomHunterApp.swift` (URL routing bootstrap)
- `mushroomHunter/Utilities/FriendCode.swift` (shared friend-code sanitize/validate/format utility used by profile create flow)

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
- After you understand the requirement, please scan through the code first, to check whehther these is code can be re-use(leverage exist function/struct/... etc) to help you write code.
- All files need to contain header comment
- All function/strcture/variable need to have comment
- All comments must be meaningful and explain intent/purpose; placeholder comments are forbidden.
- Do not use generic placeholders such as `// State or dependency property.` or similar non-informative comments.
- All boolean variables naming need to start with "is"



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
