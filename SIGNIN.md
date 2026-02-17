# Signin

## Related Files
- `mushroomHunter/Features/Profile/LoginView.swift`: sign-in UI for Apple and Google login entry points.
- `mushroomHunter/Features/Profile/CreateProfileView.swift`: first-time profile completion form (name + 12-digit friend code).
- `mushroomHunter/Features/Shared/SelectAllTextField.swift`: shared auto-select text field wrapper used by the create-profile form fields.
- `mushroomHunter/Session/SessionStore.swift`: authentication, auth state handling, and profile-complete persistence/sync.
- `mushroomHunter/App/ContentView.swift`: app root routing between login, create-profile, and main tabs.
- `mushroomHunter/App/mushroomHunterApp.swift`: app bootstrap and URL/open handling for auth and deep links.

## Feature Coverage
- Supported providers:
  - Apple Sign-In
  - Google Sign-In
- Auth state routing:
  - Signed out -> `LoginView`
  - Signed in but profile incomplete -> `CreateProfileView`
  - Signed in and profile complete -> main tab flow
- First-time user profile completion:
  - Requires display name and 12-digit friend code
  - Saves into Firestore `users/{uid}` and local state
  - Sets `profileComplete = true`

## Related Implementation
- `mushroomHunter/Features/Profile/LoginView.swift`
- `mushroomHunter/Features/Profile/CreateProfileView.swift`
- `mushroomHunter/Session/SessionStore.swift`
- `mushroomHunter/App/ContentView.swift`

## Notes
- Current code does not implement a separate swipe-card onboarding/tutorial screen.
- No dedicated Cloud Function is owned by signin flow right now.
