import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { parseDocument } from 'yaml';

const root = fileURLToPath(new URL('../src/content/docs/', import.meta.url));
const files = (await readdir(root, { recursive: true }))
  .map(file => file.replaceAll('\\', '/'))
  .filter(file => /\.mdx?$/.test(file));
const fileSet = new Set(files);
const errors = [];
for (const file of files) {
  const counterpart = file.startsWith('zh-cn/') ? file.slice(6) : `zh-cn/${file}`;
  if (!fileSet.has(counterpart)) errors.push(`${file}: missing complete counterpart ${counterpart}`);
  const source = await readFile(resolve(root, file), 'utf8');
  const match = /^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/.exec(source);
  if (!match) { errors.push(`${file}: missing frontmatter`); continue; }
  const document = parseDocument(match[1], { uniqueKeys: true });
  if (document.errors.length) { errors.push(`${file}: ${document.errors.join('; ')}`); continue; }
  const data = document.toJS();
  for (const key of ['title', 'description']) {
    if (typeof data?.[key] !== 'string' || !data[key].trim()) errors.push(`${file}: missing ${key}`);
  }
  if (data?.draft) errors.push(`${file}: documentation counterparts must be published together`);
  if (match[2].trim().length < 100) errors.push(`${file}: incomplete page body`);
}
const translations = {};
for (const language of ['en', 'zh-CN']) {
  translations[language] = JSON.parse(await readFile(new URL(`../src/content/i18n/${language}.json`, import.meta.url), 'utf8'));
}
const keys = new Set([...Object.keys(translations.en), ...Object.keys(translations['zh-CN'])]);
for (const key of keys) {
  const values = [translations.en[key], translations['zh-CN'][key]];
  if (values.some(value => typeof value !== 'string' || !value.trim())) {
    errors.push(`UI translations: missing ${key}`);
    continue;
  }
  const placeholders = value => [...value.matchAll(/\{\{[^}]+\}\}|\[[A-Z_]+\]/g)].map(match => match[0]).sort().join(',');
  if (placeholders(values[0]) !== placeholders(values[1])) errors.push(`UI translations: mismatched placeholders in ${key}`);
}
if (errors.length) throw new Error(errors.join('\n'));
console.log(`Documentation content: ${files.length / 2} complete English / Simplified Chinese pairs.`);
