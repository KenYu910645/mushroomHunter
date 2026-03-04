const {setGlobalOptions} = require("firebase-functions/v2");
const {onDocumentCreated, onDocumentUpdated, onDocumentDeleted} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

setGlobalOptions({maxInstances: 10});

admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();
let cachedMailer = null;

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

function normalizeStarsCount(value, fallback = 1) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  const rounded = Math.trunc(parsed);
  if (rounded < 1) return 1;
  if (rounded > 3) return 3;
  return rounded;
}

function feedbackEmailSubject(subject) {
  const clean = stringifyValue(subject, "HoneyHub Feedback");
  return `[HoneyHub Feedback] ${clean}`;
}

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

function normalizeToken(rawToken) {
  const token = stringifyValue(rawToken, "");
  return token;
}

function normalizeHoneyValue(value) {
  const numericValue = Number(value);
  if (!Number.isFinite(numericValue)) return 0;
  return Math.trunc(numericValue);
}

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

function resolveEventRouteKind(roomId, postcardId) {
  if (stringifyValue(roomId, "")) return "room";
  if (stringifyValue(postcardId, "")) return "postcard";
  return "none";
}

function resolveEventDocumentId(cloudEventId, uid) {
  return `${stringifyValue(cloudEventId, "event")}_${stringifyValue(uid, "unknown")}`;
}

