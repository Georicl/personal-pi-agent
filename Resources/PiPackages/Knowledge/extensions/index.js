import { spawn } from "node:child_process";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Type } from "typebox";

const extensionRoot = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(extensionRoot, "..");
const runtimeRoot = join(packageRoot, "runtime");
const runnerPath = join(runtimeRoot, "knowledge_core.py");
const bundledProjectPath = join(runtimeRoot, "pyproject.toml");
const bundledLockPath = join(runtimeRoot, "uv.lock");
const MAX_OUTPUT_BYTES = 8 * 1024 * 1024;
let environmentReady;

function enumSchema(values, options = {}) {
  return Type.Union(values.map((value) => Type.Literal(value)), options);
}

function appendBounded(chunks, chunk, currentBytes) {
  if (currentBytes >= MAX_OUTPUT_BYTES) return currentBytes;
  const remaining = MAX_OUTPUT_BYTES - currentBytes;
  const bounded = chunk.length > remaining ? chunk.subarray(0, remaining) : chunk;
  chunks.push(bounded);
  return currentBytes + bounded.length;
}

function runProcess(command, args, input, options = {}) {
  return new Promise((resolvePromise, rejectPromise) => {
    const child = spawn(command, args, {
      cwd: options.cwd,
      env: options.env ?? process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    const stdout = [];
    const stderr = [];
    let stdoutBytes = 0;
    let stderrBytes = 0;
    let settled = false;
    let timer;
    const finish = (callback) => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      options.signal?.removeEventListener("abort", abort);
      callback();
    };
    const abort = () => {
      child.kill("SIGTERM");
      setTimeout(() => child.kill("SIGKILL"), 1500).unref();
    };
    timer = setTimeout(() => {
      abort();
      finish(() => rejectPromise(new Error("Knowledge operation timed out")));
    }, options.timeoutMs ?? 300000);
    if (options.signal?.aborted) {
      abort();
      finish(() => rejectPromise(new Error("Operation aborted")));
      return;
    }
    options.signal?.addEventListener("abort", abort, { once: true });
    child.stdout.on("data", (chunk) => {
      stdoutBytes = appendBounded(stdout, chunk, stdoutBytes);
    });
    child.stderr.on("data", (chunk) => {
      stderrBytes = appendBounded(stderr, chunk, stderrBytes);
    });
    child.once("error", (error) => finish(() => rejectPromise(error)));
    child.once("close", (code) => {
      finish(() => resolvePromise({
        code,
        stdout: Buffer.concat(stdout).toString("utf8"),
        stderr: Buffer.concat(stderr).toString("utf8"),
      }));
    });
    child.stdin.end(input ?? "");
  });
}

function copyIfChanged(source, destination) {
  const sourceData = readFileSync(source);
  if (existsSync(destination) && sourceData.equals(readFileSync(destination))) return;
  copyFileSync(source, destination);
}

function resolvedPiRoot() {
  if (process.env.PERSONAL_PI_DATA_ROOT?.trim()) {
    return expandedRuntimePath(process.env.PERSONAL_PI_DATA_ROOT);
  }
  const agentDirectory = expandedRuntimePath(
    process.env.PI_CODING_AGENT_DIR?.trim() || join(homedir(), ".pi", "agent"),
  );
  return dirname(agentDirectory);
}

function expandedRuntimePath(value) {
  const path = value.trim();
  return resolve(path === "~" ? homedir() : path.startsWith("~/") ? join(homedir(), path.slice(2)) : path);
}

async function managedPython(cwd, signal, onUpdate) {
  const agentDirectory = expandedRuntimePath(
    process.env.PI_CODING_AGENT_DIR?.trim() || join(resolvedPiRoot(), "agent"),
  );
  const environmentRoot = expandedRuntimePath(
    process.env.PERSONAL_PI_KNOWLEDGE_ENVIRONMENT?.trim() ||
      join(agentDirectory, "environments", "knowledge"),
  );
  mkdirSync(environmentRoot, { recursive: true });
  copyIfChanged(bundledProjectPath, join(environmentRoot, "pyproject.toml"));
  copyIfChanged(bundledLockPath, join(environmentRoot, "uv.lock"));
  if (!environmentReady) {
    environmentReady = (async () => {
      onUpdate?.({
        content: [{ type: "text", text: "Preparing the locked knowledge environment…" }],
      });
      const result = await runProcess(
        process.env.PERSONAL_PI_UV_EXECUTABLE || "uv",
        ["sync", "--project", environmentRoot, "--locked", "--no-progress"],
        undefined,
        {
          cwd,
          signal,
          timeoutMs: 600000,
          env: { ...process.env, UV_NO_PROGRESS: "1", UV_PROJECT_ENVIRONMENT: join(environmentRoot, ".venv") },
        },
      );
      if (result.code !== 0) {
        throw new Error(result.stderr.trim() || result.stdout.trim() || "uv sync failed");
      }
      return join(environmentRoot, ".venv", "bin", "python");
    })().catch((error) => {
      environmentReady = undefined;
      throw error;
    });
  }
  return environmentReady;
}

function parseRunnerOutput(result) {
  const lines = result.stdout.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    try {
      return JSON.parse(lines[index]);
    } catch {
      // Continue to the previous line.
    }
  }
  throw new Error(result.stderr.trim() || result.stdout.trim() || "Knowledge runner failed");
}

