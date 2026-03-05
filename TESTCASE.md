# HoneyHub UI Test Cases

## Scope
This document describes the UI test cases in `HoneyHubUITests` and the product flows they cover.

UI tests run with launch arguments:
- `--ui-testing`
- `--mock-rooms`
- `--mock-postcards`
- optional deep-link route arguments:
  - `--ui-open-room <roomId>`
  - `--ui-open-postcard <postcardId>`
  - `--mock-room-joined` (launch fixture room as joined attendee for leave-flow testing)

These flags keep tests independent from live Firebase data.
In UI testing mode, profile refresh/sync paths are also short-circuited so no Firestore reads/writes are executed.

## Manuel check flow
This section is for human testcase checking flow 
Need to check both English and Chinese
1. Taps check: navigate to all three tags, don't touch anything else, see if it works
2. Create a host room and edit everything to see if the change apply , and delete the room
   - can try exceed the host room limit
   - check the event list, if it is correctly updated.
3. Register a postcard and edit everything to make sure changes apply, and delete the postcard
   - check the event list, if it is correctly updated.
TODO: invite code?

## Test Cases

### 1. Sanity: login + tab navigation
- Test: `testSanityLoginAndNavigateAllTabs`
- Coverage:
  - App enters signed-in UI testing state.
  - User can switch across all 3 main tabs:
    - Mushroom
    - Postcard
    - Profile
  - Each tab renders expected primary action UI.

### 2. Mushroom host flow (submit success)
- Test: `testHostFlowCanOpenAndFillRequiredFields`
- Coverage:
  - Open room host/create screen from Mushroom tab.
  - Required form fields are present and interactable.
  - Submit host form in mock mode and verify success path returns to browse.

### 3. Mushroom join flow (smoke)
- Test: `testJoinFlowCanOpenRoomAndJoinFixture`
- Coverage:
  - Join a fixture room in mock mode.
  - Join action path opens expected confirmation feedback.
  - Joined attendee starts in pending-approval state (`AskingToJoin`) until host accepts.
  - Raid settlement confirmation queue supports multiple pending confirmations (latest first) and three attendee responses per queue item:
    - joined success
    - seat full (no-fault)
    - missed invitation
  - Host room view provides a read-only `Raid History` page sorted latest to oldest confirmation records.
  - Each host raid-history record displays all non-host attendees with status-pill colors:
    - `Confirming` and `Seat full` (warning/yellow)
    - `Joined` (success/green)
    - `No invite` (critical/red)

### 4. Postcard buy flow
- Test: `testBuyPostcardFlow`
- Coverage:
  - Open postcard listing from Postcard tab.
  - Execute buyer action.
  - Verify buy success feedback appears.

### 5. Postcard sell flow
- Test: `testSellPostcardFlow`
- Coverage:
  - Open postcard create form from Postcard tab.
  - Submit through UI-test quick-submit path in mock mode.
  - Return to browse screen after submit.

### 6. Profile edit + settings flow
- Test: `testProfileEditAndFeedbackAndAboutFlow`
- Coverage:
  - Open settings -> edit profile, then update display name + friend code.
  - Verify updated name is reflected on profile view.
  - Open settings -> feedback, send feedback in UI-testing mode.
  - Open settings -> about and verify about content is shown.

### 7. Deep link postcard invite opens detail
- Test: `testDeepLinkPostcardInviteOpensDetail`
- Coverage:
  - Launch app with postcard deep-link argument in UI test mode.
  - Verify postcard detail opens directly.

### 8. Deep link mushroom invite opens room
- Test: `testDeepLinkMushroomInviteOpensRoom`
- Coverage:
  - Launch app with room deep-link argument in UI test mode.
  - Verify room detail screen opens directly.

### 9. Mushroom attendee leave flow
- Test: `testMushroomAttendeeLeaveFlow`
- Coverage:
  - Open room detail, join as attendee, open edit-bid flow.
  - Execute leave action and confirm.
  - Verify attendee returns to join-capable state.

### 10. Postcard seller shipping flow
- Test: `testPostcardSellerShippingFlow`
- Coverage:
  - Open seller-owned postcard detail.
  - Open shipping sheet.
  - Seller can accept/reject pending orders and mark accepted order as sent.
  - Verify shipping success feedback and recipient removal.

### 11. Badge counters (manual validation pending automation)
- Current automation status:
  - No dedicated UI test currently asserts profile tab/app-icon badge counters.
  - No dedicated UI test currently asserts per-row actionable count badges in Profile mushroom/postcard lists.
- Manual verification focus:
  - Profile actionable total equals the sum of:
    - joined `WaitingConfirmation`
    - hosted `AskingToJoin`
    - seller pending postcard orders
    - buyer shipped-awaiting-receipt orders
  - Profile tab icon shows a red dot when actionable total is greater than `0`.
  - App icon badge shows the numeric actionable total.
  - Postcard detail seller shipping icon shows a tiny red dot when pending shipping count is greater than `0`.
  - Room detail attendee confirmation-queue icon shows a tiny red dot when attendee has pending `WaitingConfirmation` in that room.
  - Room detail host `Raid History` icon opens a read-only history list and does not offer settlement action buttons.
  - Profile actionable rows (mushroom + postcard lists) show a tiny red dot marker at row-leading edge when actionable count is greater than `0`.
  - Room attendee rows show a tiny red dot before attendee name for host-visible `AskingToJoin` notification sources.

## Covered User Journeys
- Main app shell sanity (signed-in state + tab routing).
- Mushroom core actions: host create submit, join, leave, and deep-link room entry.
- Postcard marketplace core actions: buyer flow, seller create, seller shipping, and deep-link postcard entry.
- Profile maintenance and settings utility flows:
  - Edit profile fields
  - Feedback submission
  - About page navigation

## How To Run
```bash
xcodebuild -project /Users/ken/Desktop/mushroomHunter/mushroomHunter.xcodeproj \
  -scheme HoneyHub \
  -destination "platform=iOS Simulator,name=iPhone 17,OS=26.1" \
  -maximum-parallel-testing-workers 1 \
  test
```

CI workflow:
- `.github/workflows/ios-ui-tests.yml`
