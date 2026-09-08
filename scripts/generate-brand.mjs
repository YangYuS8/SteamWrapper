import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { Resvg } from '@resvg/resvg-js';

// Development-only rendering. Shipped Managers do not need Node.js or resvg.
const root = fileURLToPath(new URL('../', import.meta.url));
const check = process.argv.includes('--check');
const svg = await readFile(join(root, 'assets/brand/steamwrapper.svg'));
const render = size => new Resvg(svg, {
  fitTo: { mode: 'width', value: size },
  font: { loadSystemFonts: false },
}).render().asPng();

// Windows supports PNG-compressed images in ICO files. Render every size from
// the vector source rather than resampling the largest raster.
const sizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256];
const frames = sizes.map(render);
const directory = Buffer.alloc(6 + sizes.length * 16);
directory.writeUInt16LE(1, 2);
directory.writeUInt16LE(sizes.length, 4);
let offset = directory.length;
frames.forEach((frame, index) => {
  const entry = 6 + index * 16;
  directory[entry] = directory[entry + 1] = sizes[index] === 256 ? 0 : sizes[index];
  directory.writeUInt16LE(1, entry + 4);
  directory.writeUInt16LE(32, entry + 6);
  directory.writeUInt32LE(frame.length, entry + 8);
  directory.writeUInt32LE(offset, entry + 12);
  offset += frame.length;
});
const ico = Buffer.concat([directory, ...frames]);
const png = render(512);
const outputs = new Map([
  ['assets/brand/steamwrapper.png', png],
  ['assets/brand/steamwrapper.ico', ico],
  ['apps/manager-dioxus/assets/steamwrapper.svg', svg],
  ['apps/manager-dioxus/assets/icons/steamwrapper.png', png],
  ['apps/manager-dioxus/assets/icons/steamwrapper.ico', ico],
]);
let stale = false;
for (const [relative, bytes] of outputs) {
  const path = join(root, relative);
  if (check) {
    const existing = await readFile(path).catch(() => Buffer.alloc(0));
    if (!existing.equals(bytes)) {
      console.error(`Outdated brand asset: ${relative}. Run mise run brand:generate.`);
      stale = true;
    }
  } else {
    await writeFile(path, bytes);
    console.log(`Generated ${relative}`);
  }
}
if (stale) process.exitCode = 1;
else if (check) console.log('Brand assets match the canonical SVG at every packaged size.');

if (process.argv.includes('--preview')) {
  const preview = join(root, 'target/brand-preview');
  await mkdir(preview, { recursive: true });
  for (const size of [...sizes, 512]) {
    await writeFile(join(preview, `${size}.png`), render(size));
  }
  console.log(`Icon previews: ${preview}`);
}
