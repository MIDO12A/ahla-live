const fs = require('fs');
const path = require('path');
const admin = require('../backend/node_modules/firebase-admin');

// Parse CLI args: node restore_firestore.js [serviceAccountKey.json] [backupDir]
const args = process.argv.slice(2);
const saArg = args[0] || path.resolve(__dirname, '../backend/serviceAccountKey.json');
const backupDir = args[1] || path.resolve(__dirname, '../database_backup');

if (!fs.existsSync(saArg)) {
  console.error('Target Service Account file not found at:', saArg);
  console.error('Usage: node restore_firestore.js [path/to/target_serviceAccountKey.json] [path/to/backupDir]');
  process.exit(1);
}

const serviceAccount = require(path.resolve(saArg));
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

// Helper to deserialize types back to Firestore objects
function deserializeValue(val) {
  if (val === null || val === undefined) return val;
  if (typeof val !== 'object') return val;

  if (val.__type === 'timestamp') {
    return new admin.firestore.Timestamp(val.seconds, val.nanoseconds);
  }

  if (val.__type === 'geopoint') {
    return new admin.firestore.GeoPoint(val.latitude, val.longitude);
  }

  if (val.__type === 'reference') {
    return db.doc(val.path);
  }

  if (Array.isArray(val)) {
    return val.map(deserializeValue);
  }

  const res = {};
  for (const [k, v] of Object.entries(val)) {
    res[k] = deserializeValue(v);
  }
  return res;
}

// Restore a collection recursively in batches of 400 (Firestore max limit is 500)
async function restoreCollection(colRef, collectionData) {
  const docs = collectionData.docs || {};
  const docIds = Object.keys(docs);
  let batch = db.batch();
  let opCount = 0;
  let totalRestored = 0;

  for (const docId of docIds) {
    const item = docs[docId];
    const data = deserializeValue(item._data || {});
    const docRef = colRef.doc(docId);

    batch.set(docRef, data, { merge: true });
    opCount++;
    totalRestored++;

    if (opCount >= 400) {
      await batch.commit();
      batch = db.batch();
      opCount = 0;
    }

    // Restore subcollections if any
    if (item._subcollections) {
      for (const [subColId, subColData] of Object.entries(item._subcollections)) {
        await restoreCollection(docRef.collection(subColId), subColData);
      }
    }
  }

  if (opCount > 0) {
    await batch.commit();
  }

  return totalRestored;
}

async function main() {
  const startTime = Date.now();
  const backupFile = path.join(backupDir, 'complete_database_backup.json');
  const collectionsDir = path.join(backupDir, 'collections');

  console.log('Target Firebase Project:', serviceAccount.project_id);
  console.log('Loading backup data from:', backupDir);

  let collections = {};

  if (fs.existsSync(backupFile)) {
    console.log('Found complete_database_backup.json, loading full bundle...');
    const parsed = JSON.parse(fs.readFileSync(backupFile, 'utf8'));
    collections = parsed.collections || {};
  } else if (fs.existsSync(collectionsDir)) {
    console.log('Loading collections from directory:', collectionsDir);
    const files = fs.readdirSync(collectionsDir).filter(f => f.endsWith('.json'));
    for (const file of files) {
      const colId = path.basename(file, '.json');
      collections[colId] = JSON.parse(fs.readFileSync(path.join(collectionsDir, file), 'utf8'));
    }
  } else {
    console.error('No backup files found in:', backupDir);
    process.exit(1);
  }

  const colIds = Object.keys(collections);
  console.log(`Starting restoration of ${colIds.length} collections...`);

  let totalRestoredDocs = 0;

  for (let i = 0; i < colIds.length; i++) {
    const colId = colIds[i];
    const colData = collections[colId];
    process.stdout.write(`[${i + 1}/${colIds.length}] Restoring collection "${colId}"... `);

    try {
      const count = await restoreCollection(db.collection(colId), colData);
      totalRestoredDocs += count;
      console.log(`OK (${count} docs)`);
    } catch (err) {
      console.log(`FAILED: ${err.message}`);
    }
  }

  const duration = ((Date.now() - startTime) / 1000).toFixed(2);
  console.log('\n=========================================');
  console.log('RESTORE COMPLETED!');
  console.log(`Project:            ${serviceAccount.project_id}`);
  console.log(`Collections:        ${colIds.length}`);
  console.log(`Total Docs Restored:${totalRestoredDocs}`);
  console.log(`Time Elapsed:       ${duration}s`);
  console.log('=========================================\n');
}

main().catch(err => {
  console.error('Fatal error during restoration:', err);
  process.exit(1);
});
