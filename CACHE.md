# Cache

## Scope
- Mushroom browse list cache.
- Mushroom room page cache.
- Postcard browse list cache.
- Postcard image cache.
- Postcard page cache.

## Related Files
- `mushroomHunter/Features/Mushroom/RoomCache.swift`: `RoomCache` structured payload cache and `CacheDirtyBitStore`.
- `mushroomHunter/Features/Mushroom/RoomBrowseViewModel.swift`: mushroom browse load + dirty-bit checks.
- `mushroomHunter/Features/Mushroom/RoomViewModel.swift`: room-detail load + mutation dirty-bit writes.
- `mushroomHunter/Features/Postcard/PostcardBrowseViewModel.swift`: postcard browse load + dirty-bit checks.
- `mushroomHunter/Features/Postcard/PostcardBrowseView.swift`: postcard browse on-appear and local-delete invalidation.
- `mushroomHunter/Features/Postcard/PostcardView.swift`: postcard detail dirty-bit checks and buyer mutation invalidation.
- `mushroomHunter/Features/Postcard/PostcardCreateEditView.swift`: seller create/edit/delete invalidation.
- `mushroomHunter/Features/Postcard/PostcardOrdersView.swift`: seller ship/reject invalidation.
- `mushroomHunter/Features/EventInbox/EventInboxStore.swift`: push payload invalidation.
- `mushroomHunter/Features/Postcard/PostcardImageCache.swift`: postcard image memory+disk cache.
- `mushroomHunter/Services/Firebase/PostcardImageUploader.swift`: Storage `Cache-Control` metadata.
- `mushroomHunter/Utilities/AppConfig.swift`: image-cache sizing/TTL.

## Cache Storage Model
### RoomCache (structured payloads)
- Type: app-level memory + disk cache.
- Wrapper: `CachedPayload<Value>` with fields `cachedAt` and `value`.
- Disk root: app caches directory `/RoomCache`.
- Disk filename: `SHA256(logicalKey).json`.
- Read order: memory -> disk.
- Corrupt payload behavior: decode failure removes bad disk file and treats as miss.
- Write behavior: memory first, then best-effort atomic disk write.

### PostcardImageCache (UIImage bytes)
- Type: `NSCache` memory + disk folder cache.
- Disk root: app caches directory `/PostcardImageCache`.
- Disk filename: `SHA256(imageURL).img`.
- Read order: memory -> disk -> network.
- URLSession request policy: `.returnCacheDataElseLoad`.
- In-flight dedupe: same URL shares one network request.
- Expiration/prune:
- TTL check by file modification date.
- Over-capacity prune deletes oldest files until target ratio.

### CacheDirtyBitStore
- Type: in-memory dirty-key set + persistent `UserDefaults` storage.
- Storage key: `mh.cache.dirty.keys.v1`.
- Meaning: dirty key `ON` means next load for that scope must force backend refresh.
- Clear policy: dirty key is cleared only after successful backend fetch for that same scope.

## Logical Keys
### Structured cache keys
- Mushroom browse: `mushroom.browse.listings.v1`
- Mushroom room detail: `mushroom.room.detail.{roomId}`
- Postcard browse: `postcard.browse.listings.v1`
- Postcard detail: `postcard.detail.{postcardId}`

### Dirty-bit keys
- Mushroom browse dirty: `dirty.mushroom.browse.listings.v1`
- Mushroom room dirty: `dirty.mushroom.room.detail.{roomId}`
- Postcard browse dirty: `dirty.postcard.browse.listings.v1`
- Postcard detail dirty: `dirty.postcard.detail.{postcardId}`

## Dirty-Bit Core Rules
- If dirty bit is `ON`, force backend fetch even if cache/local state exists.
- Pull-to-refresh always forces backend fetch regardless of dirty bit.
- Browse pull-to-refresh launches an app-owned refresh task so the real backend reload can survive SwiftUI `.refreshable` task cancellation.
- Browse tab re-entry uses the same canonical forced-refresh flow as pull-to-refresh.
- Successful backend fetch clears corresponding dirty bit.
- Failed fetch keeps dirty bit `ON` (retry on next load).

## When Backend Fetch Happens
### Mushroom browse list
- Dirty bit `ON`.
- Pull-to-refresh.
- Browse tab re-entry after the page has already been rendered once.
- Search submit (`performConfirmedSearch`).
- When the list has no visible rows and browse dirty is `OFF`, disk cache can still bootstrap the first frame before the forced refresh runs.
- Canonical forced refresh is server-authoritative for both the main open-room query and pinned hosted/joined room queries.

