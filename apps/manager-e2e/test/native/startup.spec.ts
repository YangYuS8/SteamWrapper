import { $, browser, expect } from "@wdio/globals";
import "@wdio/native-types";

describe("Native Mode: SteamWrapper Manager", () => {
  it("启动真实 Manager 并默认显示游戏库", async () => {
    await expect($("[data-testid='manager-root']")).toBeDisplayed();
    await expect($("[data-testid='scan-games']")).toBeDisplayed();
  });

  it("通过 browser.tauri.execute 调用真实 Rust Command", async () => {
    const launchOption = await browser.tauri.execute(({ core }) => core.invoke("generate_launch_option", { appid: "123456" }));
    expect(launchOption).toContain('--appid "123456"');
    expect(launchOption).toContain("-- %command%");
  });
});