async function runCore(ctx, request, signal, onUpdate) {
  if (![runnerPath, bundledProjectPath, bundledLockPath].every(existsSync)) {
    throw new Error("Knowledge plugin runtime resources are incomplete");
  }
  const python = await managedPython(ctx.cwd, signal, onUpdate);
  const result = await runProcess(
    python,
    [runnerPath],
    JSON.stringify({ ...request, piRoot: resolvedPiRoot() }),
    {
      cwd: ctx.cwd,
      signal,
      env: { ...process.env, PYTHONUNBUFFERED: "1" },
    },
  );
  const payload = parseRunnerOutput(result);
  if (!payload.success) throw new Error(payload.error || "Knowledge runner failed");
  return payload;
}

function isGlobalChat(cwd) {
  return resolve(cwd) === resolve(resolvedPiRoot(), "chat");
}

function scopesFor(selection, ctx) {
  const global = { kind: "global" };
  const project = { kind: "project", projectRoot: ctx.cwd };
  if (selection === "global" || (selection === "current" && isGlobalChat(ctx.cwd))) {
    return [global];
  }
  if (selection === "project" || selection === "current") {
    if (isGlobalChat(ctx.cwd)) throw new Error("Project knowledge is unavailable in Global Chat");
    return [project];
  }
  return isGlobalChat(ctx.cwd) ? [global] : [project, global];
}

function scopeSchema(defaultDescription) {
  return Type.Optional(enumSchema(["current", "global", "project", "both"], {
    description: defaultDescription,
  }));
}

async function runForScopes(ctx, action, selection, options, signal, onUpdate) {
  const results = [];
  for (const scope of scopesFor(selection ?? "current", ctx)) {
    results.push(await runCore(ctx, { action, scope, ...options }, signal, onUpdate));
  }
  return results;
}

function toolFailure(error) {
  return {
    content: [{ type: "text", text: error instanceof Error ? error.message : String(error) }],
    details: {},
    isError: true,
  };
}

function modelJson(value, maxCharacters = 120000) {
  const text = JSON.stringify(value, null, 2);
  if (text.length <= maxCharacters) return text;
  return `${text.slice(0, maxCharacters)}\n\n[Knowledge output truncated; narrow the query or read a more specific document.]`;
}

function scopeSummary(result) {
  const name = result.scope.kind === "project" ? "Project" : "Global";
  if (result.fileCount !== undefined) {
    return `${name}: ${result.fileCount} files, ${result.totalBytes} bytes`;
  }
  const counts = result.counts ?? {};
  return `${name}: ${counts.documents ?? 0} documents, ${counts.chunks ?? 0} chunks, ${counts.errors ?? 0} errors`;
}

function sendWorkflow(pi, ctx, request) {
  if (ctx.isIdle()) pi.sendUserMessage(request);
  else pi.sendUserMessage(request, { deliverAs: "followUp" });
}

