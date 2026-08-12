import { $, expect } from "@wdio/globals";

describe("SteamWrapper Dioxus profiles", () => {
  it("saves a selected target without changing the launch-options protocol", async () => {
    await $("[data-testid='scan-games']").click();
    await $("[data-testid='game-card-123456']").click();
    const target = await $("[data-testid='target-path']");
    await target.setValue("/fixture/Steam/steamapps/common/中文 Test Game/launcher.sh");
    await $("[data-testid='save-profile']").click();

    const launchOption = await $("[data-testid='launch-option']");
    await expect(launchOption).toHaveValue(expect.stringContaining('--appid "123456" -- %command%'));
  });
});
