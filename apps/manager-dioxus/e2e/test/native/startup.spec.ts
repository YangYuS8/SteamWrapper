import { $, expect } from "@wdio/globals";

describe("SteamWrapper Dioxus Manager", () => {
  it("starts with the player-facing library flow", async () => {
    const root = await $("[data-testid='manager-root']");
    await expect(root).toBeDisplayed();
    await expect($("[data-testid='scan-games']")).toHaveText("扫描本地 Steam 游戏");
    await expect($("[data-testid='manual-add-game']")).toHaveText("手动添加游戏");
  });

  it("renders the custom desktop title bar instead of relying on native decorations", async () => {
    await expect($("[data-testid='app-titlebar']")).toBeDisplayed();
    await expect($("[data-testid='window-minimize']")).toBeDisplayed();
    await expect($("[data-testid='window-maximize']")).toBeDisplayed();
    await expect($("[data-testid='window-close']")).toBeDisplayed();
  });

  it("installs the bundled Runner into the stable user-data path on first start", async () => {
    await $("[data-testid='nav-设置']").click();
    const status = await $("[data-testid='runner-status']");
    await expect(status).toHaveText(expect.stringContaining("已安装"));
    const runnerPath = await $("[data-testid='runner-path']");
    await expect(runnerPath).toHaveText(expect.stringContaining("SteamWrapper/bin"));
  });
});
