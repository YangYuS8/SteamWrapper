import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { site, base } from '../site.config.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const routes = JSON.parse(await readFile(resolve(root, 'legacy-routes.json'), 'utf8'));
for (const [file, route] of Object.entries(routes)) {
  if (!/^[\w.-]+\.md$/.test(file) || !/^[a-z0-9/-]+\/$/.test(route) || route.includes('..')) {
    throw new Error(`Unsafe legacy route: ${file} -> ${route}`);
  }
  const path = `${base}${route}`;
  const url = `${site}${path}`;
  const chinese = route.startsWith('zh-cn/');
  const html = `<!doctype html>
<html lang="${chinese ? 'zh-CN' : 'en'}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex"><link rel="canonical" href="${url}">
<title>${chinese ? '文档已移动' : 'Documentation moved'}</title>
<script>const target=new URL(${JSON.stringify(path)},location.origin);target.search=location.search;target.hash=location.hash;location.replace(target.href);</script>
<noscript><meta http-equiv="refresh" content="0;url=${path}"></noscript>
</head><body><p><a href="${path}">${chinese ? '前往新文档' : 'Continue to the documentation'}</a></p></body></html>\n`;
  const slug = file.replace(/\.md$/, '');
  for (const relative of [`${slug}/index.html`, `${slug}.html`]) {
    const output = resolve(root, 'dist', relative);
    await mkdir(dirname(output), { recursive: true });
    await writeFile(output, html);
  }
}
console.log(`Legacy document redirects: ${Object.keys(routes).length * 2} static pages.`);

// GitHub serves /404.html for missing URLs; Starlight's locale selector links
// to /404/. Keep both real locations usable instead of ignoring a broken link.
await mkdir(resolve(root, 'dist/404'), { recursive: true });
await copyFile(resolve(root, 'dist/404.html'), resolve(root, 'dist/404/index.html'));
