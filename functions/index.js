// functions/index.js
// ═══════════════════════════════════════════════════════════════
// R.A.C.O.M.A. HRIS — Cloud Functions
// ═══════════════════════════════════════════════════════════════
// Setup sa functions folder:
//   npm install
//   firebase deploy --only functions
// ═══════════════════════════════════════════════════════════════

// ── Firebase Admin v13 (modular) ──
const { initializeApp } = require("firebase-admin/app");
const {
  getFirestore,
  FieldValue,
  Timestamp,
} = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { getMessaging } = require("firebase-admin/messaging"); // 🆕

// ── Firebase Functions v2 ──
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore"); // 🆕
const { setGlobalOptions } = require("firebase-functions/v2");
const logger = require("firebase-functions/logger");

// ── WebAuthn v14 ──
const {
  generateRegistrationOptions,
  verifyRegistrationResponse,
  generateAuthenticationOptions,
  verifyAuthenticationResponse,
} = require("@simplewebauthn/server");

// ── Initialize (once) ──
initializeApp();
const db = getFirestore();
const auth = getAuth();

// I-set ang region (Singapore — malapit sa PH)
setGlobalOptions({ region: "asia-southeast1", maxInstances: 10 });

// ═══════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════
const OFFICE_LAT = 14.6114;
const OFFICE_LNG = 120.9936;
const RADIUS_LIMIT_M = 1500.0;
const LATE_THRESHOLD_HOUR = 9;
const LATE_THRESHOLD_MIN = 15;

const RP_NAME = "HRIS Biometrics";
const RP_ID = "week-9-activity-53484.web.app";
const ORIGIN = "https://week-9-activity-53484.web.app";

// ═══════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════
function haversine(lat1, lon1, lat2, lon2) {
  const R = 6371000.0;
  const dPhi = ((lat2 - lat1) * Math.PI) / 180;
  const dLam = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dPhi / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLam / 2) ** 2;
  return R * 2 * Math.asin(Math.sqrt(a));
}

function assertAdmin(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Not signed in");
  }
  const token = request.auth.token || {};
  const isAdmin = token.admin === true || token.role === "admin";
  if (!isAdmin) {
    throw new HttpsError("permission-denied", "Admin access required");
  }
}

// ═══════════════════════════════════════════════════════════════
// (1) cascadeDeleteEmployeeData
// ═══════════════════════════════════════════════════════════════
exports.cascadeDeleteEmployeeData = onCall(async (request) => {
  assertAdmin(request);

  const employeeId = request.data.employeeId;
  if (!employeeId) {
    throw new HttpsError("invalid-argument", "Missing employeeId");
  }

  logger.info(`cascadeDeleteEmployeeData for ${employeeId}`);
  return { deleted: true, employeeId };
});

// ═══════════════════════════════════════════════════════════════
// (2) ADMIN OVERVIEW STATS
// ═══════════════════════════════════════════════════════════════
exports.getAdminOverviewStats = onCall(async (request) => {
  assertAdmin(request);

  const now = new Date();
  const startOfToday = new Date(
    now.getFullYear(), now.getMonth(), now.getDate()
  );
  const startOfYesterday = new Date(
    startOfToday.getTime() - 24 * 60 * 60 * 1000
  );

  const empSnap = await db.collection("employees").get();
  const totalStaff = empSnap.size;

  const todayLogsSnap = await db
    .collection("attendance_logs")
    .where("timestamp", ">=", Timestamp.fromDate(startOfToday))
    .get();

  const yesterdayLogsSnap = await db
    .collection("attendance_logs")
    .where("timestamp", ">=", Timestamp.fromDate(startOfYesterday))
    .where("timestamp", "<", Timestamp.fromDate(startOfToday))
    .get();

  let clockedIn = 0;
  let lateArrivals = 0;
  let totalLateMinutes = 0;
  const chart = new Array(8).fill(0);

  todayLogsSnap.forEach((doc) => {
    const d = doc.data();
    const type = (d.type || "").toUpperCase();
    if (type === "IN" || type === "LOGIN") {
      clockedIn++;
      const dt = d.timestamp.toDate();
      const idx = Math.min(7, Math.floor(dt.getHours() / 3));
      chart[idx]++;

      const threshold = new Date(
        dt.getFullYear(),
        dt.getMonth(),
        dt.getDate(),
        LATE_THRESHOLD_HOUR,
        LATE_THRESHOLD_MIN
      );
      if (dt > threshold) {
        lateArrivals++;
        totalLateMinutes += Math.floor((dt - threshold) / 60000);
      }
    }
  });

  const avgLateMinutes =
    lateArrivals === 0 ? 0 : Math.round(totalLateMinutes / lateArrivals);

  const yesterdayIds = new Set();
  yesterdayLogsSnap.forEach((doc) => {
    const d = doc.data();
    const type = (d.type || "").toUpperCase();
    if (type === "IN" || type === "LOGIN") {
      const id = (d.employee_id || d.employeeId || "").toString();
      if (id) yesterdayIds.add(id);
    }
  });
  const yesterdayActive = yesterdayIds.size;

  const locSnap = await db.collection("locations").get();
  const latestByEmp = {};
  locSnap.forEach((doc) => {
    const d = doc.data();
    const id = (d.employee_id || d.employeeId || "").toString();
    if (!id) return;
    const ts = d.timestamp || d.created_at || d.updated_at;
    const tsMillis = ts && ts.toMillis ? ts.toMillis() : 0;
    const existing = latestByEmp[id];
    if (!existing || tsMillis > existing.tsMillis) {
      latestByEmp[id] = {
        lat: Number(d.latitude ?? d.lat ?? 0),
        lng: Number(d.longitude ?? d.lng ?? 0),
        tsMillis,
      };
    }
  });

  let outRange = 0;
  Object.values(latestByEmp).forEach((loc) => {
    if (loc.lat === 0 && loc.lng === 0) return;
    const dist = haversine(loc.lat, loc.lng, OFFICE_LAT, OFFICE_LNG);
    if (dist > RADIUS_LIMIT_M) outRange++;
  });

  logger.info(`getAdminOverviewStats by ${request.auth.uid}`, {
    totalStaff,
    clockedIn,
    lateArrivals,
    outRange,
  });

  return {
    totalStaff,
    clockedIn,
    lateArrivals,
    avgLateMinutes,
    outRange,
    yesterdayActive,
    chart,
    serverTime: now.toISOString(),
  };
});

