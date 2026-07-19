import { spawn, type ChildProcess } from "node:child_process";
import { mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { browser } from "@wdio/globals";

const packageDir = dirname(fileURLToPath(import.meta.url));
const managerDir = resolve(packageDir, "../manager");
let vite: ChildProcess | undefined;

async function waitForVite(url: string, timeoutMs = 120_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      if ((await fetch(url)).ok) return;
    } catch {
      // Vite is still starting.
    }
    await new Promise((resolveDelay) => setTimeout(resolveDelay, 250));
  }
  throw new Error(`Vite dev server did not become ready: ${url}`);
}

export const config = {
  runner: "local",
  specs: ["./test/browser/**/*.spec.ts"],
  maxInstances: 1,
  maxInstancesPerCapability: 1,
  capabilities: [{ browserName: "tauri", "wdio:maxInstances": 1, "goog:chromeOptions": { args: ["--headless=new", "--window-size=1440,1000", "--no-sandbox", "--disable-dev-shm-usage"] }, "wdio:tauriServiceOptions": { mode: "browser", devServerUrl: "http://127.0.0.1:1420" } }],
  logLevel: "info",
  outputDir: "./artifacts/browser/logs",
  waitforTimeout: 10_000,
  connectionRetryTimeout: 120_000,
  connectionRetryCount: 2,
  services: [["tauri", { mode: "browser", devServerUrl: "http://127.0.0.1:1420" }]],
  framework: "mocha",
  reporters: ["spec"],
  mochaOpts: { ui: "bdd", timeout: 60_000 },
  tsConfigPath: resolve(packageDir, "tsconfig.json"),
  onPrepare: async () => {
    vite = spawn("pnpm", ["dev"], { cwd: managerDir, env: { ...process.env, VITE_STEAMWRAPPER_E2E: "0" }, stdio: "pipe" });
    await waitForVite("http://127.0.0.1:1420");
  },
  onComplete: async () => vite?.kill(),
  before: async () => {
    const invokeBridge = await browser.execute(() => {
      const win = window as Window & { __TAURI_INTERNALS__?: { invoke?: unknown }; __TAURI__?: unknown };
      return typeof win.__TAURI_INTERNALS__?.invoke === "function" || typeof win.__TAURI__ !== "undefined";
    });
    if (!invokeBridge) throw new Error("Browser Mode did not install the Tauri IPC mock bridge");
  },
  afterTest: async (_test: unknown, _context: unknown, result: { passed: boolean }) => {
    if (!result.passed) {
      const screenshots = resolve(packageDir, "artifacts/browser/screenshots");
      await mkdir(screenshots, { recursive: true });
      await browser.saveScreenshot(resolve(screenshots, `${Date.now()}.png`));
    }
  },
};
