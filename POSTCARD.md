# Postcard

## Related Files
- `mushroomHunter/Features/Postcard/PostcardBrowseView.swift`: postcard tab root + listing browse/search UI and listing cards.
- `mushroomHunter/Features/Postcard/PostcardView.swift`: postcard detail screen with buyer/seller actions.
- `mushroomHunter/Features/Postcard/PostcardShippingView.swift`: seller shipping queue and send confirmation flow.
- `mushroomHunter/Features/Postcard/PostcardFormView.swift`: consolidated postcard create/edit form implementation.
- `mushroomHunter/Features/Postcard/PostcardBrowseViewModel.swift`: browse filtering, sorting, and refresh state logic.
- `mushroomHunter/Features/Postcard/PostcardDomainModel.swift`: postcard listing/order/location models and status enums.
- `mushroomHunter/Features/Shared/BrowseViewTopActionBar.swift`: shared honey/search/create header used by browse screens (stars hidden on postcard browse).
- `mushroomHunter/Features/Shared/SelectAllTextField.swift`: shared auto-select text field wrapper used by postcard form inputs.
- `mushroomHunter/Features/Shared/SelectAllTextEditor.swift`: shared auto-select text editor wrapper used by postcard description inputs.
- `mushroomHunter/Features/Shared/OutsideTapKeyboardDismissBridge.swift`: shared UIKit bridge that dismisses keyboard on outside taps without collapsing during scroll.
- `mushroomHunter/Features/Shared/HoneyMessageBox.swift`: shared custom confirmation/error dialog used across postcard screens.
- `mushroomHunter/Features/Shared/CachedPostcardImageView.swift`: shared postcard image cache component with memory+disk cache and cache-first loading.
- `mushroomHunter/Services/Firebase/PostcardRepo.swift`: Firestore operations for listings, orders, shipping, and receipt confirmation.
- `mushroomHunter/Services/Firebase/PostcardImageUploader.swift`: image crop/encode/upload to Firebase Storage.
- `mushroomHunter/Utilities/RoomInviteLink.swift`: postcard invite link generation/parsing for `honeyhub://postcard/{postcardId}`.
- `mushroomHunter/Utilities/SearchTokens.swift`: normalized token generation for postcard search fields.
- `mushroomHunter/Utilities/CountryLocalization.swift`: shared locale-aware country + room-location display resolver used by postcard/room labels.
- `mushroomHunter/Utilities/AppConfig.swift`: centralized owner-managed postcard settings (price/stock/text caps, fetch limits, image cache limits, order timeout windows).
- `mushroomHunter/Utilities/FriendCode.swift`: shared friend-code sanitizing/formatting/validation utility used across profile, room, and postcard flows.
- `mushroomHunter/App/HoneyHubApp.swift`: handles postcard deep-link routing from invite links.
- `mushroomHunter/App/ContentView.swift`: presents postcard detail sheet when a postcard invite link is opened.
- `mushroomHunter/Features/Shared/InviteShareSheet.swift`: shared invite QR sheet component reused by postcard detail.
- `functions/index.js`: server-side push triggers for postcard order/shipping/completion events.