// ═══════════════════════════════════════════════════════════════
// (3) WEBAUTHN — REGISTRATION OPTIONS
// ═══════════════════════════════════════════════════════════════
exports.webauthnGenerateRegistrationOptions = onCall(async (request) => {
  const { employeeId } = request.data;
  if (!employeeId) {
    throw new HttpsError("invalid-argument", "Missing employeeId");
  }

  const empDoc = await db.collection("employees").doc(employeeId).get();
  if (!empDoc.exists) {
    throw new HttpsError("not-found", "Employee not found");
  }
  const employee = empDoc.data();

  const credsSnap = await db
    .collection("employees")
    .doc(employeeId)
    .collection("webauthnCredentials")
    .get();

  const excludeCredentials = credsSnap.docs.map((d) => ({
    id: d.id,
    transports: d.data().transports || [],
  }));

  const options = await generateRegistrationOptions({
    rpName: RP_NAME,
    rpID: RP_ID,
    userID: new TextEncoder().encode(employeeId),
    userName: employee.email || employeeId,
    userDisplayName: employee.fullName || employee.email || employeeId,
    attestationType: "none",
    excludeCredentials,
    authenticatorSelection: {
      authenticatorAttachment: "platform",
      userVerification: "required",
      residentKey: "preferred",
    },
  });

  await db.collection("webauthnChallenges").doc(employeeId).set({
    challenge: options.challenge,
    type: "registration",
    createdAt: FieldValue.serverTimestamp(),
  });

  return options;
});

// ═══════════════════════════════════════════════════════════════
// (4) WEBAUTHN — VERIFY REGISTRATION
// ═══════════════════════════════════════════════════════════════
exports.webauthnVerifyRegistration = onCall(async (request) => {
  const { employeeId, credential: registrationResponse, deviceLabel } =
    request.data;
  if (!employeeId || !registrationResponse) {
    throw new HttpsError(
      "invalid-argument",
      "Missing employeeId or credential"
    );
  }

  const challengeDoc = await db
    .collection("webauthnChallenges")
    .doc(employeeId)
    .get();
  if (!challengeDoc.exists) {
    throw new HttpsError("failed-precondition", "No pending challenge");
  }
  const { challenge } = challengeDoc.data();

  let verification;
  try {
    verification = await verifyRegistrationResponse({
      response: registrationResponse,
      expectedChallenge: challenge,
      expectedOrigin: ORIGIN,
      expectedRPID: RP_ID,
    });
  } catch (err) {
    throw new HttpsError("invalid-argument", `Verification failed: ${err.message}`);
  }

  if (!verification.verified || !verification.registrationInfo) {
    throw new HttpsError(
      "permission-denied",
      "Registration could not be verified"
    );
  }

  const { credential } = verification.registrationInfo;

  await db
    .collection("employees")
    .doc(employeeId)
    .collection("webauthnCredentials")
    .doc(credential.id)
    .set({
      publicKey: Buffer.from(credential.publicKey).toString("base64"),
      counter: credential.counter,
      transports: credential.transports || [],
      createdAt: FieldValue.serverTimestamp(),
      deviceLabel: deviceLabel || "Unknown device",
    });

  await db.collection("webauthnChallenges").doc(employeeId).delete();

  return { verified: true };
});

