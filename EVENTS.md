# Events

## Related Files
- `functions/index.js`: event producers, event-history writes, Action Event resolution, and push emission.
- `mushroomHunter/User/NotificationInboxStore.swift`: event-history reads, pagination, Action/Record rendering semantics.
- `mushroomHunter/Features/Shared/NotificationInboxView.swift`: inbox list UI and row tap behavior.
- `mushroomHunter/Features/Mushroom/RoomBrowseView.swift`: mushroom-tab bell tap handler that refreshes inbox before presenting it.
- `mushroomHunter/Features/Postcard/PostcardBrowseView.swift`: postcard-tab bell tap handler that refreshes inbox before presenting it.
- `mushroomHunter/App/HoneyHubApp.swift`: APNs tap routing (`room`/`postcard`) and inbox refresh hooks.
- `mushroomHunter/Resources/en.lproj/Localizable.strings`: English `event_type_*` and `push_*` localization keys.
- `mushroomHunter/Resources/zh-Hant.lproj/Localizable.strings`: Traditional Chinese `event_type_*` and `push_*` localization keys.

## Scope
- This file is the single review doc for event history and event-driven push notification behavior.
- Event history storage target: `users/{uid}/events/{eventId}`.
- Event display text is stored as snapshot text in each event document (`title`, `message`) when the event is created.

## Client Refresh Timing (Current Policy)
- Bell tap refresh: when user taps the top-right bell icon, app must call `refreshFromServer()` first, then open the inbox sheet so the list is the latest from Firestore.
- Action Event push refresh: when app receives a push whose `type` is an Action Event (`JOIN_REQUESTED_HOST`, `RAID_CONFIRM_ATTENDEE`, `POSTCARD_ORDER_SELLER`, `POSTCARD_SENT_BUYER`), app must force `refreshFromServer()` so badge count stays accurate.
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
- `isResolved` (Bool): true when the action is already processed; record events are written as resolved. (This is the only field that can be changed)
- `createdAt` (Timestamp): event creation time.

## Global Policy
- Only Event flows can send push notifications.
- A push sender must first produce at least one event document in the same Cloud Function flow.
- Not all events send push notifications.
- Every Action Event must always send push notification.
- Badge count counts unresolved Action Events only.
- For push-enabled events, push copy and event-list copy are generated from the same server-side snapshot text (`title`/`message`) per user locale at event creation time.

## Stored Event Types (`users/{uid}/events.type`)

### Mushroom Events

- `ROOM_CREATED_HOST`
  - Class: Record Event.
  - Producer: `recordRoomCreatedEvent`.
  - Trigger: room document created.
  - Target: host
  - Title(Eng): `Mushroom Room Created`
  - Title(Chinese): `已建立蘑菇房`
  - Message(Eng): `You created a mushroom room: %@.`
  - Message(Chinese): `你已建立蘑菇房間：%@。`
  - Push: none.

- `ROOM_CLOSED_HOST`
  - Class: Record Event.
  - Producer: `recordRoomClosedEvent`.
  - Trigger: room document deleted (host closes room).
  - Target: host
  - Title(Eng): `Mushroom Room Closed`
  - Title(Chinese): `已關閉蘑菇房`
  - Message(Eng): `You closed a mushroom room: %@.`
  - Message(Chinese): `你已關閉蘑菇房間：%@。`
  - Push: none.

- `JOIN_REQUESTED_ATTENDEE`
  - Class: Record Event.
  - Producer: `notifyHostJoinRequest`.
  - Trigger: attendee creates `AskingToJoin` row (joiner copy).
  - Target: attendee
  - Title(Eng): `Sent Join Request`
  - Title(Chinese): `已送出加入申請`
  - Message(Eng): `You sent a request to join %@.`
  - Message(Chinese): `你已送出加入 %@ 申請。`
  - Push: none.

