// functions/index.js
// ═══════════════════════════════════════════════════════════════
// R.A.C.O.M.A. HRIS — Cloud Functions (v2 — Security Hardened)
// ═══════════════════════════════════════════════════════════════
// CHANGES vs v1:
//   🔧 FIX 1  — assertAdmin uses Firestore lookup (custom claims unset)
//   🔧 FIX 2  — WebAuthn requires employee ownership
//   🔧 FIX 3  — WebAuthn challenges expire after 5 min
//   🔧 FIX 4  — FCM resolves doc ID OR employeeId code
//   🔧 FIX 5  — HTML escaping in emails (phishing prevention)
//   🔧 FIX 6  — cascadeDeleteEmployeeData actually deletes
//   🔧 FIX 7  — onDemoRequestRetry guarded against duplicate fires
//   🔧 FIX 8  — onDemoRequestApproved fires on regenerated codes
//   🔧 FIX 9  — getAdminOverviewStats uses correct collection + PHT
//   🔧 FIX 10 — FCM chunked at 500 + stale token cleanup
//   🔧 FIX 11 — Notification sender verification (spam prevention)
//   🔧 FIX 12 — Per-function timeout & memory config
//   🔧 BONUS  — syncAdminClaims + retryDemoRequestEmail callable
// ═══════════════════════════════════════════════════════════════

const { initializeApp } = require("firebase-admin/app");
const {
  getFirestore,
  FieldValue,
  Timestamp,
} = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { getMessaging } = require("firebase-admin/messaging");

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2");
const { defineString, defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");

const nodemailer = require("nodemailer");
const {
  generateRegistrationOptions,
  verifyRegistrationResponse,
  generateAuthenticationOptions,
  verifyAuthenticationResponse,
} = require("@simplewebauthn/server");

initializeApp();
const db = getFirestore();
const auth = getAuth();

setGlobalOptions({ region: "asia-southeast1", maxInstances: 10 });

// ═══════════════════════════════════════════════════════════════
// CONFIG
// ═══════════════════════════════════════════════════════════════
const EMAIL_USER = defineString("EMAIL_USER", { default: "noreply@racoma.app" });
const ADMIN_EMAIL = defineString("ADMIN_EMAIL", { default: "admin@racoma.app" });
const EMAIL_PASS = defineSecret("EMAIL_PASS");

// 🔧 FIX 12 — externalize WebAuthn config
const RP_NAME = defineString("WEBAUTHN_RP_NAME", { default: "HRIS Biometrics" });
const RP_ID = defineString("WEBAUTHN_RP_ID", { default: "week-9-activity-53484.web.app" });
const ORIGIN = defineString("WEBAUTHN_ORIGIN", { default: "https://week-9-activity-53484.web.app" });

function makeTransporter() {
  return nodemailer.createTransport({
    service: "gmail",
    auth: { user: EMAIL_USER.value(), pass: EMAIL_PASS.value() },
  });
}

const OFFICE_LAT = 14.6114;
const OFFICE_LNG = 120.9936;
const RADIUS_LIMIT_M = 1500.0;
const LATE_THRESHOLD_HOUR = 9;
const LATE_THRESHOLD_MIN = 15;
const PHT_OFFSET_MS = 8 * 60 * 60 * 1000; // Philippines = UTC+8

const MAX_EMAIL_RETRIES = 2;
const RETRY_DELAY_MS = 3000;

const CHALLENGE_TTL_MS = 5 * 60 * 1000; // 🔧 FIX 3
const FCM_CHUNK = 500;                  // 🔧 FIX 10

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

// 🔧 FIX 5 — HTML escape user input in emails
function escapeHtml(s) {
  if (s == null) return "";
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#x27;");
}

function isValidEmail(s) {
  return typeof s === "string" && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s);
}

function tsToMs(ts) {
  if (!ts) return 0;
  if (typeof ts.toMillis === "function") return ts.toMillis();
  return 0;
}

// 🔧 FIX 9 — PHT midnight to UTC Date
function phtMidnightUtc(daysAgo = 0) {
  const now = new Date();
  const pht = new Date(now.getTime() + PHT_OFFSET_MS);
  const ms = Date.UTC(
    pht.getUTCFullYear(),
    pht.getUTCMonth(),
    pht.getUTCDate() - daysAgo
  );
  return new Date(ms - PHT_OFFSET_MS);
}

// 🔧 FIX 1 — Admin cache (1-min TTL) to avoid 1 read per call
const adminCache = new Map();
const ADMIN_CACHE_TTL = 60 * 1000;

