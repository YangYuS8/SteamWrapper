import { $, browser, expect } from "@wdio/globals";

const game = { appid: "123456", name: "中文 Test Game", install_dir: "C:\\Steam Library\\common\\中文 Test Game", cover_path: null };
const dialogStatus = () => $("[data-testid='config-dialog'] [data-testid='status-text']");

describe("Browser Mode: 配置", () => {
  async function openFixtureGame() {
    const scan = await browser.tauri.mock("scan_local_steam_games_command");
    await scan.mockResolvedValue([game]);
    const scanButton = $("[data-testid='scan-games']");
    await scanButton.waitForClickable();
    await scanButton.click();
    const card = $("[data-testid='game-card-123456']");
    await card.waitForClickable();
    await card.click();
    await $("[data-testid='config-dialog']").waitForDisplayed();
  }

  beforeEach(async () => {
    const dialog = $("[data-testid='config-dialog']");
    if (await dialog.isExisting()) await $("[data-testid='config-dialog'] button").click();
  });

  it("未填写目标程序时禁止保存", async () => {
    await openFixtureGame();
    await $("[data-testid='save-profile']").click();
    await expect(dialogStatus()).toHaveText(expect.stringContaining("请填写"));
  });

  it("保存时传递准确参数并显示启动选项", async () => {
    await openFixtureGame();
    const save = await browser.tauri.mock("save_profile");
    const launchOption = await browser.tauri.mock("generate_launch_option");
    const profiles = await browser.tauri.mock("list_profiles");
    await save.mockResolvedValue(undefined);
    await launchOption.mockResolvedValue('"C:\\Test\\SteamWrapperRunner.exe" --appid "123456" -- %command%');
    await profiles.mockResolvedValue([]);
    await $("[data-testid='target-path']").setValue("C:\\Steam Library\\common\\中文 Test Game\\launcher.exe");
    await $("[data-testid='save-profile']").click();
    await expect($("[data-testid='launch-option']")).toHaveValue(expect.stringContaining('--appid "123456"'));
    await expect(dialogStatus()).toHaveText("配置已保存");
    await save.update();
    expect(save).toHaveBeenCalledWith({ request: { appid: "123456", name: "中文 Test Game", game_dir: "C:\\Steam Library\\common\\中文 Test Game", target: "C:\\Steam Library\\common\\中文 Test Game\\launcher.exe" } }, null);
  });

  it("保存失败会显示错误而非静默失败", async () => {
    await openFixtureGame();
    const save = await browser.tauri.mock("save_profile");
    await save.mockRejectedValue(new Error("fixture save failed"));
    await $("[data-testid='target-path']").setValue("C:\\fixture.exe");
    await $("[data-testid='save-profile']").click();
    await expect(dialogStatus()).toHaveText(expect.stringContaining("保存失败"));
  });

  it("Runner 不可用时保存配置会明确提示，不伪造可用启动选项", async () => {
    await openFixtureGame();
    const save = await browser.tauri.mock("save_profile");
    const launchOption = await browser.tauri.mock("generate_launch_option");
    const profiles = await browser.tauri.mock("list_profiles");
    await save.mockResolvedValue(undefined);
    await launchOption.mockRejectedValue(new Error("Runner 尚未安装"));
    await profiles.mockResolvedValue([]);

    await $("[data-testid='target-path']").setValue("C:\\fixture.exe");
    await $("[data-testid='save-profile']").click();

    await expect(dialogStatus()).toHaveText(expect.stringContaining("Runner 尚不可用"));
    await expect($("[data-testid='launch-option']")).toHaveValue("");
  });
});
