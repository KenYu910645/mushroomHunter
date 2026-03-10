const {setGlobalOptions} = require("firebase-functions/v2");
const {onDocumentCreated, onDocumentUpdated, onDocumentDeleted} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

// Cap concurrent containers to reduce runaway cost during event spikes.
setGlobalOptions({maxInstances: 10});

admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();
// SMTP transport is lazily initialized and then reused across invocations.
let cachedMailer = null;
const userLocaleCache = new Map();

// Build a reusable SMTP mailer from environment variables.
function getMailer() {
  if (cachedMailer) return cachedMailer;

  const host = (process.env.SMTP_HOST || "").trim();
  const portRaw = (process.env.SMTP_PORT || "587").trim();
  const user = (process.env.SMTP_USER || "").trim();
  const pass = (process.env.SMTP_PASS || "").trim();
  const secure = (process.env.SMTP_SECURE || "false").toLowerCase() === "true";

  if (!host || !user || !pass) {
    return null;
  }

  const port = Number(portRaw);
  cachedMailer = nodemailer.createTransport({
    host,
    port: Number.isFinite(port) ? port : 587,
    secure,
    auth: {user, pass},
  });
  return cachedMailer;
}

function stringifyValue(value, fallback = "-") {
  if (value === null || value === undefined) return fallback;
  const text = String(value).trim();
  return text ? text : fallback;
}

// Clamp stars into valid app range [1, 3] and provide fallback when invalid.
function normalizeStarsCount(value, fallback = 1) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  const rounded = Math.trunc(parsed);
  if (rounded < 1) return 1;
  if (rounded > 3) return 3;
  return rounded;
}

// Compose feedback email subject.
function feedbackEmailSubject(subject) {
  const clean = stringifyValue(subject, "HoneyHub Feedback");
  return `[HoneyHub Feedback] ${clean}`;
}

// Compose feedback email plain text body.
function feedbackEmailText(feedbackId, data) {
  return [
    "HoneyHub feedback received",
    "",
    `Feedback ID: ${feedbackId}`,
    `User ID: ${stringifyValue(data.userId)}`,
    `Display Name: ${stringifyValue(data.displayName)}`,
    `Friend Code: ${stringifyValue(data.friendCode)}`,
    `Locale: ${stringifyValue(data.localeIdentifier)}`,
    `Platform: ${stringifyValue(data.platform)}`,
    `App Version: ${stringifyValue(data.appVersion)}`,
    `Build Number: ${stringifyValue(data.buildNumber)}`,
    "",
    "Subject:",
    stringifyValue(data.subject, "HoneyHub Feedback"),
    "",
    "Message:",
    stringifyValue(data.message),
  ].join("\n");
}

// Normalize APNs/FCM token values.
function normalizeToken(rawToken) {
  const token = stringifyValue(rawToken, "");
  return token;
}

// Normalize honey values into integer balance deltas.
function normalizeHoneyValue(value) {
  const numericValue = Number(value);
  if (!Number.isFinite(numericValue)) return 0;
  return Math.trunc(numericValue);
}

