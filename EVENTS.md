# Events

## Related Files
- `functions/index.js`: event producers, event-history writes, Action Event resolution, and push emission.
- `mushroomHunter/Features/EventInbox/EventInboxStore.swift`: event-history reads, pagination, Action/Record rendering semantics.
- `mushroomHunter/Features/EventInbox/EventInboxView.swift`: inbox list UI and row tap behavior.
- `mushroomHunter/Features/Mushroom/RoomBrowseView.swift`: mushroom-tab bell tap handler that refreshes inbox before presenting it.
- `mushroomHunter/Features/Postcard/PostcardBrowseView.swift`: postcard-tab bell tap handler that refreshes inbox before presenting it.
- `mushroomHunter/Features/DailyReward/DailyRewardView.swift`: DailyReward claim flow that refreshes inbox after successful reward event creation.
- `mushroomHunter/App/HoneyHubApp.swift`: APNs tap routing (`room`/`postcard`) and inbox refresh hooks.
- `mushroomHunter/Resources/en.lproj/Localizable.strings`: English `event_type_*` and `push_*` localization keys.
- `mushroomHunter/Resources/zh-Hant.lproj/Localizable.strings`: Traditional Chinese `event_type_*` and `push_*` localization keys.

## Scope
- This file is the single review doc for event history and event-driven push notification behavior.
- Event history storage target: `users/{uid}/events/{eventId}`.
- Event display text is stored as snapshot text in each event document (`title`, `message`) when the event is created.

## Client Refresh Timing (Current Policy)
- Bell tap refresh: when user taps the top-right bell icon, app must call `refreshFromServer()` first, then open the inbox sheet so the list is the latest from Firestore.
- Action Event push refresh: when app receives a push whose `type` is an Action Event (`JOIN_REQUESTED_HOST`, `RAID_CONFIRM_ATTENDEE`, `POSTCARD_ORDER_SELLER`, `POSTCARD_SENT_BUYER`), app immediately applies delivered APS badge when present and also forces `refreshFromServer()` plus app-shell badge recomputation so icon/tab counts stay accurate.
- No other automatic refresh timing is enabled for inbox list sync.

## Event History Collection

### Path
- `users/{uid}/events/{eventId}`

### Document ID
- `${cloudEventId}_${uid}`

### Fields
Current event document fields:
- `type` (String): backend event type code.
- `title` (String): snapshot title shown in event list.
- `message` (String): snapshot message shown in event list.
- `roomId` (String): room target id when room-related.
- `postcardId` (String): postcard target id when postcard-related.
- `orderId` (String): postcard order id when applicable.
- `relatedUid` (String): related user id for action-correlation flows (for example host-side join-request action rows).
- `isActionEvent` (Bool): true when the event requires user action.
- `isResolved` (Bool): true when the action is already processed; record events are written as resolved.
- `isRead` (Bool): true when the user has already opened the action row from the inbox; unresolved action events stop showing red-dot/bold emphasis after they are read.
- `createdAt` (Timestamp): event creation time.

## Global Policy
- Only Event flows can send push notifications.
- A push sender must first produce at least one event document in the same Cloud Function flow.
- Not all events send push notifications.
- Every Action Event must always send push notification.
- Badge count counts unresolved Action Events only.
- Action Event push payload must include APNs `aps.badge` using latest unresolved Action Event count for receiver, so home-screen app icon badge updates immediately even when app is backgrounded.
- For push-enabled events, push copy and event-list copy are generated from the same server-side snapshot text (`title`/`message`) per user locale at event creation time.
- Inbox highlight state is stricter than badge state: a row stays highlighted only while it is both unresolved and unread.

## Stored Event Types (`users/{uid}/events.type`)

### Mushroom Events

- `HONEY_REWARD`
  - Class: Record Event.
  - Producer: `claimDailyHoneyReward`.
  - Trigger: user successfully claims today's DailyReward honey.
  - Target: claimant
  - Title(Eng): `Honey Reward`
  - Title(Chinese): `蜂蜜獎勵`
  - Message(Eng): `You have received %@ honey as reward.`
  - Message(Chinese): `您已獲得 %@ 蜂蜜獎勵。`
  - Push: none.

