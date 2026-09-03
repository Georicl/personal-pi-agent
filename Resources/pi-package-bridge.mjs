#!/usr/bin/env node

import { existsSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join, relative, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const RESOURCE_TYPES = ["extensions", "skills", "prompts", "themes"];

function emit(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

function resolveSdkEntry(piExecutable) {
  const resolvedPi = realpathSync(piExecutable);
  const executableDirectory = dirname(resolvedPi);
  const candidates = [
    join(executableDirectory, "..", "index.js"),
    join(executableDirectory, "index.js"),
    join(executableDirectory, "..", "..", "dist", "index.js"),
  ];
  const sdkEntry = candidates.find((candidate) => existsSync(candidate));
  if (!sdkEntry) {
    throw new Error("The current Pi installation does not expose the JavaScript SDK");
  }
  return sdkEntry;
}

function parsePayload(encoded) {
  if (!encoded) return {};
  try {
    return JSON.parse(Buffer.from(encoded, "base64url").toString("utf8"));
  } catch {
    throw new Error("Invalid package operation payload");
  }
}

function sourceString(entry) {
  return typeof entry === "string" ? entry : entry.source;
}

function isLocalSource(source) {
  return !source.startsWith("npm:")
    && !source.startsWith("git:")
    && !/^[a-z][a-z0-9+.-]*:\/\//i.test(source);
}

function sourceBase(scope, cwd, agentDir) {
  return scope === "project" ? join(cwd, ".pi") : agentDir;
}

function resolvedLocalSource(source, scope, cwd, agentDir) {
  const expanded = source === "~" || source.startsWith("~/")
    ? join(homedir(), source.slice(2))
    : source;
  return resolve(sourceBase(scope, cwd, agentDir), expanded);
}

function sourcesMatch(left, leftScope, right, rightScope, cwd, agentDir) {
  if (left === right) return true;
  if (!isLocalSource(left) || !isLocalSource(right)) return false;
  return resolvedLocalSource(left, leftScope, cwd, agentDir)
    === resolvedLocalSource(right, rightScope, cwd, agentDir);
}

function patternTarget(entry) {
  return /^[!+-]/.test(entry) ? entry.slice(1) : entry;
}

function displayName(resource) {
  const fileName = basename(resource.path);
  const parentName = basename(dirname(resource.path));
  if (resource.resourceType === "extensions" && parentName !== "extensions") {
    return `${parentName}/${fileName}`;
  }
  if (resource.resourceType === "skills" && fileName === "SKILL.md") {
    return parentName;
  }
  return fileName;
}

function packagePattern(resource) {
  return relative(resource.baseDir || dirname(resource.path), resource.path);
}

function topLevelBase(scope, cwd, agentDir) {
  return scope === "project" ? join(cwd, ".pi") : agentDir;
}

function topLevelPattern(resource, scope, cwd, agentDir) {
  const sourceScope = resource.sourceScope === "project" ? "project" : "user";
  if (scope !== sourceScope) return resource.path;
  return relative(resource.baseDir || topLevelBase(sourceScope, cwd, agentDir), resource.path);
}

function topLevelPatterns(resource, scope, cwd, agentDir) {
  const base = topLevelBase(scope, cwd, agentDir);
  const values = new Set([
    topLevelPattern(resource, scope, cwd, agentDir),
    resource.path,
    relative(base, resource.path),
  ]);
  if (resource.baseDir) values.add(relative(resource.baseDir, resource.path));
  return values;
}

function overrideFromEntries(entries, patterns, emptyArrayIsUnload) {
  if (entries.length === 0 && emptyArrayIsUnload) return "unload";
  let state = "inherit";
  for (const entry of entries) {
    if (!patterns.has(patternTarget(entry))) continue;
    state = entry.startsWith("!") || entry.startsWith("-") ? "unload" : "load";
  }
  return state;
}

function findPackage(settings, resource, targetScope, cwd, agentDir) {
  return (settings.packages || []).find((entry) => sourcesMatch(
    resource.source,
    resource.sourceScope,
    sourceString(entry),
    targetScope,
    cwd,
    agentDir,
  ));
}

function projectOverrideState(resource, projectSettings, cwd, agentDir) {
  if (resource.origin === "top-level") {
    return overrideFromEntries(
      projectSettings[resource.resourceType] || [],
      topLevelPatterns(resource, "project", cwd, agentDir),
      false,
    );
  }
  const entry = findPackage(projectSettings, resource, "project", cwd, agentDir);
  if (!entry || typeof entry === "string") return "inherit";
  const values = entry[resource.resourceType];
  if (values === undefined) return "inherit";
  return overrideFromEntries(values, new Set([packagePattern(resource)]), entry.autoload !== false);
}

function resourceKey(resourceType, path) {
  return `${resourceType}:${resolve(path)}`;
}

function serializeResources(
  paths,
  projectSettings,
  cwd,
  agentDir,
  includeOverrides,
  inheritedKeys = new Set(),
) {
  const serialized = [];
  for (const resourceType of RESOURCE_TYPES) {
    for (const item of paths[resourceType] || []) {
      const resource = {
        resourceType,
        path: item.path,
        enabled: item.enabled,
        source: item.metadata.source,
        sourceScope: item.metadata.scope === "project" ? "project" : "user",
        origin: item.metadata.origin,
        baseDir: item.metadata.baseDir,
      };
      serialized.push({
        ...resource,
        name: displayName(resource),
        inherited: includeOverrides && (
          resource.sourceScope === "user"
          || inheritedKeys.has(resourceKey(resource.resourceType, resource.path))
        ),
        overrideState: includeOverrides
          ? projectOverrideState(resource, projectSettings, cwd, agentDir)
          : resource.enabled ? "load" : "unload",
      });
    }
  }
  return serialized;
}

function settingsErrors(settingsManager) {
  return settingsManager.drainErrors().map((item) => {
    const prefix = item.scope === "project" ? "Project settings" : "Global settings";
    return `${prefix}: ${item.error?.message || String(item.error)}`;
  });
}

function configuredPaths(settings) {
  return Object.fromEntries(RESOURCE_TYPES.map((type) => [type, settings[type] || []]));
}

function assertNoSettingsErrors(errors) {
  if (errors.length > 0) {
    throw new Error(`Package management is unavailable until settings errors are fixed. ${errors.join(" ")}`);
  }
}

async function createRuntime(piExecutable, cwd) {
  const sdk = await import(pathToFileURL(resolveSdkEntry(piExecutable)).href);
  const agentDir = process.env.PI_CODING_AGENT_DIR;
  if (!agentDir) throw new Error("PI_CODING_AGENT_DIR is required");
  const settingsManager = sdk.SettingsManager.create(cwd, agentDir, { projectTrusted: true });
  const packageManager = new sdk.DefaultPackageManager({ cwd, agentDir, settingsManager });
  return { sdk, agentDir, settingsManager, packageManager };
}

async function listSnapshot(runtime, cwd) {
  const globalSettingsManager = runtime.sdk.SettingsManager.create(cwd, runtime.agentDir, {
    projectTrusted: false,
  });
  const globalPackageManager = new runtime.sdk.DefaultPackageManager({
    cwd,
    agentDir: runtime.agentDir,
    settingsManager: globalSettingsManager,
  });
  const [globalPaths, projectPaths] = await Promise.all([
    globalPackageManager.resolve(async () => "skip"),
    runtime.packageManager.resolve(async () => "skip"),
  ]);
  const globalErrors = settingsErrors(globalSettingsManager);
  const projectErrors = settingsErrors(runtime.settingsManager);
  const projectSettings = runtime.settingsManager.getProjectSettings();
  const globalResources = serializeResources(
    globalPaths,
    projectSettings,
    cwd,
    runtime.agentDir,
    false,
  );
  const inheritedKeys = new Set(
    globalResources.map((resource) => resourceKey(resource.resourceType, resource.path)),
  );
  emit({
    type: "snapshot",
    packages: runtime.packageManager.listConfiguredPackages(),
    globalResources,
    projectResources: serializeResources(
      projectPaths,
      projectSettings,
      cwd,
      runtime.agentDir,
      true,
      inheritedKeys,
    ),
    globalConfiguredPaths: configuredPaths(runtime.settingsManager.getGlobalSettings()),
    projectConfiguredPaths: configuredPaths(projectSettings),
    errors: [...new Set([...globalErrors, ...projectErrors])],
  });
}

function setResourcePaths(settingsManager, scope, type, paths) {
  const project = scope === "project";
  if (type === "extensions") {
    project ? settingsManager.setProjectExtensionPaths(paths) : settingsManager.setExtensionPaths(paths);
  } else if (type === "skills") {
    project ? settingsManager.setProjectSkillPaths(paths) : settingsManager.setSkillPaths(paths);
  } else if (type === "prompts") {
    project ? settingsManager.setProjectPromptTemplatePaths(paths) : settingsManager.setPromptTemplatePaths(paths);
  } else if (type === "themes") {
    project ? settingsManager.setProjectThemePaths(paths) : settingsManager.setThemePaths(paths);
  } else {
    throw new Error(`Unsupported resource type: ${type}`);
  }
}

function setTopLevelResource(runtime, cwd, resource, targetScope, desiredState) {
  const settings = targetScope === "project"
    ? runtime.settingsManager.getProjectSettings()
    : runtime.settingsManager.getGlobalSettings();
  const current = [...(settings[resource.resourceType] || [])];

  if (targetScope === "project") {
    const inherited = resource.inherited || resource.sourceScope === "user";
    const pattern = inherited
      ? resource.path
      : topLevelPattern(resource, "project", cwd, runtime.agentDir);
    const patterns = topLevelPatterns(resource, "project", cwd, runtime.agentDir);
    const updated = current.filter((entry) => {
      const target = patternTarget(entry);
      if (/^[!+-]/.test(entry) && patterns.has(target)) return false;
      return !(desiredState === "inherit" && inherited && target === pattern);
    });
    if (desiredState !== "inherit") {
      if (inherited && !updated.includes(pattern)) updated.push(pattern);
      updated.push(`${desiredState === "load" ? "+" : "-"}${pattern}`);
    }
    setResourcePaths(runtime.settingsManager, targetScope, resource.resourceType, updated);
    return;
  }

  const pattern = topLevelPattern(resource, "user", cwd, runtime.agentDir);
  const updated = current.filter((entry) => patternTarget(entry) !== pattern);
  updated.push(`${desiredState === "load" ? "+" : "-"}${pattern}`);
  setResourcePaths(runtime.settingsManager, targetScope, resource.resourceType, updated);
}

function createProjectPackageDelta(resource, cwd, agentDir) {
  if (!isLocalSource(resource.source)) {
    return { source: resource.source, autoload: false };
  }
  const sourcePath = resolvedLocalSource(resource.source, resource.sourceScope, cwd, agentDir);
  return {
    source: relative(topLevelBase("project", cwd, agentDir), sourcePath) || ".",
    autoload: false,
  };
}

function setPackageResource(runtime, cwd, resource, targetScope, desiredState) {
  const settings = targetScope === "project"
    ? runtime.settingsManager.getProjectSettings()
    : runtime.settingsManager.getGlobalSettings();
  const packages = [...(settings.packages || [])];
  let index = packages.findIndex((entry) => sourcesMatch(
    resource.source,
    resource.sourceScope,
    sourceString(entry),
    targetScope,
    cwd,
    runtime.agentDir,
  ));

  if (index === -1) {
    if (desiredState === "inherit") return;
    if (targetScope !== "project") {
      throw new Error(`Package is not configured in Global settings: ${resource.source}`);
    }
    packages.push(createProjectPackageDelta(resource, cwd, runtime.agentDir));
    index = packages.length - 1;
  }

  let entry = packages[index];
  if (typeof entry === "string") entry = { source: entry };
  const pattern = packagePattern(resource);
  const updated = [...(entry[resource.resourceType] || [])]
    .filter((value) => patternTarget(value) !== pattern);
  if (desiredState !== "inherit") {
    updated.push(`${desiredState === "load" ? "+" : "-"}${pattern}`);
  }
  if (updated.length > 0) entry[resource.resourceType] = updated;
  else delete entry[resource.resourceType];

  const hasFilters = RESOURCE_TYPES.some((type) => entry[type] !== undefined);
  if (!hasFilters) {
    if (entry.autoload === false) packages.splice(index, 1);
    else packages[index] = entry.source;
  } else {
    packages[index] = entry;
  }

  if (targetScope === "project") runtime.settingsManager.setProjectPackages(packages);
  else runtime.settingsManager.setPackages(packages);
}

async function setResource(runtime, cwd, payload) {
  const { scope, desiredState, resource } = payload;
  if (!resource || !RESOURCE_TYPES.includes(resource.resourceType)) {
    throw new Error("Resource operation is missing a supported resource");
  }
  if (scope !== "user" && scope !== "project") throw new Error("Invalid resource scope");
  if (!new Set(["inherit", "load", "unload"]).has(desiredState)) {
    throw new Error("Invalid resource override state");
  }
  if (scope === "user" && desiredState === "inherit") {
    throw new Error("Global resources cannot inherit another scope");
  }
  if (resource.origin === "package") {
    setPackageResource(runtime, cwd, resource, scope, desiredState);
  } else {
    setTopLevelResource(runtime, cwd, resource, scope, desiredState);
  }
  await runtime.settingsManager.flush();
}

async function setConfiguredPaths(runtime, payload) {
  if (payload.scope !== "user" && payload.scope !== "project") {
    throw new Error("Invalid resource path scope");
  }
  for (const type of RESOURCE_TYPES) {
    const paths = payload.paths?.[type];
    if (!Array.isArray(paths) || paths.some((entry) => typeof entry !== "string")) {
      throw new Error(`Invalid ${type} resource paths`);
    }
    setResourcePaths(runtime.settingsManager, payload.scope, type, paths);
  }
  await runtime.settingsManager.flush();
}

async function main() {
  const [mode, piExecutable, cwd, encodedPayload] = process.argv.slice(2);
  if (!mode || !piExecutable || !cwd) {
    throw new Error("Usage: pi-package-bridge.mjs <list|install|remove|update|set_resource|set_paths> <pi> <cwd> [payload]");
  }
  const payload = parsePayload(encodedPayload);
  const runtime = await createRuntime(piExecutable, cwd);

  if (mode === "list") {
    await listSnapshot(runtime, cwd);
    return;
  }
  const errors = settingsErrors(runtime.settingsManager);
  assertNoSettingsErrors(errors);

  if (mode === "install") {
    if (!payload.source) throw new Error("Package source is required");
    await runtime.packageManager.installAndPersist(payload.source, {
      local: payload.scope === "project",
    });
    await runtime.settingsManager.flush();
  } else if (mode === "remove") {
    if (!payload.source) throw new Error("Package source is required");
    const removed = await runtime.packageManager.removeAndPersist(payload.source, {
      local: payload.scope === "project",
    });
    await runtime.settingsManager.flush();
    if (!removed) throw new Error(`No matching package found for ${payload.source}`);
  } else if (mode === "update") {
    await runtime.packageManager.update(payload.source || undefined);
  } else if (mode === "set_resource") {
    await setResource(runtime, cwd, payload);
  } else if (mode === "set_paths") {
    await setConfiguredPaths(runtime, payload);
  } else {
    throw new Error(`Unknown package bridge mode: ${mode}`);
  }

  assertNoSettingsErrors(settingsErrors(runtime.settingsManager));
  emit({ type: "result", success: true, mode, source: payload.source });
}

main().catch((error) => {
  emit({
    type: "result",
    success: false,
    error: error instanceof Error ? error.message : String(error),
  });
  process.exitCode = 1;
});