async function isAdminUid(uid) {
  if (!uid) return false;
  const cached = adminCache.get(uid);
  if (cached && Date.now() < cached.expiresAt) return cached.isAdmin;

  try {
    const doc = await db.collection("admins").doc(uid).get();
    const data = doc.data() || {};
    const ok =
      doc.exists && data.revoked !== true && data.isActive !== false;
    adminCache.set(uid, { isAdmin: ok, expiresAt: Date.now() + ADMIN_CACHE_TTL });
    return ok;
  } catch (_) {
    return false;
  }
}

// 🔧 FIX 1 — assertAdmin: Firestore lookup, works without custom claims
async function assertAdmin(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Not signed in");
  }
  // Fast path via custom claims if syncAdminClaims has run
  const token = request.auth.token || {};
  if (token.admin === true || token.role === "admin") return;
  // Slow path via Firestore
  const ok = await isAdminUid(request.auth.uid);
  if (!ok) {
    throw new HttpsError("permission-denied", "Admin access required");
  }
}

// 🔧 FIX 2/4 — resolve employee by doc ID, employeeId code, or authUid
async function resolveEmployee(idOrCode) {
  if (!idOrCode) return null;
  try {
    const doc = await db.collection("employees").doc(String(idOrCode)).get();
    if (doc.exists) return doc;
  } catch (_) { /* invalid doc-id format */ }

  try {
    const q = await db
      .collection("employees")
      .where("employeeId", "==", String(idOrCode))
      .limit(1)
      .get();
    if (!q.empty) return q.docs[0];
  } catch (_) {}

  try {
    const q = await db
      .collection("employees")
      .where("authUid", "==", String(idOrCode))
      .limit(1)
      .get();
    if (!q.empty) return q.docs[0];
  } catch (_) {}

  return null;
}

// 🔧 FIX 2 — Verify that authUid on employee matches request.auth.uid
async function assertEmployeeOwner(request, idOrCode) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Not signed in");
  }
  const empDoc = await resolveEmployee(idOrCode);
  if (!empDoc) {
    throw new HttpsError("not-found", "Employee not found");
  }
  const data = empDoc.data() || {};
  if (data.authUid !== request.auth.uid) {
    logger.warn(
      `🚫 Owner check failed: ${request.auth.uid} ≠ ${data.authUid} for ${empDoc.id}`
    );
    throw new HttpsError("permission-denied", "Not your employee record");
  }
  return empDoc;
}

async function batchUpdate(docs, updateFn) {
  const CHUNK = 400;
  let total = 0;
  for (let i = 0; i < docs.length; i += CHUNK) {
    const batch = db.batch();
    const slice = docs.slice(i, i + CHUNK);
    slice.forEach((d) => batch.update(d.ref, updateFn(d)));
    await batch.commit();
    total += slice.length;
  }
  return total;
}

// 🔧 FIX 3 — Load + expire webauthn challenge
async function loadAndCheckChallenge(employeeDocId, expectedType) {
  const ref = db.collection("webauthnChallenges").doc(employeeDocId);
  const doc = await ref.get();
  if (!doc.exists) {
    throw new HttpsError("failed-precondition", "No pending challenge");
  }
  const data = doc.data();
  const age = Date.now() - (data.createdAt?.toMillis?.() ?? 0);
  if (age > CHALLENGE_TTL_MS) {
    await ref.delete();
    throw new HttpsError("failed-precondition", "Challenge expired — try again");
  }
  if (expectedType && data.type !== expectedType) {
    throw new HttpsError("failed-precondition", "Challenge type mismatch");
  }
  return { ref, challenge: data.challenge };
}

// 🔧 FIX 10 — Chunked FCM send + stale token cleanup
async function sendFcmInChunks(tokens, payload) {
  const allResponses = [];
  for (let i = 0; i < tokens.length; i += FCM_CHUNK) {
    const chunk = tokens.slice(i, i + FCM_CHUNK);
    try {
      const resp = await getMessaging().sendEachForMulticast({ tokens: chunk, ...payload });
      allResponses.push({ offset: i, chunk, resp });
    } catch (e) {
      logger.error(`FCM chunk ${i / FCM_CHUNK} failed:`, e.message);
    }
  }
  return allResponses;
}

async function cleanupStaleToken(token) {
  try {
    const q = await db
      .collection("employees")
      .where("fcmToken", "==", token)
      .get();
    for (const d of q.docs) {
      await d.ref.update({
        fcmToken: null,
        fcmTokenInvalidatedAt: FieldValue.serverTimestamp(),
      });
    }
    if (q.size > 0) logger.info(`🗑️ Cleaned ${q.size} stale token(s)`);
  } catch (_) {}
}