- `ROOM_CREATED_HOST`
  - Class: Record Event.
  - Producer: `recordRoomCreatedEvent`.
  - Trigger: room document created.
  - Target: host
  - Title(Eng): `Mushroom Room Created`
  - Title(Chinese): `已建立蘑菇房`
  - Message(Eng): `You created a mushroom room: %@.`
  - Message(Chinese): `您已建立蘑菇房間：%@。`
  - Push: none.

- `ROOM_CLOSED_HOST`
  - Class: Record Event.
  - Producer: `recordRoomClosedEvent`.
  - Trigger: room document deleted (host closes room).
  - Target: host
  - Title(Eng): `Mushroom Room Closed`
  - Title(Chinese): `已關閉蘑菇房`
  - Message(Eng): `You closed a mushroom room: %@.`
  - Message(Chinese): `您已關閉蘑菇房間：%@。`
  - Push: none.

- `JOIN_REQUESTED_ATTENDEE`
  - Class: Record Event.
  - Producer: `notifyHostJoinRequest`.
  - Trigger: attendee creates `AskingToJoin` row (joiner copy).
  - Target: attendee
  - Title(Eng): `Sent Join Request`
  - Title(Chinese): `已送出加入申請`
  - Message(Eng): `You sent a request to join %@.`
  - Message(Chinese): `您已送出加入 %@ 申請。`
  - Push: none.

- `JOIN_REQUESTED_HOST`
  - Class: Action Event.
  - Producer: `notifyHostJoinRequest`.
  - Trigger: attendee creates `AskingToJoin` row (host copy).
  - Target: host
  - Push: `notifyHostJoinRequest`.
  - Title(Eng): `New Join Request`
  - Title(Chinese): `申請加入`
  - Message(Eng): `%@ requested to join %@. Tap to respond`
  - Message(Chinese): `%@ 申請加入 %@，點擊以回覆。`

- `JOIN_ACCEPTED_ATTENDEE`
  - Class: Record Event.
  - Producer: `handleRoomAttendeeUpdatedEvents`.
  - Trigger: attendee status `AskingToJoin -> Ready` (joiner copy).
  - Target: attendee
  - Push: `handleRoomAttendeeUpdatedEvents`.
  - Title(Eng): `Join Request Accepted`
  - Title(Chinese): `加入申請已接受`
  - Message(Eng): `Host accepted your request to join %@.`
  - Message(Chinese): `主持人已接受您加入 %@ 的申請。`

- `JOIN_ACCEPTED_HOST`
  - Class: Record Event.
  - Producer: `handleRoomAttendeeUpdatedEvents`.
  - Trigger: attendee status `AskingToJoin -> Ready` (host copy).
  - Target: host
  - Title(Eng): `New Joiner Accepted`
  - Title(Chinese): `新成員加入`
  - Message(Eng): `%@ joined your room: %@.`
  - Message(Chinese): `%@ 已加入房間：%@。`
  - Push: none.

- `JOIN_REJECTED_ATTENDEE`
  - Class: Record Event.
  - Producer: `notifyJoinApplicantRejected`.
  - Trigger: `AskingToJoin` attendee row deleted (joiner copy).
  - Target: attendee
  - Push: `notifyJoinApplicantRejected`.
  - Title(Eng): `Join Request Rejected`
  - Title(Chinese): `已拒絕加入申請`
  - Message(Eng): `Host rejected your request to join %@.`
  - Message(Chinese): `主持人已拒絕您加入 %@ 的申請。`

- `JOIN_REJECTED_HOST`
  - Class: Record Event.
  - Producer: `notifyJoinApplicantRejected`.
  - Trigger: `AskingToJoin` attendee row deleted (host copy).
  - Target: host
  - Title(Eng): `Joiner Rejected`
  - Title(Chinese): `已拒絕加入申請`
  - Message(Eng): `You rejected a join request from %@.`
  - Message(Chinese): `您已拒絕來自 %@ 的加入申請。`
  - Push: none.

