import { launcher as DioxusLauncher } from "@wdio/dioxus-service";

export { default } from "@wdio/dioxus-service";

export class launcher extends DioxusLauncher {
  async onPrepare(...args) {
    try {
      await super.onPrepare(...args);
    } catch (error) {
      // WDIO skips onComplete when onPrepare fails. The pinned service flushes
      // its app stdout/stderr writer there, so finish it before WDIO exits.
      try {
        await super.onComplete();
      } catch (cleanupError) {
        console.error("Dioxus startup cleanup failed:", cleanupError);
      }
      throw error;
    }
  }
}
