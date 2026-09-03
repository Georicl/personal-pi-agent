# Pi Compatibility Record

This file records the Pi runtime contract that Personal Pi has actually checked. It is not a promise that every future Pi release has the same behavior.

## Verified baseline

| Component | Verified value | Evidence |
|---|---:|---|
| Pi coding agent | `0.84.3` | `pi --version` and npm `latest` on 2026-08-27 |
| Package | `@earendil-works/pi-coding-agent` | Installed npm package |
| Node.js | `25.2.1` | Local Finder-launch and RPC test |
| macOS | 13+ target | `Package.swift` |
| GUI transport | RPC JSONL over stdin/stdout | Pi RPC documentation and live GUI test |
| Auth status adapter | `pi auth check --json --no-refresh` | Credential-free JSON checked for DeepSeek and OpenAI Codex |
| Provider login adapter | Pi SDK `createAgentSessionServices` + `ModelRuntime.login` | Version-local SDK and installed `/login` implementation |

Primary online documentation:

- <https://pi.dev/docs/latest/settings>
- <https://pi.dev/docs/latest/security>
- <https://pi.dev/docs/latest/skills>
- <https://pi.dev/docs/latest/prompt-templates>
- <https://pi.dev/docs/latest/extensions>
- <https://pi.dev/docs/latest/rpc>
- <https://pi.dev/docs/latest/sessions>
- <https://pi.dev/docs/latest/session-format>
- <https://pi.dev/docs/latest/compaction>

The installed package contains matching version-local documentation under its `docs/` directory. When online `latest` and the installed package differ, Personal Pi must follow the installed package until compatibility is re-tested.

## Resource and configuration matrix

| Capability | Global | Project | Verified behavior |
|---|---|---|---|
| Settings | `~/.pi/agent/settings.json` | `.pi/settings.json` | Project keys override global keys; nested objects merge |
| Context | `~/.pi/agent/AGENTS.md` | `AGENTS.md`, `CLAUDE.md`, or `AGENTS.override.md` while walking from cwd | Context files load independently of project resource trust unless disabled |
| System prompt | `~/.pi/agent/SYSTEM.md` or `APPEND_SYSTEM.md` | `.pi/SYSTEM.md` or `.pi/APPEND_SYSTEM.md` | `SYSTEM.md` replaces and `APPEND_SYSTEM.md` appends |
| Skills | `~/.pi/agent/skills/`, `~/.agents/skills/` | `.pi/skills/`, ancestor `.agents/skills/` | Project resources require trust; skills use progressive disclosure |
| Prompt templates | `~/.pi/agent/prompts/*.md` | `.pi/prompts/*.md` | Project templates require trust; auto-discovery is non-recursive |
| Extensions | `~/.pi/agent/extensions/` | `.pi/extensions/` | TypeScript loads through jiti; project extensions require trust |
| Themes | `~/.pi/agent/themes/` | `.pi/themes/` | Project themes require trust |
| Packages | `~/.pi/agent/npm/` and Global Git package storage | `.pi/npm/` and Project Git package storage | npm, Git, URL and local sources; project entries override matching Global entries |
| Sessions | `~/.pi/agent/sessions/` by default | Grouped by session cwd | JSONL tree, configurable with `sessionDir` |
| Trust decisions | `~/.pi/agent/trust.json` | Canonical project path | Trust controls project resource loading, not tool execution isolation |

Personal Pi launches project RPC sessions with the project root as `cwd` and `--approve`. Global Chat uses `~/.pi/chat`, so it does not load a selected project's `.pi` resources.

Account cards call Pi's `auth check` command without `--credentials`. Swift receives only `status`, `provider`, `authType`, and `reason`; it does not read `auth.json`, API keys, OAuth tokens, or provider-private usage endpoints. Pi 0.84.3 does not expose subscription limits through this command, so the GUI shows credential readiness and leaves daily/weekly limits unspecified.

