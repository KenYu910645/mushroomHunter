# Tutorial

## Goal
- Replace the current static swipe-card tutorial with dynamic, interactive, in-context tutorials.
- Show guidance exactly when users enter key feature pages, using live UI highlight steps.
- Use temporary tutorial data for first-time walkthrough scenes, then switch to real Firebase data after completion.

## Trigger Matrix
Tutorial runs once per signed-in user (uid-scoped flags) for each scenario:

1. First time entering Mushroom browse list.
2. First time opening Room page in normal personal view (viewer/attendee flow).
3. First time opening Room page in host view (newly created room owner flow).
4. First time entering Postcard browse list.
5. First time opening Postcard page in buyer view.
6. First time opening Postcard page in seller view.

## Current Implementation Status
- Implemented:
  - Mushroom browse first-entry tutorial (`mushroomBrowseFirstVisit`).
  - Room detail personal first-entry tutorial (`roomPersonalFirstVisit`).
  - Room detail host first-entry tutorial (`roomHostFirstVisit`).
  - Postcard browse first-entry tutorial (`postcardBrowseFirstVisit`).
  - Postcard detail buyer first-entry tutorial (`postcardBuyerFirstVisit`).
  - Postcard detail seller first-entry tutorial (`postcardSellerFirstVisit`).
  - Help entry now opens a tutorial scenario list so users can replay available tutorials.
  - Single-file tuning support via `mushroomHunter/Features/Tutorial/TutorialConfig.swift`.
  - Shared browse-tutorial infrastructure extracted:
    - `TutorialStepController` for reusable step-state transitions.
    - `TutorialCoachOverlay` for reusable browse coach-mark rendering.
    - `RoomBrowseView` and `PostcardBrowseView` now use the shared components.
  - Shared detail-tutorial infrastructure extracted:
    - `FeatureTutorialCoordinator` centralizes room/postcard first-load tutorial start decisions.
    - `RoomView` and `PostcardView` now reuse `TutorialCoachOverlay` (including floating toolbar highlight support).
  - Structured tutorial event logging:
    - `TutorialEventLogger` records start/back/next/finish/cancel events for room/postcard browse/detail tutorials.

## Refactor Cleanup Tracker
This tracker maps to the 1~7 cleanup plan and should be kept updated.

1. Shared `FeatureTutorialController` state machine:
   - `DONE`: browse + room detail + postcard detail now all use shared `TutorialStepController`.
2. Reusable `TutorialOverlayView`:
   - `DONE`: room/postcard browse/detail overlays now reuse `TutorialCoachOverlay` (with floating-toolbar support).
3. Move scenario-start decision logic out of views:
   - `DONE`: room/postcard first-load tutorial start decisions now use `FeatureTutorialCoordinator`.
4. Replace multi-boolean view state with explicit tutorial phase enum:
   - `DONE`: `RoomView` and `PostcardView` now use explicit tutorial phase enums (`inactive` / `firstVisit` / `replay`) instead of optional-scenario + replay-flag style state.
5. Simplify highlight target modeling (remove fixed row0...row9 pattern):
   - `DONE`: room attendee highlights now use semantic target ids (`roomHostInfoFriendCodeArea`, `roomFirstNonHostStatusStrip`, `roomPendingJoinActionButtons`) instead of fixed `roomAttendeeRow0...row9` cases.
6. Add structured tutorial event logging:
   - `DONE`: `TutorialEventLogger` now logs all room/postcard browse/detail tutorial actions.
7. Separate/deprecate legacy static tutorial path (`Features/Profile/TutorialView.swift`):
   - `DONE`: legacy static screenshot tutorial is deprecated; `TutorialView` is now a compatibility wrapper that routes to `TutorialCatalogView`.

## Core Tutorial Pattern
- Load a predefined tutorial scene model for the target page.
- Freeze interactive mutations during tutorial (no real create/join/order/close actions).
- Disable room/postcard top-right action buttons during tutorial to prevent opening operational sheets.
- Render scripted fake data directly in the page so the user learns from a realistic UI.
- Hide bottom tab bar during tutorial so users focus on guided flow only.
- Resolve highlight boxes from live UI anchors only (target-id based). Room attendee semantic steps do not section-fallback; if a row-level anchor is missing, no cutout is rendered so wrong-area highlighting cannot occur.
- For navigation-bar toolbar targets (top-right action buttons), keep original toolbar UI and render highlight stroke in a floating top-level overlay window so the rectangle always appears above nav-bar chrome.
- Toolbar-target classification is centralized in `TutorialHighlightTarget.isNavigationToolbarActionTarget` to avoid per-screen duplicate target lists.
- Show multi-step coach marks:
  - Dim background.
  - Highlight target component.
  - Show 1-2 short explanatory sentences.
  - Provide fixed-position `Next`, `Back`, and `Done` controls near bottom corners.
  - Intro step rule: first step should use `highlightTarget: nil`; this renders as full-screen dim style without a cutout focus box.
  - Navigation controls behavior:
    - `Back` is pinned at bottom-left.
    - `Next`/`Done` is pinned at bottom-right.
    - Buttons are semi-transparent and stay in the bottom safe-area dock (tab-bar replacement zone).
