import { $, browser, expect } from "@wdio/globals";
import "@wdio/native-types";

describe("Native Mode: 假 Steam Library", () => {
  it("扫描中文路径游戏，过滤运行时工具并合并跨库重复 AppID", async () => {
    const games = await browser.tauri.execute(({ core }) => core.invoke("scan_local_steam_games_command")) as Array<Record<string, string | null>>;
    expect(games).toHaveLength(1);
    expect(games[0]).toEqual(expect.objectContaining({ appid: "123456", name: "中文 Test Game" }));
    expect(games[0]?.install_dir).toContain("中文 Test Game");
    expect(games[0]?.cover_path).toContain("123456_library_600x900.png");

    await $("[data-testid='scan-games']").click();
    await expect($("[data-testid='game-card-123456']")).toBeDisplayed();
  });
});
