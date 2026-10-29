// functions/index.js
// ═══════════════════════════════════════════════════════════════
// R.A.C.O.M.A. HRIS — Cloud Functions
// ═══════════════════════════════════════════════════════════════
// Setup sa functions folder:
//   npm install
//   firebase functions:secrets:set EMAIL_PASS     (16-char app password)
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
const { getMessaging } = require("firebase-admin/messaging");

// ── Firebase Functions v2 ──
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2");
const {
  defineString,
  defineSecret,
} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");

// ── Third-party ──
const nodemailer = require("nodemailer");

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
// 🆕 EMAIL PARAMS
// ═══════════════════════════════════════════════════════════════
// Set via:
//   firebase functions:config — DEPRECATED, use env vars below
//   firebase deploy --set-env-vars EMAIL_USER=x,ADMIN_EMAIL=y
//   firebase functions:secrets:set EMAIL_PASS
// ═══════════════════════════════════════════════════════════════
const EMAIL_USER = defineString("EMAIL_USER", {
  default: "noreply@racoma.app",
  description: "Gmail address used to send notification emails",
});
const ADMIN_EMAIL = defineString("ADMIN_EMAIL", {
  default: "admin@racoma.app",
  description: "Admin email that receives demo requests",
});
const EMAIL_PASS = defineSecret("EMAIL_PASS"); // Gmail app password

function makeTransporter() {
  return nodemailer.createTransport({
    service: "gmail",
    auth: {
      user: EMAIL_USER.value(),
      pass: EMAIL_PASS.value(),
    },
  });
}

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

// Demo request email retry config
const MAX_EMAIL_RETRIES = 2;         // 1 initial + 2 retries = 3 total
const RETRY_DELAY_MS = 3000;

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

// 🆕 Convert Firestore Timestamp → ms (defensive)
function tsToMs(ts) {
  if (!ts) return 0;
  if (typeof ts.toMillis === "function") return ts.toMillis();
  return 0;
}

// 🆕 Batch update — safe for >500 docs
async function batchUpdate(docs, updateFn) {
  const CHUNK = 400;
  let totalUpdated = 0;
  for (let i = 0; i < docs.length; i += CHUNK) {
    const batch = db.batch();
    const slice = docs.slice(i, i + CHUNK);
    slice.forEach((doc) => batch.update(doc.ref, updateFn(doc)));
    await batch.commit();
    totalUpdated += slice.length;
  }
  return totalUpdated;
}

