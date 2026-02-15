# Profile

## Related Files
- `mushroomHunter/Features/Profile/ProfileView.swift`: profile UI, settings, feedback compose, about page, and user-owned content sections.
- `mushroomHunter/Features/Profile/ProfileTextField.swift`: reusable `UITextField` bridge used by profile edit/create screens (select-all on focus, keyboard/input configuration).
- `mushroomHunter/Services/Firebase/FirebaseProfileHostRepository.swift`: Firestore queries for hosted/joined mushroom rooms shown in profile.
- `mushroomHunter/Services/Firebase/FirebaseFeedbackRepository.swift`: writes in-app feedback submissions to Firestore `feedbackSubmissions`.
- `mushroomHunter/Services/Firebase/FirebasePostcardRepository.swift`: Firestore queries for on-shelf and ordered postcards shown in profile.
- `mushroomHunter/Session/SessionStore.swift`: profile state storage and sync (display name, friend code, stars, honey, limits, tokens).
- `functions/index.js`: server-side email trigger for profile feedback submissions.

## Feature Coverage
- User can view and edit profile data:
  - Display name
  - Friend code
  - Stars/reputation (displayed community value)
- Profile tab includes user-related content views:
  - Joined mushroom rooms
  - Hosted mushroom rooms
  - On-shelf postcards
  - Ordered postcards
- Settings includes:
  - `Feedback`: opens in-app compose sheet (subject/message) and submits to Firestore `feedbackSubmissions`.
  - `About`: shows contact information (phone, email, website).

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
- `userId` (String): sender uid (resolved from `SessionStore.authUid`, fallback to `Auth.auth().currentUser?.uid`).
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
