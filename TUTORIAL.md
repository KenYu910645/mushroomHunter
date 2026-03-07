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
  - Help entry now opens a tutorial scenario list so users can replay available tutorials.
  - Single-file tuning support via `mushroomHunter/Features/Tutorial/TutorialConfig.swift`.
- Planned (not implemented yet):
  - Room personal/host tutorials.
  - Postcard browse/buyer/seller tutorials.

## Core Tutorial Pattern
- Load a predefined tutorial scene model for the target page.
- Freeze interactive mutations during tutorial (no real create/join/order/close actions).
- Render scripted fake data directly in the page so the user learns from a realistic UI.
- Show multi-step coach marks:
  - Dim background.
  - Highlight target component.
  - Show 1-2 short explanatory sentences.
  - Provide `Next`, `Back`, `Skip`, and `Done`.
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
For Mushroom browse tutorial, tune these values in one place:
- File: `mushroomHunter/Features/Tutorial/TutorialConfig.swift`
- Tunable content:
  - `steps`: controls page count, step card title/message copy, and optional highlight rectangle geometry (`normalizedRect = nil` means full-screen highlight with no focus rectangle).
  - `fakeRooms`: controls fake room list content (room names, types, colors, size, location, etc.).
  - `hostRoomIds` / `joinedRoomIds`: controls which fake rows show Host/Joined ownership tags.
- Language format:
  - EN/zh-Hant are defined side-by-side in each entry (`BilingualText`) so translators can edit line by line.

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
