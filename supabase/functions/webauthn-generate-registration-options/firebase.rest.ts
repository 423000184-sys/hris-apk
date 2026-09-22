// supabase/functions/webauthn-verify-auth/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { verifyAuthenticationResponse } from "jsr:@simplewebauthn/server@13";
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
    const { employeeId, credential } = await req.json();
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
    const expectedChallenge = fromFsDoc(challengeDoc)?.data.challenge;

    // ✅ Get credential via REST
    const credentialId = credential.id;
    const credDoc = await firestoreGet(
      `employees/${employeeId}/webauthnCredentials/${credentialId}`
    );
    if (!credDoc) {
      return new Response(
        JSON.stringify({ error: "Credential not found" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }
    const credData = fromFsDoc(credDoc)!.data;

    // Decode stored public key
    const publicKeyB64 = credData.credentialPublicKey as string;
    const publicKeyBytes = Uint8Array.from(atob(publicKeyB64), (c) =>
      c.charCodeAt(0)
    );

    // Decode credential ID
    const credIdBytes = Uint8Array.from(
      atob(credentialId.replace(/-/g, "+").replace(/_/g, "/")),
      (c) => c.charCodeAt(0)
    );

    const verification = await verifyAuthenticationResponse({
      response: credential,
      expectedChallenge,
      expectedOrigin: ORIGIN,
      expectedRPID: RP_ID,
      credential: {
        id: credentialId,
        publicKey: publicKeyBytes,
        counter: credData.counter || 0,
        transports: credData.transports || [],
      },
    });

    if (!verification.verified) {
      return new Response(JSON.stringify({ verified: false }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ✅ Update counter via REST
    await firestoreSet(
      `employees/${employeeId}/webauthnCredentials/${credentialId}`,
      {
        ...Object.fromEntries(
          Object.entries(credData).map(([k, v]) => [k, toFsValue(v)])
        ),
        counter: toFsValue(verification.authenticationInfo.newCounter),
        lastUsedAt: toFsValue(new Date().toISOString()),
      }
    );

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