- After final step:
  - Mark scenario as completed.
  - Unfreeze the page.
  - Load real Firebase data and continue normal flow.

## Fake Data Strategy
- Tutorial scene uses local, deterministic payloads only (no Firestore read/write).
- Data should mirror production UI structures:
  - Mushroom browse tutorial: one host-owned room, one joined room, several normal rooms.
  - Room tutorial (personal + host): both scenarios now reuse one shared attendee list; only "which row is the current user" changes by role.
  - Postcard browse tutorial: mixed listings, ownership tags, queue badges.
  - Postcard detail buyer tutorial: order action and status explanation.
  - Postcard detail seller tutorial: order queue and seller actions explanation.
- Scene data must be isolated from caches and never persisted as real content.

## Single-File Tuning
For Mushroom browse + Room personal + Room host + Postcard browse + Postcard buyer + Postcard seller tutorials, tune these values in one place:
- File: `mushroomHunter/Features/Tutorial/TutorialConfig.swift`
- Tunable content:
  - `steps`: controls page count, step card title/message copy, and highlight target id.
  - `highlightTarget`: stable UI anchor id used for automatic highlight detection across devices/Dynamic Type.
  - Room detail attendee steps now target semantic attendee cards:
    - `roomAttendeeTopThreeArea`: aggregate highlight over attendee cards 0~2 (used by "Attendee list/成員列表" step).
    - `roomHostInfoFriendCodeArea`: host attendee card.
    - `roomFirstNonHostStatusStrip`: first non-host attendee card.
    - `roomPendingJoinActionButtons`: asking-to-join attendee card.
  - Legacy row-index anchor (`roomAttendeeRow(index:)`) is still attached at row container level for compatibility/debug.
  - Room attendee semantic targets resolve using first-match only (no multi-anchor union), preventing accidental expansion to the whole attendee section.
  - Room detail tutorial mode renders attendee rows through fixed slot positions (host/member slot 0..N) while reusing the same attendee row view component as production mode; this keeps tutorial anchors deterministic without diverging UI styling.
  - Room detail tutorial attendee rendering now reads from scenario-static attendee payload (`TutorialConfig` fake attendees) instead of runtime room attendee state, so slot-based anchors are always emitted even if runtime payload is empty/delayed.
  - During room tutorial, attendee UI is no longer rendered as one combined attendee section container; attendee cards are rendered as top-level siblings parallel to room header.
  - Room production and tutorial now share the same attendee-card layout path; tutorial only swaps data source/anchor bindings.
  - Room detail tutorial attendee list is rendered as stacked single-attendee cards (one card per attendee slot) while preserving the same row view; this isolates row geometry so each slot can emit its own independent tutorial anchor.
  - Tutorial attendee cards use compact vertical stack spacing so slot-to-slot gaps stay small and keep highlights visually tight.
  - Room detail tutorial mode now hard-binds key semantic targets to static attendee slots (`index 0 -> host info`, `index 1 -> member info`) so those anchors are always emitted even if runtime attendee state ordering shifts.
  - Legacy row-index target (`roomAttendeeRow(index:)`) remains available for compatibility and still resolves using the first matched row anchor (not union of all matched rows) to keep highlight rectangles tight.
  - Postcard browse tutorial startup now follows Mushroom browse timing: tutorial starts immediately on appear, while profile refresh runs in parallel (non-blocking) to keep early-step top-bar targets stable.
  - Postcard browse tutorial now disables top-bar container anchor emission during tutorial so child top-bar targets (`Honey`, `Search`, `+`) resolve independently for steps 2~4.
  - Postcard browse tutorial `Done` now forces one backend refresh handoff, so the fake tutorial scene is always replaced by real Firebase browse data immediately.
  - Postcard browse tutorial now splits card highlights into `postcardBrowsePinnedOwnershipArea` (owned rows) and `postcardBrowseGeneralListingsArea` (non-owned lower rows) so step-level card targeting stays deterministic.
  - Postcard detail tutorial now exposes dedicated targets for the hero snapshot (`postcardDetailSnapshot`) and seller top-right toolbar actions (`postcardSellerShareButton`, `postcardSellerShippingButton`, `postcardSellerEditButton`).
  - Postcard detail tutorial `Done` now restores data using the original postcard id that opened the page, preventing fallback to browse caused by refreshing tutorial fake ids.
  - Message-card Y auto-placement:
    - When a highlight target exists, the message card is auto-placed near the target.
    - Default is below the highlighted target.
    - If the highlighted target is near the bottom, the message card auto-switches above it.
    - Intro/no-highlight steps use a shared default center position.
  - `fakeRooms` / `fakeRoom` / `fakeListing` / `fakeListings`: controls fake scene content (room/postcard names, attendees, location, status, etc.).
  - Room detail tutorial fake room payload no longer stores mushroom target color/attribute/size values; tutorial scenes use neutral target defaults in runtime mapping.
  - `hostRoomIds` / `joinedRoomIds` / `onShelfListingIds` / `orderedListingIds`: controls ownership tag rendering for fake browse scenes.
  - Postcard tutorial snapshot assets:
    - `mushroomHunter/Resources/Assets.xcassets/TutorialPostcardSnapshotBaby.imageset/baby.PNG`
    - `mushroomHunter/Resources/Assets.xcassets/TutorialPostcardSnapshotHippo.imageset/hippo.PNG`
    - `mushroomHunter/Resources/Assets.xcassets/TutorialPostcardSnapshotHugePikmin.imageset/huge_pikmin.PNG`
    - `mushroomHunter/Resources/Assets.xcassets/TutorialPostcardSnapshotDuck.imageset/duck.PNG`
    - Mapping:
      - Postcard browse `tutorial-postcard-browse-main` -> `baby.PNG`
      - Postcard browse `tutorial-postcard-ordered` -> `hippo.PNG`
      - Postcard browse `tutorial-postcard-general-1` -> `huge_pikmin.PNG`
      - Postcard browse `tutorial-postcard-general-2` -> `duck.PNG`
      - Postcard detail buyer/seller tutorial -> `duck.PNG`
    - Rendering behavior:
      - Tutorial snapshots now reuse postcard production preprocessing (`cropSnapshotImage`) before showing in browse/detail tutorial views.