// ═══════════════════════════════════════════════════════════════
// HELPER — Send admin demo-request email with retries
// ═══════════════════════════════════════════════════════════════
async function trySendAdminEmail(snap, attempt = 0) {
  const data = snap.data() || {};
  const requestId = snap.id;

  // 🔧 FIX 5 — escape all interpolated fields
  const html = `
    <div style="font-family:sans-serif;max-width:600px;margin:0 auto">
      <h2 style="color:#FF6900">🎭 New Demo Access Request</h2>
      <table style="border-collapse:collapse;width:100%">
        <tr><td style="padding:6px;font-weight:bold">Name:</td><td>${escapeHtml(data.name)}</td></tr>
        <tr><td style="padding:6px;font-weight:bold">Email:</td><td>${escapeHtml(data.email)}</td></tr>
        <tr><td style="padding:6px;font-weight:bold">Company:</td><td>${escapeHtml(data.company || "N/A")}</td></tr>
        <tr><td style="padding:6px;font-weight:bold">Phone:</td><td>${escapeHtml(data.phone || "N/A")}</td></tr>
        <tr><td style="padding:6px;font-weight:bold">Reason:</td><td>${escapeHtml(data.reason || "N/A")}</td></tr>
        <tr><td style="padding:6px;font-weight:bold">Request ID:</td><td><code>${escapeHtml(requestId)}</code></td></tr>
      </table>
      <hr/>
      <p>👉 Open <b>Admin Panel → Demo Requests</b> to approve or reject.</p>
    </div>`;

  try {
    const transporter = makeTransporter();
    await transporter.sendMail({
      from: `"R.A.C.O.M.A Demo" <${EMAIL_USER.value()}>`,
      to: ADMIN_EMAIL.value(),
      subject: `🎭 New Demo Request from ${escapeHtml(data.name || "?")}`,
      html,
    });

    await snap.ref.update({
      status: "pending",
      emailSent: true,
      emailSentAt: FieldValue.serverTimestamp(),
      emailAttempts: attempt + 1,
      emailError: null,
    });
    logger.info(`✅ Admin email sent (attempt ${attempt + 1}) → ${requestId}`);
  } catch (err) {
    logger.error(`❌ Email attempt ${attempt + 1} failed for ${requestId}: ${err.message}`);

    if (attempt < MAX_EMAIL_RETRIES) {
      await new Promise((r) => setTimeout(r, RETRY_DELAY_MS * (attempt + 1)));
      return trySendAdminEmail(snap, attempt + 1);
    }

    try {
      await snap.ref.update({
        status: "email_failed",
        emailSent: false,
        emailError: String(err.message || "unknown").slice(0, 500),
        emailAttempts: attempt + 1,
      });
    } catch (_) { /* doc may have been deleted */ }
  }
}

// ═══════════════════════════════════════════════════════════════
// (0) BONUS — syncAdminClaims (fast-path for assertAdmin)
// ═══════════════════════════════════════════════════════════════
exports.syncAdminClaims = onDocumentWritten(
  { document: "admins/{uid}", region: "asia-southeast1" },
  async (event) => {
    const uid = event.params.uid;
    const after = event.data?.after?.data();
    try {
      const active =
        after && after.revoked !== true && after.isActive !== false;
      await auth.setCustomUserClaims(uid, active
        ? { role: "admin", admin: true }
        : { role: null, admin: null });
      adminCache.delete(uid);
      logger.info(`${active ? "🔐" : "🔓"} Claims synced for ${uid}`);
    } catch (e) {
      logger.error(`syncAdminClaims failed for ${uid}:`, e.message);
    }
  }
);