// ═══════════════════════════════════════════════════════════════
// 🆕 HELPER: Send admin demo-request email with retries
// ═══════════════════════════════════════════════════════════════
async function trySendAdminEmail(snap, attempt = 0) {
  const data = snap.data();
  const requestId = snap.id;

  const html = `
    <div style="font-family:sans-serif;max-width:600px;margin:0 auto">
      <h2 style="color:#FF6900">🎭 New Demo Access Request</h2>
      <table style="border-collapse:collapse;width:100%">
        <tr><td style="padding:6px;font-weight:bold">Name:</td><td>${data.name}</td></tr>
        <tr><td style="padding:6px;font-weight:bold">Email:</td><td>${data.email}</td></tr>
        <tr><td style="padding:6px;font-weight:bold">Company:</td><td>${data.company || "N/A"}</td></tr>
        <tr><td style="padding:6px;font-weight:bold">Phone:</td><td>${data.phone || "N/A"}</td></tr>
        <tr><td style="padding:6px;font-weight:bold">Reason:</td><td>${data.reason || "N/A"}</td></tr>
        <tr><td style="padding:6px;font-weight:bold">Request ID:</td><td><code>${requestId}</code></td></tr>
      </table>
      <hr/>
      <p>👉 Open <b>Admin Panel → Demo Requests</b> to approve or reject.</p>
    </div>
  `;

  try {
    const transporter = makeTransporter();
    await transporter.sendMail({
      from: `"R.A.C.O.M.A Demo" <${EMAIL_USER.value()}>`,
      to: ADMIN_EMAIL.value(),
      subject: `🎭 New Demo Request from ${data.name}`,
      html,
    });

    // ✅ SUCCESS → visible to admin
    await snap.ref.update({
      status: "pending",
      emailSent: true,
      emailSentAt: FieldValue.serverTimestamp(),
      emailAttempts: attempt + 1,
      emailError: null,
    });
    logger.info(`✅ Admin email sent (attempt ${attempt + 1}) → ${requestId}`);
  } catch (err) {
    logger.error(
      `❌ Email attempt ${attempt + 1} failed for ${requestId}: ${err.message}`
    );

    if (attempt < MAX_EMAIL_RETRIES) {
      await new Promise((r) => setTimeout(r, RETRY_DELAY_MS * (attempt + 1)));
      return trySendAdminEmail(snap, attempt + 1);
    }

    // ❌ ALL FAILED → stuck state
    await snap.ref.update({
      status: "email_failed",
      emailSent: false,
      emailError: err.message,
      emailAttempts: attempt + 1,
    });
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
    now.getFullYear(),
    now.getMonth(),
    now.getDate()
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
    throw new HttpsError(
      "invalid-argument",
      `Verification failed: ${err.message}`
    );
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
// (7) FCM TRIGGER — Employee Notification Push
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

    logger.info(`📤 [${event.params.notifId}] → ${employeeId}: ${title}`);

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
        logger.info(`   Token for ${employeeId}: ${t ? "YES" : "NO"}`);
      }

      if (tokens.length === 0) {
        logger.warn("⚠️ No FCM tokens — skip");
        return;
      }

      const response = await getMessaging().sendEachForMulticast({
        tokens,
        notification: { title, body: message },
        data: {
          type,
          priority,
          notifId: event.params.notifId,
          title,
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
              alert: { title, body: message },
              sound: "default",
              badge: 1,
            },
          },
        },
      });

      logger.info(
        `✅ Sent: ${response.successCount} ok, ${response.failureCount} fail`
      );

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

// ═══════════════════════════════════════════════════════════════
// (8) 🆕 DEMO REQUEST — onCreate → email admin
// ═══════════════════════════════════════════════════════════════
exports.onDemoRequestCreated = onDocumentCreated(
  {
    document: "demo_requests/{requestId}",
    secrets: [EMAIL_PASS],
  },
  async (event) => {
    if (!event.data) {
      logger.warn("No data in onCreate event");
      return;
    }
    await trySendAdminEmail(event.data, 0);
  }
);

// ═══════════════════════════════════════════════════════════════
// (9) 🆕 DEMO REQUEST — onUpdate → user retry triggers resend
// ═══════════════════════════════════════════════════════════════
exports.onDemoRequestRetry = onDocumentUpdated(
  {
    document: "demo_requests/{requestId}",
    secrets: [EMAIL_PASS],
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after;
    if (!before || !after) return;

    const afterData = after.data();
    if (
      afterData.status === "sending" &&
      before.status !== "sending" &&
      !afterData.emailSent
    ) {
      logger.info(`🔄 Retry triggered for ${after.id}`);
      await trySendAdminEmail(after, 0);
    }
  }
);

// ═══════════════════════════════════════════════════════════════
// (10) 🆕 DEMO REQUEST — onUpdate → approved sends code to user
// ═══════════════════════════════════════════════════════════════
exports.onDemoRequestApproved = onDocumentUpdated(
  {
    document: "demo_requests/{requestId}",
    secrets: [EMAIL_PASS],
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after;
    if (!before || !after) return;

    const afterData = after.data();
    if (before.status === afterData.status) return;
    if (afterData.status !== "approved") return;
    if (!afterData.accessCode) return;

    const expiry =
      afterData.expiresAt?.toDate?.()?.toLocaleString() || "N/A";

    const html = `
      <div style="font-family:sans-serif;max-width:600px;margin:0 auto">
        <h2 style="color:#16A34A">✅ Your Demo Access is Approved</h2>
        <p>Hi ${afterData.name},</p>
        <p>Your demo access has been approved. Use the code below:</p>
        <p style="font-size:36px;font-weight:900;letter-spacing:10px;
                  padding:20px;background:#fff4e6;border-radius:12px;
                  display:inline-block;color:#FF6900">${afterData.accessCode}</p>
        <p><b>Expires:</b> ${expiry}</p>
        <p>Enter this code in the app to start your demo session.</p>
      </div>
    `;

    try {
      const transporter = makeTransporter();
      await transporter.sendMail({
        from: `"R.A.C.O.M.A Demo" <${EMAIL_USER.value()}>`,
        to: afterData.email,
        subject: "✅ Your R.A.C.O.M.A Demo Access Code",
        html,
      });
      await after.ref.update({ approvalEmailSent: true });
      logger.info(`✅ Approval email sent to ${afterData.email}`);
    } catch (err) {
      logger.error("Approval email failed:", err.message);
    }
  }
);

