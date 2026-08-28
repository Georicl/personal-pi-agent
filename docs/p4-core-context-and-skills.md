# P4 Core Context and Skills

This phase establishes Personal Pi's always-on global working context and four on-demand workflows. It intentionally does not add prompt templates, extensions, a knowledge database, or browser automation.

## Public and private boundary

The repository stores generic starter resources under `Resources/StarterPack/`. Personal runtime copies live under `~/.pi/agent/` and are not committed to this public repository.

| Starter resource | Runtime destination |
|---|---|
| `global/AGENTS.md` | `~/.pi/agent/AGENTS.md` |
| `skills/<name>/` | `~/.pi/agent/skills/<name>/` |

The global context contains only stable working rules. Skills use progressive disclosure: Pi keeps names and descriptions available, then reads the complete `SKILL.md` only when a task matches or the user invokes `/skill:<name>`.

## Responsibilities

- `project-start`: read-only project discovery and bounded planning.
- `code-change`: implementation, validation, review, and authorized Git integration.
- `research`: traceable evidence retrieval and synthesis.
- `knowledge-capture`: explicit structured writes to global or project knowledge.

## Validation

Validate frontmatter and discovery against the installed Pi version. Then run Pi in both Global Chat and a trusted project and confirm that all four `/skill:*` commands are returned by `get_commands`.

Run the repository check with:

```bash
scripts/check-starter-pack.sh
```
