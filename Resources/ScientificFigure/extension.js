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

const resourceRoot = dirname(fileURLToPath(import.meta.url));
const runnerPath = join(resourceRoot, "runner.py");
const bundledProjectPath = join(resourceRoot, "pyproject.toml");
const bundledLockPath = join(resourceRoot, "uv.lock");
const libraryReferencePath = join(
  resourceRoot,
  "skill",
  "references",
  "library-routing.md",
);

const MAX_OUTPUT_BYTES = 4 * 1024 * 1024;
const MAX_ITERATIONS = 5;
const confirmedStatistics = new Set();
let environmentReady;

const libraryDocs = {
  matplotlib: "https://matplotlib.org/stable/",
  seaborn: "https://seaborn.pydata.org/",
  pandas: "https://pandas.pydata.org/docs/",
  numpy: "https://numpy.org/doc/stable/",
  scipy: "https://docs.scipy.org/doc/scipy/",
  plotnine: "https://plotnine.org/",
  pillow: "https://pillow.readthedocs.io/en/stable/",
  tifffile: "https://github.com/cgohlke/tifffile",
  "scikit-image": "https://scikit-image.org/docs/stable/",
  statsmodels: "https://www.statsmodels.org/stable/",
  lifelines: "https://lifelines.readthedocs.io/",
  networkx: "https://networkx.org/documentation/stable/",
};

function enumSchema(values) {
  return Type.Union(values.map((value) => Type.Literal(value)));
}

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return {};
  }
}

function deepMerge(base, override) {
  const result = { ...base };
  for (const [key, value] of Object.entries(override ?? {})) {
    if (
      value &&
      typeof value === "object" &&
      !Array.isArray(value) &&
      result[key] &&
      typeof result[key] === "object" &&
      !Array.isArray(result[key])
    ) {
      result[key] = deepMerge(result[key], value);
    } else {
      result[key] = value;
    }
  }
  return result;
}

function expandPath(value, cwd) {
  if (!value) return value;
  let expanded = value;
  if (value === "~") expanded = homedir();
  else if (value.startsWith("~/")) expanded = join(homedir(), value.slice(2));
  return isAbsolute(expanded) ? resolve(expanded) : resolve(cwd, expanded);
}

function effectiveSettings(cwd) {
  const agentDirectory =
    process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");
  const globalSettings = readJson(join(agentDirectory, "settings.json"));
  const projectSettings = readJson(join(cwd, ".pi", "settings.json"));
  return {
    agentDirectory,
    settings: deepMerge(globalSettings, projectSettings),
  };
}

function copyIfChanged(source, destination) {
  const sourceData = readFileSync(source);
  if (existsSync(destination)) {
    const destinationData = readFileSync(destination);
    if (sourceData.equals(destinationData)) return;
  }
  copyFileSync(source, destination);
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
      finish(() =>
        rejectPromise(
          new Error(
            `Process timed out after ${Math.round((options.timeoutMs ?? 180000) / 1000)} seconds`,
          ),
        ),
      );
    }, options.timeoutMs ?? 180000);

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
    child.once("close", (code, signal) => {
      finish(() =>
        resolvePromise({
          code,
          signal,
          stdout: Buffer.concat(stdout).toString("utf8"),
          stderr: Buffer.concat(stderr).toString("utf8"),
        }),
      );
    });
    if (input) child.stdin.end(input);
    else child.stdin.end();
  });
}

async function managedPython(cwd, signal, onUpdate) {
  const { agentDirectory, settings } = effectiveSettings(cwd);
  const configuration = settings.scientificFigure ?? {};
  if (typeof configuration.pythonPath === "string" && configuration.pythonPath) {
    return {
      python: expandPath(configuration.pythonPath, cwd),
      configuration,
      managed: false,
    };
  }

  const environmentRoot = expandPath(
    process.env.PERSONAL_PI_FIGURE_ENVIRONMENT ||
      join(agentDirectory, "environments", "scientific-figure"),
    cwd,
  );
  mkdirSync(environmentRoot, { recursive: true });
  copyIfChanged(bundledProjectPath, join(environmentRoot, "pyproject.toml"));
  copyIfChanged(bundledLockPath, join(environmentRoot, "uv.lock"));

  if (!environmentReady) {
    environmentReady = (async () => {
      onUpdate?.({
        content: [
          {
            type: "text",
            text: "Preparing the locked scientific Python environment…",
          },
        ],
      });
      const uv = process.env.PERSONAL_PI_UV_EXECUTABLE || "uv";
      const result = await runProcess(
        uv,
        ["sync", "--project", environmentRoot, "--locked", "--no-progress"],
        undefined,
        {
          cwd,
          signal,
          timeoutMs: 600000,
          env: { ...process.env, UV_NO_PROGRESS: "1" },
        },
      );
      if (result.code !== 0) {
        throw new Error(
          result.stderr.trim() ||
            result.stdout.trim() ||
            `uv sync failed with exit code ${result.code}`,
        );
      }
      return join(environmentRoot, ".venv", "bin", "python");
    })().catch((error) => {
      environmentReady = undefined;
      throw error;
    });
  }

  return {
    python: await environmentReady,
    configuration,
    managed: true,
  };
}

