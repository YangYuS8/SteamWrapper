import { existsSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { browser } from "@wdio/globals";

const packageDir = dirname(fileURLToPath(import.meta.url));
const workspaceDir = resolve(packageDir, "../..");
const binaryName = process.platform === "win32" ? "steamwrapper-manager.exe" : "steamwrapper-manager";
const appBinaryPath = resolve(workspaceDir, "target/debug", binaryName);

if (!existsSync(appBinaryPath)) throw new Error(`Tauri E2E binary not found: ${appBinaryPath}. Run pnpm e2e:native:build first.`);
const fixtureRoot = process.env.STEAMWRAPPER_E2E_ROOT;
if (!fixtureRoot) throw new Error("STEAMWRAPPER_E2E_ROOT is required; use pnpm e2e:native.");

const appEnv = { STEAM_DIR: resolve(fixtureRoot, "Steam"), XDG_DATA_HOME: resolve(fixtureRoot, "xdg-data"), LOCALAPPDATA: resolve(fixtureRoot, "local-app-data") };

export const config = {
  runner: "local",
  specs: ["./test/native/**/*.spec.ts"],
  maxInstances: 1,
  maxInstancesPerCapability: 1,
  capabilities: [{ browserName: "tauri", "tauri:options": { application: appBinaryPath }, "wdio:tauriServiceOptions": { appBinaryPath, driverProvider: "embedded", autoDownloadEdgeDriver: true, env: appEnv, captureBackendLogs: true, captureFrontendLogs: true, backendLogLevel: "debug", frontendLogLevel: "debug", startTimeout: 120_000, statusPollTimeout: 10_000 } }],
  logLevel: process.env.DEBUG ? "debug" : "info",
  outputDir: "./artifacts/native/logs",
  waitforTimeout: 15_000,
  connectionRetryTimeout: 120_000,
  connectionRetryCount: 2,
  services: [["@wdio/tauri-service", { driverProvider: "embedded", autoDownloadEdgeDriver: true, captureBackendLogs: true, captureFrontendLogs: true }]],
  framework: "mocha",
  reporters: ["spec"],
  mochaOpts: { ui: "bdd", timeout: 120_000 },
  tsConfigPath: resolve(packageDir, "tsconfig.json"),
  afterTest: async (_test: unknown, _context: unknown, result: { passed: boolean }) => {
    if (!result.passed) {
      const screenshots = resolve(packageDir, "artifacts/native/screenshots");
      await mkdir(screenshots, { recursive: true });
      await browser.saveScreenshot(resolve(screenshots, `${Date.now()}.png`));
    }
  },
};
