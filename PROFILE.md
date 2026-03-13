# Profile

## Related Files
- `mushroomHunter/Features/Profile/ProfileView.swift`: profile container UI, account identity section, edit/settings sheets, help navigation push, feedback success handling, and sign-out action.
- `mushroomHunter/Features/Premium/PremiumView.swift`: profile-linked premium membership screen with benefit copy, current status, subscribe, and restore actions.
- `mushroomHunter/Features/Premium/PremiumStore.swift`: shared StoreKit 2 premium manager that loads the monthly product, observes transaction updates, and syncs entitlements to Firebase.
- `mushroomHunter/Features/Profile/ProfileCreateEditView.swift`: shared profile form used by profile edit and onboarding profile creation.
- `mushroomHunter/Features/Profile/FeedbackView.swift`: in-app feedback compose view and submission payload model.
- `mushroomHunter/Features/Profile/AboutView.swift`: settings-linked about page with app background copy plus Gmail and website support links.
- `mushroomHunter/Features/Tutorial/TutorialCatalogView.swift`: settings-linked tutorial scenario list.
- `mushroomHunter/Features/Mushroom/RoomBrowseView.swift`: first interactive tutorial replay destination (`Mushroom Browse Basics`) using the real browse page.
- `mushroomHunter/Features/EventInbox/EventInboxView.swift`: shared in-app event inbox sheet opened from the profile top-right bell.
- `mushroomHunter/Features/EventInbox/EventInboxStore.swift`: shared Firestore-backed event history state used by the bell badge and inbox list.
- `mushroomHunter/Features/DailyReward/DailyRewardView.swift`: shared DailyReward month sheet opened from the profile top-right calendar icon.
- `mushroomHunter/Features/DailyReward/DailyRewardToolbarActions.swift`: shared calendar + bell toolbar controls used on the profile tab.
- `mushroomHunter/Features/Shared/TopActionBar.swift`: shared top action bar in honey+stars display mode.
- `mushroomHunter/Features/Shared/MessageBox.swift`: shared confirmation/success dialog used by feedback/profile flows.
- `mushroomHunter/Services/Firebase/FeedbackRepo.swift`: writes feedback payloads to Firestore `feedbackSubmissions`.
- `mushroomHunter/App/ContentView.swift`: app icon badge sync, global DailyReward sheet routing, and tab routing.
- `mushroomHunter/User/UserSessionStore.swift`: shared session state and DailyReward pending-state store.
- `mushroomHunter/Utilities/AppConfig.swift`: premium product id, premium DailyReward amount, and premium room-limit constants.

## Feature Coverage
- Profile tab now focuses on account management only:
  - Display name and friend code (read-only identity rows) appear in the first block without a visible section title.
  - Top-right calendar entry opens the shared DailyReward sheet.
  - The shared calendar icon shows a red dot whenever today's Taipei DailyReward is still unclaimed.
  - Top-right bell entry opens the shared event inbox sheet.
  - Profile form can expose an `Upgrade to Premium` / `升級為高級會員` row above `Settings` when `AppConfig.Premium.isPremiumEntryEnabled` is turned on.
  - When the premium row is enabled, tapping it opens a dedicated membership sheet that shows:
    - active/free status,
    - monthly StoreKit price,
    - premium benefits,
    - subscribe action,
    - restore purchases action,
    - terms/privacy links.
  - Top-right settings icon was removed.
  - `Settings` button now appears in the form section above `Sign Out`, opens the same settings sheet as before, and uses localized text (`settings_title`).
  - Settings sheet top-left dismiss control now uses back chevron icon (`chevron.left`) instead of close `X`.
  - Settings routes now include `Edit Profile`, `Feedback`, `Help`, and `About`.
  - `Help` now dismisses settings and pushes tutorial scenario list inside the Profile tab navigation stack so replay pages stay in the root `TabView` context.
  - During feature tutorials, bottom tab bar stays visible but tab switching is locked until tutorial completes.
  - Sign-out action now shows a confirmation dialog (`Are you sure you want to sign out?`) before session sign-out executes.
  - About page now removes the phone row and the old `聯絡資訊` header, adds a multiline app-introduction section, and keeps Gmail plus website as the remaining support links.
- Mushroom and postcard owned activity lists were removed from profile and moved into browse tabs:
  - Mushroom browse pins user `Joined` and `Host` rooms at the top with ownership tags.
  - Postcard browse pins user `On-shelf` and `Ordered` postcards at the top with ownership tags.
- Profile tab no longer shows any legacy actionable badge count.
- App icon badge is recomputed from unresolved non-DailyReward Action Events plus `1` when today's Taipei DailyReward is still pending.
- Premium subscription state is refreshed from StoreKit on app launch/auth changes and then synced to Firebase-backed profile state:
  - `users/{uid}.isPremium`
  - `users/{uid}.premiumSource`
  - `users/{uid}.premiumProductId`
  - `users/{uid}.premiumExpirationAt`
  - `users/{uid}.premiumLastVerifiedAt`
  - effective `maxHostRoom` / `maxJoinRoom`
- Signed-in session state now keeps a live Firestore listener on `users/{uid}` so honey/stars/profile fields update in-app when backend transactions change them.
- Profile bootstrap no longer overwrites authoritative backend counters like `stars` or `honey` from stale local cache; first-session ensure writes only create missing fields.
- Premium benefits currently include:
  - DailyReward increases from `10` honey to `30` honey while premium is active.
  - Mushroom host room limit increases from `1` to `5`.
  - Mushroom joined-room limit increases from `3` to `10`.
  - Mushroom settlement payouts and postcard seller payouts are unchanged by premium.
- Profile edits and wallet changes now generate per-user event-history rows (`users/{uid}/events`) so bell Events includes:
  - display-name updates,
  - friend-code updates,
  - honey balance deltas (spend/gain/refund from room/postcard flows).
- UI testing mode (`--ui-testing`) keeps profile backend reads/writes disabled for deterministic offline test execution.
- Shared `MessageBox` centers its message text content.

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
