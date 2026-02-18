# Signin

## Related Files
- `mushroomHunter/Features/Profile/LoginView.swift`: sign-in UI for Apple and Google login entry points.
- `mushroomHunter/Features/Profile/ProfileFormView.swift`: shared profile form; signin flow uses create mode for first-time profile completion (name + 12-digit friend code).
- `mushroomHunter/Features/Profile/TutorialView.swift`: one-time swipe tutorial shown after first successful profile creation.
- `mushroomHunter/Features/Shared/SelectAllTextField.swift`: shared auto-select text field wrapper used by the create-profile form fields.
- `mushroomHunter/User/UserSessionStore.swift`: shared user session state container.
- `mushroomHunter/User/UserAuth.swift`: authentication and auth state handling.
- `mushroomHunter/User/UserProfile.swift`: profile-complete persistence/sync.
- `mushroomHunter/Utilities/FriendCode.swift`: shared friend-code sanitizing/formatting/validation utility used by profile create flow.
- `mushroomHunter/App/ContentView.swift`: app root routing between login, profile-form create mode, and main tabs.
- `mushroomHunter/App/mushroomHunterApp.swift`: app bootstrap and URL/open handling for auth and deep links.

## Feature Coverage
- Supported providers:
  - Apple Sign-In
  - Google Sign-In
- Auth state routing:
  - Signed out -> `LoginView`
  - Signed in but profile incomplete -> `ProfileFormView(mode: .create)`
  - Signed in and profile complete -> main tab flow
- First-time user profile completion:
  - Requires display name and 12-digit friend code
  - Saves into Firestore `users/{uid}` and local state
  - Sets `profileComplete = true`
  - Immediately presents a one-time full-screen swipe tutorial after successful create-profile submit.
  - Tutorial card order:
    1. Honey & Stars
    2. Join Mushroom Rooms
    3. Host a Room
    4. Postcard Market
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
- Tutorial is only triggered from first-time profile creation (`ProfileSaveSource.onboarding`) and not from profile edit.
- No dedicated Cloud Function is owned by signin flow right now.
