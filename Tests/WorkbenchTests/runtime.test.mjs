import { test } from "node:test";
import assert from "node:assert/strict";
import { promises as fs } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execute } from "../../Resources/PiPackages/Workbench/runtime.mjs";

test("text import, targeted revision and restart preserve original and source references", async () => {
  const cwd = await fs.mkdtemp(join(tmpdir(),"pi-workbench-"));
  try {
    const original = join(cwd,"notes.md");
    await fs.writeFile(original,"# 结果\n样本量为 12。\n");
    const first = (await execute({action:"import",cwd,path:original})).artifact;
    const second = (await execute({action:"publish",cwd,artifactId:first.artifactId,baseVersion:1,
      baseHash:first.contentHash,title:first.title,content:"# 结果\n共纳入 12 个样本。\n"})).artifact;
    assert.equal(second.version,2);
    assert.equal(second.parentVersion,1);
    assert.deepEqual(second.sources,[original]);
    assert.equal(await fs.readFile(original,"utf8"),"# 结果\n样本量为 12。\n");
    assert.equal((await execute({action:"read",cwd,artifactId:first.artifactId,version:1})).content,"# 结果\n样本量为 12。\n");
    assert.equal((await execute({action:"list",cwd})).artifacts.length,2);
    await assert.rejects(execute({action:"publish",cwd,artifactId:first.artifactId,baseVersion:1,
      baseHash:first.contentHash,title:"stale",content:"wrong"}),/Stale revision/);
    await assert.rejects(execute({action:"publish",cwd,artifactId:first.artifactId,baseVersion:2,
      baseHash:first.contentHash,title:"wrong hash",content:"wrong"}),/does not match/);
  } finally { await fs.rm(cwd,{recursive:true,force:true}); }
});

test("concurrent edits have one winner and retain an intact base",async () => {
  const cwd = await fs.mkdtemp(join(tmpdir(),"pi-workbench-"));
  try {
    const first = (await execute({action:"publish",cwd,title:"A",content:"base"})).artifact;
    const results = await Promise.allSettled(["left","right"].map(content => execute({action:"publish",cwd,
      artifactId:first.artifactId,baseVersion:1,baseHash:first.contentHash,title:"A",content})));
    assert.equal(results.filter(x => x.status==="fulfilled").length,1);
    assert.equal((await execute({action:"list",cwd})).artifacts.length,2);
    assert.equal((await execute({action:"read",cwd,artifactId:first.artifactId,version:1})).content,"base");
  } finally { await fs.rm(cwd,{recursive:true,force:true}); }
});

test("modified files and cross-project or symlink references cannot become a revision base",async () => {
  const cwd = await fs.mkdtemp(join(tmpdir(),"pi-workbench-"));
  try {
    const a=join(cwd,"a"),b=join(cwd,"b"); await fs.mkdir(a);await fs.mkdir(b);
    assert.deepEqual(await execute({action:"list",cwd:a}),{artifacts:[]});
    assert.deepEqual(await fs.readdir(a),[]);
    const first=(await execute({action:"publish",cwd:a,title:"A",content:"base"})).artifact;
    await assert.rejects(execute({action:"read",cwd:b,artifactId:first.artifactId,version:1}));
    await fs.writeFile(first.sourcePath,"external change");
    await assert.rejects(execute({action:"read",cwd:a,artifactId:first.artifactId,version:1}),/changed on disk/);
    await assert.rejects(execute({action:"publish",cwd:a,artifactId:"../escape",title:"A",content:"bad"}),/Invalid artifact/);
    const link=join(cwd,"link");await fs.mkdir(link);await fs.symlink(join(a,".pi"),join(link,".pi"));
    await assert.rejects(execute({action:"list",cwd:link}),/symlinks/);
  } finally { await fs.rm(cwd,{recursive:true,force:true}); }
});
