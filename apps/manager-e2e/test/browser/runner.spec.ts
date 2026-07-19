import { $, browser, expect } from "@wdio/globals";

const healthyRunner = {
  installed: true,
  healthy: true,
  path: "C:\\data\\SteamWrapper\\bin\\SteamWrapperRunner.exe",
  bundled_version: "a".repeat(64),
  installed_version: "a".repeat(64),
  needs_install: false,
  needs_update: false,
  last_error: null,
};

async function openSettings() {
  await browser.execute(() => document.querySelector<HTMLElement>("[data-testid='nav-settings']")?.click());
}

describe("Browser Mode: Runner 状态", () => {
  it("展示健康 Runner 的稳定路径和摘要", async () => {
    const status = await browser.tauri.mock("get_runner_status");
    await status.mockResolvedValue(healthyRunner);

    await openSettings();
    await $("[data-testid='refresh-runner-status']").click();

    await expect($("[data-testid='runner-status']")).toHaveText(expect.stringContaining("已安装"));
    await expect($("[data-testid='runner-path']")).toHaveText(expect.stringContaining("SteamWrapperRunner.exe"));
    await expect($("[data-testid='runner-version']")).toHaveText(expect.stringContaining("a".repeat(12)));
  });

  it("缺失时安装 Runner 并刷新为健康状态", async () => {
    const status = await browser.tauri.mock("get_runner_status");
    const install = await browser.tauri.mock("install_runner");
    await status.mockResolvedValue({
      ...healthyRunner,
      installed: false,
      healthy: false,
      installed_version: null,
      needs_install: true,
      needs_update: false,
    });
    await install.mockResolvedValue({ changed: true, status: healthyRunner });

    await openSettings();
    await $("[data-testid='refresh-runner-status']").click();
    await expect($("[data-testid='runner-status']")).toHaveText(expect.stringContaining("未安装"));
    await $("[data-testid='runner-install']").click();

    await expect($("[data-testid='runner-status']")).toHaveText(expect.stringContaining("已安装"));
    await expect($("[data-testid='runner-path']")).toHaveText(expect.stringContaining("SteamWrapperRunner.exe"));
    await install.update();
    expect(install).toHaveBeenCalledTimes(1);
  });

  it("修复失败时展示明确错误", async () => {
    const status = await browser.tauri.mock("get_runner_status");
    const repair = await browser.tauri.mock("repair_runner");
    await status.mockResolvedValue({
      ...healthyRunner,
      healthy: false,
      installed_version: "b".repeat(64),
      needs_install: false,
      needs_update: true,
    });
    await repair.mockRejectedValue(new Error("Runner 正被 Steam 占用"));

    await openSettings();
    await $("[data-testid='refresh-runner-status']").click();
    await $("[data-testid='runner-repair']").click();

    await expect($("[data-testid='runner-error']")).toHaveText(expect.stringContaining("占用"));
  });
});