- `KICKED_ATTENDEE`
  - Class: Record Event.
  - Producer: `recordRoomKickEvents`.
  - Trigger: When attendee has been kicked out of a room 
  - Target: attendee
  - Push: none.
  - Title(Eng): `Kicked Out`
  - Title(Chinese): `已被踢出房間`
  - Message(Eng): `You have been kicked out of room: %@. Your deposited %@ honey has been returned.`
  - Message(Chinese): `您已被踢出房間:%@，您儲值的%@蜂蜜已返還。`

- `KICKED_HOST`
  - Class: Record Event.
  - Producer: `recordRoomKickEvents`.
  - Trigger: When attendee has been kicked out of a room 
  - Target: host
  - Title(Eng): `Kicked Out`
  - Title(Chinese): `已將玩家踢出房間`
  - Message(Eng): `You kicked %@ out of room: %@.`
  - Message(Chinese): `您已將%@踢出房間:%@`
  - Push: none.


- `RAID_INVITED_HOST`
  - Class: Record Event.
  - Producer: `recordHostRaidInviteEvent`.
  - Trigger: new raid confirmation cycle prepended in room history.
  - Target: host
  - Title(Eng): `Mushroom Raid Invited`
  - Title(Chinese): `已發送蘑菇邀請`
  - Message(Eng): `Raid confirmation invitations were sent to all attendees, wait for them to confirm.`
  - Message(Chinese): `您已發送蘑菇邀請確認，等待所有參加者確認。`
  - Push: none.

- `RAID_CONFIRM_ATTENDEE`
  - Class: Action Event.
  - Producer: `handleRoomAttendeeUpdatedEvents`.
  - Trigger: attendee status transitions into `WaitingConfirmation`, or host appends a new key into `pendingConfirmationRequests` for that attendee while they are already in `WaitingConfirmation`.
  - Target: attendee
  - Push: `handleRoomAttendeeUpdatedEvents`.
  - Title(Eng): `Mushroom Invitation`
  - Title(Chinese): `蘑菇邀請確認`
  - Message(Eng): `Action required: confirm whether you received the mushroom raid invitation from %@.`
  - Message(Chinese): `需要處理：請確認您是否收到來自 %@ 的蘑菇邀請。`
  - Message args: host display name resolved from room host snapshot/user profile fallback.

- `REPLY_HOST`
  - Class: Record Event.
  - Producer: `handleRoomAttendeeUpdatedEvents`.
  - Trigger: attendee status `WaitingConfirmation -> Ready`.
  - Target: host
  - Push: `handleRoomAttendeeUpdatedEvents`.
  - Title(Eng): `Attendee Confirmed` or `Attendee Missed Invite`
  - Title(Chinese): `參加者已確認` or `參加者未看到邀請`
  - Message(Eng): `%@ confirmed raid join and paid you %@ honey.` or `%@ reported invited but seat full and paid you %@ honey.` or `%@ reported no invitation was seen.`
  - Message(Chinese): `%@ 已確認參加戰鬥，已支付您 %@ 蜂蜜。` or `%@ 回報蘑菇滿位，已支付您 %@ 蜂蜜。` or `%@ 回報未看到邀請。`

- `STAR_RECEIVED`
  - Class: Record Event.
  - Producer: `handleRoomAttendeeUpdatedEvents` (legacy mushroom attendee-flag flow), `handleRoomRatingTaskUpdatedEvents` (current mushroom queue-rating flow), `handlePostcardOrderUpdatedEvents`.
  - Trigger: mushroom room-rating task transitions to `Rated`, legacy mushroom attendee-rating transition, or postcard order-rating transition emits receiver-side history.
  - Target: receiver
  - Push: `handleRoomAttendeeUpdatedEvents`, `handleRoomRatingTaskUpdatedEvents`, `handlePostcardOrderUpdatedEvents`.
  - Title(Eng): `Stars Received`
  - Title(Chinese): `收到評價`
  - Message(Eng): `%@ gave you %@ stars.`
  - Message(Chinese): `%@ 給了您 %@ 顆星。`