async function recordUserEvent({
  uid,
  cloudEventId,
  type,
  title,
  message,
  titleLocKey = "",
  titleLocArgs = [],
  messageLocKey = "",
  messageLocArgs = [],
  roomId = "",
  postcardId = "",
  orderId = "",
  isOpeningConfirmationQueue = false,
  isOpeningOrderPage = false,
  routeKind = "",
}) {
  const normalizedUid = stringifyValue(uid, "");
  if (!normalizedUid) return;

  const normalizedRoomId = stringifyValue(roomId, "");
  const normalizedPostcardId = stringifyValue(postcardId, "");
  const normalizedOrderId = stringifyValue(orderId, "");
  const resolvedRouteKind = stringifyValue(
      routeKind,
      resolveEventRouteKind(normalizedRoomId, normalizedPostcardId),
  );
  const eventId = resolveEventDocumentId(cloudEventId, normalizedUid);
  const eventRef = db.collection("users")
      .doc(normalizedUid)
      .collection("events")
      .doc(eventId);

  try {
    const serializedTitleLocArgs = Array.isArray(titleLocArgs) ?
      titleLocArgs.map((value) => String(value ?? "")) : [];
    const serializedMessageLocArgs = Array.isArray(messageLocArgs) ?
      messageLocArgs.map((value) => String(value ?? "")) : [];
    await eventRef.create({
      type: stringifyValue(type, "unknown"),
      title: stringifyValue(title, "Notification"),
      message: stringifyValue(message, "-"),
      titleLocKey: stringifyValue(titleLocKey, ""),
      titleLocArgs: serializedTitleLocArgs,
      messageLocKey: stringifyValue(messageLocKey, ""),
      messageLocArgs: serializedMessageLocArgs,
      roomId: normalizedRoomId,
      postcardId: normalizedPostcardId,
      orderId: normalizedOrderId,
      routeKind: resolvedRouteKind,
      isOpeningConfirmationQueue: Boolean(isOpeningConfirmationQueue),
      isOpeningOrderPage: Boolean(isOpeningOrderPage),
      isRead: false,
      readAt: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (error) {
    const isAlreadyExistsError =
        error && typeof error.code === "number" && error.code === 6;
    if (!isAlreadyExistsError) {
      throw error;
    }
  }
}

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

function isTimestampReached(timestampValue, nowTimestamp) {
  const isHasTimestamp = timestampValue &&
      typeof timestampValue.toMillis === "function";
  if (!isHasTimestamp) {
    return false;
  }
  return timestampValue.toMillis() <= nowTimestamp.toMillis();
}

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

exports.recordRoomCreatedEvent = onDocumentCreated(
    {
      document: "rooms/{roomId}",
      region: "us-central1",
    },
    async (event) => {
      const roomData = event.data?.data();
      if (!roomData) return;

      const roomId = event.params.roomId;
      const hostUid = stringifyValue(roomData.hostUid, "");
      const roomTitle = stringifyValue(roomData.title, "your room");

      await recordUserEvent({
        uid: hostUid,
        cloudEventId: event.id,
        type: "room_created",
        title: "Mushroom Room Created",
        message: `You created mushroom room: ${roomTitle}.`,
        titleLocKey: "event_room_created_title",
        messageLocKey: "event_room_created_message",
        messageLocArgs: [roomTitle],
        roomId,
      });
    },
);

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
      const hostUid = stringifyValue(afterData.hostUid, "");
      const roomTitle = stringifyValue(afterData.title, "your room");

      await recordUserEvent({
        uid: hostUid,
        cloudEventId: `${event.id}_${newFirstId}`,
        type: "raid_invited",
        title: "Mushroom Raid Invited",
        message: `You invited participants to confirm raid result for: ${roomTitle}.`,
        titleLocKey: "event_raid_invited_title",
        messageLocKey: "event_raid_invited_message",
        messageLocArgs: [roomTitle],
        roomId,
      });
    },
);

exports.recordPostcardCreatedEvent = onDocumentCreated(
    {
      document: "postcards/{postcardId}",
      region: "us-central1",
    },
    async (event) => {
      const postcardData = event.data?.data();
      if (!postcardData) return;

      const postcardId = event.params.postcardId;
      const sellerUid = stringifyValue(postcardData.sellerId, "");
      const postcardTitle = stringifyValue(postcardData.title, "a postcard");

      await recordUserEvent({
        uid: sellerUid,
        cloudEventId: event.id,
        type: "postcard_registered",
        title: "Postcard Registered",
        message: `You registered postcard: ${postcardTitle}.`,
        titleLocKey: "event_postcard_registered_title",
        messageLocKey: "event_postcard_registered_message",
        messageLocArgs: [postcardTitle],
        postcardId,
      });
    },
);

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

      const beforeHoney = normalizeHoneyValue(beforeData.honey);
      const afterHoney = normalizeHoneyValue(afterData.honey);
      const honeyDelta = afterHoney - beforeHoney;
      if (honeyDelta !== 0) {
        const isHoneyIncreased = honeyDelta > 0;
        const deltaText = String(Math.abs(honeyDelta));
        pendingEvents.push(
            recordUserEvent({
              uid,
              cloudEventId: `${event.id}_honey`,
              type: "wallet_honey_changed",
              title: "Honey Balance Updated",
              message: isHoneyIncreased ?
                `Your honey increased by ${deltaText}. Current balance: ${afterHoney}.` :
                `Your honey decreased by ${deltaText}. Current balance: ${afterHoney}.`,
              titleLocKey: "event_wallet_honey_changed_title",
              messageLocKey: isHoneyIncreased ?
                "event_wallet_honey_increased_message" :
                "event_wallet_honey_decreased_message",
              messageLocArgs: [deltaText, String(afterHoney)],
            }),
        );
      }

      const beforeName = stringifyValue(beforeData.displayName, "");
      const afterName = stringifyValue(afterData.displayName, "");
      if (beforeName !== afterName && afterName) {
        pendingEvents.push(
            recordUserEvent({
              uid,
              cloudEventId: `${event.id}_name`,
              type: "profile_name_updated",
              title: "Display Name Updated",
              message: `Your display name was updated to ${afterName}.`,
              titleLocKey: "event_profile_name_updated_title",
              messageLocKey: "event_profile_name_updated_message",
              messageLocArgs: [afterName],
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
              type: "profile_friend_code_updated",
              title: "Friend Code Updated",
              message: "Your friend code was updated.",
              titleLocKey: "event_profile_friend_code_updated_title",
              messageLocKey: "event_profile_friend_code_updated_message",
            }),
        );
      }

      if (pendingEvents.length > 0) {
        await Promise.all(pendingEvents);
      }
    },
);

