# Pi Compatibility Record

Literature MVP uses the same Pi 0.84.3 Package/Extension contract: `/literature`
plus `literature_plan/search/save/draft`. The isolated native RPC check invokes
the actual plan/save/draft handlers with Pi's context, without model credentials.
Search provider access is separately opt-in with `PERSONAL_PI_TEST_LITERATURE_LIVE=1`.

This file records the Pi runtime contract that Personal Pi has actually checked. It is not a promise that every future Pi release has the same behavior.

## Compiler baseline

GitHub Actions explicitly selects Xcode 16.4 / Swift 6.1.2 on `macos-15` for both jobs. A successful build with a newer local Xcode does not replace this compatibility check. Keep construction of MainActor-owned dependencies inside initializer bodies: an isolated `PiRPCClient()` default argument on `AppState.init` triggered a Swift 6.1.2 compiler crash when lowering the app delegate's stored-property initializer. The no-argument convenience initializer preserves production startup and the explicit-client initializer preserves test injection without that default-argument thunk.

## Verified baseline

| Component | Verified value | Evidence |
|---|---:|---|
| Pi coding agent | `0.84.3` | `pi --version` and npm `latest` on 2026-08-27 |
| Package | `@earendil-works/pi-coding-agent` | Installed npm package |
| Node.js | `25.2.1` | Local Finder-launch and RPC test |
| macOS | 13+ target | `Package.swift` |
| GUI transport | RPC JSONL over stdin/stdout | Pi RPC documentation and live GUI test |
| Figure Python environment | uv lock/sync | Locked runner smoke test |
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

The GUI supplies the remaining session-oriented slash commands itself. Tree inspection, fork, clone, HTML export and last-reply copy use Pi RPC directly. Pi 0.84.3 does not expose same-file `navigateTree()` or resource `reload()` as RPC commands, so the app loads a bundled internal extension and invokes those two Pi-native extension-context actions without sending a model prompt. Internal command names are filtered out of the user command palette.

The Packages & Resources page uses the installed Pi SDK's `SettingsManager` and `DefaultPackageManager`, matching `pi list`, `pi install`, `pi remove`, `pi update --extensions`, and the resource-filter behavior of `pi config`. Snapshot refreshes call `resolve(() => "skip")`, so merely opening the page never installs a missing package. Project resource overrides use Pi's package delta and `+` / `-` / `!` path semantics. Package code is reloaded only after an explicit mutation completes.

The app loads the bundled Figure Pi Package on every Pi RPC launch with one `--extension <package-root>` argument. Pi resolves the package manifest and loads its Extension and optional `figure` Skill together. The Extension registers the explicit `/figure` command, so GUI activation does not depend on automatic Skill selection. Pi 0.84.3 preserves tool `details` on `tool_execution_end`, allowing the extension to send a typed `personalPiFigureArtifact` manifest without encoding file paths in assistant prose. Extension `ctx.ui.confirm` is used for the mandatory statistical-method confirmation. When `ctx.model.input` advertises image support, the tool may also return its PNG preview for the agent's visual revision loop. The package and GUI artifact contract are documented in `docs/figure-plugin.md`.

The bundled Knowledge Pi Package follows the same package-root launch contract. It registers `/knowledge`, an optional `knowledge` workflow Skill, and tools for status, inventory, indexing, search, full-document reads, draft/source capture, and confirmed draft publication. Runtime work starts only when a command or tool is invoked. Human-readable files remain authoritative and SQLite remains derived; package behavior is documented in `docs/knowledge-plugin.md`.

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
- `export_html`
- `fork`
- `clone`
- `get_fork_messages`
- `get_tree`
- `get_last_assistant_text`
- `get_session_stats`
- `set_session_name`
- `extension_ui_response`

Pi 0.84.3 also documents, but the GUI does not yet expose:

- steering and follow-up queues
- model and thinking cycling commands
- Pi CLI self-update (`pi update --self`); the GUI manages packages and model catalogs but does not replace its own bundled/runtime updater
- standalone bash execution and cancellation
- `get_entries`

The Settings page edits common Global and Project Pi settings while preserving unknown JSON keys. It covers model defaults, `enabledModels`, `modelThinkingLevels`, `thinkingBudgets`, compaction thresholds, retry timing, message delivery, provider transport, image handling, and built-in tools. Its Advanced Runtime card covers `httpProxy`, `httpIdleTimeoutMs`, `websocketConnectTimeoutMs`, provider retry timeout/count, `sessionDir`, `shellPath`, `shellCommandPrefix`, `npmCommand`, branch-summary settings, the Anthropic extra-usage warning, and the Personal Pi-owned nested `figure` settings. Legacy `scientificFigure` values are read as fallback and their known fields migrate on save. `httpProxy` is Global-only because Pi reads it before project settings are applied. The session catalog mirrors Pi's Global/Project merge and `PI_CODING_AGENT_SESSION_DIR` precedence, resolves relative custom paths from each runtime cwd, and scans both the default session tree and unique effective custom roots. The Packages & Resources page owns package entries and the `extensions`, `skills`, `prompts`, and `themes` path arrays. Model thinking choices are derived from the full model metadata returned by Pi. Each editable scope is loaded independently, and saving reapplies the GUI-owned fields to the latest file contents before writing. The Session composer merges native GUI actions with `get_commands` results, so GUI-native commands, extension commands, prompt templates, and skill commands are available through the slash-command palette.

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
