import { spawn } from "node:child_process";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const packageDir = resolve(fileURLToPath(new URL("..", import.meta.url)));
const workspaceDir = resolve(packageDir, "../..");
const child = spawn(
  "pnpm",
  ["--filter", "steamwrapper-manager", "tauri", "build", "--debug", "--no-bundle", "--features", "e2e", "--config", "src-tauri/tauri.e2e.conf.json"],
  {
    cwd: workspaceDir,
    env: { ...process.env, VITE_STEAMWRAPPER_E2E: "1" },
    stdio: "inherit",
  },
);
process.exit(await new Promise((resolveExit) => child.once("exit", (code) => resolveExit(code ?? 1))));
