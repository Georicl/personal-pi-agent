# Knowledge Core

Knowledge Core is the storage, parsing, indexing, and retrieval foundation for Personal Pi knowledge. The runtime is bundled below `Resources/PiPackages/Knowledge/runtime/`; the Knowledge Pi Package exposes it to Pi CLI, and the Swift GUI consumes the same protocol instead of creating a second database implementation.

## 1. Source-of-truth boundary

Human-readable files are authoritative:

- `inbox/`: unreviewed source material; excluded from search by default.
- `sources/`: registered Markdown, text, and text-layer PDF evidence.
- `cards/`: reviewed Markdown knowledge cards.
- `drafts/`: proposed cards; excluded from search by default.
- `attachments/`: managed attachments reserved for later import workflows; not indexed directly in PR A.

Legacy `entries/` directories from the Starter Pack are indexed for compatibility. New writes use `drafts/` or `cards/`; an `entries/` file with `status: draft` remains excluded from default search.

SQLite databases are derived indexes. They may be deleted and rebuilt without deleting source files or cards. Agent instructions remain in `AGENTS.md`; session history remains in Pi JSONL. Neither belongs in the knowledge database.

## 2. Scope and paths

Global content:

~~~text
~/.pi/knowledge/{inbox,sources,cards,drafts,attachments}/
~~~

Project content:

~~~text
<project>/.pi/knowledge/{inbox,sources,cards,drafts,attachments}/
~~~

Derived indexes stay outside projects:

~~~text
~/.pi/personal/knowledge/global.sqlite
~/.pi/personal/knowledge/projects/<canonical-project-path-hash>/index.sqlite
~~~

`piRoot` may override `~/.pi` for tests or portable deployments. Project identity is derived from the canonical project root, so `/var` and `/private/var` aliases do not create duplicate scopes on macOS.

## 3. Supported documents

PR A indexes:

- Markdown: heading-aware sections plus optional YAML frontmatter.
- TXT: paragraph-preserving chunks.
- PDF: text extraction with one-based page locators.

Hidden files and symbolic links are skipped. A file may be at most 50 MiB and extracted text may be at most 5 million characters. Scanned/image-only PDFs require future OCR support and currently produce no searchable chunks.

Each indexed document records:

- stable source/card ID;
- Global or Project scope;
- relative source path and category;
- title, status, type, confidence, tags, and source references;
- SHA-256 content hash, byte size, modification time, and indexing time;
- parsing error when indexing fails.

Each chunk preserves its source document, ordinal, heading, page number or section locator, text, and content hash.

## 4. Knowledge card contract

Files in `cards/` and `drafts/` require YAML frontmatter:

~~~yaml
---
id: card-graph-construction
title: Graph construction for spatial data
type: method
status: reviewed
confidence: medium
tags: [graph, spatial-omics]
sources:
  - source_id: source-paper-1
    locator: "Methods, page 4"
---
~~~

Required fields are `id`, `title`, `type`, `status`, and `sources`. `status` is `draft`, `reviewed`, or `deprecated`; `confidence` is `unknown`, `low`, `medium`, or `high`. Draft cards must live in `drafts/`; `cards/` cannot contain a draft. A card may use an empty `sources` list only when a later workflow explicitly records a user-originated judgment.

Malformed cards remain visible in index status as errors but are never returned by search.

## 5. SQLite schema

`schema.sql` defines:

| Table | Purpose |
|---|---|
| `schema_info` | Schema version |
| `scopes` | Canonical Global/Project roots |
| `documents` | SourceRecord and KnowledgeCard metadata, including legacy `entries/` |
| `chunks` | Located document content |
| `chunks_fts` | Trigram FTS5 index for English and Chinese substring retrieval |
| `indexing_runs` | Incremental/rebuild audit records and counts |

SQLite runs with foreign keys and WAL enabled. FTS entries are synchronized by insert, update, and delete triggers.

## 6. Runner protocol

`knowledge_core.py` reads one JSON object from stdin and writes one JSON object to stdout. It supports:

| Action | Required fields | Behavior |
|---|---|---|
| `initialize` | `scope` | Create canonical directories and schema |
| `status` | `scope` | Report document/chunk/error counts and latest run |
| `inventory` | `scope` | List files, category/byte totals, format support, and index state |
| `index` | `scope` | Incrementally add, update, retain, and remove records |
| `rebuild` | `scope` | Replace only the derived index, then rescan files |
| `search` | `scopes`, `query` | Search one or more indexes and return located chunks |
| `get` | `scope`, `documentId` | Return one document and all chunks |
| `capture` | `scope`, `category`, `title`, `content` | Create an inbox item, source, or draft card and index it |
| `publish` | `scope`, `documentId`, `userConfirmed` | Move a confirmed draft into reviewed cards and reindex |

Global initialization example:

~~~json
{
  "action": "initialize",
  "scope": {"kind": "global"}
}
~~~

Merged Project-first search:

~~~json
{
  "action": "search",
  "query": "graph construction",
  "scopes": [
    {"kind": "project", "projectRoot": "/path/to/project"},
    {"kind": "global"}
  ],
  "includeDrafts": false,
  "includeInbox": false,
  "limit": 20
}
~~~

Every result contains the document identity and provenance plus an exact chunk, locator, heading/page, and deterministic score. Multi-term full-text queries require every term to match the same chunk; semantic expansion and optional broad fallback belong to the later Pi Extension layer. A missing scope index is reported in the `scopes` array rather than being silently represented as a valid empty result.

## 7. Incremental behavior

The indexer hashes every supported file and records five independent counts:

- `indexed`: new documents;
- `updated`: changed documents;
- `unchanged`: matching content hashes, including unchanged invalid files;
- `removed`: stale database records deleted after the source disappears;
- `failed`: newly encountered parse or validation failures.

Deleting or rebuilding an index never removes knowledge files. The runner ignores unrelated files and does not follow symlinks outside the knowledge root.

## 8. Current boundary

The current core and Pi Package do not yet provide:

- redesigned Knowledge GUI;
- embeddings or model reranking;
- OCR, DOCX, HTML, or web ingestion;
- literature database adapters.

The deterministic local index remains useful without those layers. See [Knowledge Plugin](knowledge-plugin.md) for the Pi tools and command contract.

## 9. Validation

~~~bash
scripts/check-knowledge-core.sh
scripts/check-knowledge-plugin.sh
~~~

The check validates the lock file and runs isolated tests for canonical paths, directory/schema creation, English and Chinese search, Global/Project merging, reviewed cards and draft exclusion, legacy-entry compatibility, invalid-card auditing, file size bounds, PDF page locators, incremental updates/removals and stable-ID file moves, rebuild, and the stdin/stdout JSON protocol.
