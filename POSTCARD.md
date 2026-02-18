# Postcard

## Related Files
- `mushroomHunter/Features/Postcard/PostcardBrowseView.swift`: postcard tab root + listing browse/search UI and listing cards.
- `mushroomHunter/Features/Postcard/PostcardView.swift`: postcard detail screen with buyer/seller actions.
- `mushroomHunter/Features/Postcard/PostcardShippingView.swift`: seller shipping queue and send confirmation flow.
- `mushroomHunter/Features/Postcard/PostcardFormView.swift`: consolidated postcard create/edit form implementation.
- `mushroomHunter/Features/Postcard/PostcardBrowseViewModel.swift`: browse filtering, sorting, and refresh state logic.
- `mushroomHunter/Features/Postcard/PostcardDomainModel.swift`: postcard listing/order/location models and status enums.
- `mushroomHunter/Features/Shared/BrowseViewTopActionBar.swift`: shared honey/search/create header used by browse screens.
- `mushroomHunter/Features/Shared/SelectAllTextField.swift`: shared auto-select text field wrapper used by postcard form inputs.
- `mushroomHunter/Features/Shared/SelectAllTextEditor.swift`: shared auto-select text editor wrapper used by postcard description inputs.
- `mushroomHunter/Services/Firebase/PostcardRepo.swift`: Firestore operations for listings, orders, shipping, and receipt confirmation.
- `mushroomHunter/Services/Firebase/PostcardImageUploader.swift`: image crop/encode/upload to Firebase Storage.
- `mushroomHunter/Utilities/RoomInviteLink.swift`: postcard invite link generation/parsing for `honeyhub://postcard/{postcardId}`.
- `mushroomHunter/Utilities/SearchTokens.swift`: normalized token generation for postcard search fields.
- `mushroomHunter/Utilities/AppConfig.swift`: centralized owner-managed postcard settings (price/stock/text caps, fetch limits, order timeout windows).
- `mushroomHunter/Utilities/FriendCode.swift`: shared friend-code sanitizing/formatting/validation utility used across profile, room, and postcard flows.
- `mushroomHunter/App/mushroomHunterApp.swift`: handles postcard deep-link routing from invite links.
- `mushroomHunter/App/ContentView.swift`: presents postcard detail sheet when a postcard invite link is opened.
- `mushroomHunter/Features/Shared/InviteShareSheet.swift`: shared invite QR sheet component reused by postcard detail.
- `functions/index.js`: server-side push triggers for postcard order/shipping/completion events.

## Feature Coverage
- Browse and search postcard listings.
- Browse search prompt is presented as a sheet, and its text input auto-selects all text on focus via shared `SelectAllTextField`.
- Register flow uploads postcard image to Firebase Storage, then creates Firestore listing.
- Register success dismisses the sheet and refreshes browse list.
- Pull-to-refresh is supported in postcard browse, detail, and shipping flows.
- Seller can open shipping sheet in postcard detail to see waiting buyers and mark each order as sent.
- Seller can open a top-right share action in postcard detail to show an invite sheet with QR code, share link, and copy link actions.
- Postcard invite links use deep link format `honeyhub://postcard/{postcardId}`.
- Opening a postcard invite link routes to postcard detail in-app when the listing still exists.
- Buyer order lifecycle:
  - Buyer places order -> seller receives push to process shipping.
  - Seller marks shipped (`InTransit`) -> buyer receives push.
  - Buyer confirms receipt:
    - `Yes`: completes transaction and transfers held honey to seller.
    - `No`: keeps honey on hold and continues waiting.
- Register/edit forms use left-label and right-input rows.
- Register/edit forms start with pre-filled defaults for title, price, province, stock, and description (instead of gray placeholder hints).
- Register/edit description field auto-selects all content on focus.
- Country selector is dropdown-based and uses the same country source as room host form.
- Register form defaults country to Taiwan (`TW`).
- Snapshot area itself opens photo picker (no separate upload button).
- Detail text field is capped at 100 characters.
- Detail placeholder text is localized via `postcard_detail_placeholder`.

## Cloud Functions (Postcard Use Cases)
- `sendPostcardOrderCreatedPush`
  - Trigger: create on `postcardOrders/{orderId}`
  - Sends only when new order status is `AwaitingSellerSend`
  - Push target: `postcardOrders/{orderId}.sellerFcmToken` first, with `users/{sellerId}.fcmToken` fallback
  - Payload data: `type=postcard_order_created`, `orderId`, `postcardId`
- `sendPostcardShippedPush`
  - Trigger: update on `postcardOrders/{orderId}`
  - Sends only when order status transitions into `InTransit`
  - Push target: `postcardOrders/{orderId}.buyerFcmToken` first, with `users/{buyerId}.fcmToken` fallback
  - Payload data: `type=postcard_shipped`, `orderId`, `postcardId`