- Language format:
  - EN/zh-Hant are defined side-by-side in each entry (`BilingualText`) so translators can edit line by line.
  - Tutorial message copy supports inline bullet lines: prefix a line with `*` (or `＊`) in `TutorialConfig` and it will render as a bullet row in the message box.

## Tutorial Step Model (Recommended)
- `sceneId`: unique tutorial scene id.
- `stepId`: ordered step id in scene.
- `highlightAnchorId`: stable UI anchor id to focus.
- `titleKey` / `messageKey`: localized copy keys.
- `placement`: tooltip position relative to anchor.
- `allowedAction`: `nextOnly` / `tapHighlighted` / `free`.
- `isBlocking`: whether outside taps are blocked for this step.

## State and Persistence
- Persist completion flags in uid-scoped local storage (same pattern as existing onboarding flag).
- Suggested key shape:
  - `mh.tutorial.mushroomBrowse.completed`
  - `mh.tutorial.roomPersonal.completed`
  - `mh.tutorial.roomHost.completed`
  - `mh.tutorial.postcardBrowse.completed`
  - `mh.tutorial.postcardBuyer.completed`
  - `mh.tutorial.postcardSeller.completed`
- All keys should be read/written through one tutorial state manager.

## UX Rules
- One step explains one concept only.
- Keep each message concise and action-oriented.
- Always allow skip.
- Do not show multiple tutorials at the same time.
- Help replay should stay in root tab navigation context (not a modal sheet) so tutorial pages match real tab-based layout.
- When a tutorial is opened from Settings -> Help -> Tutorial list, tapping `Done` should pop back to the tutorial list.
- Tutorial list page no longer shows a top-left close (`X`) button and no longer displays the replay footer hint line.
- If deep-link/push opens a page with pending critical action, defer tutorial until action is cleared.

## Rollout Plan (Several Steps)
1. Build shared tutorial engine:
   - Overlay, anchor registry, step controller, completion persistence.
2. Implement Mushroom browse tutorial with fake list scene and Firebase-load handoff.
3. Implement Room personal tutorial.
4. Implement Room host tutorial (triggered after host creates room and enters host view first time).
5. Implement Postcard browse tutorial.
6. Implement Postcard buyer and seller tutorials.
7. Add Profile Settings entry to replay each tutorial manually.
8. Add UI tests for first-run trigger, skip, completion, and post-tutorial real-data load.

## Success Criteria
- Users can complete each tutorial in short, guided steps without leaving the page.
- First page experience uses tutorial scene; normal Firebase data appears immediately after tutorial completion.
- Each scenario tutorial appears exactly once per user unless replayed from settings.
