import { readdir, readFile, stat } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseHTML } from 'linkedom';
import { site as origin, base } from '../site.config.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const repository = resolve(root, '..');
const dist = resolve(root, 'dist');
const htmlFiles = (await readdir(dist, { recursive: true }))
  .map(file => file.replaceAll('\\', '/')).filter(file => file.endsWith('.html'));
const documents = new Map();
const errors = new Set();
let links = 0;
const exists = async file => (await stat(file).catch(() => undefined))?.isFile();
const routeFor = file => base + file.replace(/index\.html$/, '');
for (const file of htmlFiles) {
  documents.set(file, parseHTML(await readFile(resolve(dist, file), 'utf8')).document);
}
for (const [file, document] of documents) {
  const current = new URL(routeFor(file), origin);
  for (const element of document.querySelectorAll('[href], [src]')) {
    const value = element.getAttribute('href') ?? element.getAttribute('src');
    if (!value || /^(data:|mailto:|tel:)/.test(value)) continue;
    const target = new URL(value, current);
    const repoLink = /^\/YangYuS8\/SteamWrapper\/(?:blob|tree|edit)\/v2\/(.+)$/.exec(target.pathname);
    if (target.hostname === 'github.com' && repoLink) {
      const path = resolve(repository, decodeURIComponent(repoLink[1]));
      if (!(await stat(path).catch(() => undefined))) errors.add(`${file}: missing repository target ${value}`);
    }
    if (target.origin !== origin) continue;
    links++;
    if (!target.pathname.startsWith(base)) { errors.add(`${file}: escapes Pages base ${value}`); continue; }
    let relative = decodeURIComponent(target.pathname.slice(base.length));
    if (!relative || relative.endsWith('/')) relative += 'index.html';
    if (!(await exists(resolve(dist, relative)))) { errors.add(`${file}: missing target ${value}`); continue; }
    const linkedDocument = documents.get(relative);
    if (target.hash && linkedDocument) {
      const id = decodeURIComponent(target.hash.slice(1));
      if (!linkedDocument.getElementById(id) && ![...linkedDocument.querySelectorAll('a[name]')].some(a => a.getAttribute('name') === id)) {
        errors.add(`${file}: missing anchor ${value}`);
      }
    }
  }
}
const content = (await readdir(resolve(root, 'src/content/docs'), { recursive: true }))
  .map(file => file.replaceAll('\\', '/')).filter(file => /\.mdx?$/.test(file));
for (const file of content) {
  const route = file.replace(/\.mdx?$/, '').replace(/(^|\/)index$/, '$1');
  const output = route === '' ? 'index.html' : `${route.replace(/\/$/, '')}/index.html`;
  // Starlight emits the default error page as 404.html for static hosts.
  const page = documents.get(output) ?? (route === '404' ? documents.get('404.html') : undefined);
  if (!page) { errors.add(`${file}: no built page`); continue; }
  const expectedLanguage = file.startsWith('zh-cn/') ? 'zh-CN' : 'en';
  if (page.documentElement.getAttribute('lang') !== expectedLanguage) errors.add(`${file}: wrong HTML language`);
  if (!page.querySelector('main h1')) errors.add(`${file}: missing main heading`);
  if (route !== '404') {
    const expected = `${origin}${base}${route ? `${route.replace(/\/$/, '')}/` : ''}`;
    if (page.querySelector('link[rel="canonical"]')?.getAttribute('href') !== expected) errors.add(`${file}: wrong canonical URL`);
  }
}
if (!(await exists(resolve(dist, '404.html')))) errors.add('Missing static-host 404.html');
const pagefind = JSON.parse(await readFile(resolve(dist, 'pagefind/pagefind-entry.json'), 'utf8'));
for (const language of ['en', 'zh-cn']) {
  if (!Object.keys(pagefind.languages ?? {}).some(key => key.toLowerCase() === language)) errors.add(`Missing ${language} search index`);
}
if (errors.size) throw new Error([...errors].join('\n'));
console.log(`Static documentation: ${content.length} content pages, ${htmlFiles.length} HTML files, ${links} local links/assets, both search languages verified.`);
