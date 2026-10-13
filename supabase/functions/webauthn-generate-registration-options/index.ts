// supabase/functions/webauthn-generate-registration-options/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { generateRegistrationOptions } from "jsr:@simplewebauthn/server@13";
import {
  firestoreGet,
  firestoreSet,
  firestoreListSubcollection,
  fromFsDoc,
  toFsValue,
} from "../_shared/firebase_rest.ts";

const RP_NAME = "HRIS Biometrics";
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

    // ✅ Fetch employee via REST API (walang gRPC)
    const empDoc = await firestoreGet(`employees/${employeeId}`);
    if (!empDoc) {
      return new Response(JSON.stringify({ error: "Employee not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const empParsed = fromFsDoc(empDoc);
    const employee = empParsed?.data || {};

    // ✅ Fetch existing credentials via REST
    const credsDocs = await firestoreListSubcollection(
      `employees/${employeeId}`,
      "webauthnCredentials"
    );
    const existingCredentials = credsDocs
      .map((d) => fromFsDoc(d))
      .filter((d) => d !== null)
      .map((d) => ({
        id: d!.id,
        transports: d!.data.transports || [],
      }));

    const options = await generateRegistrationOptions({
      rpName: RP_NAME,
      rpID: RP_ID,
      userID: new TextEncoder().encode(employeeId) as Uint8Array,
      userName: employee.email || employeeId,
      userDisplayName: employee.fullName || employee.email || employeeId,
      attestationType: "none",
      excludeCredentials: existingCredentials,
      authenticatorSelection: {
        authenticatorAttachment: "platform",
        userVerification: "required",
        residentKey: "preferred",
      },
    });

    // ✅ Save challenge via REST
    await firestoreSet(`webauthnChallenges/${employeeId}`, {
      challenge: toFsValue(options.challenge),
      type: toFsValue("registration"),
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