### Postcard Events

- `POSTCARD_CREATED_SELLER`
  - Class: Record Event.
  - Producer: `recordPostcardCreatedEvent`.
  - Trigger: postcard listing created.
  - Target: seller
  - Title(Eng): `Postcard Registered`
  - Title(Chinese): `已上架明信片`
  - Message(Eng): `You registered a postcard: %@.`
  - Message(Chinese): `您已上架明信片：%@。`
  - Push: none.

- `POSTCARD_CLOSED_SELLER`
  - Class: Record Event.
  - Producer: `recordPostcardClosedEvent`.
  - Trigger: postcard listing deleted (seller removes from market).
  - Target: seller
  - Title(Eng): `Postcard Removed`
  - Title(Chinese): `明信片已下架`
  - Message(Eng): `You removed a postcard from market: %@.`
  - Message(Chinese): `您已將明信片從市場下架：%@。`
  - Push: none.

- `POSTCARD_ORDER_SELLER`
  - Class: Action Event.
  - Producer: `sendPostcardOrderCreatedPush`.
  - Trigger: order created in `AwaitingShipping` (seller copy).
  - Target: seller
  - Push: `sendPostcardOrderCreatedPush`.
  - Title(Eng): `New Postcard Order`
  - Title(Chinese): `收到新訂單`
  - Message(Eng): `Action required: process a new order.`
  - Message(Chinese): `需要處理：請處理新的明信片訂單。`

- `POSTCARD_ORDER_BUYER`
  - Class: Record Event.
  - Producer: `sendPostcardOrderCreatedPush`.
  - Trigger: order created in `AwaitingShipping` (buyer copy).
  - Target: buyer
  - Title(Eng): `Order Sent`
  - Title(Chinese): `訂單已送出`
  - Message(Eng): `You placed a postcard order on %@.`
  - Message(Chinese): `您已送出明信片訂單：%@。`
  - Push: none.

- `POSTCARD_SENT_BUYER`
  - Class: Action Event.
  - Producer: `handlePostcardOrderUpdatedEvents`.
  - Trigger: order status transitions into `Shipped` (buyer copy).
  - Target: buyer
  - Push: `handlePostcardOrderUpdatedEvents`.
  - Title(Eng): `Postcard Shipped`
  - Title(Chinese): `明信片已寄出`
  - Message(Eng): `Action required: confirm postcard receipt: %@.`
  - Message(Chinese): `需要處理：請確認是否已收到明信片：%@。`
  
- `POSTCARD_SENT_SELLER`
  - Class: Record Event.
  - Producer: `handlePostcardOrderUpdatedEvents`.
  - Trigger: order status transitions into `Shipped` (seller copy).
  - Target: seller
  - Title(Eng): `Postcard Sent`
  - Title(Chinese): `明信片已寄出`
  - Message(Eng): `You have shipped postcard %@ to %@.`
  - Message(Chinese): `您已將 %@ 寄給 %@。`
  - Push: none.

- `POSTCARD_RECEIVED_SELLER`
  - Class: Record Event.
  - Producer: `handlePostcardOrderUpdatedEvents`.
  - Trigger: order status transitions into `Completed` or `CompletedAuto` (seller copy).
  - Target: seller
  - Push: `handlePostcardOrderUpdatedEvents`.
  - Title(Eng): `Order Completed`
  - Title(Chinese): `訂單完成`
  - Message(Eng): `%@ confirmed receipt. %@ honey has been transferred to you.`
  - Message(Chinese): `%@ 已確認收件，%@ 蜂蜜已轉給您。`
  - Placeholder order: first argument is buyer name, second argument is the honey amount transferred to the seller.
  - Event arg contract: server stores an internal leading completion-mode discriminator (`manual` or `auto`) and remaps placeholders so manual completion still renders buyer name first and honey amount second.
  - Note: if order is `CompletedAuto`, the message becomes `%@ postcard received timed out. %@ honey has been transferred to you.` / `「%@」收件確認逾時，%@ 蜂蜜已轉給您。`.
  - Note: seller-side postcard rating is not attached to this event row; the completed order doc carries `isSellerRatingRequired` until the seller rates the buyer.

