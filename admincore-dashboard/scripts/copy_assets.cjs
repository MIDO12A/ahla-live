const fs = require('fs');
const path = require('path');

const srcDir = path.resolve(__dirname, '../../assets');
const destDir = path.resolve(__dirname, '../public/assets');

function copyFolderSync(from, to) {
  if (!fs.existsSync(from)) {
    console.warn(`Source directory not found: ${from}`);
    return;
  }
  fs.mkdirSync(to, { recursive: true });
  fs.readdirSync(from).forEach(element => {
    const stat = fs.lstatSync(path.join(from, element));
    if (stat.isFile()) {
      try {
        fs.copyFileSync(path.join(from, element), path.join(to, element));
      } catch (err) {
        // Ignore locked or busy files
      }
    } else if (stat.isDirectory()) {
      copyFolderSync(path.join(from, element), path.join(to, element));
    }
  });
}

console.log('Copying Flutter assets to dashboard public/assets...');
copyFolderSync(srcDir, destDir);
console.log('Assets copied successfully!');