// ═══════════════════════════════════════════════════════════════
// (1) cascadeDeleteEmployeeData  🔧 FIX 6
// ═══════════════════════════════════════════════════════════════
exports.cascadeDeleteEmployeeData = onCall(
  { timeoutSeconds: 300, memory: "512MiB" },
  async (request) => {
    await assertAdmin(request);
    const { employeeId } = request.data || {};
    if (!employeeId) {
      throw new HttpsError("invalid-argument", "Missing employeeId");
    }

    const empDoc = await db.collection("employees").doc(employeeId).get();
    if (!empDoc.exists) {
      throw new HttpsError("not-found", "Employee not found");
    }
    const authUid = empDoc.data().authUid || null;

    logger.info(`cascadeDeleteEmployeeData: ${employeeId} (authUid=${authUid})`);
    const results = {};

    const targets = [
      { name: "attendance_logs",        fields: ["employee_id", "employeeId", "authUid"] },
      { name: "leave_applications",     fields: ["employeeId", "employee_id", "employeeAuthUid"] },
      { name: "user_locations",         fields: ["employeeId", "employee_id"] },
      { name: "user locations",         fields: ["employeeId", "employee_id"] },
      { name: "employee_notifications", fields: ["employeeId"] },
      { name: "clock_ins",              fields: ["employee_id"] },
      { name: "clock_outs",             fields: ["employee_id"] },
      { name: "pdf_exports",            fields: ["employee_id"] },
      { name: "tasks",                  fields: ["employeeId"] },
      { name: "client_meeting_assignments", fields: ["employee_id", "employeeId"] },
    ];

    for (const t of targets) {
      let total = 0;
      try {
        const values = [employeeId, authUid].filter(Boolean);
        for (const field of t.fields) {
          for (const value of values) {
            try {
              const snap = await db.collection(t.name).where(field, "==", value).get();
              if (snap.empty) continue;
              const CHUNK = 400;
              for (let i = 0; i < snap.docs.length; i += CHUNK) {
                const batch = db.batch();
                snap.docs.slice(i, i + CHUNK).forEach((d) => batch.delete(d.ref));
                await batch.commit();
              }
              total += snap.size;
            } catch (_) { /* collection missing or field mismatch */ }
          }
        }
        results[t.name] = total;
      } catch (e) {
        results[t.name] = `error: ${e.message}`;
      }
    }

    // Presence (doc-id based)
    try {
      const p = await db.collection("employee_presence").doc(employeeId).get();
      if (p.exists) { await p.ref.delete(); results.employee_presence = 1; }
      else results.employee_presence = 0;
    } catch (e) { results.employee_presence = `error: ${e.message}`; }

    // WebAuthn credentials subcollection
    try {
      const creds = await db.collection("employees").doc(employeeId)
        .collection("webauthnCredentials").get();
      for (const c of creds.docs) await c.ref.delete();
      results.webauthnCredentials = creds.size;
    } catch (e) { results.webauthnCredentials = `error: ${e.message}`; }

    await empDoc.ref.delete();
    results.employee = 1;

    logger.info(`✅ cascadeDeleteEmployeeData complete`, results);
    return { deleted: true, employeeId, results };
  }
);

