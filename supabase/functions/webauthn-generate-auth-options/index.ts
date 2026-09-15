// supabase/functions/webauthn-generate-auth-options/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { generateAuthenticationOptions } from "jsr:@simplewebauthn/server@13";
import {
  firestoreSet,
  firestoreListSubcollection,
  fromFsDoc,
  toFsValue,
} from "../_shared/firebase_rest.ts";

const RP_ID = "week-9-activity-53484.web.app";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { employeeId } = await req.json();
    if (!employeeId) {
      return new Response(JSON.stringify({ error: "Missing employeeId" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ✅ Fetch credentials via REST
    const credsDocs = await firestoreListSubcollection(
      `employees/${employeeId}`,
      "webauthnCredentials"
    );

    if (credsDocs.length === 0) {
      return new Response(
        JSON.stringify({
          error: "Walang naka-enroll na fingerprint sa device na ito.",
        }),
        {
          status: 412,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const allowCredentials = credsDocs
      .map((d) => fromFsDoc(d))
      .filter((d) => d !== null)
      .map((d) => ({
        id: d!.id,
        transports: d!.data.transports || [],
      }));

    const options = await generateAuthenticationOptions({
      rpID: RP_ID,
      allowCredentials,
      userVerification: "required",
    });

    // ✅ Save challenge via REST
    await firestoreSet(`webauthnChallenges/${employeeId}`, {
      challenge: toFsValue(options.challenge),
      type: toFsValue("authentication"),
      createdAt: toFsValue(new Date().toISOString()),
    });

    return new Response(JSON.stringify(options), {
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