import { $, browser, expect } from "@wdio/globals";

const statusText = () => browser.execute(
  () => document.querySelector("[data-testid='status-text']")?.textContent ?? "",
);

describe("Browser Mode: 游戏库", () => {
  it("使用 mock 扫描结果渲染中文游戏、空格路径和封面占位", async () => {
    const scan = await browser.tauri.mock("scan_local_steam_games_command");
    await scan.mockResolvedValue([{ appid: "123456", name: "中文 Test Game", install_dir: "C:\\Steam Library\\common\\中文 Test Game", cover_path: null }]);
    await $("[data-testid='scan-games']").click();
    await expect($("[data-testid='game-card-123456']")).toBeDisplayed();
    await expect($("[data-testid='game-card-123456']")).toHaveText(expect.stringContaining("中文 Test Game"));
    await expect($("[data-testid='game-card-123456']")).toHaveText(expect.stringContaining("C:\\Steam Library"));
    await expect($("[data-testid='game-card-123456']")).toHaveText(expect.stringContaining("本地封面缓存未找到"));
    await scan.update();
    expect(scan).toHaveBeenCalledTimes(1);
  });

  it("扫描空结果和扫描错误都会显示明确状态", async () => {
    const scan = await browser.tauri.mock("scan_local_steam_games_command");
    await scan.mockResolvedValue([]);
    await $("[data-testid='scan-games']").click();
    await browser.waitUntil(async () => (await statusText()) === "没有扫描到本地 Steam 游戏");
    await scan.mockRejectedValue(new Error("fixture scan failed"));
    await $("[data-testid='scan-games']").click();
    await browser.waitUntil(async () => (await statusText()).includes("扫描失败"));
  });
});
