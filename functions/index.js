/**
 * ═══════════════════════════════════════════════════════════════
 * WEBAUTHN CLOUD FUNCTIONS — IDAGDAG ITO SA DULO NG EXISTING index.js MO
 * (huwag galawin ang existing cascadeDeleteEmployeeData mo sa taas)
 * ═══════════════════════════════════════════════════════════════
 *
 * SETUP (sa functions folder, terminal):
 *   cd functions
 *   npm install @simplewebauthn/server
 *
 * Ito ay tugma sa modular admin SDK style mo (firebase-admin/app,
 * firebase-admin/firestore) — GINAGAMIT NIYA ANG `db` NA NASA TAAS
 * NA NG FILE MO. Huwag ulitin ang initializeApp() o getFirestore().
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");
const {
  generateRegistrationOptions,
  verifyRegistrationResponse,
  generateAuthenticationOptions,
  verifyAuthenticationResponse,
} = require("@simplewebauthn/server");

// ⚠️ PALITAN ITO KAPAG NAG-DEPLOY KA NA SA TALAGANG DOMAIN MO
const RP_NAME = "HRIS Biometrics";
const RP_ID = "week-9-activity-53484.web.app"; // walang https://, walang trailing slash
const ORIGIN = "https://week-9-activity-53484.web.app";

// ─────────────────────────────────────────────────────────────
// 1. GENERATE REGISTRATION OPTIONS (unang beses mag-e-enroll)
// ─────────────────────────────────────────────────────────────
exports.webauthnGenerateRegistrationOptions = onCall(async (request) => {
  const employeeId = request.data.employeeId;
  if (!employeeId) throw new HttpsError("invalid-argument", "Missing employeeId");

  const empDoc = await db.collection("employees").doc(employeeId).get();
  if (!empDoc.exists) throw new HttpsError("not-found", "Employee not found");
  const employee = empDoc.data();

  // Kunin ang existing credentials niya (kung meron, para hindi siya
  // makapag-enroll ulit ng parehong device)
  const credsSnap = await db
    .collection("employees").doc(employeeId)
    .collection("webauthnCredentials").get();
  const existingCredentials = credsSnap.docs.map((d) => ({
    id: d.id,
    transports: d.data().transports || [],
  }));

  const options = await generateRegistrationOptions({
    rpName: RP_NAME,
    rpID: RP_ID,
    userID: Buffer.from(employeeId, "utf-8"),
    userName: employee.email || employeeId,
    userDisplayName: employee.fullName || employee.email || employeeId,
    attestationType: "none",
    excludeCredentials: existingCredentials,
    authenticatorSelection: {
      authenticatorAttachment: "platform", // platform = built-in fingerprint/FaceID, hindi USB key
      userVerification: "required",
      residentKey: "preferred",
    },
  });

  // I-save ang challenge pansamantala para ma-verify natin sa susunod na call
  await db.collection("webauthnChallenges").doc(employeeId).set({
    challenge: options.challenge,
    type: "registration",
    createdAt: FieldValue.serverTimestamp(),
  });

  return options;
});

// ─────────────────────────────────────────────────────────────
// 2. VERIFY REGISTRATION RESPONSE (matapos mag-scan ang employee)
// ─────────────────────────────────────────────────────────────
exports.webauthnVerifyRegistration = onCall(async (request) => {
  const { employeeId, credential } = request.data;
  if (!employeeId || !credential) {
    throw new HttpsError("invalid-argument", "Missing employeeId or credential");
  }

  const challengeDoc = await db.collection("webauthnChallenges").doc(employeeId).get();
  if (!challengeDoc.exists) throw new HttpsError("failed-precondition", "No pending challenge");
  const { challenge } = challengeDoc.data();

  let verification;
  try {
    verification = await verifyRegistrationResponse({
      response: credential,
      expectedChallenge: challenge,
      expectedOrigin: ORIGIN,
      expectedRPID: RP_ID,
    });
  } catch (err) {
    throw new HttpsError("invalid-argument", `Verification failed: ${err.message}`);
  }

  if (!verification.verified || !verification.registrationInfo) {
    throw new HttpsError("permission-denied", "Registration could not be verified");
  }

  const { credentialID, credentialPublicKey, counter } = verification.registrationInfo;

  // I-save ang bagong credential (public key lang, hindi private key)
  await db
    .collection("employees").doc(employeeId)
    .collection("webauthnCredentials").doc(credentialID)
    .set({
      publicKey: Buffer.from(credentialPublicKey).toString("base64"),
      counter,
      transports: credential.response.transports || [],
      createdAt: FieldValue.serverTimestamp(),
      deviceLabel: request.data.deviceLabel || "Unknown device",
    });

  await db.collection("webauthnChallenges").doc(employeeId).delete();

  return { verified: true };
});

// ─────────────────────────────────────────────────────────────
// 3. GENERATE AUTHENTICATION OPTIONS (tuwing mag-c-clock in)
// ─────────────────────────────────────────────────────────────
exports.webauthnGenerateAuthOptions = onCall(async (request) => {
  const employeeId = request.data.employeeId;
  if (!employeeId) throw new HttpsError("invalid-argument", "Missing employeeId");

  const credsSnap = await db
    .collection("employees").doc(employeeId)
    .collection("webauthnCredentials").get();

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

// ─────────────────────────────────────────────────────────────
// 4. VERIFY AUTHENTICATION RESPONSE (ito ang nagbibigay ng "success")
// ─────────────────────────────────────────────────────────────
exports.webauthnVerifyAuth = onCall(async (request) => {
  const { employeeId, credential } = request.data;
  if (!employeeId || !credential) {
    throw new HttpsError("invalid-argument", "Missing employeeId or credential");
  }

  const challengeDoc = await db.collection("webauthnChallenges").doc(employeeId).get();
  if (!challengeDoc.exists) throw new HttpsError("failed-precondition", "No pending challenge");
  const { challenge } = challengeDoc.data();

  const credDocRef = db
    .collection("employees").doc(employeeId)
    .collection("webauthnCredentials").doc(credential.id);
  const credDoc = await credDocRef.get();
  if (!credDoc.exists) throw new HttpsError("not-found", "Credential not recognized");
  const storedCred = credDoc.data();

  let verification;
  try {
    verification = await verifyAuthenticationResponse({
      response: credential,
      expectedChallenge: challenge,
      expectedOrigin: ORIGIN,
      expectedRPID: RP_ID,
      authenticator: {
        credentialID: credential.id,
        credentialPublicKey: Buffer.from(storedCred.publicKey, "base64"),
        counter: storedCred.counter,
      },
    });
  } catch (err) {
    throw new HttpsError("invalid-argument", `Auth verification failed: ${err.message}`);
  }

  if (!verification.verified) {
    throw new HttpsError("permission-denied", "Fingerprint did not match");
  }

  // I-update ang counter (anti-replay protection)
  await credDocRef.update({ counter: verification.authenticationInfo.newCounter });
  await db.collection("webauthnChallenges").doc(employeeId).delete();

  return { verified: true };
});