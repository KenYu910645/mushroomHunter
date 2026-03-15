# Signin

## Related Files
- `mushroomHunter/Features/Profile/LoginView.swift`: sign-in UI for Apple and Google login entry points.
- `mushroomHunter/Features/Profile/ProfileCreateEditView.swift`: shared profile form; signin flow uses create mode for first-time profile completion (name + 12-digit friend code).
- `mushroomHunter/Features/Tutorial/TutorialCatalogView.swift`: tutorial scenario list opened from Profile -> Settings -> Help.
- `mushroomHunter/Features/Mushroom/RoomBrowseView.swift`: first implemented interactive tutorial scene (Mushroom browse) rendered on the real browse UI.
- `mushroomHunter/Features/Shared/SmartTextField.swift`: shared auto-select text field wrapper used by the create-profile form fields.
- `mushroomHunter/Features/Shared/KeyboardDismissBridge.swift`: shared UIKit bridge used by profile create form to dismiss keyboard on outside taps without collapsing during scroll.
- `mushroomHunter/User/UserSessionStore.swift`: shared user session state container.
- `mushroomHunter/User/UserAuth.swift`: authentication and auth state handling.
- `mushroomHunter/User/UserProfile.swift`: profile-complete persistence/sync.
- `mushroomHunter/Utilities/FriendCode.swift`: shared friend-code sanitizing/formatting/validation utility used by profile create flow.
- `mushroomHunter/App/ContentView.swift`: app root routing between login, profile-form create mode, and main tabs.
- `mushroomHunter/App/HoneyHubApp.swift`: app bootstrap and URL/open handling for auth and deep links.

## Feature Coverage
- Supported providers:
  - Apple Sign-In
  - Google Sign-In
- Sign-in page presentation:
  - Uses the app honey icon (`HoneyIcon` asset) as the branded hero icon.
  - Uses a rounded auth card layout on top of the shared honey-toned background gradient.
  - Displays a localized subtitle under the `HoneyHub` title for clearer onboarding context.
  - Styles the Google sign-in button with a solid Google-brand blue fill for stronger entry visibility.
- Auth state routing:
  - Signed out -> `LoginView`
  - Signed in but profile incomplete -> `ProfileCreateEditView(mode: .create)`
  - Signed in and profile complete -> main tab flow
- First-time user profile completion:
  - Requires display name and 12-digit friend code
  - Focused form inputs auto-scroll above keyboard overlap; single-line input keyboard dismisses on `Enter`.
  - Create-profile form dismisses keyboard on outside taps (without collapsing during scroll) and includes keyboard toolbar `Done`.
  - Saves into Firestore `users/{uid}` and local state.
  - The onboarding save path repairs partial auth/bootstrap user docs so required wallet/profile defaults always exist, including `honey`, `stars`, room-limit fields, premium fields, locale, and timestamps.
  - Sets `isProfileComplete = true`
  - Does not auto-open a static swipe tutorial anymore.
  - Interactive tutorials are now scenario-based and triggered contextually when users first enter relevant feature pages.
  - During first-login handoff into the initial Mushroom browse tutorial, the root tab bar is hidden before the tab shell appears so the tutorial `Back`/`Next` controls stay unobstructed.

## Related Implementation
- `mushroomHunter/Features/Profile/LoginView.swift`
- `mushroomHunter/Features/Profile/ProfileCreateEditView.swift`
- `mushroomHunter/Features/Tutorial/TutorialCatalogView.swift`
- `mushroomHunter/Features/Mushroom/RoomBrowseView.swift`
- `mushroomHunter/User/UserSessionStore.swift`
- `mushroomHunter/User/UserAuth.swift`
- `mushroomHunter/User/UserProfile.swift`
- `mushroomHunter/App/ContentView.swift`

## Notes
- Tutorial replay entry remains at Profile -> Settings -> Help, now opening a scenario list instead of one static swipe pager.
- No dedicated Cloud Function is owned by signin flow right now.
