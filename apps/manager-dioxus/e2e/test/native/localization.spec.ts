import { $, browser, expect } from "@wdio/globals";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

function settingsPath() {
  const root = process.env.STEAMWRAPPER_E2E_ROOT;
  if (!root) throw new Error("Language tests require the disposable E2E fixture");
  return join(root, process.platform === "win32" ? "local-app-data" : "xdg-data", "SteamWrapper", "ui-settings.json");
}

describe("SteamWrapper bilingual interface", () => {
  afterEach(async () => {
    const close = await $("[data-testid='close-config']");
    if (await close.isExisting()) await close.click();
    await $("[data-testid='language-en']").click();
    await $("[data-testid='nav-library']").click();
  });

  it("switches navigation, existing status, validation, placeholders and accessible names", async () => {
    await $("[data-testid='nav-library']").click();
    await expect($("[data-testid='language-en']")).toHaveAttribute("aria-pressed", "true");
    await $("[data-testid='scan-games']").click();
    await expect($("[data-testid='status-text']")).toHaveText("Found 1 local Steam game(s)");
    await $("[data-testid='language-zh']").click();
    await expect($("[data-testid='manager-root']")).toHaveAttribute("lang", "zh-CN");
    await expect($("[data-testid='language-picker']")).toHaveAttribute("aria-label", "语言");
    await expect($("[data-testid='status-text']")).toHaveText("已找到 1 个本地 Steam 游戏");
    await expect($("[data-testid='nav-configured']")).toHaveText(expect.stringContaining("已配置游戏"));
    await expect($("[data-testid='window-close']")).toHaveAttribute("aria-label", "关闭窗口");
    await expect($("[data-testid='sidebar-toggle']")).toHaveAttribute("aria-label", "折叠侧边栏");
    await expect($("[data-testid='game-card-123456']")).toHaveText(expect.stringContaining("中文 Test Game"));
    const cover = await $("[data-testid='game-cover-123456'] img");
    if (await cover.isExisting()) {
      await expect(cover).toHaveAttribute("alt", "中文 Test Game 的封面");
      await browser.execute(() => document.querySelector("[data-testid='game-cover-123456'] img")?.dispatchEvent(new Event("error")));
    }
    await expect($("[data-testid='game-cover-123456']")).toHaveText(expect.stringContaining("封面暂不可用"));
    await $("[data-testid='game-card-123456']").click();
    await expect($("[data-testid='target-path']")).toHaveAttribute("placeholder", "例如 Game_CHS.exe 或 launcher.exe");
    await expect($("[data-testid='target-path']")).toHaveAttribute("aria-label", "真正要启动的程序");
    await expect($("[data-testid='save-profile']")).toHaveText("保存并生成启动选项");
    await $("[data-testid='save-profile']").click();
    await expect($("[data-testid='status-text']")).toHaveText("请填写真正要启动的 exe 或 launcher 路径");
    await $("[data-testid='close-config']").click();
    await $("[data-testid='language-en']").click();
    await expect($("[data-testid='status-text']")).toHaveText("Enter the path to the executable or launcher to start");
    await expect($("[data-testid='window-close']")).toHaveAttribute("aria-label", "Close window");
    await $("[data-testid='language-zh']").click();
    await $("[data-testid='nav-settings']").click();
    await expect($("[data-testid='runner-status']")).toHaveText("Runner 状态： 已安装");
    await expect($("[data-testid='refresh-paths']")).toHaveText("刷新路径");
    await $("[data-testid='nav-logs']").click();
    await expect($(".panel-header h1")).toHaveText("日志");
    await expect($("[data-testid='refresh-logs']")).toHaveText("刷新");
  });

  it("preserves malformed settings and keeps the selected language when saving fails", async () => {
    const path = settingsPath();
    const original = await readFile(path);
    const malformed = "{broken settings";
    try {
      await writeFile(path, malformed);
      await $("[data-testid='language-zh']").click();
      await expect($("[data-testid='language-error']")).toHaveText(expect.stringContaining("not a valid JSON object"));
      await expect($("[data-testid='manager-root']")).toHaveAttribute("lang", "en-US");
      await expect($("[data-testid='language-en']")).toHaveAttribute("aria-pressed", "true");
      expect(await readFile(path, "utf8")).toBe(malformed);
    } finally {
      await writeFile(path, original);
    }
  });
});
