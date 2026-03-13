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
2. Create, Edit, and Delete Room:
   - Create a host room and edit everything to see if the change apply , and delete the room
   - can try exceed the host room limit
   - check the event list, if it is correctly updated.
3. Create, Edit and Delete postcard: 
   - Register a postcard and edit everything to make sure changes apply, and delete the postcard
   - check the event list, if it is correctly updated. (Create Room and CLose Room should have notification in Event list)
   - complete one postcard order and verify buyer rates seller from the inline buyer card while seller rates buyer from the seller order queue
   - verify `Skip` permanently removes that specific postcard rating task
   - verify manual `Completed` creates rating tasks, but `CompletedAuto` does not
4. Join room(Accept, Reject and Kick)
   - use QR code to scan to the room
   - Attendee apply join -> Check event and host MUSH receive a notification(Action EVENT) -> the badget counter need to increment
   - The event need to record correctly on both side
   - The deposit honey need to be calculated correctly 
   - Host kick must refund the kicked attendee's full deposit and create `KICKED_HOST` / `KICKED_ATTENDEE` record events without changing action badges
5. Mushroom Invite
   - Host press invite, see if the joiner get APN and the badge count need to be correct, After resolving the invitation, the red dot should disappear and badge counter --
   - Joiner reply Join Success, Mushroom full, No invitation
   - If settlement makes attendee deposit fall below `AppConfig.Mushroom.minimumRequiredDepositHoney`, attendee row status should switch to red `Not Enough Honey` / `蜂蜜不足`, and attendee should still be able to open deposit edit to top up
   - The star is correctly updated.
   - If the receiver is already viewing room detail, the attendee slot star count should update in place without pull-to-refresh.
   - If room detail still shows stale star counts, pull-to-refresh should force-correct all attendee row stars from latest profile values.
   - Host/attendee clipboard icons should show a red dot when pending rating tasks exist there.
   - Rating and skip should both work from the clipboard queue/history sheets and should never reopen a popup.
   - Receiver should get a `STAR_RECEIVED` inbox row and mushroom star push when a room rating task is completed.
6. Postcard buy flow
   - buyer buy, and seller can choose to accept or reject, the honey must update correctly
   - The notification need to be ok 
   - The star is correctly updated.
   - Seller clipboard icon should show a red dot when either shipping or seller-side rating tasks are pending.
   - Buyer rating should appear inline on postcard detail and `Skip` should permanently remove it.
   - sold-out postcard should remain visible in browse, move below in-stock browse cards, and show disabled buy state on detail for non-sellers
   - seller-owned sold-out postcard should stay pinned at the top and show `Run out` / `賣完了`

7. Tutorial flow 
   - All six tutorial flow need to work just fine.
   
8. Changing the profile acutally will work
9. Feedback feature
10. DailyReward feature
   - Verify the calendar icon appears on Mushroom, Postcard, and Profile, always to the left of bell
   - Verify the calendar icon shows a red dot whenever today's Taipei DailyReward has not been claimed yet
   - Open the DailyReward sheet from all three tabs
   - Verify the current month calendar shows and every day displays the same 10-honey reward
   - Claim today's reward once and confirm wallet, disabled button state, and inbox `HONEY_REWARD` record event
   - Confirm a second claim on the same day is blocked
   - Verify missed previous days cannot be claimed after Taipei midnight
   - Verify app icon badge adds `+1` while today's DailyReward is pending and does not double-count after the noon reminder event is created
   - Verify `DAILY_REWARD_REMINDER` push and inbox row both open the shared DailyReward sheet
11. Premium subscription feature
   - Open Profile and verify the `Upgrade to Premium` row opens the premium membership sheet
   - Verify free state shows 30-honey DailyReward benefit and 5/10 room-limit benefit copy
   - Buy or restore a premium subscription in a sandbox account, then confirm profile state becomes active
   - Confirm DailyReward calendar and success message show 30 honey for premium users and 10 honey for free users
   - Confirm premium users can host up to 5 rooms and join up to 10 rooms, while free users remain at 1/3

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
  - Manual validation must also cover host kick behavior:
    - kick with non-zero deposit refunds the full deposit
    - both host and attendee inboxes receive `KICKED_*` record rows
    - kick does not increment badge counts or create Action Event highlighting

