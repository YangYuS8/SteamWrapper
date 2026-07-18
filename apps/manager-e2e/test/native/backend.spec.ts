import { $, browser, expect } from "@wdio/globals";
import { readFile } from "node:fs/promises";
import "@wdio/native-types";

describe("Native Mode: 隔离数据目录", () => {
  it("返回隔离路径、写入 Profile 并重新读取", async () => {
    const paths = await browser.tauri.execute(({ core }) => core.invoke("get_app_paths")) as Record<string, string>;
    expect(paths.app_data_dir).toContain("SteamWrapper");
    expect(paths.profiles_path).toContain("profiles.toml");
    expect(paths.logs_dir).toContain("logs");
    expect(paths.runner_path).toMatch(
      process.platform === "win32"
        ? /SteamWrapperRunner\.exe$/
        : /steamwrapper-runner$/,
    );

    await browser.tauri.execute(({ core }) => core.invoke("save_profile", {
      request: {
        appid: "654321",
        name: "Direct Command Game",
        game_dir: "C:\\Steam Library\\common\\中文 Test Game",
        target: "C:\\Steam Library\\common\\中文 Test Game\\launcher.exe",
      },
    }));
    const profiles = await browser.tauri.execute(({ core }) => core.invoke("list_profiles")) as Array<Record<string, string>>;
    expect(profiles).toEqual(expect.arrayContaining([expect.objectContaining({ appid: "654321", name: "Direct Command Game" })]));

    const profilesToml = await readFile(paths.profiles_path, "utf8");
    expect(profilesToml).toContain("654321");
    expect(profilesToml).toContain("Direct Command Game");
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