// ═══════════════════════════════════════════════════════════════
// (2) getAdminOverviewStats  🔧 FIX 9
// ═══════════════════════════════════════════════════════════════
exports.getAdminOverviewStats = onCall(
  { timeoutSeconds: 120 },
  async (request) => {
    await assertAdmin(request);

    const startOfTodayUtc = phtMidnightUtc(0);
    const startOfYesterdayUtc = phtMidnightUtc(1);

    const empSnap = await db.collection("employees").get();
    const totalStaff = empSnap.size;

    const todayLogsSnap = await db.collection("attendance_logs")
      .where("timestamp", ">=", Timestamp.fromDate(startOfTodayUtc))
      .get();

    const yesterdayLogsSnap = await db.collection("attendance_logs")
      .where("timestamp", ">=", Timestamp.fromDate(startOfYesterdayUtc))
      .where("timestamp", "<", Timestamp.fromDate(startOfTodayUtc))
      .get();

    let clockedIn = 0;
    let lateArrivals = 0;
    let totalLateMinutes = 0;
    const chart = new Array(8).fill(0);

    todayLogsSnap.forEach((doc) => {
      const d = doc.data();
      const type = (d.type || "").toUpperCase();
      if (type !== "IN" && type !== "LOGIN") return;
      if (!d.timestamp?.toDate) return;

      clockedIn++;
      const dtUtc = d.timestamp.toDate();
      const dtPht = new Date(dtUtc.getTime() + PHT_OFFSET_MS);
      const phtHour = dtPht.getUTCHours();
      const phtMin = dtPht.getUTCMinutes();

      chart[Math.min(7, Math.floor(phtHour / 3))]++;

      const isLate =
        phtHour > LATE_THRESHOLD_HOUR ||
        (phtHour === LATE_THRESHOLD_HOUR && phtMin > LATE_THRESHOLD_MIN);

      if (isLate) {
        lateArrivals++;
        totalLateMinutes += (phtHour - LATE_THRESHOLD_HOUR) * 60 + phtMin - LATE_THRESHOLD_MIN;
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

    // 🔧 FIX 9 — use user locations/user_locations, not /locations
    const latestByEmp = {};
    function ingest(snap) {
      if (!snap || typeof snap.forEach !== "function") return;
      snap.forEach((doc) => {
        const d = doc.data();
        const id = (d.employee_id || d.employeeId || "").toString();
        if (!id) return;
        const ts = d.timestamp || d.created_at || d.updated_at;
        const ms = ts?.toMillis?.() ?? 0;
        const prev = latestByEmp[id];
        if (!prev || ms > prev.ms) {
          latestByEmp[id] = {
            lat: Number(d.latitude ?? d.lat ?? 0),
            lng: Number(d.longitude ?? d.lng ?? 0),
            ms,
          };
        }
      });
    }

    try { ingest(await db.collection("user_locations").get()); } catch (_) {}
    try { ingest(await db.collection("user locations").get()); } catch (_) {}

    let outRange = 0;
    Object.values(latestByEmp).forEach((loc) => {
      if (loc.lat === 0 && loc.lng === 0) return;
      if (haversine(loc.lat, loc.lng, OFFICE_LAT, OFFICE_LNG) > RADIUS_LIMIT_M) {
        outRange++;
      }
    });

    logger.info(`getAdminOverviewStats by ${request.auth.uid}`, {
      totalStaff, clockedIn, lateArrivals, outRange,
    });

    return {
      totalStaff,
      clockedIn,
      lateArrivals,
      avgLateMinutes,
      outRange,
      yesterdayActive,
      chart,
      serverTime: new Date().toISOString(),
    };
  }
);

// ═══════════════════════════════════════════════════════════════
// (3) WEBAUTHN — REGISTRATION OPTIONS  🔧 FIX 2
// ═══════════════════════════════════════════════════════════════
exports.webauthnGenerateRegistrationOptions = onCall(async (request) => {
  const { employeeId } = request.data || {};
  if (!employeeId) {
    throw new HttpsError("invalid-argument", "Missing employeeId");
  }

  const empDoc = await assertEmployeeOwner(request, employeeId);
  const employee = empDoc.data();
  const docId = empDoc.id;

  const credsSnap = await empDoc.ref.collection("webauthnCredentials").get();
  const excludeCredentials = credsSnap.docs.map((d) => ({
    id: d.id,
    transports: d.data().transports || [],
  }));

  const options = await generateRegistrationOptions({
    rpName: RP_NAME.value(),
    rpID: RP_ID.value(),
    userID: new TextEncoder().encode(docId),
    userName: employee.email || docId,
    userDisplayName: employee.fullName || employee.email || docId,
    attestationType: "none",
    excludeCredentials,
    authenticatorSelection: {
      authenticatorAttachment: "platform",
      userVerification: "required",
      residentKey: "preferred",
    },
  });

  await db.collection("webauthnChallenges").doc(docId).set({
    challenge: options.challenge,
    type: "registration",
    createdAt: FieldValue.serverTimestamp(),
    authUid: request.auth.uid,
  });

  return options;
});

// ═══════════════════════════════════════════════════════════════
// (4) WEBAUTHN — VERIFY REGISTRATION  🔧 FIX 2/3
// ═══════════════════════════════════════════════════════════════
exports.webauthnVerifyRegistration = onCall(async (request) => {
  const { employeeId, credential: registrationResponse, deviceLabel } = request.data || {};
  if (!employeeId || !registrationResponse) {
    throw new HttpsError("invalid-argument", "Missing employeeId or credential");
  }

  const empDoc = await assertEmployeeOwner(request, employeeId);
  const docId = empDoc.id;

  const { ref: challengeRef, challenge } = await loadAndCheckChallenge(docId, "registration");

  let verification;
  try {
    verification = await verifyRegistrationResponse({
      response: registrationResponse,
      expectedChallenge: challenge,
      expectedOrigin: ORIGIN.value(),
      expectedRPID: RP_ID.value(),
    });
  } catch (err) {
    await challengeRef.delete().catch(() => {});
    throw new HttpsError("invalid-argument", `Verification failed: ${err.message}`);
  }

  if (!verification.verified || !verification.registrationInfo) {
    await challengeRef.delete().catch(() => {});
    throw new HttpsError("permission-denied", "Registration could not be verified");
  }

  const { credential } = verification.registrationInfo;
  await empDoc.ref.collection("webauthnCredentials").doc(credential.id).set({
    publicKey: Buffer.from(credential.publicKey).toString("base64"),
    counter: credential.counter,
    transports: credential.transports || [],
    createdAt: FieldValue.serverTimestamp(),
    deviceLabel: (deviceLabel || "Unknown device").toString().slice(0, 80),
  });

  await challengeRef.delete();
  logger.info(`🔐 Fingerprint enrolled for ${docId}`);
  return { verified: true };
});

// ═══════════════════════════════════════════════════════════════
// (5) WEBAUTHN — AUTH OPTIONS  🔧 FIX 2
// ═══════════════════════════════════════════════════════════════
exports.webauthnGenerateAuthOptions = onCall(async (request) => {
  const { employeeId } = request.data || {};
  if (!employeeId) {
    throw new HttpsError("invalid-argument", "Missing employeeId");
  }

  const empDoc = await assertEmployeeOwner(request, employeeId);
  const docId = empDoc.id;

  const credsSnap = await empDoc.ref.collection("webauthnCredentials").get();
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
    rpID: RP_ID.value(),
    allowCredentials,
    userVerification: "required",
  });

  await db.collection("webauthnChallenges").doc(docId).set({
    challenge: options.challenge,
    type: "authentication",
    createdAt: FieldValue.serverTimestamp(),
    authUid: request.auth.uid,
  });

  return options;
});

// ═══════════════════════════════════════════════════════════════
// (6) WEBAUTHN — VERIFY AUTH  🔧 FIX 2/3
// ═══════════════════════════════════════════════════════════════
exports.webauthnVerifyAuth = onCall(async (request) => {
  const { employeeId, credential: authResponse } = request.data || {};
  if (!employeeId || !authResponse) {
    throw new HttpsError("invalid-argument", "Missing employeeId or credential");
  }

  const empDoc = await assertEmployeeOwner(request, employeeId);
  const docId = empDoc.id;

  const { ref: challengeRef, challenge } = await loadAndCheckChallenge(docId, "authentication");

  const credRef = empDoc.ref.collection("webauthnCredentials").doc(authResponse.id);
  const credDoc = await credRef.get();
  if (!credDoc.exists) {
    await challengeRef.delete().catch(() => {});
    throw new HttpsError("not-found", "Credential not recognized");
  }
  const stored = credDoc.data();

  let verification;
  try {
    verification = await verifyAuthenticationResponse({
      response: authResponse,
      expectedChallenge: challenge,
      expectedOrigin: ORIGIN.value(),
      expectedRPID: RP_ID.value(),
      credential: {
        id: authResponse.id,
        publicKey: Buffer.from(stored.publicKey, "base64"),
        counter: stored.counter,
        transports: stored.transports || [],
      },
    });
  } catch (err) {
    await challengeRef.delete().catch(() => {});
    throw new HttpsError("invalid-argument", `Auth verification failed: ${err.message}`);
  }

  if (!verification.verified) {
    await challengeRef.delete().catch(() => {});
    throw new HttpsError("permission-denied", "Fingerprint did not match");
  }

  await credRef.update({ counter: verification.authenticationInfo.newCounter });
  await challengeRef.delete();
  return { verified: true };
});

// ═══════════════════════════════════════════════════════════════
// (7) FCM TRIGGER  🔧 FIX 4/10/11/12
// ═══════════════════════════════════════════════════════════════
exports.sendEmployeeNotification = onDocumentCreated(
  {
    document: "employee_notifications/{notifId}",
    region: "asia-southeast1",
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data() || {};
    const employeeId = (data.employeeId || "").toString();
    const title = (data.title || "Notification").toString().slice(0, 200);
    const message = (data.message || "").toString().slice(0, 2000);
    const type = (data.type || "general").toString();
    const priority = (data.priority || "normal").toString();

    // 🔧 FIX 11 — verify sender unless it's a system/function write
    const callerUid = event.authType === "user" ? event.authId : null;
    if (callerUid) {
      const admin = await isAdminUid(callerUid);
      if (!admin) {
        if (employeeId === "ALL") {
          logger.warn(`🚫 Blocked non-admin broadcast from ${callerUid}`);
          await snap.ref.update({ deliveryStatus: "blocked", deliveryError: "Sender not admin" });
          return;
        }
        const empDoc = await resolveEmployee(employeeId);
        if (!empDoc || empDoc.data().authUid !== callerUid) {
          logger.warn(`🚫 Blocked spoofed notification: ${callerUid} → ${employeeId}`);
          await snap.ref.update({ deliveryStatus: "blocked", deliveryError: "Sender mismatch" });
          return;
        }
      }
    }

    logger.info(`📤 [${event.params.notifId}] type=${type} to=${employeeId.slice(0, 12)}`);

    try {
      const tokens = [];
      if (employeeId === "ALL") {
        const empSnap = await db.collection("employees")
          .where("fcmToken", "!=", null).get();
        empSnap.forEach((doc) => {
          const t = doc.data().fcmToken;
          if (typeof t === "string" && t.length > 0) tokens.push(t);
        });
        logger.info(`   Broadcast: ${tokens.length} tokens found`);
      } else {
        const empDoc = await resolveEmployee(employeeId); // 🔧 FIX 4
        const t = empDoc?.data()?.fcmToken;
        if (typeof t === "string" && t.length > 0) tokens.push(t);
        logger.info(`   Target ${employeeId}: token ${t ? "YES" : "NO"}`);
      }

      if (tokens.length === 0) {
        await snap.ref.update({ deliveryStatus: "no_tokens" }).catch(() => {});
        return;
      }

      const payload = {
        notification: { title, body: message },
        data: {
          type, priority,
          notifId: event.params.notifId,
          title, body: message,
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
            aps: { alert: { title, body: message }, sound: "default", badge: 1 },
          },
        },
      };

      const results = await sendFcmInChunks(tokens, payload); // 🔧 FIX 10

      let totalOk = 0, totalFail = 0;
      for (const r of results) {
        totalOk += r.resp.successCount;
        totalFail += r.resp.failureCount;
        r.resp.responses.forEach((resp, idx) => {
          if (resp.success) return;
          const code = resp.error?.code || "";
          logger.warn(`❌ Fail [${r.offset + idx}]: ${code}`);
          if (
            code === "messaging/registration-token-not-registered" ||
            code === "messaging/invalid-registration-token"
          ) {
            cleanupStaleToken(r.chunk[idx]).catch(() => {});
          }
        });
      }

      await snap.ref.update({
        deliveryStatus: totalFail === 0 ? "delivered" : "partial",
        deliveredCount: totalOk,
        failedCount: totalFail,
        deliveredAt: FieldValue.serverTimestamp(),
      }).catch(() => {});

      logger.info(`✅ Sent: ${totalOk} ok, ${totalFail} fail`);
    } catch (error) {
      logger.error("❌ FCM send error:", error);
      await snap.ref.update({ deliveryStatus: "error", deliveryError: String(error.message).slice(0, 300) }).catch(() => {});
    }
  }
);

