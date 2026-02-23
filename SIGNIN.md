# Signin

## Related Files
- `mushroomHunter/Features/Profile/LoginView.swift`: sign-in UI for Apple and Google login entry points.
- `mushroomHunter/Features/Profile/ProfileFormView.swift`: shared profile form; signin flow uses create mode for first-time profile completion (name + 12-digit friend code).
- `mushroomHunter/Features/Profile/TutorialView.swift`: one-time swipe tutorial shown after first successful profile creation.
- `mushroomHunter/Features/Shared/SelectAllTextField.swift`: shared auto-select text field wrapper used by the create-profile form fields.
- `mushroomHunter/Features/Shared/OutsideTapKeyboardDismissBridge.swift`: shared UIKit bridge used by profile create form to dismiss keyboard on outside taps without collapsing during scroll.
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
  - Signed in but profile incomplete -> `ProfileFormView(mode: .create)`
  - Signed in and profile complete -> main tab flow
- First-time user profile completion:
  - Requires display name and 12-digit friend code
  - Focused form inputs auto-scroll above keyboard overlap; single-line input keyboard dismisses on `Enter`.
  - Create-profile form dismisses keyboard on outside taps (without collapsing during scroll) and includes keyboard toolbar `Done`.
  - Saves into Firestore `users/{uid}` and local state
  - Sets `profileComplete = true`
  - Immediately presents a one-time full-screen swipe tutorial after successful create-profile submit.
  - Tutorial card order:
    1. Mushroom
    2. Postcard
    3. Profile
  - Tutorial card body uses an enlarged annotated screenshot with description text only (no extra title below image).
  - Tutorial cards support screenshot overlays with circles, arrows, and text labels rendered in-app.
  - Tutorial callouts now support both circle and rectangle highlights.
  - Tutorial annotation highlights and text labels use a unified red style across all cards.
  - Tutorial navigation text, descriptions, and callout labels are localized via `Localizable.strings` keys.
  - Arrow geometry is auto-generated from label location to nearest highlight border, so tuning only needs:
    - highlight location
    - highlight size
    - label location
  - Screenshot assets expected by default template: `Mushroom`, `Postcard`, `Profile`.
  - Tutorial layout reserves space above the pager indicator so screenshot content does not overlap page dots.
  - Tutorial supports `Skip`, `Next`, and `Get Started`.
  - Completion/skip is persisted per user (`UserDefaults` scoped by uid) so it is shown only once.

## Related Implementation
- `mushroomHunter/Features/Profile/LoginView.swift`
- `mushroomHunter/Features/Profile/ProfileFormView.swift`
- `mushroomHunter/Features/Profile/TutorialView.swift`
- `mushroomHunter/User/UserSessionStore.swift`
- `mushroomHunter/User/UserAuth.swift`
- `mushroomHunter/User/UserProfile.swift`
- `mushroomHunter/App/ContentView.swift`

## Notes
- Tutorial is auto-triggered from first-time profile creation (`ProfileSaveSource.onboarding`) and can also be opened later from Profile -> Settings -> Help.
- No dedicated Cloud Function is owned by signin flow right now.