exports.sendRaidConfirmationPush = onDocumentUpdated(
    {
      document: "rooms/{roomId}/attendees/{attendeeUid}",
      region: "us-central1",
    },
    async (event) => {
      const beforeData = event.data?.before?.data();
      const afterData = event.data?.after?.data();
      if (!afterData) return;

      const oldStatus = beforeData?.status ?? null;
      const newStatus = afterData.status ?? null;
      if (oldStatus === "WaitingConfirmation" || newStatus !== "WaitingConfirmation") {
        return;
      }

      const roomId = event.params.roomId;
      const attendeeUid = event.params.attendeeUid;
      const roomSnap = await db.collection("rooms").doc(roomId).get();

      const roomData = roomSnap.data() || {};
      const hostName = (roomData.hostName || "Host").toString();
      const attendeeEventId = resolveEventDocumentId(event.id, attendeeUid);

      await recordUserEvent({
        uid: attendeeUid,
        cloudEventId: event.id,
        type: "raid_confirmation",
        title: "Mushroom Raid Confirmation",
        message: `${hostName} invited you to confirm your mushroom raid result.`,
        titleLocKey: "event_raid_confirmation_title",
        messageLocKey: "event_raid_confirmation_message",
        messageLocArgs: [hostName],
        roomId,
        isOpeningConfirmationQueue: true,
      });

      try {
        await sendPushToUser(
            attendeeUid,
            localizedPushMessage(
                "push_mushroom_raid_confirmation_title",
                "push_mushroom_raid_confirmation_body",
                [hostName],
                {
                  type: "raid_confirmation",
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
    },
);

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

      const attendeeName = stringifyValue(afterData.name, "A player");
      const roomTitle = stringifyValue(roomData.title, "your room");
      const joinGreetingMessage = stringifyValue(afterData.joinGreetingMessage, "");
      const isHasGreetingMessage = joinGreetingMessage.length > 0;
      const hostEventId = resolveEventDocumentId(event.id, hostUid);

      await Promise.all([
        recordUserEvent({
          uid: attendeeUid,
          cloudEventId: event.id,
          type: "room_join_request_submitted",
          title: "Join Application Sent",
          message: `You sent a join request to room: ${roomTitle}.`,
          titleLocKey: "event_room_join_request_submitted_title",
          messageLocKey: "event_room_join_request_submitted_message",
          messageLocArgs: [roomTitle],
          roomId,
        }),
        recordUserEvent({
          uid: hostUid,
          cloudEventId: event.id,
          type: "room_join_request_received",
          title: "Join Application Received",
          message: `${attendeeName} applied to join your room: ${roomTitle}.`,
          titleLocKey: "event_room_join_request_received_title",
          messageLocKey: "event_room_join_request_received_message",
          messageLocArgs: [attendeeName, roomTitle],
          roomId,
        }),
      ]);

      try {
        await sendPushToUser(
            hostUid,
            localizedPushMessage(
                "push_mushroom_join_request_title",
                isHasGreetingMessage ?
                "push_mushroom_join_request_body_with_message" :
                "push_mushroom_join_request_body",
                isHasGreetingMessage ?
                [attendeeName, roomTitle, joinGreetingMessage] :
                [attendeeName, roomTitle],
                {
                  type: "room_join_request",
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

exports.notifyJoinApplicantAccepted = onDocumentUpdated(
    {
      document: "rooms/{roomId}/attendees/{attendeeUid}",
      region: "us-central1",
    },
    async (event) => {
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
      const roomTitle = stringifyValue(roomData.title, "the room");
      const attendeeName = stringifyValue(afterData.name, "A player");
      const attendeeEventId = resolveEventDocumentId(event.id, attendeeUid);

      const pendingEvents = [
        recordUserEvent({
          uid: attendeeUid,
          cloudEventId: event.id,
          type: "room_join_request_accepted",
          title: "Join Application Accepted",
          message: `Your request was accepted for room: ${roomTitle}.`,
          titleLocKey: "event_room_join_request_accepted_title",
          messageLocKey: "event_room_join_request_accepted_message",
          messageLocArgs: [roomTitle],
          roomId,
        }),
      ];
      if (hostUid) {
        pendingEvents.push(
            recordUserEvent({
              uid: hostUid,
              cloudEventId: event.id,
              type: "room_joiner_accepted",
              title: "Joiner Accepted",
              message: `You accepted ${attendeeName} into room: ${roomTitle}.`,
              titleLocKey: "event_room_joiner_accepted_title",
              messageLocKey: "event_room_joiner_accepted_message",
              messageLocArgs: [attendeeName, roomTitle],
              roomId,
            }),
        );
      }
      await Promise.all(pendingEvents);

      try {
        await sendPushToUser(
            attendeeUid,
            localizedPushMessage(
                "push_mushroom_join_request_accepted_title",
                "push_mushroom_join_request_accepted_body",
                [roomTitle],
                {
                  type: "room_join_request_accepted",
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
    },
);

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
      const roomTitle = stringifyValue(roomData.title, "the room");
      const attendeeName = stringifyValue(beforeData.name, "A player");
      const attendeeEventId = resolveEventDocumentId(event.id, attendeeUid);

      const pendingEvents = [
        recordUserEvent({
          uid: attendeeUid,
          cloudEventId: event.id,
          type: "room_join_request_rejected",
          title: "Join Application Rejected",
          message: `Your request was rejected for room: ${roomTitle}.`,
          titleLocKey: "event_room_join_request_rejected_title",
          messageLocKey: "event_room_join_request_rejected_message",
          messageLocArgs: [roomTitle],
          roomId,
        }),
      ];
      if (hostUid) {
        pendingEvents.push(
            recordUserEvent({
              uid: hostUid,
              cloudEventId: event.id,
              type: "room_joiner_rejected",
              title: "Joiner Rejected",
              message: `You rejected ${attendeeName} from room: ${roomTitle}.`,
              titleLocKey: "event_room_joiner_rejected_title",
              messageLocKey: "event_room_joiner_rejected_message",
              messageLocArgs: [attendeeName, roomTitle],
              roomId,
            }),
        );
      }
      await Promise.all(pendingEvents);

      try {
        await sendPushToUser(
            attendeeUid,
            localizedPushMessage(
                "push_mushroom_join_request_rejected_title",
                "push_mushroom_join_request_rejected_body",
                [roomTitle],
                {
                  type: "room_join_request_rejected",
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

exports.notifyHostRaidConfirmationResult = onDocumentUpdated(
    {
      document: "rooms/{roomId}/attendees/{attendeeUid}",
      region: "us-central1",
    },
    async (event) => {
      const beforeData = event.data?.before?.data();
      const afterData = event.data?.after?.data();
      if (!beforeData || !afterData) return;

      const oldStatus = beforeData.status ?? null;
      const newStatus = afterData.status ?? null;
      const transitionedFromWaiting = oldStatus === "WaitingConfirmation";
      const transitionedToReady = newStatus === "Ready";
      const transitionedToRejected = newStatus === "Rejected";
      if (!transitionedFromWaiting || (!transitionedToReady && !transitionedToRejected)) {
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
      const attendeeName = (afterData.name || "A player").toString();
      const settlementOutcome = (afterData.lastSettlementOutcome || "").toString();
      const settlementHoney = Number(afterData.lastSettlementHoney || 0);
      const raidCostHoneyText = String(raidCostHoney);
      const settlementHoneyText = String(settlementHoney);
      const hostEventId = resolveEventDocumentId(event.id, hostUid);
      const attendeeOutcomeText = transitionedToRejected ?
        "Rejected" :
        settlementOutcome === "SeatFullNoFault" ?
          "Seat Full (No Fault)" :
          settlementOutcome === "MissedInvitation" ?
            "Missed Invitation" :
            "Joined Success";

      await Promise.all([
        recordUserEvent({
          uid: hostUid,
          cloudEventId: event.id,
          type: transitionedToRejected ? "raid_confirmation_rejected" : "raid_confirmation_ready",
          title: "Raid Confirmation Result",
          message: `${attendeeName} submitted result: ${attendeeOutcomeText}.`,
          roomId,
        }),
        recordUserEvent({
          uid: attendeeUid,
          cloudEventId: event.id,
          type: transitionedToRejected ? "raid_confirmation_rejected" : "raid_confirmation_ready",
          title: "Your Confirmation Submitted",
          message: `Your raid result was submitted as: ${attendeeOutcomeText}.`,
          roomId,
          isOpeningConfirmationQueue: true,
        }),
      ]);

      const message = transitionedToReady ? (settlementOutcome === "SeatFullNoFault" ?
        localizedPushMessage(
            "push_mushroom_raid_result_seat_full_title",
            "push_mushroom_raid_result_seat_full_body",
            [attendeeName, settlementHoneyText],
            {
              type: "raid_confirmation_seat_full",
              roomId,
              room_id: roomId,
              attendeeUid,
              honeyEarned: settlementHoneyText,
              eventId: hostEventId,
              event_id: hostEventId,
            },
        ) : settlementOutcome === "MissedInvitation" ?
          localizedPushMessage(
              "push_mushroom_raid_result_missed_invite_title",
              "push_mushroom_raid_result_missed_invite_body",
              [attendeeName],
              {
                type: "raid_confirmation_missed_invite",
                roomId,
                room_id: roomId,
                attendeeUid,
                honeyEarned: "0",
                eventId: hostEventId,
                event_id: hostEventId,
              },
          ) :
          localizedPushMessage(
              "push_mushroom_raid_result_accepted_title",
              "push_mushroom_raid_result_accepted_body",
              [attendeeName, raidCostHoneyText],
              {
                type: "raid_confirmation_accepted",
                roomId,
                room_id: roomId,
                attendeeUid,
                honeyEarned: raidCostHoneyText,
                eventId: hostEventId,
                event_id: hostEventId,
              },
          )) :
        localizedPushMessage(
            "push_mushroom_raid_result_rejected_title",
            "push_mushroom_raid_result_rejected_body",
            [attendeeName],
            {
              type: "raid_confirmation_rejected",
              roomId,
              room_id: roomId,
              attendeeUid,
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
    },
);

exports.notifyMushroomStarReceived = onDocumentUpdated(
    {
      document: "rooms/{roomId}/attendees/{attendeeUid}",
      region: "us-central1",
    },
    async (event) => {
      const beforeData = event.data?.before?.data();
      const afterData = event.data?.after?.data();
      if (!beforeData || !afterData) return;

      const roomId = event.params.roomId;
      const attendeeUid = event.params.attendeeUid;
      const roomSnap = await db.collection("rooms").doc(roomId).get();
      const roomData = roomSnap.data() || {};
      const raterName = stringifyValue(afterData.name, "A player");

      const attendeeRatedHostNow =
          beforeData.attendeeRatedHost !== true && afterData.attendeeRatedHost === true;
      if (attendeeRatedHostNow) {
        const hostUid = await resolveHostUid(roomId, roomData);
        const awardedStars = normalizeStarsCount(afterData.attendeeRatedHostStars, 1);
        const hostName = stringifyValue(roomData.hostName, "Host");
        if (hostUid) {
          const hostEventId = resolveEventDocumentId(event.id, hostUid);
          await Promise.all([
            recordUserEvent({
              uid: hostUid,
              cloudEventId: event.id,
              type: "room_star_received",
              title: "Stars Received",
              message: `${raterName} gave you ${awardedStars} stars.`,
              roomId,
            }),
            recordUserEvent({
              uid: attendeeUid,
              cloudEventId: event.id,
              type: "room_star_given",
              title: "Stars Given",
              message: `You gave ${awardedStars} stars to ${hostName}.`,
              roomId,
            }),
          ]);
          try {
            await sendPushToUser(
                hostUid,
                localizedPushMessage(
                    "push_mushroom_star_received_title",
                    "push_mushroom_star_received_body",
                    [raterName, awardedStars],
                    {
                      type: "room_star_received",
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

      const hostRatedAttendeeNow =
          beforeData.hostRatedAttendee !== true && afterData.hostRatedAttendee === true;
      if (hostRatedAttendeeNow) {
        const hostUid = await resolveHostUid(roomId, roomData);
        const hostName = stringifyValue(roomData.hostName, "Host");
        const starDelta = Number(afterData.stars || 0) - Number(beforeData.stars || 0);
        const awardedStars = normalizeStarsCount(afterData.hostRatedAttendeeStars, starDelta);
        const attendeeEventId = resolveEventDocumentId(event.id, attendeeUid);
        await Promise.all([
          recordUserEvent({
            uid: attendeeUid,
            cloudEventId: event.id,
            type: "room_star_received",
            title: "Stars Received",
            message: `${hostName} gave you ${awardedStars} stars.`,
            roomId,
          }),
          recordUserEvent({
            uid: hostUid,
            cloudEventId: event.id,
            type: "room_star_given",
            title: "Stars Given",
            message: `You gave ${awardedStars} stars to ${raterName}.`,
            roomId,
          }),
        ]);
        try {
          await sendPushToUser(
              attendeeUid,
              localizedPushMessage(
                  "push_mushroom_star_received_title",
                  "push_mushroom_star_received_body",
                  [hostName, awardedStars],
                  {
                    type: "room_star_received",
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
    },
);

exports.sendPostcardShippedPush = onDocumentUpdated(
    {
      document: "postcardOrders/{orderId}",
      region: "us-central1",
    },
    async (event) => {
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

      const sellerName = (afterData.sellerName || "Seller").toString();
      const postcardTitle = (afterData.postcardTitle || "postcard").toString();
      const buyerEventId = resolveEventDocumentId(event.id, buyerUid);

      await Promise.all([
        recordUserEvent({
          uid: buyerUid,
          cloudEventId: event.id,
          type: "postcard_shipped",
          title: "Postcard Shipped",
          message: `${sellerName} shipped your order: ${postcardTitle}.`,
          postcardId: (afterData.postcardId || "").toString(),
          orderId,
          isOpeningOrderPage: true,
        }),
        recordUserEvent({
          uid: sellerUid,
          cloudEventId: event.id,
          type: "postcard_sent",
          title: "Postcard Sent",
          message: `You marked order as shipped: ${postcardTitle}.`,
          postcardId: (afterData.postcardId || "").toString(),
          orderId,
          isOpeningOrderPage: true,
        }),
      ]);

      try {
        await sendPushToUser(buyerUid, {
          apns: {
            payload: {
              aps: {
                alert: {
                  "title-loc-key": "push_postcard_shipped_title",
                  "loc-key": "push_postcard_shipped_body",
                  "loc-args": [sellerName, postcardTitle],
                },
              },
            },
          },
          data: {
            type: "postcard_shipped",
            orderId,
            postcardId: (afterData.postcardId || "").toString(),
            eventId: buyerEventId,
            event_id: buyerEventId,
          },
        }, {orderId, buyerUid}, afterData.buyerFcmToken);
        logger.info("Postcard shipped push sent", {orderId, buyerUid});
      } catch (error) {
        logger.error("Failed to send postcard shipped push", {
          orderId,
          buyerUid,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    },
);

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

      const postcardTitle = (orderData.postcardTitle || "postcard").toString();
      const sellerEventId = resolveEventDocumentId(event.id, sellerUid);
      const buyerName = stringifyValue(orderData.buyerName, "A buyer");

      await Promise.all([
        recordUserEvent({
          uid: sellerUid,
          cloudEventId: event.id,
          type: "postcard_order_created",
          title: "New Postcard Order",
          message: `${buyerName} ordered your postcard: ${postcardTitle}.`,
          postcardId: (orderData.postcardId || "").toString(),
          orderId,
          isOpeningOrderPage: true,
        }),
        recordUserEvent({
          uid: buyerUid,
          cloudEventId: event.id,
          type: "postcard_order_sent",
          title: "Order Sent",
          message: `You placed an order for postcard: ${postcardTitle}.`,
          postcardId: (orderData.postcardId || "").toString(),
          orderId,
          isOpeningOrderPage: true,
        }),
      ]);

      try {
        await sendPushToUser(sellerUid, {
          apns: {
            payload: {
              aps: {
                alert: {
                  "title-loc-key": "push_postcard_order_created_title",
                  "loc-key": "push_postcard_order_created_body",
                  "loc-args": [postcardTitle],
                },
              },
            },
          },
          data: {
            type: "postcard_order_created",
            orderId,
            postcardId: (orderData.postcardId || "").toString(),
            eventId: sellerEventId,
            event_id: sellerEventId,
          },
        }, {orderId, sellerUid}, orderData.sellerFcmToken);
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

exports.notifySellerPostcardCompleted = onDocumentUpdated(
    {
      document: "postcardOrders/{orderId}",
      region: "us-central1",
    },
    async (event) => {
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

      const buyerName = (afterData.buyerName || "Buyer").toString();
      const postcardTitle = (afterData.postcardTitle || "postcard").toString();
      const holdHoney = Number(afterData.holdHoney || 0);
      const holdHoneyText = String(holdHoney);
      const isAutoCompleted = newStatus === "CompletedAuto";
      const sellerEventId = resolveEventDocumentId(event.id, sellerUid);

      await Promise.all([
        recordUserEvent({
          uid: sellerUid,
          cloudEventId: event.id,
          type: "postcard_order_completed",
          title: "Order Completed",
          message: isAutoCompleted ?
            `Order auto-completed for ${postcardTitle}. You received ${holdHoneyText} honey.` :
            `${buyerName} confirmed receipt. You received ${holdHoneyText} honey.`,
          postcardId: (afterData.postcardId || "").toString(),
          orderId,
          isOpeningOrderPage: true,
        }),
        recordUserEvent({
          uid: buyerUid,
          cloudEventId: event.id,
          type: "postcard_received",
          title: "Postcard Received",
          message: isAutoCompleted ?
            `Your order for ${postcardTitle} was auto-completed.` :
            `You confirmed receipt for ${postcardTitle}.`,
          postcardId: (afterData.postcardId || "").toString(),
          orderId,
          isOpeningOrderPage: true,
        }),
      ]);

      try {
        await sendPushToUser(sellerUid, {
          apns: {
            payload: {
              aps: {
                alert: isAutoCompleted ? {
                  "title-loc-key": "push_postcard_completed_title",
                  "loc-key": "push_postcard_completed_auto_body",
                  "loc-args": [postcardTitle, holdHoneyText],
                } : {
                  "title-loc-key": "push_postcard_completed_title",
                  "loc-key": "push_postcard_completed_body",
                  "loc-args": [buyerName, holdHoneyText],
                },
              },
            },
          },
          data: {
            type: "postcard_order_completed",
            orderId,
            postcardId: (afterData.postcardId || "").toString(),
            honey: String(holdHoney),
            eventId: sellerEventId,
            event_id: sellerEventId,
          },
        }, {orderId, sellerUid}, afterData.sellerFcmToken);
        logger.info("Postcard completed push sent", {orderId, sellerUid});
      } catch (error) {
        logger.error("Failed to send postcard completed push", {
          orderId,
          sellerUid,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    },
);

exports.sendPostcardRejectedPush = onDocumentUpdated(
    {
      document: "postcardOrders/{orderId}",
      region: "us-central1",
    },
    async (event) => {
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

      const postcardTitle = (afterData.postcardTitle || "postcard").toString();
      const holdHoney = Number(afterData.holdHoney || afterData.priceHoney || 0);
      const holdHoneyText = String(holdHoney);
      const buyerEventId = resolveEventDocumentId(event.id, buyerUid);

      await Promise.all([
        recordUserEvent({
          uid: buyerUid,
          cloudEventId: event.id,
          type: "postcard_rejected",
          title: "Order Rejected",
          message: `Your order for ${postcardTitle} was rejected. ${holdHoneyText} honey was refunded.`,
          postcardId: (afterData.postcardId || "").toString(),
          orderId,
          isOpeningOrderPage: true,
        }),
        recordUserEvent({
          uid: sellerUid,
          cloudEventId: event.id,
          type: "postcard_order_rejected",
          title: "Order Rejected",
          message: `You rejected an order for ${postcardTitle}.`,
          postcardId: (afterData.postcardId || "").toString(),
          orderId,
          isOpeningOrderPage: true,
        }),
      ]);

      try {
        await sendPushToUser(buyerUid, {
          apns: {
            payload: {
              aps: {
                alert: {
                  "title-loc-key": "push_postcard_rejected_title",
                  "loc-key": "push_postcard_rejected_body",
                  "loc-args": [postcardTitle, holdHoneyText],
                },
              },
            },
          },
          data: {
            type: "postcard_rejected",
            orderId,
            postcardId: (afterData.postcardId || "").toString(),
            honey: holdHoneyText,
            eventId: buyerEventId,
            event_id: buyerEventId,
          },
        }, {orderId, buyerUid}, afterData.buyerFcmToken);
        logger.info("Postcard rejected push sent", {orderId, buyerUid});
      } catch (error) {
        logger.error("Failed to send postcard rejected push", {
          orderId,
          buyerUid,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    },
);

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
