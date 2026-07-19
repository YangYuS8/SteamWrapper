import { $, browser, expect } from "@wdio/globals";

describe("Browser Mode: 导航", () => {
  it("已配置游戏、日志和设置页均可通过 mock 数据渲染", async () => {
    const profiles = await browser.tauri.mock("list_profiles");
    const logs = await browser.tauri.mock("list_runner_logs");
    const paths = await browser.tauri.mock("get_app_paths");
    await profiles.mockResolvedValue([{ appid: "123456", name: "已配置游戏", game_dir: "C:\\Game", target: "C:\\Game\\run.exe", launch_option: "option" }]);
    await logs.mockResolvedValue([{ file_name: "runner.log", path: "C:\\logs\\runner.log", content: "fixture log" }]);
    await paths.mockResolvedValue({ app_data_dir: "C:\\data\\SteamWrapper", profiles_path: "C:\\data\\SteamWrapper\\profiles.toml", runner_path: "C:\\data\\SteamWrapper\\bin\\SteamWrapperRunner.exe", logs_dir: "C:\\data\\SteamWrapper\\logs", backups_dir: "C:\\data\\SteamWrapper\\backups", cache_dir: "C:\\data\\SteamWrapper\\cache" });
    await browser.execute(() => document.querySelector<HTMLElement>("[data-testid='nav-configured']")?.click());
    await $("[data-testid='refresh-profiles']").click();
    await expect($("[data-testid='configured-profile-123456']")).toBeDisplayed();
    await browser.execute(() => document.querySelector<HTMLElement>("[data-testid='nav-logs']")?.click());
    await $("[data-testid='refresh-logs']").click();
    await expect($("[data-testid='runner-log-runner.log']")).toBeDisplayed();
    await browser.execute(() => document.querySelector<HTMLElement>("[data-testid='nav-settings']")?.click());
    await $("[data-testid='refresh-paths']").click();
    await expect($("[data-testid='app-paths']")).toHaveText(expect.stringContaining("profiles.toml"));
  });
});