### 4. Postcard buy flow
- Test: `testBuyPostcardFlow`
- Coverage:
  - Open postcard listing from Postcard tab.
  - Execute buyer action.
  - Verify buy success feedback appears.

### 5. Postcard sold-out state
- Test: `testSoldOutPostcardShowsDisabledBuyState`
- Coverage:
  - Open sold-out postcard listing from Postcard tab.
  - Verify sold-out helper text appears on detail.
  - Verify buy button stays visible but disabled.

### 6. Postcard sell flow
- Test: `testSellPostcardFlow`
- Coverage:
  - Open postcard create form from Postcard tab.
  - Submit through UI-test quick-submit path in mock mode.
  - Return to browse screen after submit.

### 7. Profile edit + settings flow
- Test: `testProfileEditAndFeedbackAndAboutFlow`
- Coverage:
  - Open settings -> edit profile, then update display name + friend code.
  - Verify updated name is reflected on profile view.
  - Open settings -> feedback, send feedback in UI-testing mode.
  - Open settings -> about and verify about content is shown.

### 8. Deep link postcard invite opens detail
- Test: `testDeepLinkPostcardInviteOpensDetail`
- Coverage:
  - Launch app with postcard deep-link argument in UI test mode.
  - Verify postcard detail opens directly.

### 9. Deep link mushroom invite opens room
- Test: `testDeepLinkMushroomInviteOpensRoom`
- Coverage:
  - Launch app with room deep-link argument in UI test mode.
  - Verify room detail screen opens directly.

### 10. Mushroom attendee leave flow
- Test: `testMushroomAttendeeLeaveFlow`
- Coverage:
  - Open room detail, join as attendee, open edit-deposit flow.
  - Execute leave action and confirm.
  - Verify attendee returns to join-capable state.

### 11. Postcard seller shipping flow
- Test: `testPostcardSellerShippingFlow`
- Coverage:
  - Open seller-owned postcard detail.
  - Open shipping sheet.
  - Seller can accept/reject pending orders and mark accepted order as sent.
  - Verify shipping success feedback and recipient removal.

### 12. Badge counters (manual validation pending automation)
- Current automation status:
  - No dedicated UI test currently asserts app icon badge counters.
- Manual verification focus:
  - Profile tab shows no legacy badge count or red-dot badge.
  - App icon badge shows unresolved non-DailyReward Action Events plus `1` when today's DailyReward is still pending.
  - Postcard detail seller shipping icon shows a tiny red dot when pending shipping count is greater than `0`.
  - Room detail attendee confirmation-queue icon shows a tiny red dot when attendee has pending `WaitingConfirmation` in that room.
  - Room detail attendee confirmation-queue icon also stays dotted when attendee-side room rating tasks are pending.
  - Room detail host `Raid History` icon opens history plus pending host-side room rating actions.
  - Postcard detail seller shipping icon shows a tiny red dot when either shipping rows or seller rating rows are pending.
  - Room attendee rows show a tiny red dot before attendee name for host-visible `AskingToJoin` notification sources.

### 13. DailyReward calendar claim
- Test: `testDailyRewardCalendarClaimFlow`
- Coverage:
  - Open the shared DailyReward sheet from the top-right calendar icon.
  - Verify the current month header and reward calendar grid render.
  - Claim today's reward in UI-testing mode.
  - Verify success feedback appears and the claim button becomes disabled for the rest of the current mock day.

### 14. DailyReward toolbar pending state
- Test: `testDailyRewardToolbarPendingStateChangesWithMockClaimStatus`
- Coverage:
  - Default UI-testing launch shows the calendar toolbar button accessibility value as `pending`.
  - Launching with `--mock-daily-reward-claimed` removes the pending state and exposes accessibility value `none`.

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