## Feature Coverage
- Browse and search postcard listings.
- Browse and search use paginated fetches (`20` per page) with explicit "Load more".
- Browse search is opened from the top action bar as an inline search field above the listing grid (no dedicated sheet/alert).
- Postcard browse search matches postcard title and location text (country/city).
- Postcard browse search applies local filtering while typing; backend paged query runs only when user taps `Search`.
- Inline search field includes an `x` clear button; tapping `x` clears query and collapses the search field. Pressing keyboard Enter triggers search. Top-bar search icon toggles field show/hide.
- Postcard browse card thumbnail overlays the honey price badge (value + honey icon) at the top-right corner; stock count is not shown on browse cards.
- Postcard browse thumbnails and postcard detail/form preview images use shared cache-first loading (`memory -> disk -> network`) so revisiting recently viewed images avoids repeated Firebase Storage downloads when cache is hit.
- Postcard browse card title stays single-line, scales down for longer names, then truncates with trailing ellipsis.
- Postcard location country labels are rendered in the current user locale when possible (including legacy listings that stored English country names).
- Postcard detail view hides the navigation title so the postcard snapshot is the first visible content at the top.
- Register flow uploads full image + thumbnail to Firebase Storage, then creates Firestore listing.
- Register success dismisses the sheet and refreshes browse list.
- Pull-to-refresh is supported in postcard browse, detail, and shipping flows.
- Seller can open shipping sheet in postcard detail to see waiting buyers and mark each order as sent.
- Seller shipping toolbar button in postcard detail shows a tiny red dot when there are pending orders that need seller processing.
- Seller shipping queue rows show `Buyer ordered Postcard` title text plus a friend-request instruction line with inline copy icon for buyer friend code.
- Seller shipping queue action order is `Postcard Sent` on the left and `Reject` on the right.
- Seller shipping queue copy icon shows the shared `Copied to clipboard` toast feedback used across postcard screens.
- Seller shipping queue requires confirmation dialogs before executing `Postcard Sent` and `Reject` actions.
- Seller can open a top-right share action in postcard detail to show an invite sheet with QR code, share link, and copy link actions.
- Postcard invite links use deep link format `honeyhub://postcard/{postcardId}`.
- Opening a postcard invite link routes to postcard detail in-app when the listing still exists.
- Buyer order lifecycle:
  - Buyer places order -> order enters `AwaitingShipping`; seller receives push to ship or decline.
  - Seller can decline -> order enters `Rejected` with buyer refund and stock restore.
  - Seller marks shipped (`Shipped`) -> buyer receives push and can confirm receipt.
  - Buyer confirms receipt -> order enters `Completed` and transfers held honey to seller.
  - Buyer inactivity after shipped deadline -> Cloud Function auto-settles order as `CompletedAuto`.
  - Buyer cannot place another order for the same postcard while an active order exists (`AwaitingShipping`, `Shipped`).
  - In postcard detail buyer action area:
    - Shows explicit status (`Waiting, seller to ship`, `Shipped, on-the-way`).
    - Shows `Buy` only when no active order exists.
    - Tapping `Buy` opens the shared custom `HoneyMessageBox` dialog with tokenized text parsing (`{honey_icon}`) rendered as inline text icon content, so text wrapping keeps icon position within sentence flow.
    - Inline HoneyIcon size used in tokenized message text is owner-tunable via `AppConfig.SharedUI.honeyMessageIconSize`.
    - Shows `Confirm received, complete transaction` when order is `Shipped` (replaces buy action).
- Postcard create/edit/delete confirmations, shipping confirmations, buyer receive confirmations, success notices, and error notices all use shared `HoneyMessageBox` (no system alerts/confirmation dialogs).
- Register/edit forms use left-label and right-input rows.
- Register/edit forms start with pre-filled defaults for title, price, province, stock, and description (instead of gray placeholder hints).
- Register/edit forms dismiss keyboard on outside taps (without collapsing during scroll), on keyboard `Enter`/`Done`, and before submit/delete actions, and auto-scroll focused inputs above keyboard overlap.
- Register/edit description field auto-selects all content on focus.
- Country selector is dropdown-based and uses the same country source as room host form.
- Register form defaults country to Taiwan (`TW`).
- Snapshot area itself opens photo picker (no separate upload button).
- UI-test mock postcard mode (`--mock-postcards`) shows a quick submit button in create flow to bypass image upload and backend writes.
- UI-test mock postcard mode also mocks seller shipping recipients and "mark sent" flow without Firestore writes.
- UI-test mode hides seller share/edit toolbar actions so shipping action remains directly tappable in automated UI runs.
- UI-test mode supports postcard deep-link routing via launch arg `--ui-open-postcard {postcardId}` for deterministic invite-entry automation.
- Detail text field is capped at 100 characters.
- Detail placeholder text is localized via `postcard_detail_placeholder`.

## Cloud Functions (Postcard Use Cases)
- `sendPostcardOrderCreatedPush`
  - Trigger: create on `postcardOrders/{orderId}`
  - Sends only when new order status is `AwaitingShipping`
  - Push target: `postcardOrders/{orderId}.sellerFcmToken` first, with `users/{sellerId}.fcmToken` fallback
  - Payload data: `type=postcard_order_created`, `orderId`, `postcardId`