function parseRunnerOutput(result) {
  const lines = result.stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    try {
      return JSON.parse(lines[index]);
    } catch {
      // Continue to the previous line.
    }
  }
  throw new Error(
    result.stderr.trim() ||
      result.stdout.trim() ||
      `Scientific figure runner exited with code ${result.code}`,
  );
}

async function runRunner(ctx, request, signal, onUpdate) {
  if (!existsSync(runnerPath) || !existsSync(bundledProjectPath) || !existsSync(bundledLockPath)) {
    throw new Error("Scientific figure runtime resources are incomplete");
  }
  const runtime = await managedPython(ctx.cwd, signal, onUpdate);
  const result = await runProcess(
    runtime.python,
    [runnerPath],
    JSON.stringify(request),
    {
      cwd: ctx.cwd,
      signal,
      timeoutMs: 300000,
      env: { ...process.env, MPLBACKEND: "Agg", PYTHONUNBUFFERED: "1" },
    },
  );
  const payload = parseRunnerOutput(result);
  if (!payload.success) {
    throw new Error(payload.error || "Scientific figure runner failed");
  }
  return { payload, configuration: runtime.configuration };
}

function toolFailure(error, details = {}) {
  return {
    content: [
      {
        type: "text",
        text: error instanceof Error ? error.message : String(error),
      },
    ],
    details,
    isError: true,
  };
}

function inspectionSummary(inspection) {
  const data = inspection.data ?? {};
  if (data.kind === "dataframe") {
    const columns = (data.columnNames ?? []).slice(0, 20).join(", ");
    return [
      `Data: ${inspection.name}`,
      `Shape: ${data.rows} rows × ${data.columns} columns`,
      `Columns: ${columns}${data.columnsTruncated ? ", …" : ""}`,
      `Missing columns: ${Object.keys(data.missing ?? {}).length}`,
    ].join("\n");
  }
  if (data.kind === "ndarray") {
    return `Data: ${inspection.name}\nNumPy shape: ${(data.shape ?? []).join(" × ")}\nDtype: ${data.dtype}`;
  }
  return `Data: ${inspection.name}\nType: ${data.kind ?? "unknown"}`;
}

function validationSummary(artifact) {
  const validation = artifact.validation ?? {};
  const lines = [
    `Scientific figure ${artifact.figureId}, iteration ${artifact.version}/${MAX_ITERATIONS}`,
    `Validation: ${validation.passed ? "passed" : "needs revision"} (score ${validation.score ?? 0})`,
    `Size: ${artifact.widthMm} × ${artifact.heightMm} mm; raster DPI: ${artifact.dpi}`,
    `Formats: ${(artifact.files ?? []).map((item) => item.format).join(", ")}`,
  ];
  if (validation.errors?.length) {
    lines.push("Errors:", ...validation.errors.map((item) => `- ${item}`));
  }
  if (validation.warnings?.length) {
    lines.push("Warnings:", ...validation.warnings.map((item) => `- ${item}`));
  }
  if (!validation.passed && artifact.version >= MAX_ITERATIONS) {
    lines.push(
      "The five-iteration limit has been reached. Stop and ask the user how to proceed.",
    );
  } else if (!validation.passed) {
    lines.push("Revise the Python code and render the next iteration with the same figureId.");
  }
  return lines.join("\n");
}

function codeAppearsInferential(code) {
  return /\b(scipy\.stats|from\s+scipy\s+import\s+stats|from\s+scipy\.stats\s+import|statsmodels|pingouin|scikit[_-]posthocs|ttest|anova|mannwhitney|wilcoxon|kruskal|pearsonr|spearmanr|fisher_exact|chi2_contingency|shapiro|levene|logrank|coxph|multipletests)\b/i.test(
    code,
  );
}