- `POSTCARD_RECEIVED_BUYER`
  - Class: Record Event.
  - Producer: `handlePostcardOrderUpdatedEvents`.
  - Trigger: order status transitions into `Completed` or `CompletedAuto` (buyer copy).
  - Target: buyer
  - Title(Eng): `Postcard Received`
  - Title(Chinese): `買家已收到明信片`
  - Message(Eng): `You confirmed to receive postcard: %@.`
  - Message(Chinese): `您已確認收到明信片：%@。`
  - Push: none.
  - Note: manual `Completed` orders set `isBuyerRatingRequired` and `isSellerRatingRequired` on the order so both sides can submit stars later; `CompletedAuto` leaves postcard rating unavailable.

- `POSTCARD_REJECTED_BUYER`
  - Class: Record Event.
  - Producer: `handlePostcardOrderUpdatedEvents`.
  - Trigger: order status transitions into `Rejected` (buyer copy).
  - Target: buyer
  - Push: `handlePostcardOrderUpdatedEvents`.
  - Title(Eng): `Order Rejected`
  - Title(Chinese): `訂單已拒絕`
  - Message(Eng): `Your order for "%@" was rejected and canceled. %@ honey has been fully refunded to your account.`
  - Message(Chinese): `您購買「%@」的訂單已被拒絕並取消，%@ 蜂蜜已全額退回。`

- `POSTCARD_REJECTED_SELLER`
  - Class: Record Event.
  - Producer: `handlePostcardOrderUpdatedEvents`.
  - Trigger: order status transitions into `Rejected` (seller copy).
  - Target: seller
  - Title(Eng): `Order Rejected`
  - Title(Chinese): `訂單已拒絕`
  - Message(Eng): `You rejected a postcard order: %@.`
  - Message(Chinese): `您已拒絕明信片訂單：%@。`
  - Push: none.

### Profile Events

- `NAME_UPDATED`
  - Class: Record Event.
  - Producer: `recordUserProfileAndWalletEvents`.
  - Trigger: `users/{uid}.displayName` changed.
  - Target: self
  - Title(Eng): `Display Name Updated`
  - Title(Chinese): `名稱已更新`
  - Message(Eng): `Your display name was updated.`
  - Message(Chinese): `您的顯示名稱已更新。`
  - Push: none.

- `FRIEND_CODE_UPDATED`
  - Class: Record Event.
  - Producer: `recordUserProfileAndWalletEvents`.
  - Trigger: `users/{uid}.friendCode` changed.
  - Target: self
  - Title(Eng): `Friend Code Updated`
  - Title(Chinese): `好友碼已更新`
  - Message(Eng): `Your friend code was updated to %@.`
  - Message(Chinese): `您的好友碼已更新為 %@。`
  - Push: none.

## Resolution Rules
- `RAID_CONFIRM_ATTENDEE`: resolved when attendee submits one confirmation outcome.
- `JOIN_REQUESTED_HOST`: resolved when host accepts or rejects that request.
- `POSTCARD_ORDER_SELLER`: resolved when seller marks shipped or rejects order.
- `POSTCARD_SENT_BUYER`: resolved when buyer confirms received (or timeout auto-completion finalizes order).

## Implementation Notes
- Push data `type` now matches the event type for all push-enabled events.
- Action Event pushes set `aps.badge` from `users/{uid}/events` unresolved Action Event aggregate count.
- Badge injection classifies Action Event by `type` and also falls back to pushed `eventId` doc (`users/{uid}/events/{eventId}.isActionEvent`) so newly added Action Event types still get badge updates without missing APNs badge.
- `REPLY_HOST` includes extra push field `outcome` with values `raid_confirmation_seat_full`, `raid_confirmation_missed_invite`, or `raid_confirmation_accepted`.
