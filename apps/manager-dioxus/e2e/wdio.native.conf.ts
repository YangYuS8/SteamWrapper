import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const packageDir = dirname(fileURLToPath(import.meta.url));
const workspaceDir = resolve(packageDir, "../../..");
const binaryName = process.platform === "win32" ? "SteamWrapperManager.exe" : "SteamWrapperManager";
const binaryPath = resolve(workspaceDir, "target", "debug", binaryName);
const fixtureRoot = process.env.STEAMWRAPPER_E2E_ROOT;

if (!fixtureRoot) throw new Error("STEAMWRAPPER_E2E_ROOT is required; use pnpm e2e:native.");

const appEnv = {
  RUST_BACKTRACE: "1",
  STEAMWRAPPER_E2E_ROOT: fixtureRoot,
  STEAM_DIR: resolve(fixtureRoot, "Steam"),
  XDG_DATA_HOME: resolve(fixtureRoot, "xdg-data"),
  LOCALAPPDATA: resolve(fixtureRoot, "local-app-data"),
};

export const config = {
  runner: "local",
  specs: ["./test/native/**/*.spec.ts"],
  maxInstances: 1,
  maxInstancesPerCapability: 1,
  logLevel: process.env.DEBUG ? "debug" : "info",
  outputDir: "./artifacts/native/logs",
  waitforTimeout: 15_000,
  connectionRetryTimeout: 120_000,
  connectionRetryCount: 2,
  capabilities: [
    {
      browserName: "dioxus",
      "dioxus:options": { application: binaryPath },
      "wdio:dioxusServiceOptions": {
        driverProvider: "embedded",
        appBinaryPath: binaryPath,
        captureBackendLogs: true,
        captureFrontendLogs: true,
        backendLogLevel: "debug",
        frontendLogLevel: "debug",
        startTimeout: 120_000,
        statusPollTimeout: 15_000,
        env: appEnv,
      },
    },
  ],
  services: [
    [
      resolve(packageDir, "scripts/dioxus-service.mjs"),
      { driverProvider: "embedded", startTimeout: 120_000, statusPollTimeout: 15_000 },
    ],
  ],
  framework: "mocha",
  reporters: ["spec"],
  mochaOpts: { ui: "bdd", timeout: 120_000 },
  tsConfigPath: resolve(packageDir, "tsconfig.json"),
};
