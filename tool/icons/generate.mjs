import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { Resvg } from '@resvg/resvg-js';
import { PNG } from 'pngjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
process.chdir(root);
const source = fs.readFileSync('assets/icon/icon_rounded.svg', 'utf8');
// Keep the same rounded design, but flatten onto white for iOS (no alpha).
const iosSource = source.replace(/(<svg[^>]*>)/, '$1<rect width="1024" height="1024" fill="#FFFFFF"/>');
const cache = new Map();
function render(size, opaque = false) {
  const key = size + ':' + opaque;
  if (!cache.has(key)) {
    let bytes = new Resvg(opaque ? iosSource : source, {
      fitTo: { mode: 'width', value: size },
    }).render().asPng();
    if (opaque) {
      bytes = PNG.sync.write(PNG.sync.read(bytes), { colorType: 2 });
    }
    cache.set(key, bytes);
  }
  return cache.get(key);
}
function save(file, size, opaque = false) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, render(size, opaque));
}
function dimensions(bytes) {
  return [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
}
function pngs(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const file = path.join(dir, entry.name);
    return entry.isDirectory() ? pngs(file) : file.endsWith('.png') ? [file] : [];
  });
}

// icons_launcher still owns platform wiring, file names and asset catalogs.
// Native-size vector rendering below replaces its bitmap downsampling only.
save('assets/icon/icon_rounded.png', 1024);
save('assets/icon/icon_rounded_ios.png', 1024, true);
fs.writeFileSync('assets/icon/icon_rounded_ios.svg', iosSource);
const result = spawnSync('fvm', ['dart', 'run', 'icons_launcher:create'], { stdio: 'inherit' });
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 1);

const outputs = [];
const dirs = [
  'android/app/src/main/res',
  'ios/Runner/Assets.xcassets/AppIcon.appiconset',
  'macos/Runner/Assets.xcassets/AppIcon.appiconset',
];
for (const dir of dirs) {
  for (const file of pngs(dir)) {
    if (dir.includes('/res') && !file.endsWith('/ic_launcher.png')) continue;
    const [w, h] = dimensions(fs.readFileSync(file));
    assert.equal(w, h, 'Icon must be square: ' + file);
    save(file, w, file.startsWith('ios/'));
    outputs.push([file, w]);
  }
}
for (const [file, size] of [
  ['android/app/src/main/ic_launcher-playstore.png', 512],
  // Linux desktop environments can request 512px or larger on HiDPI screens.
  ['snap/gui/azusa.png', 1024],
]) {
  save(file, size);
  outputs.push([file, size]);
}

// ICO: every entry is independently rendered from SVG, never from another size.
const sizes = [16, 24, 32, 48, 64, 96, 128, 256];
const frames = sizes.map(size => render(size));
const header = Buffer.alloc(6 + sizes.length * 16);
header.writeUInt16LE(1, 2);
header.writeUInt16LE(sizes.length, 4);
let offset = header.length;
for (let i = 0; i < sizes.length; i++) {
  const p = 6 + i * 16;
  header[p] = header[p + 1] = sizes[i] === 256 ? 0 : sizes[i];
  header.writeUInt16LE(1, p + 4);
  header.writeUInt16LE(32, p + 6);
  header.writeUInt32LE(frames[i].length, p + 8);
  header.writeUInt32LE(offset, p + 12);
  offset += frames[i].length;
}
fs.writeFileSync('windows/runner/resources/app_icon.ico', Buffer.concat([header, ...frames]));

// Flutter chooses a native-resolution asset matching devicePixelRatio.
for (const [suffix, size] of [['', 128], ['2.0x/', 256], ['3.0x/', 384], ['4.0x/', 512]]) {
  save('assets/icon/ui/' + suffix + 'icon_rounded.png', size);
}

// Validate actual output dimensions, iOS alpha, and all ICO entries.
for (const [file, size] of outputs) {
  const data = fs.readFileSync(file);
  assert.deepEqual(dimensions(data), [size, size]);
  if (file.startsWith('ios/')) assert.equal(data[25], 2, 'iOS PNG must be RGB');
}
const ico = fs.readFileSync('windows/runner/resources/app_icon.ico');
for (let i = 0; i < sizes.length; i++) {
  const p = 6 + i * 16;
  const start = ico.readUInt32LE(p + 12);
  const length = ico.readUInt32LE(p + 8);
  assert.deepEqual(dimensions(ico.subarray(start, start + length)), [sizes[i], sizes[i]]);
}
console.log('Verified ' + outputs.length + ' native-size PNGs, 8 ICO frames and 4 Flutter density variants.');
