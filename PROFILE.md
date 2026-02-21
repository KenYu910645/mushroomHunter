# Profile

## Related Files
- `mushroomHunter/Features/Profile/ProfileView.swift`: profile container UI, account/community/sign-out sections, top-right edit-profile sheet entry, settings sheet routing, and feedback success handling.
- `mushroomHunter/Features/Profile/ProfileFormView.swift`: shared profile form used by profile edit sheet (edit mode) and signin profile completion (create mode).
- `mushroomHunter/Features/Profile/ProfileViewModel.swift`: profile tab view model for joined/hosted room and postcard list loading/error state.
- `mushroomHunter/Features/Profile/ProfileMushroom.swift`: joined/hosted mushroom list sections used by profile.
- `mushroomHunter/Features/Profile/ProfilePostcard.swift`: on-shelf/ordered postcard list sections and shared postcard summary row used by profile.
- `mushroomHunter/Features/Profile/ProfileSectionStateView.swift`: shared loading/error/empty/content state renderer reused by profile list sections.
- `mushroomHunter/Features/Profile/FeedbackView.swift`: in-app feedback compose view and submission payload model.
- `mushroomHunter/Features/Profile/AboutView.swift`: settings-linked about page with phone/email/website links.
- `mushroomHunter/Features/Shared/SelectAllTextField.swift`: shared `UITextField` bridge used by profile edit/create and mushroom host forms (select-all on focus, keyboard/input configuration).
- `mushroomHunter/Features/Shared/SelectAllTextEditor.swift`: shared `UITextView` bridge used by multiline fields (select-all on focus).
- `mushroomHunter/Features/Shared/HoneyMessageBox.swift`: shared custom confirmation/error dialog used by profile and feedback screens.
- `mushroomHunter/Services/Firebase/ProfileListRepo.swift`: Firestore queries for hosted/joined mushroom rooms shown in profile.
- `mushroomHunter/Services/Firebase/FeedbackRepo.swift`: writes in-app feedback submissions to Firestore `feedbackSubmissions`.
- `mushroomHunter/Services/Firebase/PostcardRepo.swift`: Firestore queries for on-shelf and ordered postcards shown in profile.
- `mushroomHunter/User/UserSessionStore.swift`: shared user session state container.
- `mushroomHunter/User/UserAuth.swift`: authentication methods for the shared session container.
- `mushroomHunter/User/UserProfile.swift`: profile state storage and sync (display name, friend code, limits, tokens).
- `mushroomHunter/User/UserWallet.swift`: stars/honey state helpers.
- `mushroomHunter/Utilities/AppConfig.swift`: centralized owner-managed profile constraints (friend code length) and shared list limits.
- `mushroomHunter/Utilities/AppDataCache.swift`: shared app-level memory+disk Codable cache used by profile list stale-first loading.
- `mushroomHunter/Utilities/FriendCode.swift`: shared friend-code sanitizing/formatting/validation utility used by profile create/edit and displays.
- `functions/index.js`: server-side email trigger for profile feedback submissions.

## Feature Coverage
- User can view and edit profile data:
  - Display name
  - Friend code
  - Stars/reputation (displayed community value)
- Profile identity values are read-only in profile section rows; editing is triggered by the top-right pencil button and presented in a dedicated edit-profile sheet.
- Profile tab top area now uses shared `BrowseViewTopActionBar` in honey-only mode (no search/create actions).
- Profile top action bar is rendered inside the scrolling form content so it moves with the page while scrolling.
- Community section no longer includes a separate honey row.
- Profile tab includes user-related content views:
  - Joined mushroom rooms
  - Hosted mushroom rooms
  - On-shelf postcards
  - Ordered postcards
- Joined mushroom room rows now show the attendee status directly in profile (`Host`, `Asking to join`, `Ready`, `Waiting confirmation`, `Rejected`) so users can instantly see their room state.
- Joined mushroom room statuses are highlighted with rounded-rectangle badges and urgency color coding:
  - `Ready`: green
  - `Asking to join` / `Waiting confirmation`: yellow-orange
  - `Rejected`: red
  - `Host`: blue
- Profile postcard rows display status text on the right side (stock count hidden in profile lists):
  - On-shelf section:
    - `Order Received` when seller has unprocessed queue items (`SellerConfirmPending` / `AwaitingShipping` and legacy `AwaitingSellerSend`) for that listing.
    - `On-shelf` when no unprocessed queue item exists.
  - Ordered section:
    - `Wait for shipping` for `SellerConfirmPending` / `AwaitingShipping`
    - `Shipped, on-the-way` for `Shipped`
- Profile postcard statuses also use rounded-rectangle urgency badges:
  - `On-shelf`: green
  - `Order Received`: yellow-orange
  - `Wait for shipping`: yellow-orange
  - `Shipped, on-the-way`: blue
- Settings includes:
  - `Feedback`: opens in-app compose sheet (subject/message) and submits to Firestore `feedbackSubmissions`.
  - `Help`: opens the in-app tutorial walkthrough (`TutorialView`) so users can revisit onboarding guidance anytime.
  - `About`: shows contact information (phone, email, website).
- Profile validation, feedback success, and feedback error prompts use shared `HoneyMessageBox` to keep messaging UI consistent with Mushroom/Postcard flows.
- Feedback compose subject and message both auto-select existing text on focus.
- Profile hosted-room loading queries `rooms.hostUid`; joined-room loading uses UID-scoped attendee queries.
- Profile/token sync paths now apply write guards in session scope to skip duplicate `users/{uid}` writes when values have not changed.
- FCM token sync also refreshes hosted room snapshots (`rooms.hostFcmToken` and host attendee `fcmToken`) so mushroom push flows can avoid per-push user reads.
- Profile room/postcard sections now use app-level stale-first cache:
  - Opening Profile loads cached hosted/joined/on-shelf/ordered lists first.
  - Pull-to-refresh forces latest Firestore queries and overwrites profile list cache.
  - Hosted room close callback forces hosted-room refresh to keep host list consistent after room lifecycle actions.
- UI testing mode (`--ui-testing`) disables profile Firestore reads/writes/sync paths so UI automation is fully offline from backend dependencies.

## Cloud Functions (Profile Use Cases)
- `sendFeedbackNotificationEmail`
  - Trigger: create on `feedbackSubmissions/{feedbackId}`
  - Sends one SMTP email per feedback submission
  - Defaults:
    - recipient `FEEDBACK_TO` -> `kenyu910645@gmail.com` if unset
  - Required env vars: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`
  - Optional env vars: `SMTP_SECURE`, `FEEDBACK_FROM`

#### `feedbackSubmissions/{feedbackId}`
User feedback submitted from profile settings.
Fields:
- `userId` (String): sender uid (resolved from `UserSessionStore.authUid`, fallback to `Auth.auth().currentUser?.uid`).
- `displayName` (String): sender display name snapshot.
- `friendCode` (String): sender friend code snapshot.
- `subject` (String): feedback subject (fallback defaults to `HoneyHub Feedback`).
- `message` (String): feedback message body.
- `appVersion` (String): app short version.
- `buildNumber` (String): app build number.
- `bundleId` (String): app bundle identifier.
- `localeIdentifier` (String): current device locale id.
- `platform` (String): client platform (`iOS`).
- `createdAt` (Timestamp): feedback creation time.
