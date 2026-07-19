import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const packageDir = resolve(fileURLToPath(new URL("..", import.meta.url)));
const distDir = resolve(packageDir, "dist");
const forbiddenMarkers = ["wdioTauri", "@wdio/tauri-plugin"];

async function collectFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(
    entries.map(async (entry) => {
      const path = resolve(directory, entry.name);
      return entry.isDirectory() ? collectFiles(path) : [path];
    }),
  );
  return nested.flat();
}

const matches = [];
for (const file of await collectFiles(distDir)) {
  const contents = await readFile(file, "utf8");
  const markers = forbiddenMarkers.filter((marker) => contents.includes(marker));
  if (markers.length > 0) {
    matches.push(`${file}: ${markers.join(", ")}`);
  }
}

if (matches.length > 0) {
  throw new Error(`正式前端产物包含 E2E WebDriver 代码：\n${matches.join("\n")}`);
}

console.log("Verified release frontend excludes WDIO renderer code.");
