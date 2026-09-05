# Literature MVP contract

Literature is a bundled Pi Extension, not a skill-only feature. It uses the
Knowledge package's locked Python environment and capture/index APIs. No second
knowledge database or new model credential is introduced.
Runtime bytecode caching is disabled so importing shared Python modules cannot
modify resources inside a signed app bundle.

## Workflow

1. The GUI sends the user's question to the current Pi session only when asked.
   Pi calls `literature_plan` with an English Europe PMC query and an explanation.
   This performs no network search. The typed `personalPiLiterature` tool result
   opens the Literature page with editable conditions. Manual query entry works
   without an LLM.
2. The user reviews/edits the exact outbound query, years and result limit, then
   clicks Search. Only those search conditions go to Europe PMC, never the local
   knowledge library. `literature_search` provides the same operation to Pi;
   agent workflow must show conditions and obtain confirmation before searching.
3. Results show title, authors, year, DOI/PMID/PMCID, abstract and source links.
   Missing fields remain missing. Abstract text is source evidence, not full-text
   evidence or a model summary. DOI/PMID/PMCID and source IDs deduplicate records;
   titles alone do not identify papers. Search run ID, exact query, UTC retrieval
   time, provider, original record IDs and links accompany each record.
4. Only selected records are saved, into the explicitly captured current Project
   `sources/` (Global Chat uses Global sources). Repeated imports reuse existing
   literature sources in that scope. No full-text download occurs in this MVP.
5. A user can request a summary of saved sources in Pi. `literature_draft` writes
   model synthesis to `drafts/`, linked to local source IDs; publication continues
   through Knowledge's existing preview/hash/confirmation protocol. It cannot
   write reviewed cards.

## Implementation boundaries

- `runtime/literature.py` accepts JSON `plan`, `search`, `save`, `draft`; uses the
  sibling Knowledge runtime, and emits one JSON success/error envelope.
- Searches store bounded snapshots under `<piRoot>/personal/literature/<runId>.json`.
  Every snapshot is bound to the canonical project or Global scope. Save accepts
  run ID and selected record IDs, not model-reconstructed bibliographic facts.
  Snapshots are retained for provenance; no automatic deletion. No API tokens.
- GUI state is cleared on scope change. Async callbacks are generation-checked.
  A save already submitted completes only in its captured original scope; it
  never follows a later project switch. Search revisions prevent older results
  replacing a newer request or edited query.
- Typed tool details include schemaVersion=1, kind=plan/search/saved/draft, cwd,
  and result. AppState accepts them only for its current runtime cwd.
- `literature_plan` does not silently run a search or save sources. Search does
  not create chat tasks unless the model itself is running.
- Online data is untrusted text. No HTML execution, downloaded code, guessed
  bibliographic metadata, automatic publication or silent fallback provider.
- MVP provider: Europe PMC production REST `/search`, JSON `resultType=core`,
  at most 50 results per explicit search. The total hit count is shown separately
  from retrieved count; this is not an exhaustive systematic-review export.
  Errors/timeouts are explicit and retry is user-triggered.

Official references: [REST API](https://europepmc.org/RestfulWebService),
[search syntax](https://europepmc.org/searchsyntax),
[official mirror of API documentation](https://dev.europepmc.org/RestfulWebService).

## Validation

`scripts/check-literature-plugin.sh`: offline normalization, deduplication,
provenance, capture/draft integration, wrong-project rejection, error paths and
native Pi RPC command discovery. `PERSONAL_PI_TEST_LITERATURE_LIVE=1` additionally
checks a public query against the real provider. Swift tests cover typed events,
scope fencing and GUI state. Xcode UI smoke covers the localized page.