### Mushroom room detail
- Dirty bit `ON` for this room.
- Pull-to-refresh.
- Room opened with explicit force-refresh route. this means `RoomView` is initialized with `isForceRefreshOnAppear=true`, so first load calls `vm.load(forceRefresh: true)` and bypasses cache. Flows that set this route flag are push room-open (`didOpenRoomFromPush`), push confirmation-open (`didOpenRoomConfirmationFromPush`), room invite deep-link open (`honeyhub://room/{roomId}` routed through `didOpenRoomFromPush`), and UI-test launch argument route (`--ui-open-room`).

### Postcard browse
- Dirty bit `ON` for postcard browse.
- Pull-to-refresh.
- Browse tab re-entry after the page has already been rendered once.
- Search/clear-search backend fetch flow.
- Dirty bit `OFF` and in-memory list empty: apply postcard browse disk cache first when available.
- Canonical forced refresh is server-authoritative for the main browse query and the pinned on-shelf/ordered queries; these forced refreshes do not silently fall back to Firestore local cache when the server query fails.

### Postcard detail
- Dirty bit `ON` for this postcard.
- Pull-to-refresh.
- Sheet dismiss callbacks (edit/shipping flows) call normal refresh; dirty bit decides whether backend fetch is required.
- Dirty bit `OFF`: detail can use `postcard.detail.{postcardId}` cache payload.

### Postcard image bytes
- Memory miss and disk miss.
- Disk entry expired/pruned.
- Image URL changes (new key).

## Dirty-Bit Write Matrix (Local Operations)
### Mushroom operations
- `join room` (browse or detail):
- Set `dirty.mushroom.browse.listings.v1`
- Set `dirty.mushroom.room.detail.{roomId}`
- `leave room`:
- Set browse dirty
- Set current room dirty
- `update deposit`:
- Set current room dirty
- `approve join request`:
- Set browse dirty
- Set current room dirty
- `reject join request`:
- Set browse dirty
- Set current room dirty
- `kick attendee`:
- Set browse dirty
- Set current room dirty
- `finish raid`:
- Set current room dirty
- `respond to raid confirmation`:
- Set current room dirty
- `rate host` / `rate attendee`:
- Set current room dirty
- `close room`:
- Set browse dirty
- Clear current room dirty
- Remove room structured cache entry

### Postcard operations
- `create postcard`:
- Set `dirty.postcard.browse.listings.v1`
- `edit postcard`:
- Set postcard browse dirty
- Set `dirty.postcard.detail.{postcardId}`
- `delete postcard`:
- Set postcard browse dirty
- Set postcard detail dirty
- `buy postcard`:
- Set postcard browse dirty
- Set postcard detail dirty
- `confirm received`:
- Set postcard browse dirty
- Set postcard detail dirty
- `seller mark sent`:
- Set postcard detail dirty
- `seller reject order`:
- Set postcard browse dirty
- Set postcard detail dirty

## Dirty-Bit Write Matrix (Push / Event Ingestion)
- On push receive, if payload has `roomId`:
- Set mushroom browse dirty
- Set mushroom room dirty for that `roomId`
- On push receive, if payload has `postcardId`:
- Set postcard browse dirty
- Set postcard detail dirty for that `postcardId`

This includes Cloud Function event types where payload carries room/postcard ids (for example join-request outcomes, raid confirmations, postcard order/shipping lifecycle pushes).

## Hit/Miss Behavior Summary
### Mushroom structured cache
- Hit (dirty `OFF`): cached payload can be used for immediate render.
- Miss or dirty `ON`: backend fetch and overwrite cache.

### Postcard image cache
- Hit: image renders from memory/disk without Storage fetch.
- Miss: network fetch fills memory+disk.

## Config Tunables
`AppConfig.Postcard` image cache knobs:
- `imageMemoryCacheEntryLimit`
- `imageDiskCacheMaxBytes`
- `imageDiskCachePruneTargetRatio`
- `imageDiskCacheMaxAgeSeconds`

## Firebase Storage Cache Metadata
- Uploaded postcard images are tagged with `Cache-Control: public,max-age=86400`.
- Set in `PostcardImageUploader.uploadImageData(...)`.

## Documentation Policy
- Cache and dirty-bit behavior must be documented in `CACHE.md` only.
- Other docs should reference this file instead of duplicating cache semantics.
