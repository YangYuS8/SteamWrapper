import { $, expect } from "@wdio/globals";

describe("SteamWrapper Dioxus game library", () => {
  it("scans the isolated local Steam fixture and opens a game configuration dialog", async () => {
    await $("[data-testid='scan-games']").click();
    const game = await $("[data-testid='game-card-123456']");
    await expect(game).toBeDisplayed();
    await expect(game).toHaveText(expect.stringContaining("中文 Test Game"));
    await expect($("[data-testid='game-cover-123456'] img")).toHaveAttribute(
      "src",
      "https://cdn.cloudflare.steamstatic.com/steam/apps/123456/library_600x900.jpg",
    );

    await game.click();
    await expect($("[data-testid='config-dialog']")).toBeDisplayed();
    await expect($("[data-testid='target-path']")).toBeDisplayed();
  });
});
