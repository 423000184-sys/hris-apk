// supabase/functions/_shared/firebase_rest.ts

let cachedToken: { token: string; expiresAt: number } | null = null;

function base64UrlEncode(data: Uint8Array | string): string {
  const bytes = typeof data === "string"
    ? new TextEncoder().encode(data)
    : data;
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

async function importPrivateKey(pemKey: string): Promise<CryptoKey> {
  const pemContents = pemKey
    .replace(/-----BEGIN[^-]+-----/g, "")
    .replace(/-----END[^-]+-----/g, "")
    .replace(/[^A-Za-z0-9+/=]/g, "");

  console.log("🔍 PEM body length:", pemContents.length);
  console.log("🔍 PEM first 40:", pemContents.substring(0, 40));

  if (pemContents.length < 100) {
    throw new Error("PEM too short: " + pemContents.length);
  }

  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

  return await crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );
}

export async function getAccessToken(): Promise<string> {
  const now = Date.now();

  if (cachedToken && cachedToken.expiresAt > now + 5 * 60 * 1000) {
    return cachedToken.token;
  }

  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL");
  if (!clientEmail) throw new Error("FIREBASE_CLIENT_EMAIL not set");

  const rawKey = Deno.env.get("FIREBASE_PRIVATE_KEY");
  if (!rawKey || rawKey.length < 100) {
    throw new Error("FIREBASE_PRIVATE_KEY missing or too short");
  }
  const privateKey = rawKey.replace(/\\n/g, "\n");

  console.log("🔑 Key length:", privateKey.length);

  const iat = Math.floor(now / 1000);
  const exp = iat + 3600;

  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/datastore",
    aud: "https://oauth2.googleapis.com/token",
    iat,
    exp,
  };

  const unsignedToken =
    `${base64UrlEncode(JSON.stringify(header))}.` +
    `${base64UrlEncode(JSON.stringify(payload))}`;

  const key = await importPrivateKey(privateKey);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsignedToken)
  );

  const signedToken =
    `${unsignedToken}.${base64UrlEncode(new Uint8Array(signature))}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: signedToken,
    }),
  });

  if (!tokenRes.ok) {
    const err = await tokenRes.text();
    throw new Error(`Failed to get access token: ${err}`);
  }

  const tokenData = await tokenRes.json();

  cachedToken = {
    token: tokenData.access_token,
    expiresAt: now + tokenData.expires_in * 1000,
  };

  return tokenData.access_token;
}

const getBaseUrl = () => {
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID");
  if (!projectId) throw new Error("FIREBASE_PROJECT_ID not set");
  return `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
};

export async function firestoreGet(path: string): Promise<any | null> {
  const token = await getAccessToken();
  const res = await fetch(`${getBaseUrl()}/${path}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (res.status === 404) return null;
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Firestore GET ${path}: ${res.status} ${err}`);
  }
  return await res.json();
}

export async function firestoreSet(
  path: string,
  fields: Record<string, any>
): Promise<any> {
  const token = await getAccessToken();
  const res = await fetch(`${getBaseUrl()}/${path}`, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ fields }),
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Firestore SET ${path}: ${res.status} ${err}`);
  }
  return await res.json();
}

export async function firestoreDelete(path: string): Promise<void> {
  const token = await getAccessToken();
  const res = await fetch(`${getBaseUrl()}/${path}`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok && res.status !== 404) {
    const err = await res.text();
    throw new Error(`Firestore DELETE ${path}: ${res.status} ${err}`);
  }
}

export async function firestoreListSubcollection(
  parentPath: string,
  subcollection: string
): Promise<any[]> {
  const token = await getAccessToken();
  const url = `${getBaseUrl()}/${parentPath}/${subcollection}`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (res.status === 404) return [];
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Firestore LIST ${url}: ${res.status} ${err}`);
  }
  const data = await res.json();
  return data.documents || [];
}

export function toFsValue(value: any): any {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") {
    return Number.isInteger(value)
      ? { integerValue: value.toString() }
      : { doubleValue: value };
  }
  if (typeof value === "string") return { stringValue: value };
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(toFsValue) } };
  }
  if (typeof value === "object") {
    const fields: Record<string, any> = {};
    for (const [k, v] of Object.entries(value)) {
      fields[k] = toFsValue(v);
    }
    return { mapValue: { fields } };
  }
  return { stringValue: String(value) };
}

export function fromFsValue(fv: any): any {
  if (!fv) return null;
  if (fv.nullValue !== undefined) return null;
  if (fv.booleanValue !== undefined) return fv.booleanValue;
  if (fv.integerValue !== undefined) return parseInt(fv.integerValue);
  if (fv.doubleValue !== undefined) return parseFloat(fv.doubleValue);
  if (fv.stringValue !== undefined) return fv.stringValue;
  if (fv.arrayValue !== undefined) {
    return (fv.arrayValue.values || []).map(fromFsValue);
  }
  if (fv.mapValue !== undefined) {
    const result: any = {};
    for (const [k, v] of Object.entries(fv.mapValue.fields || {})) {
      result[k] = fromFsValue(v);
    }
    return result;
  }
  return null;
}

export function fromFsDoc(doc: any): { id: string; data: any } | null {
  if (!doc || !doc.name) return null;
  const parts = doc.name.split("/");
  const id = parts[parts.length - 1];
  const data: any = {};
  for (const [k, v] of Object.entries(doc.fields || {})) {
    data[k] = fromFsValue(v);
  }
  return { id, data };
}