- `sendPostcardShippedPush`
  - Trigger: update on `postcardOrders/{orderId}`
  - Sends only when order status transitions into `Shipped`
  - Push target: `postcardOrders/{orderId}.buyerFcmToken` first, with `users/{buyerId}.fcmToken` fallback
  - Payload data: `type=postcard_shipped`, `orderId`, `postcardId`
- `sendPostcardRejectedPush`
  - Trigger: update on `postcardOrders/{orderId}`
  - Sends only when order status transitions into `Rejected`
  - Push target: `postcardOrders/{orderId}.buyerFcmToken` first, with `users/{buyerId}.fcmToken` fallback
  - Payload data: `type=postcard_rejected`, `orderId`, `postcardId`, `honey`
- `notifySellerPostcardCompleted`
  - Trigger: update on `postcardOrders/{orderId}`
  - Sends only when order status transitions into `Completed` or `CompletedAuto`
  - Push target: `postcardOrders/{orderId}.sellerFcmToken` first, with `users/{sellerId}.fcmToken` fallback
  - Payload data: `type=postcard_order_completed`, `orderId`, `postcardId`, `honey`
- `processPostcardOrderTimeouts`
  - Trigger: scheduler every 15 minutes
  - Processes order deadline transitions:
    - `AwaitingShipping` timeout -> `FailedSellerNoShip` (+ buyer refund, stock restore)
    - `Shipped` timeout -> `CompletedAuto` (+ seller payout)

### Firebase Storage
- Path: `postcards/{ownerId}/{uuid}.jpg` where `ownerId` is the authenticated uploader uid.
- Image is uploaded with `image/jpeg` metadata and the download URL is stored in `postcards.imageUrl`.
- Uploaded postcard images are tagged with `Cache-Control: public,max-age=86400` metadata, and client also persists local memory+disk cache for cache-first rendering.
- Cache sizing/TTL is owner-tunable in `AppConfig.Postcard` (`imageMemoryCacheEntryLimit`, `imageDiskCacheMaxBytes`, `imageDiskCachePruneTargetRatio`, `imageDiskCacheMaxAgeSeconds`).
- Client-side upload preprocessing crops postcard snapshots to fixed pixel rect `(x:20, y:20) -> (x:665, y:655)` before JPEG encoding/upload.
- If the selected source image cannot safely contain that crop rect, client shows an error and skips upload.

#### `postcards/{postcardId}`
Postcard marketplace listings. Client reads for browse, creates from Postcard Register, and seller can edit/delete from Postcard Detail.
Fields:
- `title` (String): listing title.
- `priceHoney` (Int): price per postcard.
- `sellerId` (String): seller uid for ownership checks.
- `sellerName` (String): seller display name.
- `sellerFriendCode` (String): seller friend code snapshot used by detail display to avoid extra user reads.
- `sellerFcmToken` (String, optional): seller push token snapshot used by order-push functions.
- `stock` (Int): available quantity.
- `imageUrl` (String, optional): public URL of postcard image.
- `thumbnailUrl` (String, optional): low-resolution public URL used by browse cards.
- `location` (Map): `{ country, province, detail }` strings.
- `searchTokens` ([String]): normalized tokens for search.
- `createdAt` (Timestamp): listing creation time.
- `updatedAt` (Timestamp): last listing update time.
Notes:
- Register flow uploads full image + compressed thumbnail to Firebase Storage first, then writes listing doc URLs.
- `searchTokens` are generated by `SearchTokenBuilder` from title + seller name + location fields for search.
- Client UI input caps: `title` max `20` chars, `location.province` max `20` chars, `location.detail` max `100` chars.
- Postcard detail view behavior:
  - Seller (`auth.uid == sellerId`) sees three toolbar icons for shipping, sharing, and editing.
  - Seller can share invite QR/link, update listing fields, or delete listing.
  - Non-seller sees buy action button and buyer-order status hints.
  - Buy button is disabled while the buyer has an active order for that postcard.
  - When order status is `Shipped`, buyer sees explicit `Confirm received, complete transaction` action.
  - On buy, client runs Firestore transaction: decrements `stock` and deducts buyer `users/{uid}.honey` atomically.
  - Seller friend code is shown from `postcards.sellerFriendCode` snapshot only (no detail-screen fallback user read).
  - Postcard create/edit form clamps numeric input to avoid integer overflow (`priceHoney` max `1,000,000,000`; `stock` max `1,000,000`).
  - On edit image replacement, old full/thumbnail objects are deleted with best-effort cleanup.
  - On listing delete, Firestore doc and linked full/thumbnail storage objects are deleted (best effort for storage).

