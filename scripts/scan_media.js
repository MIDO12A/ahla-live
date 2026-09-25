const fs = require('fs');
const path = require('path');

const colsDir = path.resolve(__dirname, '../database_backup/collections');
const files = fs.readdirSync(colsDir);
const urls = new Set();
const domains = {};
const mediaTypes = {
  images: new Set(),
  svga: new Set(),
  videos: new Set(),
  others: new Set()
};

const urlRegex = /https?:\/\/[^\s"'<>]+/g;

for (const file of files) {
  const content = fs.readFileSync(path.join(colsDir, file), 'utf8');
  let match;
  while ((match = urlRegex.exec(content)) !== null) {
    let u = match[0].replace(/[\\,\}]+$/, '');
    urls.add(u);
    try {
      const d = new URL(u).hostname;
      domains[d] = (domains[d] || 0) + 1;
      
      const lower = u.toLowerCase();
      if (lower.includes('.svga')) {
        mediaTypes.svga.add(u);
      } else if (lower.includes('.mp4') || lower.includes('vap')) {
        mediaTypes.videos.add(u);
      } else if (lower.includes('.png') || lower.includes('.jpg') || lower.includes('.jpeg') || lower.includes('.webp') || lower.includes('.gif')) {
        mediaTypes.images.add(u);
      } else {
        mediaTypes.others.add(u);
      }
    } catch(e) {}
  }
}

console.log('Total unique URLs found:', urls.size);
console.log('Domains breakdown:', JSON.stringify(domains, null, 2));
console.log('SVGA count:', mediaTypes.svga.size);
console.log('Videos/VAP count:', mediaTypes.videos.size);
console.log('Images count:', mediaTypes.images.size);
console.log('Others count:', mediaTypes.others.size);
