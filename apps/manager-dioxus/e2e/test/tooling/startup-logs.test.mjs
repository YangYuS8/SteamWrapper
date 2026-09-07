import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import test from "node:test";

const e2eDir = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const wdioCli = fileURLToPath(new URL("../bin/wdio.js", import.meta.resolve("@wdio/cli")));

test("a process that exits before WebDriver is ready leaves stdout and stderr artifacts", async () => {
  const fixture = await mkdtemp(join(tmpdir(), "steamwrapper-startup-logs-"));
  const logsDir = join(fixture, "logs");
  const configPath = join(fixture, "wdio.fixture.conf.mjs");
  const stdoutMarker = "startup fixture stdout before readiness";
  const stderrMarker = "startup fixture stderr before readiness";
  try {
    await writeFile(configPath, `
import { config as base } from ${JSON.stringify(pathToFileURL(join(e2eDir, "wdio.native.conf.ts")).href)};
const application = ${JSON.stringify(process.execPath)};
export const config = {
  ...base,
  outputDir: ${JSON.stringify(logsDir)},
  specs: [${JSON.stringify(join(e2eDir, "test/native/startup.spec.ts"))}],
  capabilities: base.capabilities.map(cap => ({
    ...cap,
    "dioxus:options": { application },
    "wdio:dioxusServiceOptions": {
      ...cap["wdio:dioxusServiceOptions"],
      appBinaryPath: application,
      appArgs: ["-e", ${JSON.stringify(`process.stdout.write(${JSON.stringify(stdoutMarker + "\n")}); process.stderr.write(${JSON.stringify(stderrMarker + "\n")}); process.exitCode = 101;`)}],
      startTimeout: 1000,
    },
  })),
};
`);
    const child = spawnSync(process.execPath, [wdioCli, "run", configPath], {
      cwd: e2eDir,
      env: { ...process.env, STEAMWRAPPER_E2E_ROOT: fixture },
      encoding: "utf8",
      timeout: 20_000,
    });
    assert.ifError(child.error);
    assert.equal(child.status, 1, `${child.stdout}\n${child.stderr}`);
    assert.match(`${child.stdout}\n${child.stderr}`, /code=101/);
    const logFiles = await readdir(logsDir);
    const logs = (await Promise.all(logFiles.map(file => readFile(join(logsDir, file), "utf8")))).join("\n");
    assert.ok(logs.includes(stdoutMarker), `stdout missing from artifacts: ${logFiles.join(", ")}`);
    assert.ok(logs.includes(stderrMarker), `stderr missing from artifacts: ${logFiles.join(", ")}`);
  } finally {
    await rm(fixture, { recursive: true, force: true });
  }
});

test("a failed startup finishes log capture before another attempt uses a new artifact directory", async () => {
  const fixture = await mkdtemp(join(tmpdir(), "steamwrapper-startup-retry-"));
  const previousRoot = process.env.STEAMWRAPPER_E2E_ROOT;
  process.env.STEAMWRAPPER_E2E_ROOT = fixture;
  const instances = [];
  try {
    const { config } = await import(pathToFileURL(join(e2eDir, "wdio.native.conf.ts")).href);
    const [servicePath, options] = config.services[0];
    const { launcher: Launcher } = await import(isAbsolute(servicePath) ? pathToFileURL(servicePath).href : servicePath);
    for (const attempt of [1, 2]) {
      const outputDir = join(fixture, `attempt-${attempt}`);
      const marker = `startup stderr attempt ${attempt}`;
      const capabilities = [{
        ...config.capabilities[0],
        "dioxus:options": { application: process.execPath },
        "wdio:dioxusServiceOptions": {
          ...config.capabilities[0]["wdio:dioxusServiceOptions"],
          appArgs: ["-e", `process.stderr.write(${JSON.stringify(marker + "\n")}); process.exitCode = 101;`],
          startTimeout: 1000,
        },
      }];
      const attemptConfig = { ...config, outputDir };
      const instance = new Launcher(options, capabilities, attemptConfig);
      instances.push(instance);
      await assert.rejects(instance.onPrepare(attemptConfig, capabilities), /code=101/);
      if (attempt === 2) {
        const files = await readdir(outputDir);
        const logs = (await Promise.all(files.map(file => readFile(join(outputDir, file), "utf8")))).join("\n");
        assert.ok(logs.includes(marker), "retry stderr must be flushed into its own artifact directory");
      }
    }
  } finally {
    for (const instance of instances) await instance.onComplete();
    if (previousRoot === undefined) delete process.env.STEAMWRAPPER_E2E_ROOT;
    else process.env.STEAMWRAPPER_E2E_ROOT = previousRoot;
    await rm(fixture, { recursive: true, force: true });
  }
});