// ═══════════════════════════════════════════════════════════════
// (8) DEMO REQUEST — onCreate → email admin  🔧 FIX 12
// ═══════════════════════════════════════════════════════════════
exports.onDemoRequestCreated = onDocumentCreated(
  {
    document: "demo_requests/{requestId}",
    secrets: [EMAIL_PASS],
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async (event) => {
    if (!event.data) return;
    // Skip if there's nothing to notify about (e.g. test writes)
    const data = event.data.data() || {};
    if (!data.email || !isValidEmail(data.email)) {
      logger.warn(`⚠️ Skipping email — invalid recipient for ${event.params.requestId}`);
      return;
    }
    await trySendAdminEmail(event.data, 0);
  }
);

// ═══════════════════════════════════════════════════════════════
// (9) DEMO REQUEST — retry trigger  🔧 FIX 7
// ═══════════════════════════════════════════════════════════════
exports.onDemoRequestRetry = onDocumentUpdated(
  {
    document: "demo_requests/{requestId}",
    secrets: [EMAIL_PASS],
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after;
    if (!before || !after) return;
    const afterData = after.data() || {};

    // Only fire when explicitly requested by client (status → sending)
    if (afterData.status !== "sending") return;
    if (before.status === "sending") return;
    if (afterData.emailSent === true) return;
    // Only from failed or pending states — prevents re-entry loop
    if (before.status !== "email_failed" && before.status !== "pending") return;

    logger.info(`🔄 Retry triggered for ${after.id}`);
    await trySendAdminEmail(after, 0);
  }
);

// ═══════════════════════════════════════════════════════════════
// (9b) BONUS — Callable retry (admin-triggered, bypasses client)
// ═══════════════════════════════════════════════════════════════
exports.retryDemoRequestEmail = onCall(
  { secrets: [EMAIL_PASS], timeoutSeconds: 120, memory: "256MiB" },
  async (request) => {
    await assertAdmin(request);
    const { requestId } = request.data || {};
    if (!requestId) throw new HttpsError("invalid-argument", "Missing requestId");

    const ref = db.collection("demo_requests").doc(requestId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Request not found");

    const data = snap.data() || {};
    if (data.emailSent === true) {
      return { sent: false, reason: "already_sent" };
    }

    await trySendAdminEmail(snap, 0);

    const updated = await ref.get();
    return { sent: updated.data()?.emailSent === true };
  }
);

// ═══════════════════════════════════════════════════════════════
// (10) DEMO REQUEST APPROVED → send access code  🔧 FIX 8
// ═══════════════════════════════════════════════════════════════
exports.onDemoRequestApproved = onDocumentUpdated(
  {
    document: "demo_requests/{requestId}",
    secrets: [EMAIL_PASS],
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after;
    if (!before || !after) return;
    const afterData = after.data() || {};

    const statusChanged = before.status !== afterData.status;
    const codeChanged = before.accessCode !== afterData.accessCode;

    // 🔧 FIX 8 — fire on status change OR code regeneration
    if (!statusChanged && !codeChanged) return;
    if (afterData.status !== "approved") return;
    if (!afterData.accessCode) return;

    // Debounce duplicate sends (e.g. admin clicks twice quickly)
    const lastSent = afterData.approvalEmailSentAt?.toMillis?.() ?? 0;
    if (Date.now() - lastSent < 10_000) {
      logger.info(`⏭️ Skipping duplicate approval email (recent send)`);
      return;
    }

    if (!isValidEmail(afterData.email)) {
      logger.warn(`⚠️ Invalid recipient: ${afterData.email}`);
      return;
    }

    const expiry = afterData.expiresAt?.toDate?.()?.toLocaleString() || "N/A";

    // 🔧 FIX 5 — escape user fields
    const html = `
      <div style="font-family:sans-serif;max-width:600px;margin:0 auto">
        <h2 style="color:#16A34A">✅ Your Demo Access is Approved</h2>
        <p>Hi ${escapeHtml(afterData.name)},</p>
        <p>Your demo access has been approved. Use the code below:</p>
        <p style="font-size:36px;font-weight:900;letter-spacing:10px;
                  padding:20px;background:#fff4e6;border-radius:12px;
                  display:inline-block;color:#FF6900">${escapeHtml(afterData.accessCode)}</p>
        <p><b>Expires:</b> ${escapeHtml(expiry)}</p>
        <p>Enter this code in the app to start your demo session.</p>
      </div>`;

    try {
      const transporter = makeTransporter();
      await transporter.sendMail({
        from: `"R.A.C.O.M.A Demo" <${EMAIL_USER.value()}>`,
        to: afterData.email,
        subject: "✅ Your R.A.C.O.M.A Demo Access Code",
        html,
      });
      await after.ref.update({
        approvalEmailSent: true,
        approvalEmailSentAt: FieldValue.serverTimestamp(),
      });
      logger.info(`✅ Approval email sent to ${afterData.email}`);
    } catch (err) {
      logger.error("Approval email failed:", err.message);
      await after.ref.update({
        approvalEmailError: String(err.message).slice(0, 300),
      }).catch(() => {});
    }
  }
);

// ═══════════════════════════════════════════════════════════════
// (11) DEMO REQUEST — hourly cleanup  🔧 FIX 12
// ═══════════════════════════════════════════════════════════════
exports.cleanupStuckDemoRequests = onSchedule(
  {
    schedule: "every 1 hours",
    timeZone: "Asia/Manila",
    timeoutSeconds: 300,
    memory: "256MiB",
    maxInstances: 1,
  },
  async () => {
    const now = Date.now();
    const fiveMinAgo = now - 5 * 60 * 1000;
    const oneDayAgo = now - 24 * 60 * 60 * 1000;
    const sevenDaysAgo = now - 7 * 24 * 60 * 60 * 1000;
    const ninetyDaysAgo = now - 90 * 24 * 60 * 60 * 1000;

    logger.info("🧹 Cleanup run started");

    async function runPhase(label, statuses, cutoffMs, updateFn) {
      try {
        const snap = await db.collection("demo_requests")
          .where("status", "in", statuses)
          .limit(500)
          .get();
        if (snap.empty) return;
        const stale = snap.docs.filter((d) => {
          const ms = tsToMs(d.data().requestedAt);
          return ms > 0 && ms < cutoffMs;
        });
        if (!stale.length) return;
        const n = await batchUpdate(stale, updateFn);
        logger.info(`✅ ${label}: ${n} updated`);
      } catch (e) {
        logger.error(`❌ ${label} failed:`, e.message);
      }
    }

    await runPhase("sending→email_failed", ["sending"], fiveMinAgo, () => ({
      status: "email_failed",
      emailError: "Timed out — no email within 5 minutes (auto-marked)",
      timedOutAt: FieldValue.serverTimestamp(),
    }));

    await runPhase("email_failed→expired", ["email_failed"], oneDayAgo, () => ({
      status: "expired",
      expiredReason: "Email delivery failed — auto-expired after 24 hours",
      expiredAt: FieldValue.serverTimestamp(),
    }));

    await runPhase("pending→expired", ["pending"], sevenDaysAgo, () => ({
      status: "expired",
      expiredReason: "Not reviewed by admin within 7 days",
      expiredAt: FieldValue.serverTimestamp(),
    }));

    // Delete very old approved/expired docs (data retention)
    try {
      const old = await db.collection("demo_requests")
        .where("status", "in", ["approved", "expired"])
        .where("requestedAt", "<", Timestamp.fromDate(new Date(ninetyDaysAgo)))
        .limit(500)
        .get();
      if (!old.empty) {
        const batch = db.batch();
        old.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        logger.info(`🗑️ Purged ${old.size} old demo requests`);
      }
    } catch (e) {
      logger.error("❌ Purge old failed:", e.message);
    }

    logger.info("✅ Cleanup run complete");
  }
);