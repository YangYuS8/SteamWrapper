import { copyFile, mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const packageDir = resolve(fileURLToPath(new URL("..", import.meta.url)));
const workspaceDir = resolve(packageDir, "../..");
const fixtureRoot = await mkdtemp(join(tmpdir(), "steamwrapper-e2e-"));
const steamApps = join(fixtureRoot, "Steam", "steamapps");
const duplicateSteamApps = join(fixtureRoot, "Steam Extra", "steamapps");
const gameDir = join(steamApps, "common", "中文 Test Game");
const coverDir = join(fixtureRoot, "Steam", "appcache", "librarycache");

async function write(relativePath, content = "") {
  const path = join(fixtureRoot, relativePath);
  await mkdir(resolve(path, ".."), { recursive: true });
  await writeFile(path, content);
}

await mkdir(gameDir, { recursive: true });
await mkdir(duplicateSteamApps, { recursive: true });
await mkdir(coverDir, { recursive: true });
await write("Steam/steamapps/libraryfolders.vdf", `"libraryfolders"\n{\n  "0"\n  {\n    "path" "${resolve(fixtureRoot, "Steam").replaceAll("\\", "\\\\")}"\n  }\n  "1"\n  {\n    "path" "${resolve(fixtureRoot, "Steam Extra").replaceAll("\\", "\\\\")}"\n  }\n}\n`);
for (const [appid, name, installDir] of [
  ["123456", "中文 Test Game", "中文 Test Game"],
  ["228980", "Steamworks Common Redistributables", "Steamworks Shared"],
  ["1493710", "Proton Experimental", "Proton - Experimental"],
  ["1070560", "Steam Linux Runtime 1.0 (scout)", "SteamLinuxRuntime"],
]) {
  await write(`Steam/steamapps/appmanifest_${appid}.acf`, `"AppState"\n{\n  "appid" "${appid}"\n  "name" "${name}"\n  "installdir" "${installDir}"\n  "StateFlags" "4"\n}\n`);
}
await write("Steam Extra/steamapps/appmanifest_123456.acf", `"AppState"\n{\n  "appid" "123456"\n  "name" "Duplicate Test Game"\n  "installdir" "Duplicate Test Game"\n  "StateFlags" "4"\n}\n`);
await write("Steam/appcache/librarycache/123456_library_600x900.png", "fixture cover");

const child = spawn("pnpm", ["exec", "wdio", "run", "wdio.native.conf.ts"], {
  cwd: packageDir,
  env: { ...process.env, STEAMWRAPPER_E2E_ROOT: fixtureRoot },
  stdio: "inherit",
});
const exitCode = await new Promise((resolveExit) => child.once("exit", (code) => resolveExit(code ?? 1)));

await mkdir(join(packageDir, "artifacts", "native", "fixture"), { recursive: true });
const artifactFixtureDir = join(packageDir, "artifacts", "native", "fixture");
const appDataRoot = process.platform === "win32" ? "local-app-data" : "xdg-data";
const profilesPath = join(fixtureRoot, appDataRoot, "SteamWrapper", "profiles.toml");
try {
  const artifactProfilesPath = join(artifactFixtureDir, "profiles.toml");
  await copyFile(profilesPath, artifactProfilesPath);
  await writeFile(
    artifactProfilesPath,
    (await readFile(artifactProfilesPath, "utf8")).replaceAll(fixtureRoot, "<fixture>"),
  );
} catch (error) {
  if (error?.code !== "ENOENT") throw error;
}
await writeFile(join(artifactFixtureDir, "README.txt"), "This artifact contains only test-generated fixture data.\n");
await rm(fixtureRoot, { recursive: true, force: true });
process.exit(exitCode);