// ═══════════════════════════════════════════════════════════════
// (5) WEBAUTHN — AUTH OPTIONS
// ═══════════════════════════════════════════════════════════════
exports.webauthnGenerateAuthOptions = onCall(async (request) => {
  const { employeeId } = request.data;
  if (!employeeId) {
    throw new HttpsError("invalid-argument", "Missing employeeId");
  }

  const credsSnap = await db
    .collection("employees")
    .doc(employeeId)
    .collection("webauthnCredentials")
    .get();

  if (credsSnap.empty) {
    throw new HttpsError(
      "failed-precondition",
      "Walang naka-enroll na fingerprint sa device na ito. Mag-enroll muna."
    );
  }

  const allowCredentials = credsSnap.docs.map((d) => ({
    id: d.id,
    transports: d.data().transports || [],
  }));

  const options = await generateAuthenticationOptions({
    rpID: RP_ID,
    allowCredentials,
    userVerification: "required",
  });

  await db.collection("webauthnChallenges").doc(employeeId).set({
    challenge: options.challenge,
    type: "authentication",
    createdAt: FieldValue.serverTimestamp(),
  });

  return options;
});

// ═══════════════════════════════════════════════════════════════
// (6) WEBAUTHN — VERIFY AUTH
// ═══════════════════════════════════════════════════════════════
exports.webauthnVerifyAuth = onCall(async (request) => {
  const { employeeId, credential: authResponse } = request.data;
  if (!employeeId || !authResponse) {
    throw new HttpsError(
      "invalid-argument",
      "Missing employeeId or credential"
    );
  }

  const challengeDoc = await db
    .collection("webauthnChallenges")
    .doc(employeeId)
    .get();
  if (!challengeDoc.exists) {
    throw new HttpsError("failed-precondition", "No pending challenge");
  }
  const { challenge } = challengeDoc.data();

  const credDocRef = db
    .collection("employees")
    .doc(employeeId)
    .collection("webauthnCredentials")
    .doc(authResponse.id);
  const credDoc = await credDocRef.get();
  if (!credDoc.exists) {
    throw new HttpsError("not-found", "Credential not recognized");
  }
  const storedCred = credDoc.data();

  let verification;
  try {
    verification = await verifyAuthenticationResponse({
      response: authResponse,
      expectedChallenge: challenge,
      expectedOrigin: ORIGIN,
      expectedRPID: RP_ID,
      credential: {
        id: authResponse.id,
        publicKey: Buffer.from(storedCred.publicKey, "base64"),
        counter: storedCred.counter,
        transports: storedCred.transports || [],
      },
    });
  } catch (err) {
    throw new HttpsError(
      "invalid-argument",
      `Auth verification failed: ${err.message}`
    );
  }

  if (!verification.verified) {
    throw new HttpsError("permission-denied", "Fingerprint did not match");
  }

  await credDocRef.update({
    counter: verification.authenticationInfo.newCounter,
  });
  await db.collection("webauthnChallenges").doc(employeeId).delete();

  return { verified: true };
});

// ═══════════════════════════════════════════════════════════════
// (7) 🆕 FCM TRIGGER — Employee Notification Push
// ═══════════════════════════════════════════════════════════════
// Kapag may bagong doc sa `employee_notifications`, automatic na
// nagpapadala ng FCM push sa employee device (kahit killed ang app).
// ═══════════════════════════════════════════════════════════════
exports.sendEmployeeNotification = onDocumentCreated(
  {
    document: "employee_notifications/{notifId}",
    region: "asia-southeast1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) {
      logger.warn("No data in event");
      return;
    }

    const data = snap.data();
    const employeeId = data.employeeId;
    const title = data.title || "Notification";
    const message = data.message || "";
    const type = data.type || "general";
    const priority = data.priority || "normal";

    logger.info(
        `📤 [${event.params.notifId}] → ${employeeId}: ${title}`
    );

    try {
      let tokens = [];

      if (employeeId === "ALL") {
        const empSnap = await db
            .collection("employees")
            .where("fcmToken", "!=", null)
            .get();

        empSnap.forEach((doc) => {
          const t = doc.data().fcmToken;
          if (t && typeof t === "string" && t.length > 0) {
            tokens.push(t);
          }
        });
        logger.info(`   Found ${tokens.length} tokens (ALL)`);
      } else {
        const empDoc = await db
            .collection("employees")
            .doc(employeeId)
            .get();

        const t = empDoc.data()?.fcmToken;
        if (t) tokens.push(t);
        logger.info(
            `   Token for ${employeeId}: ${t ? "YES" : "NO"}`
        );
      }

      if (tokens.length === 0) {
        logger.warn("⚠️ No FCM tokens — skip");
        return;
      }

      const response = await getMessaging().sendEachForMulticast({
        tokens: tokens,
        notification: {
          title: title,
          body: message,
        },
        data: {
          type: type,
          priority: priority,
          notifId: event.params.notifId,
          title: title,
          body: message,
        },
        android: {
          priority: "high",
          notification: {
            channelId: "employee_notifications_channel",
            priority: "high",
            sound: "default",
            defaultSound: true,
            defaultVibrateTimings: true,
          },
        },
        apns: {
          payload: {
            aps: {
              alert: { title: title, body: message },
              sound: "default",
              badge: 1,
            },
          },
        },
      });

      logger.info(
          `✅ Sent: ${response.successCount} ok, ${response.failureCount} fail`
      );

      // Log failures for debugging
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          logger.warn(
              `❌ Fail [${idx}]: ${resp.error?.code} — ${resp.error?.message}`
          );
        }
      });
    } catch (error) {
      logger.error("❌ FCM send error:", error);
    }
  }
);