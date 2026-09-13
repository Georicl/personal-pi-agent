import { Type } from "typebox";
import { execute } from "../runtime.mjs";

export default function(pi) {
  const register = (name, description, parameters, action, guidelines) => pi.registerTool({
    name, label:name.replaceAll("_"," "), description, parameters:Type.Object(parameters),
    promptGuidelines:guidelines,
    async execute(_id,params,_signal,_onUpdate,ctx) {
      try {
        const result = await execute({...params,action,cwd:ctx.cwd,sessionId:ctx.sessionManager.getSessionId?.()});
        return {content:[{type:"text",text:JSON.stringify(result)}],
          details:result.artifact ? {personalPiTextArtifact:result.artifact} : {}};
      } catch(error) { return {content:[{type:"text",text:error.message}],isError:true}; }
    },
  });
  register("workbench_publish_text", "Create a versioned Markdown research output, or save a targeted revision for preview and comparison.", {
    title:Type.String({minLength:1,maxLength:300}), content:Type.String({minLength:1,maxLength:200000}),
    artifactId:Type.Optional(Type.String()), baseVersion:Type.Optional(Type.Integer({minimum:1})),
    baseHash:Type.Optional(Type.String()), sources:Type.Optional(Type.Array(Type.String(),{maxItems:100})),
  },"publish",[
    "Publish requested reports, synthesis and edited text through this tool so they appear in the workbench. Keep ordinary chat answers in chat.",
    "For review references, read the exact base version with workbench_read_text, apply the user's selected changes, and publish with the same artifactId, baseVersion and baseHash. Preserve unrelated text and evidence references.",
    "Sources are actual file paths, source IDs or URLs read during the task; distinguish source facts, analysis results and inference. Never invent citations or statistical results.",
    "A stale-version error requires showing the difference to the user; do not silently replace the base version. Do not overwrite immutable artifact files with generic editing tools.",
  ]);
  register("workbench_read_text", "Read an exact saved text version before revising it.", {
    artifactId:Type.String(), version:Type.Integer({minimum:1}),
  },"read",[]);
  pi.registerCommand("workbench",{
    description:"Create or revise a research text in the workbench",
    async handler(args,ctx) {
      if (!args.trim()) { ctx.ui.notify("Usage: /workbench <report or revision request>","info"); return; }
      pi.sendUserMessage(`Create or revise the requested research text with workbench_publish_text. Use only the evidence and analysis needed for this request. Request: ${args}`,
        ctx.isIdle() ? undefined : {deliverAs:"followUp"});
    },
  });
}