- `notifySellerPostcardCompleted`
  - Trigger: update on `postcardOrders/{orderId}`
  - Sends only when order status transitions into `Completed`
  - Push target: `postcardOrders/{orderId}.sellerFcmToken` first, with `users/{sellerId}.fcmToken` fallback
  - Payload data: `type=postcard_order_completed`, `orderId`, `postcardId`, `honey`

### Firebase Storage
- Path: `postcards/{ownerId}/{uuid}.jpg` where `ownerId` is the authenticated uploader uid.
- Image is uploaded with `image/jpeg` metadata and the download URL is stored in `postcards.imageUrl`.
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
- `location` (Map): `{ country, province, detail }` strings.
- `searchTokens` ([String]): normalized tokens for search.
- `createdAt` (Timestamp): listing creation time.
- `updatedAt` (Timestamp): last listing update time.
Notes:
- Register flow uploads image to Firebase Storage first, then writes listing doc with returned `imageUrl`.
- `searchTokens` are generated by `SearchTokenBuilder` from title + seller name + location fields for search.
- Client UI input caps: `title` max `20` chars, `location.province` max `20` chars, `location.detail` max `100` chars.
- Postcard detail view behavior:
  - Seller (`auth.uid == sellerId`) sees share/edit/shipping toolbar actions and can share invite QR/link, update listing fields, or delete listing.
  - Non-seller sees buy action button only.
  - On buy, client runs Firestore transaction: decrements `stock` and deducts buyer `users/{uid}.honey` atomically.
  - Seller friend code is shown from `postcards.sellerFriendCode` snapshot only (no detail-screen fallback user read).
  - Postcard create/edit form clamps numeric input to avoid integer overflow (`priceHoney` max `1,000,000,000`; `stock` max `1,000,000`).

#### `postcardOrders/{orderId}`
Postcard transaction documents created when buyer confirms purchase.
Fields:
- `postcardId` (String): source listing id.
- `postcardTitle` (String): snapshot title at purchase time.
- `postcardImageUrl` (String): snapshot image URL at purchase time.
- `location` (Map): snapshot `{ country, province, detail }`.
- `status` (String): current transaction state. Starts as `AwaitingSellerSend`.
- `buyerId` (String): buyer uid.
- `buyerName` (String): buyer display name snapshot.
- `buyerFriendCode` (String): buyer friend code snapshot used by seller shipping list.
- `buyerFcmToken` (String, optional): buyer push token snapshot used by order-push functions.
- `sellerId` (String): seller uid.
- `sellerName` (String): seller display name snapshot.
- `sellerFcmToken` (String, optional): seller push token snapshot copied from listing.
- `priceHoney` (Int): listing price at purchase.
- `holdHoney` (Int): honey held for escrow (equal to `priceHoney` in MVP).
- `sellerReminderAt` (Timestamp): next seller reminder time.
- `sellerDeadlineAt` (Timestamp): current seller deadline.
- `buyerReminderAt` (Timestamp): default buyer reminder anchor.
- `buyerAutoCompleteAt` (Timestamp): default buyer auto-complete deadline anchor.
- `sentAt` (Timestamp, optional): set when seller marks postcard sent.
- `completedAt` (Timestamp, optional): set when buyer confirms receipt and transaction completes.
- `timeouts` (Map): hour-based parameters written to each order:
  - `sellerSendReminderHours`
  - `sellerSendDeadlineHours`
  - `buyerReceiveReminderHours`
  - `buyerAutoCompleteHours`
- `createdAt` (Timestamp): order creation time.
- `updatedAt` (Timestamp): latest order update time.
Notes:
- Seller shipping action transitions status from `AwaitingSellerSend` -> `InTransit` and updates `sentAt`, `buyerReminderAt`, and `buyerAutoCompleteAt`.
- Buyer "not received yet" keeps honey on hold and sets status to `AwaitingBuyerDecision`.
- Buyer confirmation transitions status to `Completed` and transfers `holdHoney` to seller `users/{sellerId}.honey`.
- Profile ordered-postcards view uses one server-side query: `buyerId + status in [AwaitingSellerSend, InTransit, AwaitingBuyerDecision]`, ordered by `createdAt desc`, limited by profile fetch cap.
- Buyer latest-order lookup uses a server-side query with `buyerId + postcardId + status in [AwaitingSellerSend, InTransit, AwaitingBuyerDecision]`, ordered by `createdAt desc`, limited to `1`.
- Shipping recipients are fetched with server-side filters on `postcardId`, `sellerId`, and `status = AwaitingSellerSend`; buyer friend codes are read from order snapshots with users lookup fallback for legacy orders.
- Register/edit upload flow performs best-effort cleanup of newly uploaded image blobs if subsequent Firestore write fails.
