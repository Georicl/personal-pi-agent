#!/usr/bin/env node

import { randomUUID } from "node:crypto";
import { existsSync, realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";

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

async function createPiRuntime(sdkEntry, workingDirectory) {
  const sdk = await import(pathToFileURL(sdkEntry).href);
  const agentDirectory = process.env.PI_CODING_AGENT_DIR;
  if (!agentDirectory) {
    throw new Error("PI_CODING_AGENT_DIR is required");
  }

  const modelRuntime = await sdk.ModelRuntime.create({
    authPath: join(agentDirectory, "auth.json"),
    modelsPath: join(agentDirectory, "models.json"),
    allowModelNetwork: false,
  });
  const settingsManager = sdk.SettingsManager.create(
    workingDirectory,
    agentDirectory,
    { projectTrusted: true },
  );
  const services = await sdk.createAgentSessionServices({
    cwd: workingDirectory,
    agentDir: agentDirectory,
    modelRuntime,
    settingsManager,
  });
  return services.modelRuntime;
}

function serializeProvider(runtime, provider) {
  const methods = [];
  if (provider.auth.oauth) {
    methods.push({
      type: "oauth",
      name: provider.auth.oauth.name,
      loginLabel: provider.auth.oauth.loginLabel,
      interactive: true,
      subscription: provider.auth.oauth.isSubscription === true,
    });
  }
  if (provider.auth.apiKey) {
    methods.push({
      type: "api_key",
      name: provider.auth.apiKey.name,
      interactive: typeof provider.auth.apiKey.login === "function",
      subscription: false,
    });
  }

  const status = runtime.getProviderAuthStatus(provider.id);
  return {
    id: provider.id,
    name: provider.name,
    configured: status.configured,
    configuredAuthType: status.configured
      ? runtime.isUsingOAuth(provider.id)
        ? "oauth"
        : "api_key"
      : undefined,
    methods,
  };
}

function promptPayload(prompt) {
  return {
    type: prompt.type,
    message: prompt.message,
    placeholder: prompt.placeholder,
    options: prompt.type === "select" ? prompt.options : undefined,
  };
}

async function runLogin(runtime, providerId, authType) {
  const provider = runtime.getProvider(providerId);
  if (!provider) {
    throw new Error(`Unknown Pi provider: ${providerId}`);
  }
  const method = authType === "oauth" ? provider.auth.oauth : provider.auth.apiKey;
  if (!method) {
    throw new Error(`${provider.name} does not support ${authType}`);
  }
  if (authType === "api_key" && typeof method.login !== "function") {
    throw new Error(`${provider.name} authentication is configured outside Pi`);
  }

  const controller = new AbortController();
  const pendingPrompts = new Map();
  let inputBuffer = "";

  const cancel = () => {
    controller.abort();
    for (const pending of pendingPrompts.values()) {
      pending.cleanup?.();
      pending.reject(new Error("Login cancelled"));
    }
    pendingPrompts.clear();
  };

  const handleInput = (chunk) => {
    inputBuffer += chunk;
    let newline;
    while ((newline = inputBuffer.indexOf("\n")) >= 0) {
      const line = inputBuffer.slice(0, newline).replace(/\r$/, "");
      inputBuffer = inputBuffer.slice(newline + 1);
      if (!line.trim()) continue;

      let response;
      try {
        response = JSON.parse(line);
      } catch {
        continue;
      }
      if (response.type === "cancel") {
        cancel();
        continue;
      }
      if (response.type !== "response" || typeof response.id !== "string") continue;

      const pending = pendingPrompts.get(response.id);
      if (!pending) continue;
      pendingPrompts.delete(response.id);
      pending.cleanup?.();
      if (response.cancelled) {
        pending.reject(new Error("Login cancelled"));
      } else if (typeof response.value === "string") {
        pending.resolve(response.value);
      } else {
        pending.reject(new Error("Login response is missing a value"));
      }
    }
  };
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", handleInput);

  const interaction = {
    signal: controller.signal,
    prompt(prompt) {
      if (controller.signal.aborted || prompt.signal?.aborted) {
        return Promise.reject(new Error("Login cancelled"));
      }
      const id = randomUUID();
      emit({ type: "prompt", id, prompt: promptPayload(prompt) });

      return new Promise((resolve, reject) => {
        let cleanup;
        if (prompt.signal) {
          const onAbort = () => {
            pendingPrompts.get(id)?.cleanup?.();
            pendingPrompts.delete(id);
            reject(new Error("Login cancelled"));
          };
          prompt.signal.addEventListener("abort", onAbort, { once: true });
          cleanup = () => prompt.signal.removeEventListener("abort", onAbort);
        }
        pendingPrompts.set(id, { resolve, reject, cleanup });
      });
    },
    notify(event) {
      emit({ type: "notification", event });
    },
  };

  try {
    await runtime.login(providerId, authType, interaction);
    emit({ type: "result", success: true, providerId, authType });
  } catch (error) {
    const message = controller.signal.aborted
      ? "Login cancelled"
      : error instanceof Error
        ? error.message
        : String(error);
    emit({ type: "result", success: false, providerId, authType, error: message });
  } finally {
    process.stdin.off("data", handleInput);
    process.stdin.pause();
  }
}

async function main() {
  const [mode, piExecutable, workingDirectory, providerId, authType] = process.argv.slice(2);
  if (!mode || !piExecutable || !workingDirectory) {
    throw new Error("Usage: pi-auth-bridge.mjs <list|login> <pi-executable> <cwd> [provider] [auth-type]");
  }

  const sdkEntry = resolveSdkEntry(piExecutable);
  const runtime = await createPiRuntime(sdkEntry, workingDirectory);

  if (mode === "list") {
    const providers = runtime
      .getProviders()
      .map((provider) => serializeProvider(runtime, provider))
      .filter((provider) => provider.methods.length > 0)
      .sort((left, right) => left.name.localeCompare(right.name));
    emit({ type: "providers", providers });
    return;
  }

  if (mode === "login") {
    if (!providerId || (authType !== "oauth" && authType !== "api_key")) {
      throw new Error("Login requires a provider ID and auth type");
    }
    await runLogin(runtime, providerId, authType);
    return;
  }

  throw new Error(`Unknown bridge mode: ${mode}`);
}

main().catch((error) => {
  emit({
    type: "result",
    success: false,
    error: error instanceof Error ? error.message : String(error),
  });
  process.exitCode = 1;
});
