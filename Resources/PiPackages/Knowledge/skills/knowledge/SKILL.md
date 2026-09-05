---
name: knowledge
description: Search, read, capture, organize, and publish Personal Pi knowledge with Global or Project scope, exact provenance, review status, and explicit separation of facts, summaries, inferences, and user judgments.
compatibility: Requires the bundled Personal Pi Knowledge extension, uv, and Python 3.11-3.14.
---

# Knowledge workflow

Use the Knowledge extension tools instead of scanning all knowledge files into context.

## Retrieval

1. Search both Project and Global knowledge unless the user limits scope.
2. Prefer reviewed cards and registered sources. Drafts and inbox items are excluded unless explicitly requested.
3. Read the complete document with `knowledge_get` when a search chunk is insufficient.
4. Cite the document title plus section or page locator in the answer.
5. Keep source facts, model summaries, model inferences, and user judgments distinct.

## Capture

Use `knowledge_capture` only when the user explicitly requests durable storage or an active workflow requires it.

- `inbox`: unreviewed material awaiting organization.
- `sources`: source material with origin details.
- `drafts`: synthesized knowledge awaiting review.

Every draft should identify its type, confidence, tags, and sources. Use a `source_id` and locator whenever the source is already registered. Do not store credentials, private transcripts, or transient task status.

## Review and publication

Check the draft against its sources, correct unsupported claims, and surface uncertainty. Preview it with `knowledge_get` and retain that response's `document.contentHash`. Call `knowledge_publish` only after the user explicitly confirms that exact draft version, passing its hash as `expectedContentHash`. If the file or index changed, reindex, preview, and obtain confirmation again; never silently replace the confirmed hash. Never represent a draft, inbox item, or model inference as reviewed knowledge.

## Maintenance

Use incremental `knowledge_index` after file changes. Use rebuild only when the derived index is missing or inconsistent; source files remain authoritative. Use `knowledge_inventory` to report file count, total bytes, categories, unsupported attachments, and indexing errors.
