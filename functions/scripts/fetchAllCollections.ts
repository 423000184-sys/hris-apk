// functions/scripts/exportFirestore.ts
import { readFileSync, writeFileSync } from 'node:fs';
import { cert, initializeApp } from 'firebase-admin/app';
import { CollectionReference, GeoPoint, Timestamp, getFirestore } from 'firebase-admin/firestore';

interface ExportedDoc {
  id: string;
  data: Record<string, unknown>;
  subcollections: Record<string, ExportedDoc[]>;
}

const SERVICE_ACCOUNT_PATH = process.env.GOOGLE_APPLICATION_CREDENTIALS ?? './serviceAccountKey.json';
const OUTPUT_PATH = './firestore-export.json';

/**
 * Converts Firestore-specific types (Timestamp, GeoPoint, DocumentReference)
 * into plain JSON-safe values, recursing through arrays and maps.
 */
function normalize(value: unknown): unknown {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value instanceof GeoPoint) return { lat: value.latitude, lng: value.longitude };
  if (Array.isArray(value)) return value.map(normalize);
  if (value !== null && typeof value === 'object') {
    const obj = value as Record<string, unknown>;
    // DocumentReference has a `path` string and a `firestore` property.
    if (typeof obj.path === 'string' && 'firestore' in obj) return obj.path;
    return Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, normalize(v)]));
  }
  return value;
}

/**
 * Reads a collection and, for every document, recursively reads its subcollections.
 * Documents are processed one at a time to avoid flooding Firestore with requests.
 */
async function exportCollection(col: CollectionReference): Promise<ExportedDoc[]> {
  const snap = await col.get();
  const result: ExportedDoc[] = [];

  for (const doc of snap.docs) {
    const subs = await doc.ref.listCollections();
    const subcollections: Record<string, ExportedDoc[]> = {};

    for (const sub of subs) {
      subcollections[sub.id] = await exportCollection(sub);
    }

    result.push({
      id: doc.id,
      data: normalize(doc.data()) as Record<string, unknown>,
      subcollections,
    });
  }

  return result;
}

async function main(): Promise<void> {
  const serviceAccount = JSON.parse(readFileSync(SERVICE_ACCOUNT_PATH, 'utf8'));
  initializeApp({ credential: cert(serviceAccount) });
  const db = getFirestore();

  const collections = await db.listCollections();
  const output: Record<string, ExportedDoc[]> = {};

  for (const col of collections) {
    console.log(`Reading ${col.id}...`);
    output[col.id] = await exportCollection(col);
    console.log(`  ${output[col.id].length} document(s)`);
  }

  writeFileSync(OUTPUT_PATH, JSON.stringify(output, null, 2), 'utf8');
  console.log(`Done. Saved to ${OUTPUT_PATH}`);
}

main().catch((error: unknown) => {
  console.error('Export failed:', error);
  process.exit(1);
});