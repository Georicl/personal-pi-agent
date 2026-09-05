# Knowledge Pi Package

Knowledge is a bundled Pi Package that combines a deterministic Extension, an optional workflow Skill, and the Python/SQLite Knowledge Core. The Extension keeps tools and `/knowledge` available in every Personal Pi session; the Skill teaches the agent when and how to use them. Retrieval is on demand, so the knowledge library is not injected wholesale into each prompt.

This follows Pi's official [Extension](https://pi.dev/docs/latest/extensions) and [Pi Package](https://pi.dev/docs/latest/packages) contracts.

## Package layout

~~~text
Resources/PiPackages/Knowledge/
├── package.json
├── personal-pi-plugin.json
├── extensions/index.js
├── skills/knowledge/SKILL.md
└── runtime/
    ├── knowledge_core.py
    ├── schema.sql
    ├── pyproject.toml
    └── uv.lock
~~~

Personal Pi launches the package root once with `--extension`. Pi resolves both the Extension and Skill from `package.json`. The Extension does not start a process or create a knowledge directory at load time.

## Slash command

~~~text
/knowledge
/knowledge status [current|global|project|both]
/knowledge inventory [current|global|project|both]
/knowledge index [current|global|project|both]
/knowledge rebuild [current|global|project|both]
/knowledge search <query>
/knowledge capture <request>
~~~

Status, inventory, index, and rebuild execute directly. Search and capture send a structured request to the active agent so it can choose and explain the appropriate tool calls.

## Tools

| Tool | Purpose |
|---|---|
| `knowledge_status` | Indexed document, chunk, and error counts |
| `knowledge_inventory` | Files, categories, bytes, support, and index state |
| `knowledge_index` | Incremental index or explicit rebuild |
| `knowledge_search` | Global/Project retrieval with exact locators |
| `knowledge_get` | Full indexed document and chunks |
| `knowledge_capture` | New inbox item, source, or draft card |
| `knowledge_publish` | Confirmed draft-to-reviewed-card transition |

Project search defaults to Project plus Global, with Project results receiving deterministic priority. Global Chat uses only Global knowledge. Drafts, inbox, deprecated cards, and malformed records are excluded by default.

Model-facing JSON output is bounded to 120,000 characters. Truncation affects only the tool message sent into the conversation; source files and SQLite chunks remain complete. The agent should narrow its query or request a more specific document when the marker appears.

## Write boundary

`knowledge_capture` never writes directly to reviewed `cards/`. Synthesized content goes to `drafts/`; raw or registered material goes to `inbox/` or `sources/`. It creates a new stable ID and file rather than silently overwriting an existing record.

`knowledge_publish` accepts only an indexed draft and requires `userConfirmed: true` and `expectedContentHash` from the user-confirmed `knowledge_get` preview (`document.contentHash`). Both the current source bytes and the indexed snapshot must match that hash. A changed draft must be reindexed, previewed, and confirmed again; callers must not substitute a newer hash automatically. It preserves the card ID, changes status to `reviewed`, moves the Markdown file into `cards/`, and reindexes. There is no knowledge deletion tool.

Publication atomically claims the original file in `.publish-recovery/<operation>/` and retains it, then exclusively links a fully prepared reviewed snapshot into `cards/`. It never unlinks a possibly replaced draft pathname or the claimed original inode. Concurrent pathname saves and in-place edits through an editor's open descriptor are retained. Failures restore only an absent original path without overwriting a concurrent save; errors include recovery locations. Success returns `recoveryPath`. Recovery originals/snapshots are hidden from indexing and normal inventory and are not automatically deleted. If a new draft appears during publication, the operation reports a conflict, retaining the new draft and any already-published confirmed version; resolve the conflict before reindexing. Filesystems that cannot perform the atomic rename/hard-link operations fail with recoverable source data rather than falling back to destructive copy/unlink behavior.

## Managed runtime

The Extension prepares its locked Python environment lazily under:

~~~text
~/.pi/agent/environments/knowledge/
~~~

`PI_CODING_AGENT_DIR`, `PERSONAL_PI_DATA_ROOT`, `PERSONAL_PI_KNOWLEDGE_ENVIRONMENT`, and `PERSONAL_PI_UV_EXECUTABLE` provide dynamic overrides for portable builds and isolated tests. No user-specific path is embedded in the package.

## Validation

~~~bash
scripts/check-knowledge-plugin.sh
~~~

The check validates both manifests and JavaScript syntax, runs the Knowledge Core suite, launches the installed Pi 0.84.3 in offline RPC mode, verifies `/knowledge`, `/skill:knowledge`, and the internal runtime command, then performs a real Project index/search/inventory cycle in temporary directories.
