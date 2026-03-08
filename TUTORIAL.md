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

## Core Tutorial Pattern
- Load a predefined tutorial scene model for the target page.
- Freeze interactive mutations during tutorial (no real create/join/order/close actions).
- Disable room/postcard top-right action buttons during tutorial to prevent opening operational sheets.
- Render scripted fake data directly in the page so the user learns from a realistic UI.
- Hide bottom tab bar during tutorial so users focus on guided flow only.
- Resolve highlight boxes from live UI anchors only (target-id based). No fallback geometry is rendered.
- For navigation-bar toolbar targets (top-right action buttons), keep original toolbar UI and render highlight stroke in a floating top-level overlay window so the rectangle always appears above nav-bar chrome.
- Toolbar-target classification is centralized in `TutorialHighlightTarget.isNavigationToolbarActionTarget` to avoid per-screen duplicate target lists.
- Show multi-step coach marks:
  - Dim background.
  - Highlight target component.
  - Show 1-2 short explanatory sentences.
  - Provide fixed-position `Next`, `Back`, and `Done` controls near bottom corners.
  - Intro step rule: first step should use `highlightTarget: nil` and `normalizedRect: nil`; this renders as full-screen dim style without a cutout focus box.
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
  - Room tutorial (personal): host + other attendees, actionable status examples.
  - Room tutorial (host): join requests, share/raid/edit action examples.
  - Postcard browse tutorial: mixed listings, ownership tags, queue badges.
  - Postcard detail buyer tutorial: order action and status explanation.
  - Postcard detail seller tutorial: order queue and seller actions explanation.
- Scene data must be isolated from caches and never persisted as real content.

## Single-File Tuning
For Mushroom browse + Room personal + Room host + Postcard browse + Postcard buyer + Postcard seller tutorials, tune these values in one place:
- File: `mushroomHunter/Features/Tutorial/TutorialConfig.swift`
- Tunable content:
  - `steps`: controls page count, step card title/message copy, highlight target id, fallback highlight rectangle geometry, and message-card Y position.
  - `highlightTarget`: stable UI anchor id used for automatic highlight detection across devices/Dynamic Type.
  - Room detail attendee steps can now target row-level anchors (`roomAttendeeRow0`...`roomAttendeeRow9`) instead of only section-level highlighting.
  - Row-level attendee targets resolve using the first matched row anchor (not union of all matched rows) to keep highlight rectangles tight.
  - `normalizedRect`: legacy field kept in config for compatibility; ignored by runtime highlight rendering.
  - `normalizedRect: nil`: intro/no-highlight steps still render as full dim background.
  - `messageBoxNormalizedY`: fallback message-card vertical position (`0.0` top to `1.0` bottom).
  - Message-card Y auto-placement:
    - When a highlight target exists, the message card is auto-placed near the target.
    - Default is below the highlighted target.
    - If the highlighted target is near the bottom, the message card auto-switches above it.
    - `messageBoxNormalizedY` is used as fallback for intro/no-highlight steps.
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
