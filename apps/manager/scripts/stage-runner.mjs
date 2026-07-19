import { spawn } from "node:child_process";
import { chmod, copyFile, mkdir, readdir, rm } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const managerDir = resolve(fileURLToPath(new URL("..", import.meta.url)));
const workspaceDir = resolve(managerDir, "../..");
const profile = process.env.STEAMWRAPPER_RUNNER_PROFILE === "debug" ? "debug" : "release";
const skipBuild = process.env.STEAMWRAPPER_RUNNER_SKIP_BUILD === "1";
const runnerFileName = process.platform === "win32" ? "steamwrapper-runner.exe" : "steamwrapper-runner";
const bundledFileName = process.platform === "win32" ? "SteamWrapperRunner.exe" : "steamwrapper-runner";
const runnerPath = resolve(workspaceDir, "target", profile, runnerFileName);
const stagingDir = resolve(managerDir, "src-tauri", "resources", "runner");
const stagedRunnerPath = resolve(stagingDir, bundledFileName);

function run(command, args, options) {
  return new Promise((resolveExit, reject) => {
    const child = spawn(command, args, options);
    child.once("error", reject);
    child.once("exit", (code) => {
      if (code === 0) resolveExit();
      else reject(new Error(`${command} ${args.join(" ")} exited with code ${code ?? 1}`));
    });
  });
}

const cargo = process.env.CARGO ?? (process.platform === "win32" ? "cargo.exe" : "cargo");
const cargoArgs = ["build", "--package", "steamwrapper-runner"];
if (profile === "release") cargoArgs.push("--release");

if (!skipBuild) await run(cargo, cargoArgs, { cwd: workspaceDir, stdio: "inherit" });
await mkdir(stagingDir, { recursive: true });
await Promise.all(
  (await readdir(stagingDir, { withFileTypes: true })).map((entry) =>
    rm(resolve(stagingDir, entry.name), { recursive: entry.isDirectory(), force: true }),
  ),
);
await copyFile(runnerPath, stagedRunnerPath);
if (process.platform !== "win32") await chmod(stagedRunnerPath, 0o755);
console.log(`Staged ${profile} Runner: ${stagedRunnerPath}`);
