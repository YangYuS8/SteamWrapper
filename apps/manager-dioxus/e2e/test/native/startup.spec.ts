import { $, expect } from "@wdio/globals";
import { join } from "node:path";

describe("SteamWrapper Dioxus Manager", () => {
  it("starts with the player-facing library flow", async () => {
    const root = await $("[data-testid='manager-root']");
    await expect(root).toBeDisplayed();
    await expect($("[data-testid='scan-games']")).toHaveText("Scan local Steam games");
    await expect($("[data-testid='manual-add-game']")).toHaveText("Add game manually");
  });

  it("renders the custom desktop title bar instead of relying on native decorations", async () => {
    await expect($("[data-testid='app-titlebar']")).toBeDisplayed();
    await expect($("[data-testid='window-minimize']")).toBeDisplayed();
    await expect($("[data-testid='window-maximize']")).toBeDisplayed();
    await expect($("[data-testid='window-close']")).toBeDisplayed();
  });

  it("collapses only the sidebar overlay without rebuilding the workspace", async () => {
    const sidebar = await $("[data-testid='sidebar']");
    const toggle = await $("[data-testid='sidebar-toggle']");

    await toggle.click();
    await expect(sidebar).toHaveElementClass("sidebar--collapsed");
    await expect($("[data-testid='scan-games']")).toBeDisplayed();

    await toggle.click();
    await expect(sidebar).not.toHaveElementClass("sidebar--collapsed");
  });

  it("installs the bundled Runner into the stable user-data path on first start", async () => {
    await $("[data-testid='nav-settings']").click();
    const status = await $("[data-testid='runner-status']");
    await expect(status).toHaveText(expect.stringContaining("Installed"));
    const runnerPath = await $("[data-testid='runner-path']");
    const runnerFileName = process.platform === "win32" ? "SteamWrapperRunner.exe" : "steamwrapper-runner";
    await expect(runnerPath).toHaveText(expect.stringContaining(join("SteamWrapper", "bin", runnerFileName)));
  });
});
