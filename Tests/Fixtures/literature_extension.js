import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import registerLiterature from "../../Resources/PiPackages/Literature/extensions/index.js";

// Only loaded by the isolated offline test. Calls the actual registered tool
// handlers with Pi's real context; no model credentials or production hooks.
export default function (pi) {
  const handlers = new Map();
  registerLiterature({ registerTool: (tool) => handlers.set(tool.name, tool), registerCommand: () => {} });
  pi.registerCommand("__literature_test", {
    description: "Isolated Literature integration test",
    handler: async (_args, ctx) => {
      const invoke = (name, params) => handlers.get(name).execute("test", params, undefined, undefined, ctx);
      const snapshot = JSON.parse(readFileSync(join(ctx.cwd, "search-fixture.json"), "utf8"));
      const plan = await invoke("literature_plan", { question: "CD4 cells", query: '"T cell" AND CD4', limit: 10 });
      const saved = await invoke("literature_save", { runId: snapshot.runId, recordIds: snapshot.records.map((r) => r.id) });
      const sources = saved.details?.personalPiLiterature?.result?.saved ?? [];
      const draft = await invoke("literature_draft", { title: "Offline tool draft", content: "Fixture synthesis; not a research claim.", sourceIds: sources.map((s) => s.sourceId) });
      writeFileSync(join(ctx.cwd, "native-result.json"), JSON.stringify({ plan, saved, draft }));
      ctx.ui.notify("Literature native tool integration completed", "info");
    },
  });
}