The Settings provider picker is not a custom-provider form. A bundled local bridge loads the installed Pi SDK for the active cwd, including trusted project provider registrations, and returns the same provider/authentication metadata used by `/login`. Authentication is executed by `ModelRuntime.login`: OAuth and device-code URLs are handed to macOS for automatic opening, while other Pi prompts are rendered in the sheet. Credential values are neither printed nor retained by the GUI.

The same adapter lists stored credential metadata through `listCredentials`, removes selected stored credentials with `ModelRuntime.logout`, and refreshes model catalogs with `ModelRuntime.refresh`. A successful login refreshes that provider's catalog, and Settings also provides an explicit full refresh. `/login [provider]` and `/logout [provider]` are GUI-native slash commands because Pi RPC intentionally does not execute built-in TUI commands.

The Packages & Resources page uses the installed Pi SDK's `SettingsManager` and `DefaultPackageManager`, matching `pi list`, `pi install`, `pi remove`, `pi update --extensions`, and the resource-filter behavior of `pi config`. Snapshot refreshes call `resolve(() => "skip")`, so merely opening the page never installs a missing package. Project resource overrides use Pi's package delta and `+` / `-` / `!` path semantics. Package code is reloaded only after an explicit mutation completes.

## Verified RPC surface

Personal Pi currently uses:

- `get_state`
- `get_messages`
- `get_available_models`
- `get_available_thinking_levels`
- `get_commands`
- `set_model`
- `set_thinking_level`
- `new_session`
- `switch_session`
- `prompt`
- `abort`
- `compact`
- `get_session_stats`
- `set_session_name`
- `extension_ui_response`

Pi 0.84.3 also documents, but the GUI does not yet expose:

- steering and follow-up queues
- model and thinking cycling commands
- Pi CLI self-update (`pi update --self`); the GUI manages packages and model catalogs but does not replace its own bundled/runtime updater
- standalone bash execution and cancellation
- HTML export
- `fork`, `clone`, `get_fork_messages`, `get_entries`, and `get_tree`

The Settings page edits common Global and Project Pi settings while preserving unknown JSON keys. It covers model defaults, `enabledModels`, `modelThinkingLevels`, `thinkingBudgets`, compaction thresholds, retry timing, message delivery, provider transport, image handling, and built-in tools. The Packages & Resources page owns package entries and the `extensions`, `skills`, `prompts`, and `themes` path arrays. Model thinking choices are derived from the full model metadata returned by Pi. Each editable scope is loaded independently, and saving reapplies the GUI-owned fields to the latest file contents before writing. The Session composer merges native GUI actions with `get_commands` results, so GUI-native commands, extension commands, prompt templates, and skill commands are available through the slash-command palette.

The GUI handles these event families today:

- agent and turn lifecycle
- streamed message updates
- tool execution lifecycle
- compaction lifecycle
- extension errors
- extension UI requests and responses

Queue updates, retry telemetry, branch/tree events, and the complete extension UI surface remain future integration work.

## Session and context behavior

- Sessions are JSONL trees with entry IDs and parent IDs.
- `/tree` changes the active branch inside one session file.
- Fork and clone create new session files.
- Compaction summarizes older context and preserves recent context.
- Branch summarization can preserve abandoned-branch context when navigating the tree.
- Compaction and branch summaries are persisted entries and may include usage data.

## Re-test triggers

Re-run compatibility checks when any of these change:

- Pi package version
- RPC command or event parsing
- settings or resource discovery rules
- session format version
- project trust behavior
- Node runtime or executable discovery

Minimum re-test:

```bash
pi --version
npm view @earendil-works/pi-coding-agent version dist-tags --json
scripts/check-pi-compatibility.sh
scripts/build-app.sh debug
```

Then verify Finder launch, Global Chat cwd, project cwd, historical session restoration, RPC connect/disconnect, and Diagnostics.