async function confirmStatistics(ctx, params) {
  const analysis = params.statisticalAnalysis;
  if (codeAppearsInferential(params.code) && !analysis?.method) {
    throw new Error(
      "Inferential statistical code was detected. Explain the method to the user, obtain confirmation, and call again with statisticalAnalysis.method.",
    );
  }
  if (!analysis?.method) return;
  const sessionId = ctx.sessionManager.getSessionId?.() || "ephemeral";
  const figureReference = params.figureId || params.title;
  const key = `${sessionId}:${figureReference}:${analysis.method}`;
  if (confirmedStatistics.has(key)) return;
  const confirmed = await ctx.ui.confirm(
    "Confirm statistical method",
    [
      `Method: ${analysis.method}`,
      `Rationale: ${analysis.rationale || "Not supplied"}`,
      `Sample unit: ${analysis.sampleUnit || "Not supplied"}`,
      `Groups: ${analysis.groups || "Not supplied"}`,
      `Assumptions: ${analysis.assumptions || "Not supplied"}`,
      `Multiple testing: ${analysis.correction || "Not applicable / not supplied"}`,
      `Figure annotation: ${analysis.annotation || "Not supplied"}`,
      "The source data will not be modified.",
    ].join("\n\n"),
  );
  if (!confirmed) {
    throw new Error("Statistical analysis was not confirmed by the user");
  }
  confirmedStatistics.add(key);
}

function stripHtml(html) {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, " ")
    .trim();
}