// Send push notification with snapshot token first, then user profile fallback token.
async function sendPushToUser(uid, message, context, snapshotToken = "") {
  let token = normalizeToken(snapshotToken);
  if (!token) {
    const userSnap = await db.collection("users").doc(uid).get();
    if (!userSnap.exists) {
      logger.warn("User profile not found for push", {uid, ...context});
      return;
    }
    token = normalizeToken(userSnap.data()?.fcmToken);
  }

  if (!token || typeof token !== "string") {
    logger.info("Skipping push because user has no FCM token", {uid, ...context});
    return;
  }

  const incomingApns = message.apns || {};
  const incomingPayload = incomingApns.payload || {};
  const incomingAps = incomingPayload.aps || {};
  const mergedAps = {
    sound: "default",
    ...incomingAps,
  };
  const pushType = stringifyValue(message?.data?.type, "");
  const eventId = stringifyValue(message?.data?.eventId || message?.data?.event_id, "");
  let isActionPush = isActionEventType(pushType);
  if (!isActionPush && eventId) {
    try {
      const eventSnap = await db.collection("users")
          .doc(uid)
          .collection("events")
          .doc(eventId)
          .get();
      isActionPush = eventSnap.exists && eventSnap.data()?.isActionEvent === true;
    } catch (error) {
      logger.warn("Failed to resolve push Action Event flag from event document", {
        uid,
        eventId,
        type: pushType,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }
  if (isActionPush && mergedAps.badge === undefined) {
    const badgeCount = await unresolvedActionEventBadgeCount(uid);
    mergedAps.badge = Math.max(1, badgeCount);
  }

  await messaging.send({
    token,
    ...message,
    apns: {
      ...incomingApns,
      payload: {
        ...incomingPayload,
        aps: mergedAps,
      },
    },
  });
}

// Build APNs localized payload using string keys from app Localizable.strings.
function localizedPushMessage(titleLocKey, bodyLocKey, locArgs, data) {
  const serializedLocArgs = (locArgs || []).map((value) => String(value ?? ""));
  return {
    apns: {
      payload: {
        aps: {
          alert: {
            "title-loc-key": titleLocKey,
            "loc-key": bodyLocKey,
            "loc-args": serializedLocArgs,
          },
        },
      },
    },
    data,
  };
}

// Build APNs payload from resolved text snapshots so push copy equals event history copy.
function pushMessageFromSnapshot(title, body, data) {
  return {
    apns: {
      payload: {
        aps: {
          alert: {
            title: stringifyValue(title, "Notification"),
            body: stringifyValue(body, ""),
          },
        },
      },
    },
    data,
  };
}

function formatTemplate(template, args = []) {
  let cursor = 0;
  return stringifyValue(template, "").replace(/%@/g, () => {
    const value = args[cursor];
    cursor += 1;
    return String(value ?? "");
  });
}

function isChineseLocale(localeIdentifier) {
  return stringifyValue(localeIdentifier, "").toLowerCase().startsWith("zh");
}

async function resolveUserLocale(uid) {
  const normalizedUid = stringifyValue(uid, "");
  if (!normalizedUid) return "en";
  if (userLocaleCache.has(normalizedUid)) {
    return userLocaleCache.get(normalizedUid);
  }
  try {
    const userSnap = await db.collection("users").doc(normalizedUid).get();
    const localeIdentifier = stringifyValue(userSnap.data()?.localeIdentifier, "en");
    userLocaleCache.set(normalizedUid, localeIdentifier);
    return localeIdentifier;
  } catch (error) {
    logger.warn("Failed to resolve user locale; falling back to en", {
      uid: normalizedUid,
      error: error instanceof Error ? error.message : String(error),
    });
    return "en";
  }
}

function eventCopyForType(type, messageArgs, localeIdentifier) {
  const isChinese = isChineseLocale(localeIdentifier);
  const normalizedType = stringifyValue(type, "unknown");
  const argValues = (messageArgs || []).map((value) => String(value ?? ""));
  const firstArg = argValues[0] || "";

  const byType = {
    ROOM_CREATED_HOST: {
      en: ["Mushroom Room Created", "You created a mushroom room: %@."],
      zh: ["已建立蘑菇房", "您已建立蘑菇房間：%@。"],
    },
    ROOM_CLOSED_HOST: {
      en: ["Mushroom Room Closed", "You closed a mushroom room: %@."],
      zh: ["已關閉蘑菇房", "您已關閉蘑菇房間：%@。"],
    },
    RAID_INVITED_HOST: {
      en: ["Mushroom Raid Invited", "Raid confirmation invitations were sent to all attendees, wait for them to confirm."],
      zh: ["已發送蘑菇邀請", "您已發送蘑菇邀請確認，等待所有參加者確認。"],
    },
    POSTCARD_CREATED_SELLER: {
      en: ["Postcard Registered", "You registered a postcard: %@."],
      zh: ["已上架明信片", "您已上架明信片：%@。"],
    },
    POSTCARD_CLOSED_SELLER: {
      en: ["Postcard Removed", "You removed a postcard from market: %@."],
      zh: ["明信片已下架", "您已將明信片從市場下架：%@。"],
    },
    NAME_UPDATED: {
      en: ["Display Name Updated", "Your display name was updated."],
      zh: ["名稱已更新", "您的顯示名稱已更新。"],
    },
    FRIEND_CODE_UPDATED: {
      en: ["Friend Code Updated", "Your friend code was updated to %@."],
      zh: ["好友碼已更新", "您的好友碼已更新為 %@。"],
    },
    RAID_CONFIRM_ATTENDEE: {
      en: ["Mushroom Invitation", "Action required: confirm whether you received the mushroom raid invitation from %@."],
      zh: ["蘑菇邀請確認", "需要處理：請確認您是否收到來自 %@ 的蘑菇邀請。"],
    },
    JOIN_REQUESTED_ATTENDEE: {
      en: ["Sent Join Request", "You sent a request to join %@."],
      zh: ["已送出加入申請", "您已送出加入 %@ 申請。"],
    },
    JOIN_REQUESTED_HOST: {
      en: ["New Join Request", "%@ requested to join %@. Tap to respond"],
      zh: ["申請加入", "%@ 申請加入 %@，點擊以回覆。"],
    },
    JOIN_ACCEPTED_ATTENDEE: {
      en: ["Join Request Accepted", "Host accepted your request to join %@."],
      zh: ["加入申請已接受", "主持人已接受您加入 %@ 的申請。"],
    },
    JOIN_ACCEPTED_HOST: {
      en: ["New Joiner Accepted", "%@ joined your room: %@."],
      zh: ["新成員加入", "%@ 已加入房間：%@。"],
    },
    JOIN_REJECTED_ATTENDEE: {
      en: ["Join Request Rejected", "Host rejected your request to join %@."],
      zh: ["加入申請已拒絕", "主持人已拒絕您加入 %@ 的申請。"],
    },
    JOIN_REJECTED_HOST: {
      en: ["Joiner Rejected", "You rejected a join request from %@."],
      zh: ["已拒絕加入申請", "您已拒絕來自 %@ 的加入申請。"],
    },
    REPLY_HOST: {
      en: ["Attendee Replied", "Attendee confirmation was submitted."],
      zh: ["參加者已回覆", "參加者已送出蘑菇戰確認回覆。"],
    },
    STAR_RECEIVED: {
      en: ["Stars Received", "%@ gave you %@ stars."],
      zh: ["收到評價", "%@ 給了您 %@ 顆星。"],
    },
    POSTCARD_ORDER_SELLER: {
      en: ["New Postcard Order", "Action required: process a new order."],
      zh: ["收到新訂單", "需要處理：請處理新的明信片訂單。"],
    },
    POSTCARD_ORDER_BUYER: {
      en: ["Order Sent", "You placed a postcard order on %@."],
      zh: ["訂單已送出", "您已送出明信片訂單：%@。"],
    },
    POSTCARD_SENT_BUYER: {
      en: ["Postcard Shipped", "Action required: confirm postcard receipt: %@."],
      zh: ["明信片已寄出", "需要處理：請確認是否已收到明信片：%@。"],
    },
    POSTCARD_SENT_SELLER: {
      en: ["Postcard Sent", "You have shipped postcard %@ to %@."],
      zh: ["明信片已寄出", "您已將 %@ 寄給 %@。"],
    },
    POSTCARD_RECEIVED_SELLER: {
      en: ["Order Completed", "%@ confirmed receipt. %@ honey has been transferred to you."],
      zh: ["訂單完成", "%@ 已確認收件，%@ 蜂蜜已轉給您。"],
    },
    POSTCARD_RECEIVED_BUYER: {
      en: ["Postcard Received", "You confirmed to receive postcard: %@."],
      zh: ["買家已收到明信片", "您已確認收到明信片：%@。"],
    },
    POSTCARD_REJECTED_BUYER: {
      en: ["Order Rejected", "Your order for \"%@\" was rejected and canceled. %@ honey has been fully refunded to your account."],
      zh: ["訂單已拒絕", "您購買「%@」的訂單已被拒絕並取消，%@ 蜂蜜已全額退回。"],
    },
    POSTCARD_REJECTED_SELLER: {
      en: ["Order Rejected", "You rejected a postcard order: %@."],
      zh: ["訂單已拒絕", "您已拒絕明信片訂單：%@。"],
    },
  };

  const copyEntry = byType[normalizedType];
  if (!copyEntry) {
    return {
      title: "Notification",
      message: normalizedType.replaceAll("_", " "),
    };
  }

  let [titleTemplate, messageTemplate] = isChinese ? copyEntry.zh : copyEntry.en;
  let templateArgs = argValues;

  if (normalizedType === "JOIN_REQUESTED_HOST") {
    titleTemplate = isChinese ? "申請加入" : "New Join Request";
    messageTemplate = isChinese ?
      "%@ 申請加入 %@，點擊以回覆。" :
      "%@ requested to join %@. Tap to respond";
    templateArgs = argValues.slice(0, 2);
  } else if (normalizedType === "REPLY_HOST") {
    if (firstArg === "raid_confirmation_seat_full") {
      titleTemplate = isChinese ? "參加者已確認" : "Attendee Confirmed";
      messageTemplate = isChinese ?
        "%@ 回報蘑菇滿位。您獲得 %@ 蜂蜜。" :
        "%@ reported invited but seat full. You earned %@ honey.";
      templateArgs = [argValues[1] || "", argValues[2] || "0"];
    } else if (firstArg === "raid_confirmation_missed_invite") {
      titleTemplate = isChinese ? "參加者未看到邀請" : "Attendee Missed Invite";
      messageTemplate = isChinese ?
        "%@ 回報未看到邀請。" :
        "%@ reported no invitation was seen.";
      templateArgs = [argValues[1] || ""];
    } else {
      titleTemplate = isChinese ? "參加者已確認" : "Attendee Confirmed";
      messageTemplate = isChinese ?
        "%@ 已確認參加戰鬥。您獲得 %@ 蜂蜜。" :
        "%@ confirmed raid join. You earned %@ honey.";
      templateArgs = [argValues[1] || "", argValues[2] || "0"];
    }
  } else if (normalizedType === "POSTCARD_RECEIVED_SELLER") {
    const isAutoCompleted = firstArg === "auto";
    if (isAutoCompleted) {
      messageTemplate = isChinese ?
        "「%@」收件確認逾時，%@ 蜂蜜已轉給您。" :
        "%@ postcard received timed out. %@ honey has been transferred to you.";
      templateArgs = [argValues[1] || "", argValues[2] || "0"];
    }
  }

  return {
    title: formatTemplate(titleTemplate, templateArgs),
    message: formatTemplate(messageTemplate, templateArgs),
  };
}

async function resolveEventSnapshot(uid, type, messageArgs = []) {
  const localeIdentifier = await resolveUserLocale(uid);
  return eventCopyForType(type, messageArgs, localeIdentifier);
}

// Event doc id is scoped by cloud event id and receiver uid to make writes idempotent.
function resolveEventDocumentId(cloudEventId, uid) {
  return `${stringifyValue(cloudEventId, "event")}_${stringifyValue(uid, "unknown")}`;
}

// Resolve host uid from room document payload across current + legacy field names.
function resolveRoomHostUidFromData(roomData) {
  const normalizedRoomData = roomData || {};
  return stringifyValue(
      normalizedRoomData.hostUid ||
      normalizedRoomData.hostId ||
      normalizedRoomData.ownerUid ||
      normalizedRoomData.createdByUid,
      "",
  );
}

// Resolve postcard seller uid from postcard payload across current + legacy field names.
function resolvePostcardSellerUidFromData(postcardData) {
  const normalizedPostcardData = postcardData || {};
  return stringifyValue(
      normalizedPostcardData.sellerId ||
      normalizedPostcardData.sellerUid ||
      normalizedPostcardData.ownerId ||
      normalizedPostcardData.ownerUid,
      "",
  );
}

const ACTION_EVENT_TYPES = new Set([
  "RAID_CONFIRM_ATTENDEE",
  "JOIN_REQUESTED_HOST",
  "POSTCARD_ORDER_SELLER",
  "POSTCARD_SENT_BUYER",
]);

// Classify event type for Action Event semantics (badge + unresolved state + required push).
function isActionEventType(type) {
  const normalizedType = stringifyValue(type, "unknown");
  return ACTION_EVENT_TYPES.has(normalizedType);
}

// Count unresolved Action Events for APNs badge synchronization.
async function unresolvedActionEventBadgeCount(uid) {
  const normalizedUid = stringifyValue(uid, "");
  if (!normalizedUid) return 0;

  try {
    const unresolvedQuery = db.collection("users")
        .doc(normalizedUid)
        .collection("events")
        .where("isActionEvent", "==", true)
        .where("isResolved", "==", false);
    const aggregateSnapshot = await unresolvedQuery.count().get();
    const rawCount = Number(aggregateSnapshot.data().count ?? 0);
    if (!Number.isFinite(rawCount)) return 0;
    return Math.max(0, Math.trunc(rawCount));
  } catch (error) {
    logger.warn("Failed to resolve unresolved Action Event count for badge", {
      uid: normalizedUid,
      error: error instanceof Error ? error.message : String(error),
    });
    return 0;
  }
}

// Persist one event-history row in users/{uid}/events with current schema only.
async function recordUserEvent({
  uid,
  cloudEventId,
  type,
  roomId = "",
  postcardId = "",
  orderId = "",
  relatedUid = "",
  messageArgs = [],
}) {
  const normalizedUid = stringifyValue(uid, "");
  if (!normalizedUid) return;

  const normalizedRoomId = stringifyValue(roomId, "");
  const normalizedPostcardId = stringifyValue(postcardId, "");
  const normalizedOrderId = stringifyValue(orderId, "");
  const normalizedRelatedUid = stringifyValue(relatedUid, "");
  const eventId = resolveEventDocumentId(cloudEventId, normalizedUid);
  const eventRef = db.collection("users")
      .doc(normalizedUid)
      .collection("events")
      .doc(eventId);

  try {
    const normalizedType = stringifyValue(type, "unknown");
    const isActionEvent = isActionEventType(normalizedType);
    const isResolved = !isActionEvent;
    const snapshot = await resolveEventSnapshot(normalizedUid, normalizedType, messageArgs);
    await eventRef.create({
      type: normalizedType,
      title: snapshot.title,
      message: snapshot.message,
      roomId: normalizedRoomId,
      postcardId: normalizedPostcardId,
      orderId: normalizedOrderId,
      relatedUid: normalizedRelatedUid,
      isActionEvent,
      isResolved,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (error) {
    const isAlreadyExistsError =
        error && typeof error.code === "number" && error.code === 6;
    if (!isAlreadyExistsError) {
      throw error;
    }
  }
}

// Resolve matching unresolved Action Events when business flow reaches terminal state.
async function resolveUserActionEvents({
  uid,
  type = "",
  roomId = "",
  postcardId = "",
  orderId = "",
  relatedUid = "",
}) {
  const normalizedUid = stringifyValue(uid, "");
  if (!normalizedUid) return;

  const normalizedType = stringifyValue(type, "");
  const normalizedRoomId = stringifyValue(roomId, "");
  const normalizedPostcardId = stringifyValue(postcardId, "");
  const normalizedOrderId = stringifyValue(orderId, "");
  const normalizedRelatedUid = stringifyValue(relatedUid, "");

  const unresolvedSnapshot = await db.collection("users")
      .doc(normalizedUid)
      .collection("events")
      .where("isResolved", "==", false)
      .limit(100)
      .get();

  if (unresolvedSnapshot.empty) return;

  const matchingDocs = unresolvedSnapshot.docs.filter((doc) => {
    const data = doc.data() || {};
    if ((data.isActionEvent === true) === false) return false;
    if (normalizedType && stringifyValue(data.type, "") !== normalizedType) return false;
    if (normalizedRoomId && stringifyValue(data.roomId, "") !== normalizedRoomId) return false;
    if (normalizedPostcardId && stringifyValue(data.postcardId, "") !== normalizedPostcardId) return false;
    if (normalizedOrderId && stringifyValue(data.orderId, "") !== normalizedOrderId) return false;
    if (normalizedRelatedUid && stringifyValue(data.relatedUid, "") !== normalizedRelatedUid) return false;
    return true;
  });

  if (matchingDocs.length === 0) return;

  const batch = db.batch();
  for (const doc of matchingDocs) {
    batch.set(doc.ref, {
      isResolved: true,
    }, {merge: true});
  }
  await batch.commit();
}

// Resolve host uid from room snapshot first, then attendee query fallback.
async function resolveHostUid(roomId, roomData) {
  const hostUidFromRoom = stringifyValue(roomData?.hostUid, "");
  if (hostUidFromRoom) {
    return hostUidFromRoom;
  }

  const hostQuery = await db.collection("rooms").doc(roomId).collection("attendees")
      .where("status", "==", "Host")
      .limit(1)
      .get();
  return hostQuery.docs[0]?.id ?? null;
}

// Resolve host display name with legacy room field fallback, attendee snapshot fallback, and user-profile fallback.
async function resolveHostDisplayName(roomId, roomData, hostUid = "") {
  const hostNameFromRoom = stringifyValue(roomData?.hostName, "");
  if (hostNameFromRoom) {
    return hostNameFromRoom;
  }

  const normalizedHostUid = stringifyValue(hostUid, "") || await resolveHostUid(roomId, roomData);
  if (normalizedHostUid) {
    const hostAttendeeSnap = await db.collection("rooms")
        .doc(roomId)
        .collection("attendees")
        .doc(normalizedHostUid)
        .get();
    const hostAttendeeName = stringifyValue(hostAttendeeSnap.data()?.name, "");
    if (hostAttendeeName) {
      return hostAttendeeName;
    }

    const hostUserSnap = await db.collection("users").doc(normalizedHostUid).get();
    const hostUserName = stringifyValue(hostUserSnap.data()?.displayName, "");
    if (hostUserName) {
      return hostUserName;
    }
  }

  return "Host";
}

// Run one routed processor safely so one branch failure does not block other branches.
async function runEventProcessor(processorName, processor, event) {
  try {
    await processor(event);
  } catch (error) {
    logger.error("Event processor failed", {
      processorName,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

// Validate Firestore timestamp and compare to "now" for timeout jobs.
function isTimestampReached(timestampValue, nowTimestamp) {
  const isHasTimestamp = timestampValue &&
      typeof timestampValue.toMillis === "function";
  if (!isHasTimestamp) {
    return false;
  }
  return timestampValue.toMillis() <= nowTimestamp.toMillis();
}

// Timeout worker: refund buyer + restore postcard stock when seller misses shipping deadline.
async function processSellerShippingTimeouts(nowTimestamp) {
  const query = db.collection("postcardOrders")
      .where("status", "==", "AwaitingShipping")
      .where("sellerShippingDeadlineAt", "<=", nowTimestamp)
      .limit(50);
  const snap = await query.get();

  for (const doc of snap.docs) {
    const orderRef = doc.ref;
    await db.runTransaction(async (tx) => {
      const latestSnap = await tx.get(orderRef);
      const latestData = latestSnap.data();
      if (!latestData) return;

      const isStatusMatch = latestData.status === "AwaitingShipping";
      const isDeadlineReached = isTimestampReached(
          latestData.sellerShippingDeadlineAt,
          nowTimestamp,
      );
      if (!isStatusMatch || !isDeadlineReached) return;

      const buyerId = stringifyValue(latestData.buyerId, "");
      const postcardId = stringifyValue(latestData.postcardId, "");
      const holdHoney = Number(latestData.holdHoney || 0);
      const isMissingSettlementPayload = !buyerId || !postcardId || holdHoney <= 0;
      if (isMissingSettlementPayload) return;

      const buyerRef = db.collection("users").doc(buyerId);
      const postcardRef = db.collection("postcards").doc(postcardId);
      const buyerSnap = await tx.get(buyerRef);
      const postcardSnap = await tx.get(postcardRef);
      const buyerHoney = Number(buyerSnap.data()?.honey || 0);
      const stock = Number(postcardSnap.data()?.stock || 0);

      tx.set(buyerRef, {
        honey: buyerHoney + holdHoney,
        updatedAt: nowTimestamp,
      }, {merge: true});
      tx.set(postcardRef, {
        stock: stock + 1,
        updatedAt: nowTimestamp,
      }, {merge: true});
      tx.update(orderRef, {
        status: "FailedSellerNoShip",
        completedAt: nowTimestamp,
        updatedAt: nowTimestamp,
      });
    });
  }
}

// Timeout worker: auto-complete shipped orders and release held honey to seller.
async function processBuyerAutoCompletion(nowTimestamp) {
  const query = db.collection("postcardOrders")
      .where("status", "==", "Shipped")
      .where("buyerConfirmDeadlineAt", "<=", nowTimestamp)
      .limit(50);
  const snap = await query.get();

  for (const doc of snap.docs) {
    const orderRef = doc.ref;
    await db.runTransaction(async (tx) => {
      const latestSnap = await tx.get(orderRef);
      const latestData = latestSnap.data();
      if (!latestData) return;

      const isStatusMatch = latestData.status === "Shipped";
      const isDeadlineReached = isTimestampReached(
          latestData.buyerConfirmDeadlineAt,
          nowTimestamp,
      );
      if (!isStatusMatch || !isDeadlineReached) return;

      const sellerId = stringifyValue(latestData.sellerId, "");
      const holdHoney = Number(latestData.holdHoney || 0);
      const isMissingSettlementPayload = !sellerId || holdHoney <= 0;
      if (isMissingSettlementPayload) return;

      const sellerRef = db.collection("users").doc(sellerId);
      const sellerSnap = await tx.get(sellerRef);
      const sellerHoney = Number(sellerSnap.data()?.honey || 0);

      tx.set(sellerRef, {
        honey: sellerHoney + holdHoney,
        updatedAt: nowTimestamp,
      }, {merge: true});
      tx.update(orderRef, {
        status: "CompletedAuto",
        completedAt: nowTimestamp,
        updatedAt: nowTimestamp,
      });
    });
  }
}

// Scheduled timeout sweeper for postcard orders.
exports.processPostcardOrderTimeouts = onSchedule(
    {
      schedule: "every 15 minutes",
      region: "us-central1",
      timeZone: "Etc/UTC",
    },
    async () => {
      const nowTimestamp = admin.firestore.Timestamp.now();
      await processSellerShippingTimeouts(nowTimestamp);
      await processBuyerAutoCompletion(nowTimestamp);
      logger.info("Postcard order timeout sweep completed");
    },
);

// Record host-side room-created history event.
// Event: ROOM_CREATED_HOST
exports.recordRoomCreatedEvent = onDocumentCreated(
    {
      document: "rooms/{roomId}",
      region: "us-central1",
    },
    async (event) => {
      const roomData = event.data?.data();
      if (!roomData) return;

      const roomId = event.params.roomId;
      const hostUid = resolveRoomHostUidFromData(roomData);
      if (!hostUid) {
        logger.warn("Skipping ROOM_CREATED_HOST event because host uid is missing", {roomId});
        return;
      }
      await recordUserEvent({
        uid: hostUid,
        cloudEventId: event.id,
        type: "ROOM_CREATED_HOST",
        roomId,
        messageArgs: [stringifyValue(roomData.title, "Untitled Room")],
      });
    },
);

// Record host-side room-closed history event when room document is deleted.
// Event: ROOM_CLOSED_HOST
exports.recordRoomClosedEvent = onDocumentDeleted(
    {
      document: "rooms/{roomId}",
      region: "us-central1",
    },
    async (event) => {
      const roomData = event.data?.data();
      if (!roomData) return;

      const roomId = event.params.roomId;
      const hostUid = resolveRoomHostUidFromData(roomData);
      if (!hostUid) {
        logger.warn("Skipping ROOM_CLOSED_HOST event because host uid is missing", {roomId});
        return;
      }
      await recordUserEvent({
        uid: hostUid,
        cloudEventId: event.id,
        type: "ROOM_CLOSED_HOST",
        roomId,
        messageArgs: [stringifyValue(roomData.title, "Untitled Room")],
      });
    },
);

// Record host-side raid-invite cycle event when raidConfirmationHistory gets a new head record.
// Event: RAID_INVITED_HOST
exports.recordHostRaidInviteEvent = onDocumentUpdated(
    {
      document: "rooms/{roomId}",
      region: "us-central1",
    },
    async (event) => {
      const beforeData = event.data?.before?.data();
      const afterData = event.data?.after?.data();
      if (!beforeData || !afterData) return;

      const previousHistory = beforeData.raidConfirmationHistory || [];
      const latestHistory = afterData.raidConfirmationHistory || [];
      if (!Array.isArray(previousHistory) || !Array.isArray(latestHistory)) return;
      if (latestHistory.length === 0) return;

      const oldFirstId = stringifyValue(previousHistory[0]?.id, "");
      const newFirstId = stringifyValue(latestHistory[0]?.id, "");
      if (!newFirstId || oldFirstId === newFirstId) {
        return;
      }

      const roomId = event.params.roomId;
      const hostUid = resolveRoomHostUidFromData(afterData);
      if (!hostUid) {
        logger.warn("Skipping RAID_INVITED_HOST event because host uid is missing", {
          roomId,
          confirmationId: newFirstId,
        });
        return;
      }
      await recordUserEvent({
        uid: hostUid,
        cloudEventId: `${event.id}_${newFirstId}`,
        type: "RAID_INVITED_HOST",
        roomId,
      });
    },
);

// Record seller-side postcard registration history event.
// Event: POSTCARD_CREATED_SELLER
exports.recordPostcardCreatedEvent = onDocumentCreated(
    {
      document: "postcards/{postcardId}",
      region: "us-central1",
    },
    async (event) => {
      const postcardData = event.data?.data();
      if (!postcardData) return;

      const postcardId = event.params.postcardId;
      const sellerUid = resolvePostcardSellerUidFromData(postcardData);
      if (!sellerUid) {
        logger.warn("Skipping POSTCARD_CREATED_SELLER event because seller uid is missing", {postcardId});
        return;
      }
      await recordUserEvent({
        uid: sellerUid,
        cloudEventId: event.id,
        type: "POSTCARD_CREATED_SELLER",
        postcardId,
        messageArgs: [stringifyValue(postcardData.title, "postcard")],
      });
    },
);

// Record seller-side postcard-removed history event when listing is deleted.
// Event: POSTCARD_CLOSED_SELLER
exports.recordPostcardClosedEvent = onDocumentDeleted(
    {
      document: "postcards/{postcardId}",
      region: "us-central1",
    },
    async (event) => {
      const postcardData = event.data?.data();
      if (!postcardData) return;

      const postcardId = event.params.postcardId;
      const sellerUid = resolvePostcardSellerUidFromData(postcardData);
      if (!sellerUid) {
        logger.warn("Skipping POSTCARD_CLOSED_SELLER event because seller uid is missing", {postcardId});
        return;
      }
      await recordUserEvent({
        uid: sellerUid,
        cloudEventId: event.id,
        type: "POSTCARD_CLOSED_SELLER",
        postcardId,
        messageArgs: [stringifyValue(postcardData.title, "postcard")],
      });
    },
);

// Record profile/wallet history events from users/{uid} document diffs.
// Events: NAME_UPDATED, FRIEND_CODE_UPDATED
exports.recordUserProfileAndWalletEvents = onDocumentUpdated(
    {
      document: "users/{uid}",
      region: "us-central1",
    },
    async (event) => {
      const beforeData = event.data?.before?.data();
      const afterData = event.data?.after?.data();
      if (!beforeData || !afterData) return;

      const uid = event.params.uid;
      const pendingEvents = [];

      const beforeName = stringifyValue(beforeData.displayName, "");
      const afterName = stringifyValue(afterData.displayName, "");
      if (beforeName !== afterName && afterName) {
        pendingEvents.push(
            recordUserEvent({
              uid,
              cloudEventId: `${event.id}_name`,
              type: "NAME_UPDATED",
            }),
        );
      }

      const beforeFriendCode = stringifyValue(beforeData.friendCode, "");
      const afterFriendCode = stringifyValue(afterData.friendCode, "");
      if (beforeFriendCode !== afterFriendCode && afterFriendCode) {
        pendingEvents.push(
            recordUserEvent({
              uid,
              cloudEventId: `${event.id}_friendcode`,
              type: "FRIEND_CODE_UPDATED",
              messageArgs: [afterFriendCode],
            }),
        );
      }

      if (pendingEvents.length > 0) {
        await Promise.all(pendingEvents);
      }
    },
);

// Routed attendee-update branch: attendee enters WaitingConfirmation or receives a new pending
// confirmation request -> write action event + push attendee.
// Event: RAID_CONFIRM_ATTENDEE
async function processRaidConfirmationEvent(event) {
      const beforeData = event.data?.before?.data();
      const afterData = event.data?.after?.data();
      if (!afterData) return;

      const oldStatus = beforeData?.status ?? null;
      const newStatus = afterData.status ?? null;
      const beforePendingRequests = beforeData?.pendingConfirmationRequests || {};
      const afterPendingRequests = afterData.pendingConfirmationRequests || {};
      const addedConfirmationIds = Object.keys(afterPendingRequests).filter(
          (confirmationId) => !Object.prototype.hasOwnProperty.call(beforePendingRequests, confirmationId),
      );
      const isEnteringWaitingConfirmation =
        oldStatus !== "WaitingConfirmation" && newStatus === "WaitingConfirmation";
      const isReceivingNewConfirmationRequest = addedConfirmationIds.length > 0;
      if (!isEnteringWaitingConfirmation && !isReceivingNewConfirmationRequest) {
        return;
      }

      const roomId = event.params.roomId;
      const attendeeUid = event.params.attendeeUid;
      const roomSnap = await db.collection("rooms").doc(roomId).get();

      const roomData = roomSnap.data() || {};
      const hostName = await resolveHostDisplayName(roomId, roomData, "");
      const attendeeEventId = resolveEventDocumentId(event.id, attendeeUid);

      await recordUserEvent({
        uid: attendeeUid,
        cloudEventId: event.id,
        type: "RAID_CONFIRM_ATTENDEE",
        roomId,
        messageArgs: [hostName],
      });
      const attendeeSnapshot = await resolveEventSnapshot(
          attendeeUid,
          "RAID_CONFIRM_ATTENDEE",
          [hostName],
      );

      try {
        await sendPushToUser(
            attendeeUid,
            pushMessageFromSnapshot(
                attendeeSnapshot.title,
                attendeeSnapshot.message,
                {
                  type: "RAID_CONFIRM_ATTENDEE",
                  roomId,
                  room_id: roomId,
                  eventId: attendeeEventId,
                  event_id: attendeeEventId,
                },
            ),
            {roomId, attendeeUid},
            afterData.fcmToken,
        );
        logger.info("Raid confirmation push sent", {attendeeUid, roomId});
      } catch (error) {
        logger.error("Failed to send raid confirmation push", {
          attendeeUid,
          roomId,
          error: error instanceof Error ? error.message : String(error),
        });
      }
}

// Join request create trigger: write joiner/host events and push host Action Event.
// Events: JOIN_REQUESTED_ATTENDEE, JOIN_REQUESTED_HOST
exports.notifyHostJoinRequest = onDocumentCreated(
    {
      document: "rooms/{roomId}/attendees/{attendeeUid}",
      region: "us-central1",
    },
    async (event) => {
      const afterData = event.data?.data();
      if (!afterData) return;

      const attendeeStatus = afterData.status ?? null;
      if (attendeeStatus !== "AskingToJoin") return;

      const roomId = event.params.roomId;
      const attendeeUid = event.params.attendeeUid;
      const roomSnap = await db.collection("rooms").doc(roomId).get();
      const roomData = roomSnap.data() || {};
      const hostUid = await resolveHostUid(roomId, roomData);
      if (!hostUid) {
        logger.warn("Host not found for join request push", {roomId, attendeeUid});
        return;
      }
      if (hostUid === attendeeUid) {
        return;
      }

      const hostEventId = resolveEventDocumentId(event.id, hostUid);
      const attendeeName = stringifyValue(afterData.name, "A player");
      const roomTitle = stringifyValue(roomData.title, "the room");
      const joinRequestMessageArgs = [attendeeName, roomTitle];
      await Promise.all([
        recordUserEvent({
          uid: attendeeUid,
          cloudEventId: event.id,
          type: "JOIN_REQUESTED_ATTENDEE",
          roomId,
          messageArgs: [roomTitle],
        }),
        recordUserEvent({
          uid: hostUid,
          cloudEventId: event.id,
          type: "JOIN_REQUESTED_HOST",
          roomId,
          relatedUid: attendeeUid,
          messageArgs: joinRequestMessageArgs,
        }),
      ]);
      const hostSnapshot = await resolveEventSnapshot(
          hostUid,
          "JOIN_REQUESTED_HOST",
          joinRequestMessageArgs,
      );

      try {
        await sendPushToUser(
            hostUid,
            pushMessageFromSnapshot(
                hostSnapshot.title,
                hostSnapshot.message,
                {
                  type: "JOIN_REQUESTED_HOST",
                  roomId,
                  room_id: roomId,
                  attendeeUid,
                  eventId: hostEventId,
                  event_id: hostEventId,
                },
            ),
            {roomId, attendeeUid, hostUid},
            roomData.hostFcmToken,
        );
        logger.info("Host join request push sent", {roomId, attendeeUid, hostUid});
      } catch (error) {
        logger.error("Failed to send host join request push", {
          roomId,
          attendeeUid,
          hostUid,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    },
);

// Routed attendee-update branch: host accepts join request -> resolve host action + push applicant.
// Events: JOIN_ACCEPTED_ATTENDEE, JOIN_ACCEPTED_HOST
async function processJoinApplicantAcceptedEvent(event) {
      const beforeData = event.data?.before?.data();
      const afterData = event.data?.after?.data();
      if (!beforeData || !afterData) return;

      const oldStatus = beforeData.status ?? null;
      const newStatus = afterData.status ?? null;
      if (oldStatus !== "AskingToJoin" || newStatus !== "Ready") return;

      const roomId = event.params.roomId;
      const attendeeUid = event.params.attendeeUid;
      const roomSnap = await db.collection("rooms").doc(roomId).get();
      const roomData = roomSnap.data() || {};
      const hostUid = await resolveHostUid(roomId, roomData);
      const attendeeEventId = resolveEventDocumentId(event.id, attendeeUid);
      const roomTitle = stringifyValue(roomData.title, "the room");
      const attendeeName = stringifyValue(afterData.name, "A player");
      const acceptanceMessageArgs = [roomTitle];

      const pendingEvents = [
        recordUserEvent({
          uid: attendeeUid,
          cloudEventId: event.id,
          type: "JOIN_ACCEPTED_ATTENDEE",
          roomId,
          messageArgs: acceptanceMessageArgs,
        }),
      ];
      if (hostUid) {
        pendingEvents.push(
            recordUserEvent({
              uid: hostUid,
              cloudEventId: event.id,
              type: "JOIN_ACCEPTED_HOST",
              roomId,
              messageArgs: [attendeeName, roomTitle],
            }),
        );
      }
      await Promise.all(pendingEvents);
      if (hostUid) {
        await resolveUserActionEvents({
          uid: hostUid,
          type: "JOIN_REQUESTED_HOST",
          roomId,
          relatedUid: attendeeUid,
        });
      }

      try {
        const attendeeAcceptedSnapshot = await resolveEventSnapshot(
            attendeeUid,
            "JOIN_ACCEPTED_ATTENDEE",
            acceptanceMessageArgs,
        );
        await sendPushToUser(
            attendeeUid,
            pushMessageFromSnapshot(
                attendeeAcceptedSnapshot.title,
                attendeeAcceptedSnapshot.message,
                {
                  type: "JOIN_ACCEPTED_ATTENDEE",
                  roomId,
                  room_id: roomId,
                  eventId: attendeeEventId,
                  event_id: attendeeEventId,
                },
            ),
            {roomId, attendeeUid},
            afterData.fcmToken,
        );
        logger.info("Join applicant accepted push sent", {roomId, attendeeUid});
      } catch (error) {
        logger.error("Failed to send join applicant accepted push", {
          roomId,
          attendeeUid,
          error: error instanceof Error ? error.message : String(error),
        });
      }
}

// Join request delete trigger: host rejects join request -> resolve host action + push applicant.
// Events: JOIN_REJECTED_ATTENDEE, JOIN_REJECTED_HOST
exports.notifyJoinApplicantRejected = onDocumentDeleted(
    {
      document: "rooms/{roomId}/attendees/{attendeeUid}",
      region: "us-central1",
    },
    async (event) => {
      const beforeData = event.data?.data();
      if (!beforeData) return;

      const oldStatus = beforeData.status ?? null;
      if (oldStatus !== "AskingToJoin") return;

      const roomId = event.params.roomId;
      const attendeeUid = event.params.attendeeUid;
      const roomSnap = await db.collection("rooms").doc(roomId).get();
      const roomData = roomSnap.data() || {};
      const hostUid = await resolveHostUid(roomId, roomData);
      const attendeeEventId = resolveEventDocumentId(event.id, attendeeUid);
      const roomTitle = stringifyValue(roomData.title, "the room");
      const attendeeName = stringifyValue(beforeData.name, "A player");
      const rejectionMessageArgs = [roomTitle];

      const pendingEvents = [
        recordUserEvent({
          uid: attendeeUid,
          cloudEventId: event.id,
          type: "JOIN_REJECTED_ATTENDEE",
          roomId,
          messageArgs: rejectionMessageArgs,
        }),
      ];
      if (hostUid) {
        pendingEvents.push(
            recordUserEvent({
              uid: hostUid,
              cloudEventId: event.id,
              type: "JOIN_REJECTED_HOST",
              roomId,
              messageArgs: [attendeeName],
            }),
        );
      }
      await Promise.all(pendingEvents);
      if (hostUid) {
        await resolveUserActionEvents({
          uid: hostUid,
          type: "JOIN_REQUESTED_HOST",
          roomId,
          relatedUid: attendeeUid,
        });
      }

      try {
        const attendeeRejectedSnapshot = await resolveEventSnapshot(
            attendeeUid,
            "JOIN_REJECTED_ATTENDEE",
            rejectionMessageArgs,
        );
        await sendPushToUser(
            attendeeUid,
            pushMessageFromSnapshot(
                attendeeRejectedSnapshot.title,
                attendeeRejectedSnapshot.message,
                {
                  type: "JOIN_REJECTED_ATTENDEE",
                  roomId,
                  room_id: roomId,
                  eventId: attendeeEventId,
                  event_id: attendeeEventId,
                },
            ),
            {roomId, attendeeUid},
            beforeData.fcmToken,
        );
        logger.info("Join applicant rejected push sent", {roomId, attendeeUid});
      } catch (error) {
        logger.error("Failed to send join applicant rejected push", {
          roomId,
          attendeeUid,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    },
);

// Routed attendee-update branch: attendee submits confirmation result -> resolve attendee action + push host.
// Event: REPLY_HOST
async function processHostRaidConfirmationResultEvent(event) {
      const beforeData = event.data?.before?.data();
      const afterData = event.data?.after?.data();
      if (!beforeData || !afterData) return;

      const oldStatus = beforeData.status ?? null;
      const newStatus = afterData.status ?? null;
      const transitionedFromWaiting = oldStatus === "WaitingConfirmation";
      const transitionedToReady = newStatus === "Ready";
      if (!transitionedFromWaiting || !transitionedToReady) {
        return;
      }

      const roomId = event.params.roomId;
      const attendeeUid = event.params.attendeeUid;
      const roomSnap = await db.collection("rooms").doc(roomId).get();
      const roomData = roomSnap.data() || {};
      const hostUid = await resolveHostUid(roomId, roomData);

      if (!hostUid) {
        logger.warn("Host attendee not found for room", {roomId, attendeeUid});
        return;
      }

      const raidCostHoney = Number(roomData.fixedRaidCost || 0);
      const attendeeName = stringifyValue(afterData.name, "A player");
      const settlementOutcome = (afterData.lastSettlementOutcome || "").toString();
      const settlementHoney = Number(afterData.lastSettlementHoney || 0);
      const raidCostHoneyText = String(raidCostHoney);
      const settlementHoneyText = String(settlementHoney);
      const pushType = settlementOutcome === "SeatFullNoFault" ?
        "raid_confirmation_seat_full" : settlementOutcome === "MissedInvitation" ?
          "raid_confirmation_missed_invite" :
          "raid_confirmation_accepted";
      const pushHoneyEarned = settlementOutcome === "SeatFullNoFault" ?
        settlementHoneyText : settlementOutcome === "MissedInvitation" ?
          "0" : raidCostHoneyText;
      const replyHostMessageArgs = [pushType, attendeeName, pushHoneyEarned];
      const hostEventId = resolveEventDocumentId(event.id, hostUid);
      await recordUserEvent({
        uid: hostUid,
        cloudEventId: event.id,
        type: "REPLY_HOST",
        roomId,
        messageArgs: replyHostMessageArgs,
      });
      await resolveUserActionEvents({
        uid: attendeeUid,
        type: "RAID_CONFIRM_ATTENDEE",
        roomId,
      });

      const hostReplySnapshot = await resolveEventSnapshot(
          hostUid,
          "REPLY_HOST",
          replyHostMessageArgs,
      );
      const message = pushMessageFromSnapshot(
          hostReplySnapshot.title,
          hostReplySnapshot.message,
          {
            type: "REPLY_HOST",
            outcome: pushType,
            roomId,
            room_id: roomId,
            attendeeUid,
            honeyEarned: pushHoneyEarned,
            eventId: hostEventId,
            event_id: hostEventId,
          },
      );

      try {
        await sendPushToUser(hostUid, message, {roomId, attendeeUid, hostUid}, roomData.hostFcmToken);
        logger.info("Host raid confirmation result push sent", {
          roomId,
          attendeeUid,
          hostUid,
          newStatus,
        });
      } catch (error) {
        logger.error("Failed to send host raid confirmation result push", {
          roomId,
          attendeeUid,
          hostUid,
          newStatus,
          error: error instanceof Error ? error.message : String(error),
        });
      }
}

// Routed attendee-update branch: rating transitions -> star receiver history + push.
// Event: STAR_RECEIVED
async function processMushroomStarReceivedEvent(event) {
      const beforeData = event.data?.before?.data();
      const afterData = event.data?.after?.data();
      if (!beforeData || !afterData) return;

      // Most attendee updates are not rating events; skip room read unless a rating flag changed.
      const attendeeRatedHostNow =
          (beforeData.isAttendeeRatedHost === true || beforeData.attendeeRatedHost === true) === false &&
          (afterData.isAttendeeRatedHost === true || afterData.attendeeRatedHost === true);
      const hostRatedAttendeeNow =
          (beforeData.isHostRatedAttendee === true || beforeData.hostRatedAttendee === true) === false &&
          (afterData.isHostRatedAttendee === true || afterData.hostRatedAttendee === true);
      if (!attendeeRatedHostNow && !hostRatedAttendeeNow) {
        return;
      }

      const roomId = event.params.roomId;
      const attendeeUid = event.params.attendeeUid;
      const roomSnap = await db.collection("rooms").doc(roomId).get();
      const roomData = roomSnap.data() || {};
      const raterName = stringifyValue(afterData.name, "A player");
      const hostUid = await resolveHostUid(roomId, roomData);
      const hostName = await resolveHostDisplayName(roomId, roomData, hostUid || "");

      if (attendeeRatedHostNow) {
        const awardedStars = normalizeStarsCount(afterData.attendeeRatedHostStars, 1);
        if (hostUid) {
          const hostEventId = resolveEventDocumentId(event.id, hostUid);
          await Promise.all([
            recordUserEvent({
              uid: hostUid,
              cloudEventId: event.id,
              type: "STAR_RECEIVED",
              roomId,
              messageArgs: [raterName, awardedStars],
            }),
          ]);
          try {
            const hostSnapshot = await resolveEventSnapshot(
                hostUid,
                "STAR_RECEIVED",
                [raterName, awardedStars],
            );
            await sendPushToUser(
                hostUid,
                pushMessageFromSnapshot(
                    hostSnapshot.title,
                    hostSnapshot.message,
                    {
                      type: "STAR_RECEIVED",
                      roomId,
                      room_id: roomId,
                      fromUid: attendeeUid,
                      toUid: hostUid,
                      stars: String(awardedStars),
                      eventId: hostEventId,
                      event_id: hostEventId,
                    },
                ),
                {roomId, attendeeUid, hostUid},
                roomData.hostFcmToken,
            );
            logger.info("Host star received push sent", {roomId, attendeeUid, hostUid});
          } catch (error) {
            logger.error("Failed to send host star received push", {
              roomId,
              attendeeUid,
              hostUid,
              error: error instanceof Error ? error.message : String(error),
            });
          }
        }
      }

      if (hostRatedAttendeeNow) {
        const starDelta = Number(afterData.stars || 0) - Number(beforeData.stars || 0);
        const awardedStars = normalizeStarsCount(afterData.hostRatedAttendeeStars, starDelta);
        const attendeeEventId = resolveEventDocumentId(event.id, attendeeUid);
        await Promise.all([
          recordUserEvent({
            uid: attendeeUid,
            cloudEventId: event.id,
            type: "STAR_RECEIVED",
            roomId,
            messageArgs: [hostName, awardedStars],
          }),
        ]);
        try {
          const attendeeSnapshot = await resolveEventSnapshot(
              attendeeUid,
              "STAR_RECEIVED",
              [hostName, awardedStars],
          );
          await sendPushToUser(
              attendeeUid,
              pushMessageFromSnapshot(
                  attendeeSnapshot.title,
                  attendeeSnapshot.message,
                  {
                    type: "STAR_RECEIVED",
                    roomId,
                    room_id: roomId,
                    fromUid: hostUid || "",
                    toUid: attendeeUid,
                    stars: String(awardedStars),
                    eventId: attendeeEventId,
                    event_id: attendeeEventId,
                  },
              ),
              {roomId, attendeeUid},
              afterData.fcmToken,
          );
          logger.info("Attendee star received push sent", {roomId, attendeeUid, hostUid});
        } catch (error) {
          logger.error("Failed to send attendee star received push", {
            roomId,
            attendeeUid,
            hostUid,
            error: error instanceof Error ? error.message : String(error),
          });
        }
      }
}

// Single update trigger for rooms/{roomId}/attendees/{attendeeUid}; routes all attendee update event logic.
// Events: RAID_CONFIRM_ATTENDEE, JOIN_ACCEPTED_ATTENDEE, JOIN_ACCEPTED_HOST, REPLY_HOST, STAR_RECEIVED
exports.handleRoomAttendeeUpdatedEvents = onDocumentUpdated(
    {
      document: "rooms/{roomId}/attendees/{attendeeUid}",
      region: "us-central1",
    },
    async (event) => {
      await runEventProcessor("RAID_CONFIRM_ATTENDEE", processRaidConfirmationEvent, event);
      await runEventProcessor("join_applicant_accepted", processJoinApplicantAcceptedEvent, event);
      await runEventProcessor("host_raid_confirmation_result", processHostRaidConfirmationResultEvent, event);
      await runEventProcessor("mushroom_star_received", processMushroomStarReceivedEvent, event);
    },
);

// Routed order-update branch: order transitions to Shipped -> resolve seller action + push buyer.
// Events: POSTCARD_SENT_BUYER, POSTCARD_SENT_SELLER
async function processPostcardShippedEvent(event) {
      const beforeData = event.data?.before?.data();
      const afterData = event.data?.after?.data();
      if (!beforeData || !afterData) return;

      const oldStatus = beforeData.status ?? null;
      const newStatus = afterData.status ?? null;
      if (oldStatus === "Shipped" || newStatus !== "Shipped") {
        return;
      }

      const orderId = event.params.orderId;
      const buyerUid = (afterData.buyerId || "").toString();
      const sellerUid = (afterData.sellerId || "").toString();
      if (!buyerUid) {
        logger.warn("Missing buyerId for postcard order push", {orderId});
        return;
      }

      const sellerName = stringifyValue(afterData.sellerName, "Seller");
      const postcardTitle = stringifyValue(afterData.postcardTitle, "postcard");
      const buyerName = stringifyValue(afterData.buyerName, "Buyer");
      const buyerEventId = resolveEventDocumentId(event.id, buyerUid);

      await Promise.all([
        recordUserEvent({
          uid: buyerUid,
          cloudEventId: event.id,
          type: "POSTCARD_SENT_BUYER",
          postcardId: (afterData.postcardId || "").toString(),
          orderId,
          messageArgs: [sellerName, postcardTitle],
        }),
        recordUserEvent({
          uid: sellerUid,
          cloudEventId: event.id,
          type: "POSTCARD_SENT_SELLER",
          postcardId: (afterData.postcardId || "").toString(),
          orderId,
          messageArgs: [postcardTitle, buyerName],
        }),
      ]);
      await resolveUserActionEvents({
        uid: sellerUid,
        type: "POSTCARD_ORDER_SELLER",
        orderId,
      });

      try {
        const buyerSnapshot = await resolveEventSnapshot(
            buyerUid,
            "POSTCARD_SENT_BUYER",
            [sellerName, postcardTitle],
        );
        await sendPushToUser(
            buyerUid,
            pushMessageFromSnapshot(
                buyerSnapshot.title,
                buyerSnapshot.message,
                {
                  type: "POSTCARD_SENT_BUYER",
                  orderId,
                  postcardId: (afterData.postcardId || "").toString(),
                  eventId: buyerEventId,
                  event_id: buyerEventId,
                },
            ),
            {orderId, buyerUid},
            afterData.buyerFcmToken,
        );
        logger.info("Postcard shipped push sent", {orderId, buyerUid});
      } catch (error) {
        logger.error("Failed to send postcard shipped push", {
          orderId,
          buyerUid,
          error: error instanceof Error ? error.message : String(error),
        });
      }
}

// Order create trigger: AwaitingShipping order created -> write events + push seller Action Event.
// Events: POSTCARD_ORDER_SELLER, POSTCARD_ORDER_BUYER
exports.sendPostcardOrderCreatedPush = onDocumentCreated(
    {
      document: "postcardOrders/{orderId}",
      region: "us-central1",
    },
    async (event) => {
      const orderData = event.data?.data();
      if (!orderData) return;

      const status = (orderData.status || "").toString();
      if (status !== "AwaitingShipping") {
        return;
      }

      const orderId = event.params.orderId;
      const sellerUid = (orderData.sellerId || "").toString();
      const buyerUid = (orderData.buyerId || "").toString();
      if (!sellerUid) {
        logger.warn("Missing sellerId for postcard order-created push", {orderId});
        return;
      }

      const postcardTitle = stringifyValue(orderData.postcardTitle, "postcard");
      const sellerEventId = resolveEventDocumentId(event.id, sellerUid);
      await Promise.all([
        recordUserEvent({
          uid: sellerUid,
          cloudEventId: event.id,
          type: "POSTCARD_ORDER_SELLER",
          postcardId: (orderData.postcardId || "").toString(),
          orderId,
          messageArgs: [postcardTitle],
        }),
        recordUserEvent({
          uid: buyerUid,
          cloudEventId: event.id,
          type: "POSTCARD_ORDER_BUYER",
          postcardId: (orderData.postcardId || "").toString(),
          orderId,
          messageArgs: [postcardTitle],
        }),
      ]);

      try {
        const sellerSnapshot = await resolveEventSnapshot(
            sellerUid,
            "POSTCARD_ORDER_SELLER",
            [postcardTitle],
        );
        await sendPushToUser(
            sellerUid,
            pushMessageFromSnapshot(
                sellerSnapshot.title,
                sellerSnapshot.message,
                {
                  type: "POSTCARD_ORDER_SELLER",
                  orderId,
                  postcardId: (orderData.postcardId || "").toString(),
                  eventId: sellerEventId,
                  event_id: sellerEventId,
                },
            ),
            {orderId, sellerUid},
            orderData.sellerFcmToken,
        );
        logger.info("Postcard order-created push sent", {orderId, sellerUid});
      } catch (error) {
        logger.error("Failed to send postcard order-created push", {
          orderId,
          sellerUid,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    },
);

// Routed order-update branch: order transitions to Completed/CompletedAuto -> resolve actions + push seller.
// Events: POSTCARD_RECEIVED_SELLER, POSTCARD_RECEIVED_BUYER
async function processSellerPostcardCompletedEvent(event) {
      const beforeData = event.data?.before?.data();
      const afterData = event.data?.after?.data();
      if (!beforeData || !afterData) return;

      const oldStatus = (beforeData.status || "").toString();
      const newStatus = (afterData.status || "").toString();
      const isCompletionStatus = newStatus === "Completed" || newStatus === "CompletedAuto";
      const isAlreadyCompleted = oldStatus === "Completed" || oldStatus === "CompletedAuto";
      if (isAlreadyCompleted || !isCompletionStatus) {
        return;
      }

      const orderId = event.params.orderId;
      const sellerUid = (afterData.sellerId || "").toString();
      const buyerUid = (afterData.buyerId || "").toString();
      if (!sellerUid) {
        logger.warn("Missing sellerId for postcard completed push", {orderId});
        return;
      }

      const buyerName = stringifyValue(afterData.buyerName, "Buyer");
      const postcardTitle = stringifyValue(afterData.postcardTitle, "postcard");
      const holdHoney = Number(afterData.holdHoney || 0);
      const holdHoneyText = String(holdHoney);
      const isAutoCompleted = newStatus === "CompletedAuto";
      const sellerEventId = resolveEventDocumentId(event.id, sellerUid);

      await Promise.all([
        recordUserEvent({
          uid: sellerUid,
          cloudEventId: event.id,
          type: "POSTCARD_RECEIVED_SELLER",
          postcardId: (afterData.postcardId || "").toString(),
          orderId,
          messageArgs: [isAutoCompleted ? "auto" : "manual", isAutoCompleted ? postcardTitle : buyerName, holdHoneyText],
        }),
        recordUserEvent({
          uid: buyerUid,
          cloudEventId: event.id,
          type: "POSTCARD_RECEIVED_BUYER",
          postcardId: (afterData.postcardId || "").toString(),
          orderId,
          messageArgs: [postcardTitle],
        }),
      ]);
      await resolveUserActionEvents({
        uid: sellerUid,
        type: "POSTCARD_ORDER_SELLER",
        orderId,
      });
      await resolveUserActionEvents({
        uid: buyerUid,
        type: "POSTCARD_SENT_BUYER",
        orderId,
      });

      try {
        const sellerSnapshot = await resolveEventSnapshot(
            sellerUid,
            "POSTCARD_RECEIVED_SELLER",
            [isAutoCompleted ? "auto" : "manual", isAutoCompleted ? postcardTitle : buyerName, holdHoneyText],
        );
        await sendPushToUser(
            sellerUid,
            pushMessageFromSnapshot(
                sellerSnapshot.title,
                sellerSnapshot.message,
                {
                  type: "POSTCARD_RECEIVED_SELLER",
                  orderId,
                  postcardId: (afterData.postcardId || "").toString(),
                  honey: String(holdHoney),
                  eventId: sellerEventId,
                  event_id: sellerEventId,
                },
            ),
            {orderId, sellerUid},
            afterData.sellerFcmToken,
        );
        logger.info("Postcard completed push sent", {orderId, sellerUid});
      } catch (error) {
        logger.error("Failed to send postcard completed push", {
          orderId,
          sellerUid,
          error: error instanceof Error ? error.message : String(error),
        });
      }
}

// Routed order-update branch: order transitions to Rejected -> resolve seller action + push buyer.
// Events: POSTCARD_REJECTED_BUYER, POSTCARD_REJECTED_SELLER
async function processPostcardRejectedEvent(event) {
      const beforeData = event.data?.before?.data();
      const afterData = event.data?.after?.data();
      if (!beforeData || !afterData) return;

      const oldStatus = (beforeData.status || "").toString();
      const newStatus = (afterData.status || "").toString();
      if (oldStatus === "Rejected" || newStatus !== "Rejected") {
        return;
      }

      const orderId = event.params.orderId;
      const buyerUid = (afterData.buyerId || "").toString();
      const sellerUid = (afterData.sellerId || "").toString();
      if (!buyerUid) {
        logger.warn("Missing buyerId for postcard rejected push", {orderId});
        return;
      }

      const postcardTitle = stringifyValue(afterData.postcardTitle, "postcard");
      const holdHoney = Number(afterData.holdHoney || afterData.priceHoney || 0);
      const holdHoneyText = String(holdHoney);
      const buyerEventId = resolveEventDocumentId(event.id, buyerUid);

      await Promise.all([
        recordUserEvent({
          uid: buyerUid,
          cloudEventId: event.id,
          type: "POSTCARD_REJECTED_BUYER",
          postcardId: (afterData.postcardId || "").toString(),
          orderId,
          messageArgs: [postcardTitle, holdHoneyText],
        }),
        recordUserEvent({
          uid: sellerUid,
          cloudEventId: event.id,
          type: "POSTCARD_REJECTED_SELLER",
          postcardId: (afterData.postcardId || "").toString(),
          orderId,
          messageArgs: [postcardTitle],
        }),
      ]);
      await resolveUserActionEvents({
        uid: sellerUid,
        type: "POSTCARD_ORDER_SELLER",
        orderId,
      });

      try {
        const buyerSnapshot = await resolveEventSnapshot(
            buyerUid,
            "POSTCARD_REJECTED_BUYER",
            [postcardTitle, holdHoneyText],
        );
        await sendPushToUser(
            buyerUid,
            pushMessageFromSnapshot(
                buyerSnapshot.title,
                buyerSnapshot.message,
                {
                  type: "POSTCARD_REJECTED_BUYER",
                  orderId,
                  postcardId: (afterData.postcardId || "").toString(),
                  honey: String(holdHoney),
                  eventId: buyerEventId,
                  event_id: buyerEventId,
                },
            ),
            {orderId, buyerUid},
            afterData.buyerFcmToken,
        );
        logger.info("Postcard rejected push sent", {orderId, buyerUid});
      } catch (error) {
        logger.error("Failed to send postcard rejected push", {
          orderId,
          buyerUid,
          error: error instanceof Error ? error.message : String(error),
        });
      }
}

// Single update trigger for postcardOrders/{orderId}; routes all order status transition event logic.
// Events: POSTCARD_SENT_BUYER, POSTCARD_SENT_SELLER, POSTCARD_RECEIVED_SELLER, POSTCARD_RECEIVED_BUYER, POSTCARD_REJECTED_BUYER, POSTCARD_REJECTED_SELLER
exports.handlePostcardOrderUpdatedEvents = onDocumentUpdated(
    {
      document: "postcardOrders/{orderId}",
      region: "us-central1",
    },
    async (event) => {
      await runEventProcessor("POSTCARD_SENT_BUYER", processPostcardShippedEvent, event);
      await runEventProcessor("postcard_completed", processSellerPostcardCompletedEvent, event);
      await runEventProcessor("POSTCARD_REJECTED_BUYER", processPostcardRejectedEvent, event);
    },
);

// Feedback create trigger: send notification email through SMTP.
exports.sendFeedbackNotificationEmail = onDocumentCreated(
    {
      document: "feedbackSubmissions/{feedbackId}",
      region: "us-central1",
    },
    async (event) => {
      const data = event.data?.data();
      if (!data) return;

      const feedbackId = event.params.feedbackId;
      const to = (process.env.FEEDBACK_TO || "kenyu910645@gmail.com").trim();
      const from = (process.env.FEEDBACK_FROM || process.env.SMTP_USER || "").trim();
      const mailer = getMailer();

      if (!mailer) {
        logger.error("Feedback email skipped: SMTP env vars missing", {
          feedbackId,
          hasHost: Boolean((process.env.SMTP_HOST || "").trim()),
          hasUser: Boolean((process.env.SMTP_USER || "").trim()),
          hasPass: Boolean((process.env.SMTP_PASS || "").trim()),
        });
        return;
      }
      if (!from) {
        logger.error("Feedback email skipped: sender not configured", {feedbackId});
        return;
      }

      const subject = feedbackEmailSubject(data.subject);
      const text = feedbackEmailText(feedbackId, data);

      try {
        await mailer.sendMail({
          from,
          to,
          subject,
          text,
          replyTo: from,
        });
        logger.info("Feedback email sent", {feedbackId, to});
      } catch (error) {
        logger.error("Failed to send feedback email", {
          feedbackId,
          to,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    },
);
