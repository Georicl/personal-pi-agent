# Personal Pi Configuration Contract

This contract separates Pi-owned runtime state, Personal Pi data, and project-owned resources. All paths are derived from the current user's home directory or the selected project; no username, checkout path, or Node version is fixed in code.

## Global scope

```text
~/.pi/
├── agent/                         # Owned by Pi
│   ├── auth.json                  # Credentials; never read by the Swift GUI
│   ├── settings.json              # Global Pi settings
│   ├── models.json                # Custom providers and model definitions
│   ├── trust.json                 # Saved project trust decisions
│   ├── sessions/                  # Default Pi JSONL sessions
│   ├── personal-pi-figure-artifacts.json # Personal Pi artifact index
│   ├── environments/scientific-figure/   # Personal Pi managed uv environment
│   ├── AGENTS.md                  # Optional global working instructions
│   ├── SYSTEM.md                  # Optional system-prompt replacement
│   ├── APPEND_SYSTEM.md           # Optional system-prompt addition
│   ├── skills/                    # Global skills
│   ├── prompts/                   # Global prompt templates
│   └── extensions/                # Global extensions
├── chat/                          # Global Chat cwd and temporary artifacts
├── knowledge/                     # Global knowledge source files
└── personal/                      # Future Personal Pi database and indexes
```

Rules:

- Do not version-control `~/.pi/agent` as a whole.
- Never copy `auth.json` into a project or frontend bundle.
- The Swift GUI may display auth-store presence and provider readiness but never opens credential contents.
- The Swift GUI does not invent login providers. It asks the installed Pi runtime for the same provider and authentication-method catalog used by `/login`.
- Provider authentication is delegated to Pi's native model runtime. OAuth URLs are opened by the GUI when Pi emits them; API-key values exist only in the secure input long enough to answer Pi's local prompt and are not logged or retained by the GUI.
- Logout delegates to `ModelRuntime.logout` and removes only Pi's stored credential. Environment variables and ambient provider configuration remain unchanged.
- Package and resource management delegates to Pi's `SettingsManager` and `DefaultPackageManager`. Global packages use `~/.pi/agent/settings.json`; project packages and resource overrides use `<project>/.pi/settings.json` and `<project>/.pi/` managed storage.
- Package listing is read-only and skips missing-package installation. Explicit Install, Remove, Update, resource-toggle, and path-save actions are the only package-page operations that mutate Pi state.
- Project resource controls preserve Pi's `inherit`, explicit load, and explicit unload semantics, including delta overrides for resources inherited from Global packages.
- Provider readiness comes from `pi auth check --provider <id> --json --no-refresh`; the GUI never requests `--credentials`.
- Global Chat always runs with `~/.pi/chat` as cwd.
- `sessionDir` may redirect session files globally or per project. Relative paths resolve from the Pi process cwd, while `~` resolves from the current user's home directory.
- Session discovery always includes the default `~/.pi/agent/sessions/` tree plus every unique effective `sessionDir` for Global Chat and registered projects. Overlapping roots are deduplicated by canonical session-file path.
- Global knowledge is an external source; it is retrieved on demand rather than injected wholesale into every prompt.

## Project scope

```text
<project>/
├── AGENTS.md                      # Project purpose and working rules
└── .pi/
    ├── settings.json              # Optional project overrides
    ├── SYSTEM.md                  # Optional project system replacement
    ├── APPEND_SYSTEM.md           # Optional project system addition
    ├── skills/                    # Project workflows
    ├── prompts/                   # Project prompt templates
    ├── extensions/                # Project-only tools and integrations
    ├── themes/                    # Optional themes
    ├── knowledge/                 # Project knowledge sources
    ├── artifacts/figures/         # Scientific Figure image outputs
    └── npm/                       # Pi-managed package dependencies
```

Rules:

- A selected project is represented by its canonical root directory.
- Personal Pi starts RPC with the project root as cwd.
- Project `.pi` resources load through Pi's native discovery; the GUI does not copy them into global storage.
- Merely selecting a project does not create `.pi` or `.pi/knowledge`.
- Opening or writing project knowledge may create `.pi/knowledge` explicitly.
- Project resources should be trusted code and instructions. Pi trust is a loading guard, not a sandbox.

## Responsibility boundaries

| Concern | Owner |
|---|---|
| Authentication, provider catalog, model config, session JSONL | Pi under `~/.pi/agent` |
| Project selection, status, presentation | Swift GUI |
| Agent loop, context compaction, branch/session behavior | Pi runtime |
| Work methods and staged procedures | Skills |
| Reusable prompt expansion | Prompt templates |
| New tools, lifecycle hooks, external integrations | Extensions |
| Long-term structured knowledge and retrieval indexes | Future Personal Pi knowledge layer |
| Scientific plotting policy | Bundled `scientific-figure` Skill |
| Data inspection, rendering and validation | Bundled Scientific Figure Extension and locked Python runner |
| Figure preview index and export presentation | Swift GUI |

The GUI-owned `scientificFigure` object in Global or Project `settings.json` is intentionally separate from Pi's native keys. The bundled Extension reads `pythonPath` and `keepWorkFiles`; unknown sibling keys remain preserved by the GUI's atomic settings update.

## Loading policy

Personal Pi intentionally launches project RPC with `--approve` because this is a personal local workspace and the user does not want an additional GUI permission layer. This means project `.pi/settings.json`, extensions, skills, prompts, themes, and system files can load.

The implication is explicit: project-local extensions execute with the user's local permissions. Untrusted or unattended repositories require OS/container isolation; the project trust switch is not that isolation.

## Initial resource conventions

- Use `AGENTS.md` for stable project facts, canonical commands, writable/generated paths, constraints, and completion criteria.
- Use Skills for multi-step methods that should load only when relevant.
- Use prompt templates for short user-invoked task starters.
- Use Extensions only when the Agent needs a new callable tool, event interception, persistent extension state, or external integration.
- Keep personal knowledge as retrieved data with source and uncertainty metadata, not as a large permanent system prompt.
