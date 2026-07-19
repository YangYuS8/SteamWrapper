import { spawn } from "node:child_process";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const packageDir = resolve(fileURLToPath(new URL("..", import.meta.url)));
const workspaceDir = resolve(packageDir, "../..");
const child = spawn(
  process.execPath,
  [
    resolve(workspaceDir, "apps/manager/node_modules/@tauri-apps/cli/tauri.js"),
    "build",
    "--debug",
    "--no-bundle",
    "--features",
    "e2e",
    "--config",
    resolve(workspaceDir, "apps/manager/src-tauri/tauri.e2e.conf.json"),
  ],
  {
    cwd: workspaceDir,
    env: { ...process.env, VITE_STEAMWRAPPER_E2E: "1", STEAMWRAPPER_RUNNER_PROFILE: "debug" },
    stdio: "inherit",
  },
);
process.exit(await new Promise((resolveExit) => child.once("exit", (code) => resolveExit(code ?? 1))));
