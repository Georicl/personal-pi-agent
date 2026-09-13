import { promises as fs } from "node:fs";
import { resolve, join, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash, randomUUID } from "node:crypto";

const MAX_BYTES = 200000;
const digest = text => createHash("sha256").update(text).digest("hex");
const identifier = value => {
  if (typeof value !== "string" || !/^[a-zA-Z0-9_-]{1,100}$/.test(value)) throw new Error("Invalid artifact ID");
  return value;
};
async function rootFor(cwd) {
  const canonical = await fs.realpath(cwd);
  const root = join(canonical, ".pi", "artifacts", "texts");
  // Each directory remains inside this project, including existing symlinks.
  let cursor = canonical;
  for (const part of [".pi", "artifacts", "texts"]) {
    cursor = join(cursor, part);
    await fs.mkdir(cursor, { recursive: true });
    if (await fs.realpath(cursor) !== cursor) throw new Error("Artifact directories must not be symlinks");
  }
  return { cwd: canonical, root };
}
async function versions(root, id) {
  let entries;
  try { entries = await fs.readdir(join(root, identifier(id))); }
  catch (error) { if (error.code === "ENOENT") return []; throw error; }
  return entries.filter(x => /^v\d{6}$/.test(x)).map(x => Number(x.slice(1))).sort((a,b) => a-b);
}
async function readVersion(root, id, version) {
  if (!Number.isInteger(version) || version < 1 || version > 999999) throw new Error("Invalid version");
  const dir = join(root, identifier(id), `v${String(version).padStart(6,"0")}`);
  if (await fs.realpath(dir) !== dir) throw new Error("Artifact version must not be a symlink");
  const artifact = JSON.parse(await fs.readFile(join(dir,"artifact.json"),"utf8"));
  const sourcePath = join(dir,"document.md");
  if (await fs.realpath(sourcePath) !== sourcePath) throw new Error("Artifact source must not be a symlink");
  const content = await fs.readFile(sourcePath,"utf8");
  if (digest(content) !== artifact.contentHash) throw new Error("Artifact changed on disk; import it as a new document before reviewing");
  return { artifact: { ...artifact, sourcePath }, content };
}

export async function execute(request) {
  if (request.action === "list") {
    try { await fs.access(join(request.cwd,".pi","artifacts","texts")); }
    catch (error) { if (error.code === "ENOENT") return {artifacts:[]}; throw error; }
  }
  const { cwd, root } = await rootFor(request.cwd);
  if (request.action === "list") {
    const artifacts = [];
    for (const entry of await fs.readdir(root, { withFileTypes: true })) {
      if (!entry.isDirectory() || !/^[a-zA-Z0-9_-]{1,100}$/.test(entry.name)) continue;
      for (const version of await versions(root, entry.name)) {
        artifacts.push((await readVersion(root,entry.name,version)).artifact);
      }
    }
    return { artifacts };
  }
  if (request.action === "read") return readVersion(root,request.artifactId,request.version);
  if (!["publish","import"].includes(request.action)) throw new Error("Unknown workbench action");
  let content = request.content;
  let title = request.title;
  let sources = request.sources ?? [];
  if (request.action === "import") {
    const path = resolve(cwd, request.path);
    if (!/\.(md|markdown|txt)$/i.test(path)) throw new Error("Choose a Markdown or TXT file");
    if ((await fs.stat(path)).size > MAX_BYTES) throw new Error("Text preview supports files up to 200 KB");
    content = await fs.readFile(path,"utf8");
    title = basename(path);
    sources = [path];
  }
  if (typeof content !== "string" || !content.trim() || Buffer.byteLength(content) > MAX_BYTES) throw new Error("Text must contain 1–200,000 UTF-8 bytes");
  if (typeof title !== "string" || !title.trim() || title.length > 300) throw new Error("A title of 1–300 characters is required");
  if (!Array.isArray(sources) || sources.length > 100 || sources.some(x => typeof x !== "string" || x.length > 2000)) throw new Error("Invalid source references");
  const id = identifier(request.artifactId ?? randomUUID());
  const series = join(root,id);
  await fs.mkdir(series,{recursive:true});
  if (await fs.realpath(series) !== series) throw new Error("Artifact series must not be a symlink");
  const lock = join(series,".writing");
  try { await fs.mkdir(lock); }
  catch (error) { if (error.code === "EEXIST") throw new Error("Another revision is being saved; retry after it finishes"); throw error; }
  let temporary;
  try {
    const existing = await versions(root,id);
    const latest = existing.at(-1) ?? 0;
    if (latest && request.baseVersion !== latest) throw new Error(`Stale revision: latest is v${latest}; review that version before revising`);
    if (!latest && request.baseVersion != null) throw new Error("The base version does not exist");
    if (latest) {
      const previous = await readVersion(root,id,latest);
      if (request.baseHash !== previous.artifact.contentHash) throw new Error("The reviewed content does not match the base version");
      if (request.sources == null) sources = previous.artifact.sources;
    }
    const version = latest + 1;
    if (version > 999999) throw new Error("Version limit reached");
    const destination = join(series,`v${String(version).padStart(6,"0")}`);
    temporary = join(series,`.draft-${randomUUID()}`);
    await fs.mkdir(temporary);
    const artifact = {
      schemaVersion:1, kind:"text", id:`${id}-v${version}`, artifactId:id, version,
      parentVersion: latest || null, title:title.trim(), cwd, sessionId:request.sessionId ?? null,
      createdAt:new Date().toISOString(), sourcePath:join(destination,"document.md"),
      contentHash:digest(content), sources,
    };
    await fs.writeFile(join(temporary,"document.md"),content,{flag:"wx"});
    await fs.writeFile(join(temporary,"artifact.json"),JSON.stringify(artifact,null,2)+"\n",{flag:"wx"});
    await fs.rename(temporary,destination);
    temporary = undefined;
    return { artifact };
  } finally {
    if (temporary) await fs.rm(temporary,{recursive:true,force:true});
    await fs.rmdir(lock);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  let input = "";
  for await (const chunk of process.stdin) input += chunk;
  try { process.stdout.write(JSON.stringify({success:true,...await execute(JSON.parse(input))})+"\n"); }
  catch (error) { process.stdout.write(JSON.stringify({success:false,error:error.message})+"\n"); process.exitCode = 1; }
}