// ═══════════════════════════════════════════════════════════════
// (11) 🆕 DEMO REQUEST — hourly cleanup
//
//   • 'sending' > 5 min      → 'email_failed'  (user sees Retry)
//   • 'email_failed' > 24h   → 'expired'       (alert clears)
//   • 'pending' > 7 days     → 'expired'       (never reviewed)
// ═══════════════════════════════════════════════════════════════
exports.cleanupStuckDemoRequests = onSchedule(
  {
    schedule: "every 1 hours",
    timeZone: "Asia/Manila",
  },
  async () => {
    const now = Date.now();
    const fiveMinAgo = now - 5 * 60 * 1000;
    const oneDayAgo = now - 24 * 60 * 60 * 1000;
    const sevenDaysAgo = now - 7 * 24 * 60 * 60 * 1000;

    logger.info("🧹 Cleanup run started");

    // 1. Stuck 'sending' > 5 min → email_failed
    try {
      const snap = await db
        .collection("demo_requests")
        .where("status", "==", "sending")
        .get();

      const stuck = snap.docs.filter((d) => {
        const ms = tsToMs(d.data().requestedAt);
        return ms === 0 || ms < fiveMinAgo;
      });

      if (stuck.length > 0) {
        const n = await batchUpdate(stuck, () => ({
          status: "email_failed",
          emailError:
            "Timed out — no email sent within 5 minutes (auto-marked)",
          timedOutAt: FieldValue.serverTimestamp(),
        }));
        logger.info(`⏱ Marked ${n} stuck 'sending' → 'email_failed'`);
      }
    } catch (e) {
      logger.error("❌ Cleanup 'sending' error:", e.message);
    }

    // 2. 'email_failed' > 24h → expired
    try {
      const snap = await db
        .collection("demo_requests")
        .where("status", "==", "email_failed")
        .get();

      const stale = snap.docs.filter((d) => {
        const ms = tsToMs(d.data().requestedAt);
        return ms > 0 && ms < oneDayAgo;
      });

      if (stale.length > 0) {
        const n = await batchUpdate(stale, () => ({
          status: "expired",
          expiredReason:
            "Email delivery failed — auto-expired after 24 hours",
          expiredAt: FieldValue.serverTimestamp(),
        }));
        logger.info(`🕒 Expired ${n} 'email_failed' requests`);
      }
    } catch (e) {
      logger.error("❌ Cleanup 'email_failed' error:", e.message);
    }

    // 3. Stale 'pending' > 7 days → expired
    try {
      const snap = await db
        .collection("demo_requests")
        .where("status", "==", "pending")
        .get();

      const stale = snap.docs.filter((d) => {
        const ms = tsToMs(d.data().requestedAt);
        return ms > 0 && ms < sevenDaysAgo;
      });

      if (stale.length > 0) {
        const n = await batchUpdate(stale, () => ({
          status: "expired",
          expiredReason: "Not reviewed by admin within 7 days",
          expiredAt: FieldValue.serverTimestamp(),
        }));
        logger.info(`📅 Expired ${n} stale 'pending' requests`);
      }
    } catch (e) {
      logger.error("❌ Cleanup 'pending' error:", e.message);
    }

    logger.info("✅ Cleanup run complete");
  }
);