- `JOIN_REQUESTED_HOST`
  - Class: Action Event.
  - Producer: `notifyHostJoinRequest`.
  - Trigger: attendee creates `AskingToJoin` row (host copy).
  - Target: host
  - Push: `notifyHostJoinRequest`.
  - Title(Eng): `New Join Request`
  - Title(Chinese): `新加入申請`
  - Message(Eng): `%@ requested to join %@. Tap to respond`
  - Message(Chinese): `%@ 申請加入 %@。`

- `JOIN_ACCEPTED_ATTENDEE`
  - Class: Record Event.
  - Producer: `handleRoomAttendeeUpdatedEvents`.
  - Trigger: attendee status `AskingToJoin -> Ready` (joiner copy).
  - Target: attendee
  - Push: `handleRoomAttendeeUpdatedEvents`.
  - Title(Eng): `Join Request Accepted`
  - Title(Chinese): `加入申請已接受`
  - Message(Eng): `Host accepted your request to join %@.`
  - Message(Chinese): `主持人已接受你加入 %@ 的申請。`

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
  - Message(Chinese): `主持人已拒絕你加入 %@ 的申請。`

- `JOIN_REJECTED_HOST`
  - Class: Record Event.
  - Producer: `notifyJoinApplicantRejected`.
  - Trigger: `AskingToJoin` attendee row deleted (host copy).
  - Target: host
  - Title(Eng): `Joiner Rejected`
  - Title(Chinese): `已拒絕加入申請`
  - Message(Eng): `You rejected a join request from %@.`
  - Message(Chinese): `你已拒絕來自 %@ 的加入申請。`
  - Push: none.

- `RAID_INVITED_HOST`
  - Class: Record Event.
  - Producer: `recordHostRaidInviteEvent`.
  - Trigger: new raid confirmation cycle prepended in room history.
  - Target: host
  - Title(Eng): `Mushroom Raid Invited`
  - Title(Chinese): `已發送蘑菇邀請`
  - Message(Eng): `Raid confirmation invitations were sent to all attendees, wait for them to confirm.`
  - Message(Chinese): `你已發送蘑菇邀請確認，等待所有參加者確認。`
  - Push: none.

- `RAID_CONFIRM_ATTENDEE`
  - Class: Action Event.
  - Producer: `handleRoomAttendeeUpdatedEvents`.
  - Trigger: attendee status transitions into `WaitingConfirmation`.
  - Target: attendee
  - Push: `handleRoomAttendeeUpdatedEvents`.
  - Title(Eng): `Mushroom Invitation`
  - Title(Chinese): `蘑菇邀請確認`
  - Message(Eng): `Action required: confirm your mushroom raid result.`
  - Message(Chinese): `需要處理：請確認您是否收到蘑菇邀請。`

- `REPLY_HOST`
  - Class: Record Event.
  - Producer: `handleRoomAttendeeUpdatedEvents`.
  - Trigger: attendee status `WaitingConfirmation -> Ready`.
  - Target: host
  - Push: `handleRoomAttendeeUpdatedEvents`.
  - Title(Eng): `Attendee Confirmed` or `Attendee Missed Invite`
  - Title(Chinese): `參加者已確認` or `參加者未看到邀請`
  - Message(Eng): `%@ confirmed raid join. You earned %@ honey.` or `%@ reported invited but seat full. You earned %@ honey.` or `%@ reported no invitation was seen.`
  - Message(Chinese): `%@ 已確認參加戰鬥。你獲得 %@ 蜂蜜。` or `%@ 回報蘑菇滿位。你獲得 %@ 蜂蜜。` or `%@ 回報未看到邀請。`

- `STAR_RECEIVED`
  - Class: Record Event.
  - Producer: `handleRoomAttendeeUpdatedEvents`.
  - Trigger: rating transition emits receiver-side history.
  - Target: receiver
  - Push: `handleRoomAttendeeUpdatedEvents`.
  - Title(Eng): `Stars Received`
  - Title(Chinese): `收到評價`
  - Message(Eng): `%@ gave you %@ stars.`
  - Message(Chinese): `%@ 給了你 %@ 顆星。`

### Postcard Events

