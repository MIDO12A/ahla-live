const fs = require('fs');
const path = require('path');
const admin = require('../backend/node_modules/firebase-admin');

const serviceAccountPath = path.resolve(__dirname, '../backend/serviceAccountKey.json');
if (!fs.existsSync(serviceAccountPath)) {
  console.error('Service account key not found at:', serviceAccountPath);
  process.exit(1);
}

const serviceAccount = require(serviceAccountPath);
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// Helper to serialize Firestore data safely
function serializeValue(val) {
  if (val === null || val === undefined) return val;
  if (typeof val !== 'object') return val;

  // Timestamp
  if (val && typeof val.toDate === 'function') {
    return {
      __type: 'timestamp',
      seconds: val.seconds,
      nanoseconds: val.nanoseconds,
      iso: val.toDate().toISOString(),
    };
  }

  // GeoPoint
  if (val && typeof val.latitude === 'number' && typeof val.longitude === 'number') {
    return {
      __type: 'geopoint',
      latitude: val.latitude,
      longitude: val.longitude,
    };
  }

  // DocumentReference
  if (val && typeof val.path === 'string' && typeof val.id === 'string' && val.firestore) {
    return {
      __type: 'reference',
      path: val.path,
      id: val.id,
    };
  }

  // Array
  if (Array.isArray(val)) {
    return val.map(serializeValue);
  }

  // Plain Object
  const res = {};
  for (const [k, v] of Object.entries(val)) {
    res[k] = serializeValue(v);
  }
  return res;
}

// Check if any sample document in collection has subcollections
async function checkCollectionHasSubcollections(docs) {
  const sample = docs.slice(0, 5);
  for (const doc of sample) {
    const subs = await doc.ref.listCollections();
    if (subs.length > 0) return true;
  }
  return false;
}

async function exportCollection(colRef) {
  const snapshot = await colRef.get();
  const docs = {};

  if (snapshot.empty) {
    return { totalDocs: 0, docs: {} };
  }

  const hasSubcollections = await checkCollectionHasSubcollections(snapshot.docs);

  for (const doc of snapshot.docs) {
    const data = serializeValue(doc.data());
    let subData = undefined;

    if (hasSubcollections) {
      const subs = await doc.ref.listCollections();
      if (subs.length > 0) {
        subData = {};
        for (const sub of subs) {
          subData[sub.id] = await exportCollection(sub);
        }
      }
    }

    docs[doc.id] = {
      _data: data,
      ...(subData ? { _subcollections: subData } : {}),
    };
  }

  return {
    totalDocs: snapshot.size,
    docs,
  };
}

async function main() {
  const startTime = Date.now();
  const outDir = path.resolve(__dirname, '../database_backup');
  const collectionsDir = path.join(outDir, 'collections');

  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
  if (!fs.existsSync(collectionsDir)) fs.mkdirSync(collectionsDir, { recursive: true });

  console.log('Fetching collections from project:', serviceAccount.project_id);
  const collections = await db.listCollections();
  console.log(`Found ${collections.length} collections.`);

  const summary = {
    projectId: serviceAccount.project_id,
    exportedAt: new Date().toISOString(),
    totalCollections: collections.length,
    collections: {},
    totalDocuments: 0,
  };

  const fullBackup = {
    metadata: {
      projectId: serviceAccount.project_id,
      exportedAt: new Date().toISOString(),
    },
    collections: {},
  };

  for (let i = 0; i < collections.length; i++) {
    const col = collections[i];
    process.stdout.write(`[${i + 1}/${collections.length}] Exporting "${col.id}"... `);
    try {
      const colData = await exportCollection(col);
      
      // Save individual collection JSON
      fs.writeFileSync(
        path.join(collectionsDir, `${col.id}.json`),
        JSON.stringify(colData, null, 2),
        'utf8'
      );

      fullBackup.collections[col.id] = colData;
      summary.collections[col.id] = colData.totalDocs;
      summary.totalDocuments += colData.totalDocs;
      console.log(`OK (${colData.totalDocs} docs)`);
    } catch (err) {
      console.log(`ERROR: ${err.message}`);
      summary.collections[col.id] = `ERROR: ${err.message}`;
    }
  }

  // Save metadata
  summary.durationSeconds = ((Date.now() - startTime) / 1000).toFixed(2);
  fs.writeFileSync(
    path.join(outDir, 'backup_metadata.json'),
    JSON.stringify(summary, null, 2),
    'utf8'
  );

  // Save complete bundle
  console.log('\nWriting complete_database_backup.json...');
  fs.writeFileSync(
    path.join(outDir, 'complete_database_backup.json'),
    JSON.stringify(fullBackup, null, 2),
    'utf8'
  );

  console.log('\n=========================================');
  console.log('SUCCESS! Database backup finished.');
  console.log(`Total Collections: ${summary.totalCollections}`);
  console.log(`Total Documents:   ${summary.totalDocuments}`);
  console.log(`Time Elapsed:      ${summary.durationSeconds}s`);
  console.log(`Backup Directory:  ${outDir}`);
  console.log('=========================================\n');
}

main().catch(err => {
  console.error('Fatal error during backup:', err);
  process.exit(1);
});