async function documentationResult(library, topic, signal) {
  const baseURL = libraryDocs[library];
  const localReference = existsSync(libraryReferencePath)
    ? readFileSync(libraryReferencePath, "utf8")
    : "";
  if (!topic) {
    return {
      url: baseURL,
      excerpt: localReference,
      source: "bundled-reference",
    };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15000);
  const forwardAbort = () => controller.abort();
  signal?.addEventListener("abort", forwardAbort, { once: true });
  try {
    const searchURL = new URL("search.html", baseURL);
    searchURL.searchParams.set("q", topic);
    const response = await fetch(searchURL, {
      signal: controller.signal,
      headers: { "user-agent": "PersonalPi/0.1 scientific-figure-docs" },
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const excerpt = stripHtml(await response.text()).slice(0, 8000);
    return { url: searchURL.toString(), excerpt, source: "official-documentation" };
  } catch (error) {
    return {
      url: baseURL,
      excerpt: localReference,
      source: "bundled-reference",
      warning: `Official documentation search was unavailable: ${error.message}`,
    };
  } finally {
    clearTimeout(timeout);
    signal?.removeEventListener("abort", forwardAbort);
  }
}

export default function scientificFigureExtension(pi) {
  pi.registerCommand("__personal_pi_scientific_figure", {
    description: "Internal Personal Pi scientific-figure runtime check",
    handler: async (args, ctx) => {
      const encoded = args.trim();
      if (!encoded) return;
      let request;
      try {
        request = JSON.parse(Buffer.from(encoded, "base64").toString("utf8"));
      } catch {
        throw new Error("Invalid scientific-figure runtime check payload");
      }
      if (
        typeof request.responsePath !== "string" ||
        !isAbsolute(request.responsePath)
      ) {
        throw new Error("Scientific-figure runtime check requires an absolute response path");
      }
      try {
        const { payload } = await runRunner(ctx, { action: "capabilities" });
        writeFileSync(
          request.responsePath,
          JSON.stringify({ success: true, capabilities: payload.capabilities }),
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
    name: "scientific_figure_capabilities",
    label: "Scientific figure capabilities",
    description:
      "List supported scientific figure inputs, outputs, dimensions, libraries, and plot families.",
    parameters: Type.Object({}),
    async execute(_toolCallId, _params, signal, onUpdate, ctx) {
      try {
        const { payload } = await runRunner(
          ctx,
          { action: "capabilities" },
          signal,
          onUpdate,
        );
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(payload.capabilities, null, 2),
            },
          ],
          details: { personalPiFigureCapabilities: payload.capabilities },
        };
      } catch (error) {
        return toolFailure(error);
      }
    },
  });

  pi.registerTool({
    name: "scientific_figure_inspect_data",
    label: "Inspect figure data",
    description:
      "Inspect a tabular, Excel, pandas, or NumPy data file before creating a scientific figure. Returns shape, columns, types, missing values, ranges, sheets, and a small sample.",
    parameters: Type.Object({
      dataPath: Type.String({ description: "Input data path, absolute or relative to the current Pi cwd" }),
    }),
    async execute(_toolCallId, params, signal, onUpdate, ctx) {
      try {
        onUpdate?.({
          content: [{ type: "text", text: `Inspecting ${params.dataPath}…` }],
        });
        const { payload } = await runRunner(
          ctx,
          { action: "inspect", cwd: ctx.cwd, dataPath: params.dataPath },
          signal,
          onUpdate,
        );
        return {
          content: [{ type: "text", text: inspectionSummary(payload.inspection) }],
          details: { personalPiFigureInspection: payload.inspection },
        };
      } catch (error) {
        return toolFailure(error);
      }
    },
  });

  pi.registerTool({
    name: "scientific_figure_library_docs",
    label: "Scientific plotting documentation",
    description:
      "Retrieve bundled guidance and, when a topic is supplied, search the selected library's official documentation.",
    parameters: Type.Object({
      library: enumSchema(Object.keys(libraryDocs)),
      topic: Type.Optional(Type.String({ description: "API, chart type, or export topic" })),
    }),
    async execute(_toolCallId, params, signal) {
      const result = await documentationResult(params.library, params.topic, signal);
      const text = [
        `Library: ${params.library}`,
        `Official documentation: ${result.url}`,
        result.warning,
        result.excerpt,
      ]
        .filter(Boolean)
        .join("\n\n");
      return {
        content: [{ type: "text", text }],
        details: {
          library: params.library,
          topic: params.topic,
          source: result.source,
          url: result.url,
        },
      };
    },
  });

  pi.registerTool({
    name: "scientific_figure_render",
    label: "Render scientific figure",
    description:
      "Execute Python plotting code, validate an academic figure, produce PNG/TIFF/PDF, and register it for the Personal Pi artifact sidebar. The code must assign the final Matplotlib Figure to fig. Reuse figureId for revisions and stop after iteration five.",
    promptGuidelines: [
      "Inspect each data file before rendering.",
      "Iterate on validation errors with the same figureId, up to five versions.",
      "Do not run inferential statistics before explicit user confirmation.",
      "Keep work files only when the user explicitly asks.",
    ],
    parameters: Type.Object({
      title: Type.String({ description: "Short human-readable figure title" }),
      code: Type.String({ description: "Python body that assigns the final Matplotlib Figure to fig" }),
      dataPaths: Type.Optional(
        Type.Array(
          Type.String({ description: "Input table path, absolute or relative to Pi cwd" }),
          { maxItems: 20 },
        ),
      ),
      figureId: Type.Optional(
        Type.String({ description: "Stable figure ID; reuse it for later iterations" }),
      ),
      iteration: Type.Optional(
        Type.Integer({ minimum: 1, maximum: MAX_ITERATIONS }),
      ),
      widthMm: Type.Optional(Type.Number({ exclusiveMinimum: 0, maximum: 210 })),
      heightMm: Type.Optional(Type.Number({ exclusiveMinimum: 0, maximum: 148.5 })),
      dpi: Type.Optional(Type.Integer({ minimum: 72, maximum: 1200 })),
      statisticalAnalysis: Type.Optional(
        Type.Object({
          method: Type.String({ description: "Method explicitly confirmed by the user" }),
          rationale: Type.Optional(Type.String()),
          sampleUnit: Type.Optional(Type.String()),
          groups: Type.Optional(Type.String()),
          assumptions: Type.Optional(Type.String()),
          correction: Type.Optional(Type.String()),
          annotation: Type.Optional(Type.String()),
        }),
      ),
      keepWorkFiles: Type.Optional(
        Type.Boolean({
          description: "Retain source, request, validation, and logs only when explicitly requested",
        }),
      ),
    }),
    async execute(_toolCallId, params, signal, onUpdate, ctx) {
      try {
        await confirmStatistics(ctx, params);
        onUpdate?.({
          content: [
            {
              type: "text",
              text: `Rendering ${params.title}, iteration ${params.iteration ?? 1}…`,
            },
          ],
        });
        const { agentDirectory, settings } = effectiveSettings(ctx.cwd);
        const configuration = settings.scientificFigure ?? {};
        const keepWorkFiles =
          params.keepWorkFiles === true || configuration.keepWorkFiles === true;
        const sessionId = ctx.sessionManager.getSessionId?.() ?? null;
        const artifactRoot = join(ctx.cwd, ".pi", "artifacts", "figures");
        const { payload } = await runRunner(
          ctx,
          {
            action: "render",
            cwd: ctx.cwd,
            artifactRoot,
            sessionId,
            title: params.title,
            code: params.code,
            dataPaths: params.dataPaths ?? [],
            figureId: params.figureId,
            iteration: params.iteration,
            widthMm: params.widthMm,
            heightMm: params.heightMm,
            dpi: params.dpi,
            keepWorkFiles,
          },
          signal,
          onUpdate,
        );
        const artifact = payload.artifact;
        const content = [{ type: "text", text: validationSummary(artifact) }];
        const supportsImages = Array.isArray(ctx.model?.input)
          ? ctx.model.input.includes("image")
          : false;
        if (supportsImages && existsSync(artifact.previewPath)) {
          content.push({
            type: "image",
            data: readFileSync(artifact.previewPath).toString("base64"),
            mimeType: "image/png",
          });
        }
        return {
          content,
          details: {
            personalPiFigureArtifact: artifact,
            environment: {
              managed: !configuration.pythonPath,
              root: configuration.pythonPath
                ? undefined
                : join(agentDirectory, "environments", "scientific-figure"),
            },
          },
        };
      } catch (error) {
        return toolFailure(error, { personalPiFigureError: true });
      }
    },
  });
}
