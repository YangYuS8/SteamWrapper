import { $, browser, expect } from "@wdio/globals";
import { readFile, stat, writeFile } from "node:fs/promises";
import "@wdio/native-types";

type RunnerStatus = {
  installed: boolean;
  healthy: boolean;
  path: string;
  bundled_version: string | null;
  installed_version: string | null;
  needs_install: boolean;
  needs_update: boolean;
  last_error: string | null;
};

describe("Native Mode: 隔离数据目录", () => {
  it("将真实随包 Runner 安装到隔离稳定路径并修复损坏文件", async () => {
    const paths = await browser.tauri.execute(({ core }) => core.invoke("get_app_paths")) as Record<string, string>;
    expect(paths.app_data_dir).toContain("SteamWrapper");
    expect(paths.profiles_path).toContain("profiles.toml");
    expect(paths.logs_dir).toContain("logs");
    expect(paths.runner_path).toMatch(
      process.platform === "win32"
        ? /SteamWrapperRunner\.exe$/
        : /steamwrapper-runner$/,
    );
    if (process.platform === "win32") {
      expect(paths.app_data_dir).toContain("local-app-data");
      expect(paths.runner_path).toContain("local-app-data");
    }

    const status = await browser.tauri.execute(({ core }) => core.invoke("get_runner_status")) as RunnerStatus;
    expect(status).toEqual(expect.objectContaining({
      installed: true,
      healthy: true,
      path: paths.runner_path,
      needs_install: false,
      needs_update: false,
    }));
    expect(status.bundled_version).toMatch(/^[a-f0-9]{64}$/);
    expect(status.installed_version).toBe(status.bundled_version);

    const runnerBytes = await readFile(paths.runner_path);
    expect(runnerBytes.byteLength).toBeGreaterThan(0);
    if (process.platform === "win32") {
      expect(runnerBytes.subarray(0, 2).toString("ascii")).toBe("MZ");
    } else {
      expect(runnerBytes.subarray(0, 4).toString("ascii")).toBe("\x7FELF");
      expect((await stat(paths.runner_path)).mode & 0o111).not.toBe(0);
    }

    const unchanged = await browser.tauri.execute(({ core }) => core.invoke("install_runner")) as { changed: boolean; status: RunnerStatus };
    expect(unchanged).toEqual(expect.objectContaining({ changed: false, status: expect.objectContaining({ healthy: true }) }));

    await writeFile(paths.runner_path, "corrupted fixture runner");
    const damaged = await browser.tauri.execute(({ core }) => core.invoke("get_runner_status")) as RunnerStatus;
    expect(damaged).toEqual(expect.objectContaining({ healthy: false, needs_update: true }));

    const repaired = await browser.tauri.execute(({ core }) => core.invoke("repair_runner")) as { changed: boolean; status: RunnerStatus };
    expect(repaired).toEqual(expect.objectContaining({ changed: true, status: expect.objectContaining({ healthy: true }) }));
    expect((await readFile(paths.runner_path)).byteLength).toBeGreaterThan(0);

    const launchOption = await browser.tauri.execute(({ core }) => core.invoke("generate_launch_option", { appid: "123456" })) as string;
    expect(launchOption).toContain(paths.runner_path);
    expect(launchOption).toContain('--appid "123456"');
  });

  it("写入 Profile 并重新读取，且 Runner 安装不触碰 profiles.toml", async () => {
    const paths = await browser.tauri.execute(({ core }) => core.invoke("get_app_paths")) as Record<string, string>;
    await browser.tauri.execute(({ core }) => core.invoke("save_profile", {
      request: {
        appid: "654321",
        name: "Direct Command Game",
        game_dir: "C:\\Steam Library\\common\\中文 Test Game",
        target: "C:\\Steam Library\\common\\中文 Test Game\\launcher.exe",
      },
    }));
    const beforeInstall = await readFile(paths.profiles_path, "utf8");
    expect(beforeInstall).toContain(
      process.platform === "win32"
        ? "wait_mode = \"job\""
        : "wait_mode = \"process_group\"",
    );
    const install = await browser.tauri.execute(({ core }) => core.invoke("install_runner")) as { changed: boolean; status: RunnerStatus };
    expect(install.changed).toBe(false);
    expect(await readFile(paths.profiles_path, "utf8")).toBe(beforeInstall);

    const profiles = await browser.tauri.execute(({ core }) => core.invoke("list_profiles")) as Array<Record<string, string>>;
    expect(profiles).toEqual(expect.arrayContaining([expect.objectContaining({ appid: "654321", name: "Direct Command Game" })]));
    expect(beforeInstall).toContain("654321");
    expect(beforeInstall).toContain("Direct Command Game");
  });

  it("从真实 UI 保存 Profile 并生成 Launch Options", async () => {
    await $("[data-testid='scan-games']").click();
    await $("[data-testid='game-card-123456']").click();
    await expect($("[data-testid='config-dialog']")).toBeDisplayed();

    await $("[data-testid='target-path']").setValue("/tmp/中文 Test Game/launcher.sh");
    await $("[data-testid='save-profile']").click();
    await expect($("[data-testid='launch-option']")).toHaveValue(expect.stringContaining('--appid "123456"'));

    const profiles = await browser.tauri.execute(({ core }) => core.invoke("list_profiles")) as Array<Record<string, string>>;
    expect(profiles).toEqual(expect.arrayContaining([expect.objectContaining({ appid: "123456", name: "中文 Test Game" })]));
  });
});
