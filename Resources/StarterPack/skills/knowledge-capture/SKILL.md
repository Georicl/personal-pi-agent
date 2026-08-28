---
name: knowledge-capture
description: Preserve durable personal or project knowledge as structured Markdown with source, time, scope, uncertainty, and separate fact, summary, inference, and user-judgment sections. Use when the user explicitly asks to save knowledge or an active workflow explicitly requires durable capture.
compatibility: Requires write access to the selected global or project knowledge directory.
---

# Knowledge Capture

Use this workflow only for explicit or workflow-authorized knowledge writes. Do not save every conversation automatically.

Use [assets/knowledge-entry.md](assets/knowledge-entry.md) as the entry structure.

## 1. Choose the scope

- **Global:** reusable across projects; write below `~/.pi/knowledge/entries/`.
- **Project:** specific to the active project; write below `<project>/.pi/knowledge/entries/`.

If the scope materially changes where knowledge will be used and is not clear, ask the user.

## 2. Check for existing knowledge

- Search by title, aliases, identifiers, source URLs, and related tags.
- Update or link an existing entry when appropriate instead of creating a duplicate.
- Do not silently replace user-authored judgments.

## 3. Select durable content

Capture decisions, verified procedures, reusable findings, source-backed facts, and important unresolved questions.

Exclude:

- credentials or authentication material;
- full private transcripts;
- temporary status that will become stale quickly;
- unsupported conclusions presented as facts;
- generated artifacts already available elsewhere.

## 4. Preserve provenance

Every entry must include:

- capture and update time;
- global or project scope;
- source list or an explicit `user-provided` source;
- confidence and review status;
- clear separation of facts, summary, inference, and user judgment.

Use ISO 8601 timestamps. Prefer a stable descriptive slug for the filename.

## 5. Write safely

- Create only the required knowledge directories.
- Preserve unrelated entries.
- If updating an entry, retain earlier sources and user judgments unless explicitly superseded.
- Link related entries rather than copying large sections.

## 6. Report the capture

Return the written path, scope, short summary, sources, confidence, and any item requiring review.

## Output format

```markdown
## Captured

## Scope and path

## Sources and confidence

## Review needed
```
