// Extract Arabic string literals from lib/**/*.dart and translate to English
// via Google Translate gtx endpoint -> assets/lang/en.json  { "arabic": "english" }
const fs = require('fs');
const path = require('path');

const ROOT = 'F:\\سورس كود\\zero';
const LIB = path.join(ROOT, 'lib');
const OUT = path.join(ROOT, 'assets', 'lang', 'en.json');

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.dart')) out.push(p);
  }
  return out;
}

const AR = /[\u0600-\u06FF]/;
const strings = new Set();
const files = walk(LIB);

const re = /'((?:\\.|[^'\\])*)'|"((?:\\.|[^"\\])*)"/g;
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  let m;
  while ((m = re.exec(src))) {
    const raw = m[1] !== undefined ? m[1] : m[2];
    if (raw === undefined) continue;
    if (raw.includes('${')) continue;
    const s = raw
      .replace(/\\n/g, '\n')
      .replace(/\\'/g, "'")
      .replace(/\\"/g, '"')
      .replace(/\\\\/g, '\\');
    if (s.length < 2 || s.length > 800) continue;
    if (!AR.test(s)) continue;
    strings.add(s);
  }
}

const list = [...strings];
console.log(`Extracted ${list.length} unique Arabic strings`);

async function translateOne(q) {
  const params = new URLSearchParams();
  params.set('client', 'gtx');
  params.set('sl', 'ar');
  params.set('tl', 'en');
  params.set('dt', 't');
  params.append('q', q);
  const url = 'https://translate.googleapis.com/translate_a/single?' + params.toString();
  const res = await fetch(url);
  if (!res.ok) throw new Error('HTTP ' + res.status);
  const data = await res.json();
  return (data[0] || []).map(seg => seg[0]).join('');
}

(async () => {
  const result = {};
  const CONCURRENCY = 8;
  let idx = 0, done = 0, failed = 0;

  async function worker() {
    while (idx < list.length) {
      const i = idx++;
      const q = list[i];
      try {
        result[q] = await translateOne(q);
      } catch (e) {
        failed++;
        result[q] = q;
      }
      done++;
      if (done % 200 === 0) console.log(`${done}/${list.length} (failed:${failed})`);
    }
  }
  await Promise.all(Array.from({ length: CONCURRENCY }, worker));
  fs.writeFileSync(OUT, JSON.stringify(result, null, 2), 'utf8');
  console.log('Wrote ' + OUT + ' with ' + Object.keys(result).length + ' entries, failed=' + failed);
})();