export default function knowledgeExtension(pi) {
  pi.registerCommand("knowledge", {
    description: "Search, index, inspect, or capture Personal Pi knowledge",
    handler: async (args, ctx) => {
      const [action = "status", ...rest] = args.trim().split(/\s+/).filter(Boolean);
      if (["search", "capture"].includes(action)) {
        const request = rest.join(" ").trim();
        if (!request) {
          ctx.ui.notify(`Usage: /knowledge ${action} <request>`, "warning");
          return;
        }
        sendWorkflow(
          pi,
          ctx,
          action === "search"
            ? `Search Personal Pi knowledge for: ${request}\nUse knowledge_search and cite each returned locator.`
            : `Capture this as durable Personal Pi knowledge: ${request}\nUse knowledge_capture to create a draft or source record with provenance.`,
        );
        return;
      }
      const selection = ["global", "project", "both", "current"].includes(rest[0])
        ? rest[0]
        : "current";
      if (!["status", "inventory", "index", "rebuild"].includes(action)) {
        ctx.ui.notify(
          "Usage: /knowledge [status|inventory|index|rebuild|search|capture]",
          "warning",
        );
        return;
      }
      try {
        const results = await runForScopes(
          ctx,
          action === "rebuild" ? "rebuild" : action,
          selection,
          {},
        );
        ctx.ui.notify(results.map(scopeSummary).join("\n"), "info");
      } catch (error) {
        ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
      }
    },
  });

  pi.registerCommand("__personal_pi_knowledge", {
    description: "Internal Personal Pi knowledge runtime check",
    handler: async (args, ctx) => {
      const encoded = args.trim();
      if (!encoded) return;
      let request;
      try {
        request = JSON.parse(Buffer.from(encoded, "base64").toString("utf8"));
      } catch {
        throw new Error("Invalid knowledge runtime check payload");
      }
      if (typeof request.responsePath !== "string" || !isAbsolute(request.responsePath)) {
        throw new Error("Knowledge runtime check requires an absolute response path");
      }
      try {
        const sourceRoot = join(ctx.cwd, ".pi", "knowledge", "sources");
        mkdirSync(sourceRoot, { recursive: true });
        writeFileSync(
          join(sourceRoot, "runtime-smoke.md"),
          "# Runtime smoke\n\nKnowledge extension preserves exact locators.",
          "utf8",
        );
        const [indexed] = await runForScopes(ctx, "index", "project", {});
        const searched = await runCore(ctx, {
          action: "search",
          query: "exact locators",
          scopes: scopesFor("project", ctx),
        });
        const [inventory] = await runForScopes(ctx, "inventory", "project", {});
        writeFileSync(
          request.responsePath,
          JSON.stringify({ success: true, indexed, searched, inventory }),
          "utf8",
        );
      } catch (error) {
        writeFileSync(
          request.responsePath,
          JSON.stringify({
            success: false,
            error: error instanceof Error ? error.message : String(error),
          }),
          "utf8",
        );
      }
    },
  });

  pi.registerTool({
    name: "knowledge_status",
    label: "Knowledge status",
    description: "Report initialization, indexed document, chunk, and error counts for knowledge scopes.",
    parameters: Type.Object({ scope: scopeSchema("Defaults to the current scope") }),
    async execute(_id, params, signal, onUpdate, ctx) {
      try {
        const results = await runForScopes(ctx, "status", params.scope, {}, signal, onUpdate);
        return {
          content: [{ type: "text", text: results.map(scopeSummary).join("\n") }],
          details: { personalPiKnowledgeStatus: results },
        };
      } catch (error) {
        return toolFailure(error);
      }
    },
  });

  pi.registerTool({
    name: "knowledge_inventory",
    label: "Knowledge inventory",
    description: "List knowledge files, categories, total bytes, support, and index state.",
    parameters: Type.Object({
      scope: scopeSchema("Defaults to the current scope"),
      limit: Type.Optional(Type.Integer({ minimum: 1, maximum: 5000 })),
    }),
    async execute(_id, params, signal, onUpdate, ctx) {
      try {
        const results = await runForScopes(
          ctx,
          "inventory",
          params.scope,
          { limit: params.limit ?? 500 },
          signal,
          onUpdate,
        );
        return {
          content: [{ type: "text", text: modelJson(results) }],
          details: { personalPiKnowledgeInventory: results },
        };
      } catch (error) {
        return toolFailure(error);
      }
    },
  });

  pi.registerTool({
    name: "knowledge_index",
    label: "Index knowledge",
    description: "Incrementally index or rebuild Global and Project knowledge from authoritative files.",
    parameters: Type.Object({
      scope: scopeSchema("Defaults to the current scope"),
      rebuild: Type.Optional(Type.Boolean()),
    }),
    async execute(_id, params, signal, onUpdate, ctx) {
      try {
        const results = await runForScopes(
          ctx,
          params.rebuild ? "rebuild" : "index",
          params.scope,
          {},
          signal,
          onUpdate,
        );
        return {
          content: [{ type: "text", text: modelJson(results) }],
          details: { personalPiKnowledgeIndex: results },
        };
      } catch (error) {
        return toolFailure(error);
      }
    },
  });

  pi.registerTool({
    name: "knowledge_search",
    label: "Search knowledge",
    description: "Search reviewed Project and Global knowledge and return exact source locators.",
    promptGuidelines: [
      "Search Project and Global scopes unless the user limits the scope.",
      "Distinguish source facts, summaries, inferences, and user judgments.",
      "Cite document title and chunk locator for claims taken from knowledge.",
    ],
    parameters: Type.Object({
      query: Type.String(),
      scope: scopeSchema("Defaults to both scopes when a project is active"),
      includeDrafts: Type.Optional(Type.Boolean()),
      includeInbox: Type.Optional(Type.Boolean()),
      includeDeprecated: Type.Optional(Type.Boolean()),
      limit: Type.Optional(Type.Integer({ minimum: 1, maximum: 100 })),
    }),
    async execute(_id, params, signal, onUpdate, ctx) {
      try {
        const payload = await runCore(
          ctx,
          {
            action: "search",
            query: params.query,
            scopes: scopesFor(params.scope ?? "both", ctx),
            includeDrafts: params.includeDrafts ?? false,
            includeInbox: params.includeInbox ?? false,
            includeDeprecated: params.includeDeprecated ?? false,
            limit: params.limit ?? 20,
          },
          signal,
          onUpdate,
        );
        return {
          content: [{ type: "text", text: modelJson(payload) }],
          details: { personalPiKnowledgeSearch: payload },
        };
      } catch (error) {
        return toolFailure(error);
      }
    },
  });

  pi.registerTool({
    name: "knowledge_get",
    label: "Read knowledge document",
    description: "Read one indexed knowledge document with all exact chunks and locators.",
    parameters: Type.Object({
      documentId: Type.String(),
      scope: Type.Optional(enumSchema(["current", "global", "project"])),
    }),
    async execute(_id, params, signal, onUpdate, ctx) {
      try {
        const [scope] = scopesFor(params.scope ?? "current", ctx);
        const payload = await runCore(
          ctx,
          { action: "get", scope, documentId: params.documentId },
          signal,
          onUpdate,
        );
        return {
          content: [{ type: "text", text: modelJson(payload) }],
          details: {
            personalPiKnowledgeDocument: {
              document: payload.document,
              chunks: payload.chunks.map(({ text: _text, ...chunk }) => chunk),
            },
          },
        };
      } catch (error) {
        return toolFailure(error);
      }
    },
  });

  const sourceReference = Type.Object({
    source_id: Type.Optional(Type.String()),
    locator: Type.Optional(Type.String()),
    url: Type.Optional(Type.String()),
    title: Type.Optional(Type.String()),
  });
  pi.registerTool({
    name: "knowledge_capture",
    label: "Capture knowledge",
    description: "Create a new inbox item, source record, or draft knowledge card, then index it. Never publishes directly to reviewed cards.",
    promptGuidelines: [
      "Use only when the user explicitly requests durable capture or the active workflow requires it.",
      "Preserve provenance and separate facts, summary, inference, and user judgment.",
      "Use drafts for synthesized knowledge that has not been reviewed.",
    ],
    parameters: Type.Object({
      scope: Type.Optional(enumSchema(["current", "global", "project"])),
      category: enumSchema(["inbox", "sources", "drafts"]),
      title: Type.String(),
      content: Type.String(),
      type: Type.Optional(Type.String()),
      confidence: Type.Optional(enumSchema(["unknown", "low", "medium", "high"])),
      tags: Type.Optional(Type.Array(Type.String(), { maxItems: 50 })),
      sources: Type.Optional(Type.Array(sourceReference, { maxItems: 100 })),
    }),
    async execute(_id, params, signal, onUpdate, ctx) {
      try {
        const [scope] = scopesFor(params.scope ?? "current", ctx);
        const payload = await runCore(
          ctx,
          { action: "capture", ...params, scope },
          signal,
          onUpdate,
        );
        return {
          content: [{ type: "text", text: `Captured ${payload.relativePath}\nDocument ID: ${payload.document.id}` }],
          details: { personalPiKnowledgeCapture: payload },
        };
      } catch (error) {
        return toolFailure(error);
      }
    },
  });

  pi.registerTool({
    name: "knowledge_publish",
    label: "Publish knowledge card",
    description: "Move a reviewed draft into cards after the user explicitly confirms publication.",
    parameters: Type.Object({
      documentId: Type.String(),
      scope: Type.Optional(enumSchema(["current", "global", "project"])),
      userConfirmed: Type.Boolean({ description: "Must be true only after explicit user confirmation" }),
    }),
    async execute(_id, params, signal, onUpdate, ctx) {
      try {
        const [scope] = scopesFor(params.scope ?? "current", ctx);
        const payload = await runCore(
          ctx,
          { action: "publish", ...params, scope },
          signal,
          onUpdate,
        );
        return {
          content: [{ type: "text", text: `Published ${payload.relativePath}` }],
          details: { personalPiKnowledgePublish: payload },
        };
      } catch (error) {
        return toolFailure(error);
      }
    },
  });
}
