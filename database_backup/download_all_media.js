const fs = require('fs');
const path = require('path');
const https = require('https');
const http = require('http');

const backupDir = path.resolve(__dirname);
const collectionsDir = path.join(backupDir, 'collections');
const mediaDir = path.join(backupDir, 'media_backup');

const folders = {
  svga: path.join(mediaDir, 'svga_animations'),
  videos: path.join(mediaDir, 'vap_videos'),
  images: path.join(mediaDir, 'images_and_icons'),
  others: path.join(mediaDir, 'others')
};

for (const dir of Object.values(folders)) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

const urlRegex = /https?:\/\/[^\s"'<>]+/g;
const urlsToDownload = new Map();

const files = fs.readdirSync(collectionsDir).filter(f => f.endsWith('.json'));
console.log('Extracting media URLs from 44 collections...');

for (const file of files) {
  const content = fs.readFileSync(path.join(collectionsDir, file), 'utf8');
  let match;
  while ((match = urlRegex.exec(content)) !== null) {
    let rawUrl = match[0].replace(/[\\,\}]+$/, '');
    if (rawUrl.includes('res.cloudinary.com')) {
      const cleanUrl = rawUrl.split('?')[0];
      const filename = path.basename(cleanUrl);
      const ext = path.extname(cleanUrl).toLowerCase();
      
      let category = 'images';
      if (ext === '.svga') category = 'svga';
      else if (ext === '.mp4' || cleanUrl.includes('/video/')) category = 'videos';
      else if (['.png', '.jpg', '.jpeg', '.webp', '.gif'].includes(ext)) category = 'images';
      else category = 'others';

      if (!urlsToDownload.has(rawUrl)) {
        urlsToDownload.set(rawUrl, {
          url: rawUrl,
          category,
          filename: `${Date.now()}_${filename}`.replace(/[^a-zA-Z0-9._-]/g, '_'),
          originalFilename: filename
        });
      }
    }
  }
}

console.log(`Found ${urlsToDownload.size} Cloudinary media files to archive.`);

function downloadFile(fileUrl, destPath) {
  return new Promise((resolve, reject) => {
    const client = fileUrl.startsWith('https') ? https : http;
    const req = client.get(fileUrl, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return downloadFile(res.headers.location, destPath).then(resolve).catch(reject);
      }
      if (res.statusCode !== 200) {
        return reject(new Error(`HTTP ${res.statusCode}`));
      }
      const fileStream = fs.createWriteStream(destPath);
      res.pipe(fileStream);
      fileStream.on('finish', () => {
        fileStream.close();
        resolve();
      });
      fileStream.on('error', reject);
    });
    req.on('error', reject);
    req.setTimeout(15000, () => {
      req.destroy();
      reject(new Error('Timeout'));
    });
  });
}

async function main() {
  const manifest = [];
  let downloaded = 0;
  let failed = 0;
  const items = Array.from(urlsToDownload.values());

  console.log(`Starting media download (${items.length} files)...`);
  
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    const targetFolder = folders[item.category];
    const targetPath = path.join(targetFolder, item.filename);
    process.stdout.write(`[${i + 1}/${items.length}] (${item.category}) ${item.originalFilename}... `);

    try {
      await downloadFile(item.url, targetPath);
      manifest.push({
        url: item.url,
        category: item.category,
        localPath: path.relative(backupDir, targetPath),
        originalFilename: item.originalFilename
      });
      downloaded++;
      console.log('OK');
    } catch (err) {
      console.log(`FAIL (${err.message})`);
      failed++;
    }
  }

  fs.writeFileSync(
    path.join(mediaDir, 'media_manifest.json'),
    JSON.stringify(manifest, null, 2),
    'utf8'
  );

  console.log('\n=========================================');
  console.log('MEDIA ARCHIVE COMPLETE!');
  console.log(`Successfully Downloaded: ${downloaded}`);
  console.log(`Failed / Skipped:        ${failed}`);
  console.log(`Saved to:                ${mediaDir}`);
  console.log('=========================================\n');
}

main().catch(console.error);
