import { existsSync } from "node:fs";
import { copyFile, mkdtemp, mkdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const e2eDir = resolve(scriptDir, "..");
const workspaceDir = resolve(e2eDir, "../../..");
const fixtureRoot = await mkdtemp(join(tmpdir(), "steamwrapper-dioxus-e2e-"));
const steamRoot = join(fixtureRoot, "Steam");
const steamApps = join(steamRoot, "steamapps");
const gameDir = join(steamApps, "common", "中文 Test Game");
const localCoverPath = join(steamRoot, "appcache", "librarycache", "123456_library_600x900.png");

const appDataRoot = process.platform === "win32" ? "local-app-data" : "xdg-data";
const runnerFileName = process.platform === "win32" ? "SteamWrapperRunner.exe" : "steamwrapper-runner";
const runnerPath = join(fixtureRoot, appDataRoot, "SteamWrapper", "bin", runnerFileName);
const binaryName = process.platform === "win32" ? "SteamWrapperManager.exe" : "SteamWrapperManager";
const binaryPath = join(workspaceDir, "target", "debug", binaryName);
const artifactsDir = join(e2eDir, "artifacts", "native", "fixture");

async function write(relativePath, content = "") {
  const path = join(fixtureRoot, relativePath);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, content);
}

async function preserveFixtureArtifacts() {
  await mkdir(artifactsDir, { recursive: true });

  try {
    const profilesPath = join(fixtureRoot, appDataRoot, "SteamWrapper", "profiles.toml");
    const artifactProfilesPath = join(artifactsDir, "profiles.toml");
    await copyFile(profilesPath, artifactProfilesPath);
    await writeFile(
      artifactProfilesPath,
      (await readFile(artifactProfilesPath, "utf8")).replaceAll(fixtureRoot, "<fixture>"),
    );
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }

  try {
    await writeFile(
      join(artifactsDir, "runner.json"),
      `${JSON.stringify(
        {
          stable_path: runnerPath.replaceAll(fixtureRoot, "<fixture>"),
          bytes: (await stat(runnerPath)).size,
        },
        null,
        2,
      )}\n`,
    );
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }

  await writeFile(join(artifactsDir, "README.txt"), "This artifact contains only test-generated fixture data.\n");
}

try {
  await mkdir(gameDir, { recursive: true });
  if (existsSync(localCoverPath)) {
    throw new Error(`Native E2E fixture must omit the local cover cache: ${localCoverPath}`);
  }

  await write(
    "Steam/steamapps/libraryfolders.vdf",
    `"libraryfolders"\n{\n  "0"\n  {\n    "path" "${steamRoot.replaceAll("\\", "\\\\")}"\n  }\n}\n`,
  );
  await write(
    "Steam/steamapps/appmanifest_123456.acf",
    `"AppState"\n{\n  "appid" "123456"\n  "name" "中文 Test Game"\n  "installdir" "中文 Test Game"\n  "StateFlags" "4"\n}\n`,
  );


  if (existsSync(runnerPath)) throw new Error(`Native E2E fixture must start without a stable Runner: ${runnerPath}`);
  if (!existsSync(binaryPath)) {
    throw new Error(
      `Dioxus E2E binary not found: ${binaryPath}. Run cargo build -p steamwrapper-manager-dioxus --features e2e first.`,
    );
  }

  const wdioCliPath = fileURLToPath(new URL("../bin/wdio.js", import.meta.resolve("@wdio/cli")));
  const child = spawn(
    process.execPath,
    [wdioCliPath, "run", "wdio.native.conf.ts"],
    {
      cwd: e2eDir,
      env: {
        ...process.env,
        STEAMWRAPPER_E2E_ROOT: fixtureRoot,
        STEAM_DIR: steamRoot,
        XDG_DATA_HOME: join(fixtureRoot, "xdg-data"),
        LOCALAPPDATA: join(fixtureRoot, "local-app-data"),
      },
      stdio: "inherit",
    },
  );
  const exitCode = await new Promise((resolveExit, reject) => {
    child.once("error", reject);
    child.once("exit", (code) => resolveExit(code ?? 1));
  });
  await preserveFixtureArtifacts();
  process.exitCode = exitCode;
} finally {
  await rm(fixtureRoot, { recursive: true, force: true });
}
