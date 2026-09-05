import { existsSync } from "node:fs";
import path from "node:path";

// Loaded only by the opt-in native RPC test in an isolated Pi data directory.
export default function (pi) {
  pi.on("session_before_switch", async (_event, ctx) => {
    if (existsSync(path.join(process.env.PERSONAL_PI_DATA_ROOT, "veto-next"))) {
      return { cancel: true };
    }
    if (existsSync(path.join(process.env.PERSONAL_PI_DATA_ROOT, "ask-next"))) {
      return { cancel: !(await ctx.ui.confirm("Switch session?", "Native hook regression")) };
    }
  });
  pi.registerCommand("__workflow_context", {
    description: "Report actual native runtime and session cwd without a model call",
    handler: async (_args, ctx) => {
      ctx.ui.notify(JSON.stringify({ cwd: ctx.cwd, sessionCwd: ctx.sessionManager.getCwd() }), "info");
    },
  });
}