- `POSTCARD_CREATED_SELLER`
  - Class: Record Event.
  - Producer: `recordPostcardCreatedEvent`.
  - Trigger: postcard listing created.
  - Target: seller
  - Title(Eng): `Postcard Registered`
  - Title(Chinese): `已上架明信片`
  - Message(Eng): `You registered a postcard: %@.`
  - Message(Chinese): `你已上架明信片：%@。`
  - Push: none.

- `POSTCARD_CLOSED_SELLER`
  - Class: Record Event.
  - Producer: `recordPostcardClosedEvent`.
  - Trigger: postcard listing deleted (seller removes from market).
  - Target: seller
  - Title(Eng): `Postcard Removed`
  - Title(Chinese): `明信片已下架`
  - Message(Eng): `You removed a postcard from market: %@.`
  - Message(Chinese): `你已將明信片從市場下架：%@。`
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
  - Message(Chinese): `你已送出明信片訂單：%@。`
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
  - Message(Chinese): `你已將 %@ 寄給 %@。`
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
  - Message(Chinese): `%@ 已確認收件，%@ 蜂蜜已轉給你。`
  - Note: if order is `CompletedAuto`, the message becomes `%@ postcard received timed out. %@ honey has been transferred to you.` / `「%@」收件確認逾時，%@ 蜂蜜已轉給你。`.

- `POSTCARD_RECEIVED_BUYER`
  - Class: Record Event.
  - Producer: `handlePostcardOrderUpdatedEvents`.
  - Trigger: order status transitions into `Completed` or `CompletedAuto` (buyer copy).
  - Target: buyer
  - Title(Eng): `Postcard Received`
  - Title(Chinese): `買家已收到明信片`
  - Message(Eng): `You confirmed to receive postcard: %@.`
  - Message(Chinese): `你已確認收到明信片：%@。`
  - Push: none.

- `POSTCARD_REJECTED_BUYER`
  - Class: Record Event.
  - Producer: `handlePostcardOrderUpdatedEvents`.
  - Trigger: order status transitions into `Rejected` (buyer copy).
  - Target: buyer
  - Push: `handlePostcardOrderUpdatedEvents`.
  - Title(Eng): `Order Rejected`
  - Title(Chinese): `訂單已拒絕`
  - Message(Eng): `Your order for "%@" was rejected and canceled. %@ honey has been fully refunded to your account.`
  - Message(Chinese): `你購買「%@」的訂單已被拒絕並取消，%@ 蜂蜜已全額退回。`

- `POSTCARD_REJECTED_SELLER`
  - Class: Record Event.
  - Producer: `handlePostcardOrderUpdatedEvents`.
  - Trigger: order status transitions into `Rejected` (seller copy).
  - Target: seller
  - Title(Eng): `Order Rejected`
  - Title(Chinese): `訂單已拒絕`
  - Message(Eng): `You rejected a postcard order: %@.`
  - Message(Chinese): `你已拒絕明信片訂單：%@。`
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
  - Message(Chinese): `你的顯示名稱已更新。`
  - Push: none.

- `FRIEND_CODE_UPDATED`
  - Class: Record Event.
  - Producer: `recordUserProfileAndWalletEvents`.
  - Trigger: `users/{uid}.friendCode` changed.
  - Target: self
  - Title(Eng): `Friend Code Updated`
  - Title(Chinese): `好友碼已更新`
  - Message(Eng): `Your friend code was updated to %@.`
  - Message(Chinese): `你的好友碼已更新為 %@。`
  - Push: none.

## Resolution Rules
- `RAID_CONFIRM_ATTENDEE`: resolved when attendee submits one confirmation outcome.
- `JOIN_REQUESTED_HOST`: resolved when host accepts or rejects that request.
- `POSTCARD_ORDER_SELLER`: resolved when seller marks shipped or rejects order.
- `POSTCARD_SENT_BUYER`: resolved when buyer confirms received (or timeout auto-completion finalizes order).

## Implementation Notes
- Push data `type` now matches the event type for all push-enabled events.
- `REPLY_HOST` includes extra push field `outcome` with values `raid_confirmation_seat_full`, `raid_confirmation_missed_invite`, or `raid_confirmation_accepted`.
