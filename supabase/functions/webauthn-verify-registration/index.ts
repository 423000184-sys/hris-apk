// supabase/functions/webauthn-verify-registration/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { verifyRegistrationResponse } from "jsr:@simplewebauthn/server@13";
import {
  firestoreGet,
  firestoreSet,
  firestoreDelete,
  fromFsDoc,
  toFsValue,
} from "../_shared/firebase_rest.ts";

const RP_ID = "week-9-activity-53484.web.app";
const ORIGIN = "https://week-9-activity-53484.web.app";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { employeeId, credential, deviceLabel } = await req.json();
    if (!employeeId || !credential) {
      return new Response(
        JSON.stringify({ error: "Missing required fields" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // ✅ Get challenge via REST
    const challengeDoc = await firestoreGet(
      `webauthnChallenges/${employeeId}`
    );
    if (!challengeDoc) {
      return new Response(JSON.stringify({ error: "No challenge found" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const challengeParsed = fromFsDoc(challengeDoc);
    const expectedChallenge = challengeParsed?.data.challenge;

    const verification = await verifyRegistrationResponse({
      response: credential,
      expectedChallenge,
      expectedOrigin: ORIGIN,
      expectedRPID: RP_ID,
    });

    if (!verification.verified || !verification.registrationInfo) {
      return new Response(JSON.stringify({ error: "Verification failed" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const info = verification.registrationInfo as any;
    const credentialIdStr = typeof info.credentialID === "string"
      ? info.credentialID
      : btoa(String.fromCharCode(...new Uint8Array(info.credentialID)))
          .replace(/\+/g, "-")
          .replace(/\//g, "_")
          .replace(/=+$/, "");

    const publicKeyBytes = info.credentialPublicKey;
    const publicKeyB64 = typeof publicKeyBytes === "string"
      ? publicKeyBytes
      : btoa(String.fromCharCode(...new Uint8Array(publicKeyBytes)));

    // ✅ Save credential via REST
    await firestoreSet(
      `employees/${employeeId}/webauthnCredentials/${credentialIdStr}`,
      {
        credentialPublicKey: toFsValue(publicKeyB64),
        counter: toFsValue(info.counter || 0),
        transports: toFsValue(credential.response?.transports || []),
        deviceLabel: toFsValue(deviceLabel || "Web Browser"),
        createdAt: toFsValue(new Date().toISOString()),
      }
    );

    // ✅ Delete challenge
    await firestoreDelete(`webauthnChallenges/${employeeId}`);

    return new Response(JSON.stringify({ verified: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("❌ Error:", err);
    return new Response(
      JSON.stringify({ error: (err as Error).message }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});