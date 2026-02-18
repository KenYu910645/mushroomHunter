const {setGlobalOptions} = require("firebase-functions/v2");
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
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

  await messaging.send({
    token,
    ...message,
    apns: {
      payload: {
        aps: {
          sound: "default",
        },
      },
    },
  });
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
      const roomTitle = (roomData.title || "your room").toString();

      try {
        await sendPushToUser(attendeeUid, {
        notification: {
          title: "Confirmation Require",
          body: `${hostName} claimed to invite you to mushroom raid. Tap to respond.`,
        },
        data: {
          type: "raid_confirmation",
          roomId,
          room_id: roomId,
        },
      }, {roomId, attendeeUid}, afterData.fcmToken);
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

      const message = transitionedToReady ? {
        notification: {
          title: "Attendee Confirmed",
          body: `${attendeeName} confirmed. You earned ${raidCostHoney} honey.`,
        },
        data: {
          type: "raid_confirmation_accepted",
          roomId,
          room_id: roomId,
          attendeeUid,
          honeyEarned: String(raidCostHoney),
        },
      } : {
        notification: {
          title: "Attendee Rejected",
          body: `${attendeeName} rejected your confirmation. Tap to resolve it.`,
        },
        data: {
          type: "raid_confirmation_rejected",
          roomId,
          room_id: roomId,
          attendeeUid,
        },
      };

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
      if (oldStatus === "InTransit" || newStatus !== "InTransit") {
        return;
      }

      const orderId = event.params.orderId;
      const buyerUid = (afterData.buyerId || "").toString();
      if (!buyerUid) {
        logger.warn("Missing buyerId for postcard order push", {orderId});
        return;
      }

      const sellerName = (afterData.sellerName || "Seller").toString();
      const postcardTitle = (afterData.postcardTitle || "postcard").toString();

      try {
        await sendPushToUser(buyerUid, {
          notification: {
            title: "Postcard Sent",
            body: `${sellerName} marked "${postcardTitle}" as sent. Please check delivery and confirm receipt in app.`,
          },
          data: {
            type: "postcard_shipped",
          orderId,
          postcardId: (afterData.postcardId || "").toString(),
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
      if (status !== "AwaitingSellerSend") {
        return;
      }

      const orderId = event.params.orderId;
      const sellerUid = (orderData.sellerId || "").toString();
      if (!sellerUid) {
        logger.warn("Missing sellerId for postcard order-created push", {orderId});
        return;
      }

      const buyerName = (orderData.buyerName || "A buyer").toString();
      const postcardTitle = (orderData.postcardTitle || "postcard").toString();

      try {
        await sendPushToUser(sellerUid, {
          notification: {
            title: "New Postcard Order",
            body: `${buyerName} ordered "${postcardTitle}". Open postcard detail to process shipping.`,
          },
          data: {
            type: "postcard_order_created",
          orderId,
          postcardId: (orderData.postcardId || "").toString(),
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
      if (oldStatus === "Completed" || newStatus !== "Completed") {
        return;
      }

      const orderId = event.params.orderId;
      const sellerUid = (afterData.sellerId || "").toString();
      if (!sellerUid) {
        logger.warn("Missing sellerId for postcard completed push", {orderId});
        return;
      }

      const buyerName = (afterData.buyerName || "Buyer").toString();
      const holdHoney = Number(afterData.holdHoney || 0);

      try {
        await sendPushToUser(sellerUid, {
          notification: {
            title: "Order Completed",
            body: `${buyerName} confirmed receipt. ${holdHoney} honey has been transferred to you.`,
          },
          data: {
            type: "postcard_order_completed",
            orderId,
            postcardId: (afterData.postcardId || "").toString(),
            honey: String(holdHoney),
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
