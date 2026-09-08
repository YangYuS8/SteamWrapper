import { $, expect } from "@wdio/globals";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

describe("Language preference across native process restarts", () => {
  it("uses the preference stored by the previous Manager process", async () => {
    const root = process.env.STEAMWRAPPER_E2E_ROOT;
    if (!root) throw new Error("A disposable E2E fixture is required");
    const data = join(root, process.platform === "win32" ? "local-app-data" : "xdg-data", "SteamWrapper");
    const profilesBefore = await readFile(join(data, "profiles.toml"));
    if (process.env.STEAMWRAPPER_E2E_LANGUAGE_PHASE === "save") {
      await expect($("[data-testid='scan-games']")).toHaveText("Scan local Steam games");
      await $("[data-testid='language-zh']").click();
      await expect($("[data-testid='scan-games']")).toHaveText("扫描本地 Steam 游戏");
    } else {
      await expect($("[data-testid='language-zh']")).toHaveAttribute("aria-pressed", "true");
      await expect($("[data-testid='scan-games']")).toHaveText("扫描本地 Steam 游戏");
      await expect($("[data-testid='window-minimize']")).toHaveAttribute("aria-label", "最小化窗口");
      await $("[data-testid='language-en']").click();
      await expect($("[data-testid='scan-games']")).toHaveText("Scan local Steam games");
    }
    expect(await readFile(join(data, "profiles.toml"))).toEqual(profilesBefore);
    const expected = process.env.STEAMWRAPPER_E2E_LANGUAGE_PHASE === "save" ? "zh-CN" : "en-US";
    expect(JSON.parse(await readFile(join(data, "ui-settings.json"), "utf8")).language).toBe(expected);
  });
});
