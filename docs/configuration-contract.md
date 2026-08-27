# Personal Pi Configuration Contract

This contract separates Pi-owned runtime state, Personal Pi data, and project-owned resources. All paths are derived from the current user's home directory or the selected project; no username, checkout path, or Node version is fixed in code.

## Global scope

```text
~/.pi/
├── agent/                         # Owned by Pi
│   ├── auth.json                  # Credentials; never read by the GUI diagnostics
│   ├── settings.json              # Global Pi settings
│   ├── trust.json                 # Saved project trust decisions
│   ├── sessions/                  # Pi JSONL sessions
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
- The Swift GUI may display credential presence and provider status but not credential contents.
- Global Chat always runs with `~/.pi/chat` as cwd.
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
| Authentication, model config, session JSONL | Pi under `~/.pi/agent` |
| Project selection, status, presentation | Swift GUI |
| Agent loop, context compaction, branch/session behavior | Pi runtime |
| Work methods and staged procedures | Skills |
| Reusable prompt expansion | Prompt templates |
| New tools, lifecycle hooks, external integrations | Extensions |
| Long-term structured knowledge and retrieval indexes | Future Personal Pi knowledge layer |

## Loading policy

Personal Pi intentionally launches project RPC with `--approve` because this is a personal local workspace and the user does not want an additional GUI permission layer. This means project `.pi/settings.json`, extensions, skills, prompts, themes, and system files can load.

The implication is explicit: project-local extensions execute with the user's local permissions. Untrusted or unattended repositories require OS/container isolation; the project trust switch is not that isolation.

## Initial resource conventions

- Use `AGENTS.md` for stable project facts, canonical commands, writable/generated paths, constraints, and completion criteria.
- Use Skills for multi-step methods that should load only when relevant.
- Use prompt templates for short user-invoked task starters.
- Use Extensions only when the Agent needs a new callable tool, event interception, persistent extension state, or external integration.
- Keep personal knowledge as retrieved data with source and uncertainty metadata, not as a large permanent system prompt.
