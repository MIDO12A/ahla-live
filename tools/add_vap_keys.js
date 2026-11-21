#!/usr/bin/env node
/**
 * add_vap_keys.js — Inject dynamic placeholder keys into a VAP mp4
 * (mp4 with embedded `vapc` JSON box, e.g. voiceroom_bg_luckdraw_anim_n.mp4).
 *
 * Usage:
 *   node tools/add_vap_keys.js <input.mp4> <output.mp4> <keys.json>
 *
 * keys.json — array of key definitions:
 * [
 *   {
 *     "tag": "mykey",            // placeholder tag used in imageReplacement/textReplacement
 *     "type": "img",             // "img" | "text"
 *     "w": 120, "h": 40,         // content size (src w/h)
 *     "mFrame": [x, y, w, h],    // position/size on the video canvas (videoW x videoH space)
 *     "frame":  [x, y, w, h],    // optional — source rect inside the injected image (default [0,0,w,h])
 *     "z": 3,                    // z-order (higher = on top)
 *     "loadType": "net",         // optional, default "net"
 *     "fitType": "fitXY",        // optional, default "fitXY"
 *     "srcExtra": { ... },       // optional extra fields merged into the src entry
 *     "objExtra": { ... }        // optional extra fields merged into every frame obj
 *   }
 * ]
 *
 * The script rewrites the mp4 and fixes the stco chunk offset so the file
 * stays valid. Run it on a copy first and test in the app.
 */

const fs = require('fs');

function readBoxHeader(buf, pos) {
  let size = buf.readUInt32BE(pos);
  const type = buf.toString('ascii', pos + 4, pos + 8);
  let headerSize = 8;
  if (size === 1) {
    size = Number(buf.readBigUInt64BE(pos + 8));
    headerSize = 16;
  } else if (size === 0) {
    size = buf.length - pos;
  }
  return { size, type, headerSize };
}

function findBox(buf, type, from = 0, to = buf.length) {
  for (let p = from; p < to - 8; p++) {
    if (buf.toString('ascii', p + 4, p + 8) === type) {
      // verify it looks like a real box (plausible size)
      const size = buf.readUInt32BE(p);
      if (size >= 8 && p + size <= buf.length) return p;
    }
  }
  return -1;
}

function patchStcoOffsets(buf, delta, onlyAfter) {
  // Patch every stco box: add delta to each chunk offset that points beyond `onlyAfter`
  let p = 0;
  let patched = 0;
  while ((p = findBox(buf, 'stco', p)) !== -1) {
    const size = buf.readUInt32BE(p);
    const count = buf.readUInt32BE(p + 12);
    for (let k = 0; k < count; k++) {
      const offPos = p + 16 + k * 4;
      const off = buf.readUInt32BE(offPos);
      if (off > onlyAfter) {
        buf.writeUInt32BE(off + delta, offPos);
        patched++;
      }
    }
    p += size;
  }
  return patched;
}

function main() {
  const [input, output, keysFile] = process.argv.slice(2);
  if (!input || !output || !keysFile) {
    console.error('Usage: node add_vap_keys.js <input.mp4> <output.mp4> <keys.json>');
    process.exit(1);
  }

  const buf = fs.readFileSync(input);
  const newKeys = JSON.parse(fs.readFileSync(keysFile, 'utf8'));
  if (!Array.isArray(newKeys) || newKeys.length === 0) {
    console.error('keys.json must be a non-empty array');
    process.exit(1);
  }

  // Locate vapc box
  const vapcPos = buf.indexOf('vapc', 'ascii');
  if (vapcPos === -1) {
    console.error('No vapc box found — this mp4 has no embedded VAP config.');
    process.exit(1);
  }
  const boxStart = vapcPos - 4;
  const { size: oldBoxSize, headerSize } = readBoxHeader(buf, boxStart);
  const payloadStart = boxStart + headerSize;
  const payloadEnd = boxStart + oldBoxSize;

  // Parse existing JSON (payload is raw JSON, possibly with trailing NULs)
  let jsonText = buf.toString('utf8', payloadStart, payloadEnd);
  const nulIdx = jsonText.indexOf('\0');
  if (nulIdx !== -1) jsonText = jsonText.slice(0, nulIdx);
  const vapc = JSON.parse(jsonText);
  if (!vapc.src || !vapc.frame) {
    console.error('vapc JSON missing src/frame arrays');
    process.exit(1);
  }

  // Validate + append src entries
  const existingTags = new Set(vapc.src.map(s => s.srcTag));
  const additions = [];
  for (const k of newKeys) {
    if (!k.tag || !k.type || !k.mFrame) {
      console.error('Each key needs: tag, type, mFrame (and w/h). Got:', JSON.stringify(k));
      process.exit(1);
    }
    if (existingTags.has(k.tag)) {
      console.error(`Tag "${k.tag}" already exists in this video.`);
      process.exit(1);
    }
    existingTags.add(k.tag);
    const srcId = String(vapc.src.length + additions.length);
    const srcEntry = {
      srcId,
      srcType: k.type,
      srcTag: k.tag,
      loadType: k.loadType || 'net',
      fitType: k.fitType || 'fitXY',
      w: k.w,
      h: k.h,
      ...(k.srcExtra || {}),
    };
    const objEntry = {
      srcId,
      z: k.z !== undefined ? k.z : vapc.src.length + additions.length,
      frame: k.frame || [0, 0, k.w, k.h],
      mFrame: k.mFrame,
      mt: 0,
      ...(k.objExtra || {}),
    };
    additions.push({ srcEntry, objEntry });
  }

  for (const a of additions) vapc.src.push(a.srcEntry);
  for (const f of vapc.frame) {
    for (const a of additions) f.obj.push({ ...a.objEntry });
  }

  const newJson = JSON.stringify(vapc);
  const newPayload = Buffer.from(newJson, 'utf8');
  const newBoxSize = headerSize + newPayload.length;
  const delta = newBoxSize - oldBoxSize;

  // Rebuild file: [before box] + [new box] + [after box]
  const out = Buffer.concat([
    buf.subarray(0, boxStart),
    (() => {
      const head = Buffer.alloc(headerSize);
      if (headerSize === 16) {
        head.writeUInt32BE(1, 0); // largesize marker
        head.write('vapc', 4, 'ascii');
        head.writeBigUInt64BE(BigInt(newBoxSize), 8);
      } else {
        head.writeUInt32BE(newBoxSize, 0);
        head.write('vapc', 4, 'ascii');
      }
      return Buffer.concat([head, newPayload]);
    })(),
    buf.subarray(payloadEnd),
  ]);

  // Fix chunk offsets that point past the old vapc box end
  const patched = patchStcoOffsets(out, delta, payloadEnd);

  fs.writeFileSync(output, out);
  console.log(`OK: ${input} -> ${output}`);
  console.log(`  added ${additions.length} key(s): ${newKeys.map(k => k.tag).join(', ')}`);
  console.log(`  vapc box ${oldBoxSize} -> ${newBoxSize} bytes (delta ${delta >= 0 ? '+' : ''}${delta})`);
  console.log(`  patched ${patched} stco chunk offset(s)`);
}

main();
