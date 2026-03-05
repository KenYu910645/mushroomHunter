# Cache

`CACHE.md` for HoneyHub cache behavior.

## Scope
- Postcard image cache used by browse thumbnails, postcard detail hero image, and postcard form preview.
- Mushroom browse-list cache.
- Mushroom room-detail cache (`room header + attendees`).

## Related Files
- `mushroomHunter/Utilities/AppDataCache.swift`: app-level Codable payload cache (memory + disk).
- `mushroomHunter/Features/Shared/CachedPostcardImageView.swift`: postcard image cache/view wrapper.
- `mushroomHunter/Features/Mushroom/RoomBrowseViewModel.swift`: browse cache read/write flow.
- `mushroomHunter/Features/Mushroom/RoomViewModel.swift`: room-detail cache read/write/remove flow.
- `mushroomHunter/Utilities/AppConfig.swift`: postcard cache tuning knobs.
- `mushroomHunter/Services/Firebase/PostcardImageUploader.swift`: Storage `Cache-Control` metadata for uploaded postcard images.

## Storage Model
### AppDataCache (structured payloads)
- Type: app-level memory + disk cache.
- Payload wrapper: `CachedPayload<Value>` with:
  - `cachedAt`
  - `value`
- Disk path: app caches directory `/AppDataCache`.
- Disk filename: SHA256 hash of logical key + `.json`.
- Behavior:
  - Load order: memory -> disk.
  - Corrupt payloads are ignored; bad disk files are removed.
  - Save writes memory first, then best-effort atomic disk write.

### PostcardImageCache (UIImage bytes)
- Type: in-memory `NSCache` + disk folder cache.
- Disk path: app caches directory `/PostcardImageCache`.
- Disk filename: SHA256 hash of image URL + `.img`.
- Load order: memory -> disk -> network.
- Network request policy: `.returnCacheDataElseLoad`.
- In-flight dedupe: same URL fan-outs one request to multiple callbacks.
- Expiration and pruning:
  - TTL based on file modification date.
  - Over-capacity prune removes oldest files until target ratio is reached.

## Cache Keys
### Mushroom
- Browse list: `mushroom.browse.listings.v1`
- Room detail: `mushroom.room.detail.{roomId}`

## Hit/Miss Behavior
### Postcard image cache
- Hit: image bytes found in memory or disk; UI renders without Storage fetch.
- Miss: network fetch runs, then memory+disk cache are populated.

### Mushroom browse cache
- Hit: cached room listings applied immediately.
- Miss: Firestore query fills state and overwrites cache.

### Mushroom room-detail cache
- Hit: cached room detail payload applied immediately.
- Miss: Firestore `rooms/{roomId}` + `attendees` query fills state and overwrites cache.

## Refresh and Invalidation Rules
- Pull-to-refresh always forces backend refresh and cache overwrite.
- Mushroom browse keyboard search submit forces backend refresh before local filter application.
- Mushroom room state-changing actions force backend refresh and cache overwrite, including:
  - join / leave / update deposit
  - approve / reject join application
  - kick attendee
  - finish raid
  - attendee confirmation response
  - host/attendee rating
- Room close removes that room-detail cache key.

## When Server Fetch Happens
### Postcard image cache
- Server fetch happens when image bytes are not available from memory or disk cache.
- Server fetch also happens when disk entry is expired or pruned.
- If image URL changes, it is treated as a new cache key and fetches again.

### Mushroom browse cache
- On Mushroom tab initial entry (`loadListingsOnAppear`), app applies cached list first (if any), then always fetches latest list from Firestore and overwrites cache.
- Pull-to-refresh always fetches latest list from Firestore and overwrites cache.
- Keyboard search submit always fetches latest list from Firestore before applying local filtering.
- After successful join, browse list is fetched again to sync latest counts/status.

### Mushroom room-detail cache
- Opening room fetches from Firestore only when cache is missing.
- Pull-to-refresh always fetches latest `rooms/{roomId}` + `attendees` and overwrites cache.
- Room state-changing actions fetch latest backend state and overwrite cache:
  - join / leave / update deposit
  - approve / reject join application
  - kick attendee
  - finish raid
  - attendee confirmation response
  - host/attendee rating

## Config Tunables
`AppConfig.Postcard` controls image cache sizing and retention:
- `imageMemoryCacheEntryLimit`
- `imageDiskCacheMaxBytes`
- `imageDiskCachePruneTargetRatio`
- `imageDiskCacheMaxAgeSeconds`

## Firebase Storage Cache Metadata
- Uploaded postcard images are tagged with `Cache-Control: public,max-age=86400`.
- This is set in `PostcardImageUploader.uploadImageData(...)`.

## Documentation Policy
- Cache behavior must be documented only in `CACHE.md`.
- Other docs should reference this file instead of duplicating cache semantics.