#### `postcardOrders/{orderId}`
Postcard transaction documents created when buyer confirms purchase.
Fields:
- `postcardId` (String): source listing id.
- `postcardTitle` (String): snapshot title at purchase time.
- `postcardImageUrl` (String): snapshot image URL at purchase time.
- `location` (Map): snapshot `{ country, province, detail }`.
- `status` (String): current transaction state. New orders start as `AwaitingShipping` (legacy `SellerConfirmPending` may still exist in old data).
- `buyerId` (String): buyer uid.
- `buyerName` (String): buyer display name snapshot.
- `buyerFriendCode` (String): buyer friend code snapshot used by seller shipping list.
- `buyerFcmToken` (String, optional): buyer push token snapshot used by order-push functions.
- `sellerId` (String): seller uid.
- `sellerName` (String): seller display name snapshot.
- `sellerFcmToken` (String, optional): seller push token snapshot copied from listing.
- `priceHoney` (Int): listing price at purchase.
- `holdHoney` (Int): honey held for escrow (equal to `priceHoney` in MVP).
- `sellerShippingDeadlineAt` (Timestamp): seller shipping deadline set at order creation.
- `buyerReminderAt` (Timestamp, optional): buyer reminder anchor after seller marks shipped.
- `buyerConfirmDeadlineAt` (Timestamp, optional): buyer confirmation deadline after shipment.
- `sentAt` (Timestamp, optional): set when seller marks postcard sent.
- `completedAt` (Timestamp, optional): set when buyer confirms receipt and transaction completes.
- `timeouts` (Map): hour-based parameters written to each order:
  - `sellerShippingDeadlineHours`
  - `buyerReceiveReminderHours`
  - `buyerConfirmDeadlineHours`
- `createdAt` (Timestamp): order creation time.
- `updatedAt` (Timestamp): latest order update time.
Notes:
- Seller decline action transitions status from `AwaitingShipping` -> `Rejected` and refunds buyer + restores stock.
- Seller decline action also sends buyer push notification that order was rejected/canceled and honey was fully refunded.
- Seller shipping action transitions status from `AwaitingShipping` -> `Shipped` and updates `sentAt`, `buyerReminderAt`, and `buyerConfirmDeadlineAt`.
- Buyer confirmation transitions status to `Completed` and transfers `holdHoney` to seller `users/{sellerId}.honey`.
- Timeout sweep can transition into `FailedSellerNoShip` and `CompletedAuto`.
- Postcard push notification copy is localized through APNs localization keys backed by app `Localizable.strings` entries.
- Browse/search list fetch is paginated by `AppConfig.Postcard.browseListFetchLimit` (`20`) and uses cursor-based "Load more".
- Profile ordered-postcards view uses one server-side query: `buyerId + status in [AwaitingShipping, Shipped]` (plus legacy aliases), ordered by `createdAt desc`, limited by profile fetch cap.
- Buyer latest-order lookup uses a server-side query with `buyerId + postcardId + status in [AwaitingShipping, Shipped]` (plus legacy aliases), ordered by `createdAt desc`, limited to `1`.
- Shipping recipients are fetched with server-side filters on `postcardId`, `sellerId`, and `status in [AwaitingShipping]` (plus legacy aliases); buyer friend codes are read from order snapshots with users lookup fallback for legacy orders.
- Register/edit upload flow performs best-effort cleanup of newly uploaded image blobs if subsequent Firestore write fails.
