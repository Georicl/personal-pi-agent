import { writeFileSync } from "node:fs";
import workbench from "../../Resources/PiPackages/Workbench/extensions/index.js";

export default function(pi) {
  const tools = new Map();
  workbench(new Proxy(pi,{get(target,key) {
    if(key === "registerTool") return tool => { tools.set(tool.name,tool); target.registerTool(tool); };
    return target[key];
  }}));
  pi.registerCommand("__personal_pi_test_workbench",{
    description:"Offline Workbench test fixture",
    async handler(_args,ctx) {
      const publish=tools.get("workbench_publish_text"), read=tools.get("workbench_read_text");
      const first=await publish.execute("one",{title:"Fixture",content:"# Result\nOriginal evidence."},undefined,undefined,ctx);
      const artifact=first.details.personalPiTextArtifact;
      const loaded=await read.execute("read",{artifactId:artifact.artifactId,version:1},undefined,undefined,ctx);
      const revised=await publish.execute("two",{title:"Fixture",content:"# Result\nRevised wording.",
        artifactId:artifact.artifactId,baseVersion:1,baseHash:artifact.contentHash},undefined,undefined,ctx);
      writeFileSync(process.env.PERSONAL_PI_WORKBENCH_TEST_RESULT,JSON.stringify({first,loaded,revised}));
    },
  });
}
