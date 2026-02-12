const {setGlobalOptions} = require("firebase-functions/v2");
const {onDocumentUpdated} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

setGlobalOptions({maxInstances: 10});

admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

async function sendPushToUser(uid, message, context) {
  const userSnap = await db.collection("users").doc(uid).get();
  if (!userSnap.exists) {
    logger.warn("User profile not found for push", {uid, ...context});
    return;
  }

  const token = userSnap.data()?.fcmToken;
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

async function getHostUid(roomId) {
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
      }, {roomId, attendeeUid});
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
      const [roomSnap, hostUid] = await Promise.all([
        db.collection("rooms").doc(roomId).get(),
        getHostUid(roomId),
      ]);

      if (!hostUid) {
        logger.warn("Host attendee not found for room", {roomId, attendeeUid});
        return;
      }

      const roomData = roomSnap.data() || {};
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
        await sendPushToUser(hostUid, message, {roomId, attendeeUid, hostUid});
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
