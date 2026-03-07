# Profile

## Related Files
- `mushroomHunter/Features/Profile/ProfileView.swift`: profile container UI, account identity section, edit/settings sheets, help navigation push, feedback success handling, and sign-out action.
- `mushroomHunter/Features/Profile/ProfileCreateEditView.swift`: shared profile form used by profile edit and onboarding profile creation.
- `mushroomHunter/Features/Profile/FeedbackView.swift`: in-app feedback compose view and submission payload model.
- `mushroomHunter/Features/Profile/AboutView.swift`: settings-linked about page with contact links.
- `mushroomHunter/Features/Tutorial/TutorialCatalogView.swift`: settings-linked tutorial scenario list.
- `mushroomHunter/Features/Mushroom/RoomBrowseView.swift`: first interactive tutorial replay destination (`Mushroom Browse Basics`) using the real browse page.
- `mushroomHunter/Features/EventInbox/EventInboxView.swift`: shared in-app event inbox sheet opened from the profile top-right bell.
- `mushroomHunter/Features/EventInbox/EventInboxStore.swift`: shared Firestore-backed event history state used by the bell badge and inbox list.
- `mushroomHunter/Features/Shared/TopActionBar.swift`: shared top action bar in honey+stars display mode.
- `mushroomHunter/Features/Shared/MessageBox.swift`: shared confirmation/success dialog used by feedback/profile flows.
- `mushroomHunter/Services/Firebase/FeedbackRepo.swift`: writes feedback payloads to Firestore `feedbackSubmissions`.
- `mushroomHunter/Services/Firebase/ProfileListRepo.swift`: hosted/joined room summary reads used for profile badge aggregation and mushroom browse pinning.
- `mushroomHunter/Services/Firebase/PostcardRepo.swift`: on-shelf/ordered postcard reads used for profile badge aggregation and postcard browse pinning.
- `mushroomHunter/App/ContentView.swift`: app icon badge sync and tab routing.
- `mushroomHunter/User/UserSessionStore.swift`: shared session state and badge count store.

## Feature Coverage
- Profile tab now focuses on account management only:
  - Display name and friend code (read-only identity rows).
  - Top-right bell entry opens the shared event inbox sheet.
  - Top-right settings icon was removed.
  - `Settings` button now appears in the form section above `Sign Out`, opens the same settings sheet as before, and uses localized text (`settings_title`).
  - Settings routes now include `Edit Profile`, `Feedback`, `Help`, and `About`.
  - `Help` now dismisses settings and pushes tutorial scenario list inside the Profile tab navigation stack so replay pages stay in the root `TabView` context.
  - During feature tutorials, bottom tab bar stays visible but tab switching is locked until tutorial completes.
  - Sign-out action now shows a confirmation dialog (`Are you sure you want to sign out?`) before session sign-out executes.
- Mushroom and postcard owned activity lists were removed from profile and moved into browse tabs:
  - Mushroom browse pins user `Joined` and `Host` rooms at the top with ownership tags.
  - Postcard browse pins user `On-shelf` and `Ordered` postcards at the top with ownership tags.
- Profile actionable badge totals are refreshed by app-root tab logic in `ContentView` using Firebase repositories.
- Profile edits and wallet changes now generate per-user event-history rows (`users/{uid}/events`) so bell Events includes:
  - display-name updates,
  - friend-code updates,
  - honey balance deltas (spend/gain/refund from room/postcard flows).
- UI testing mode (`--ui-testing`) keeps profile backend reads/writes disabled for deterministic offline test execution.

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
