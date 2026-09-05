# Merged-main and Literature MVP acceptance

Date: 2026-09-06 (Asia/Shanghai).
Merged baseline: `e1db632` (PR #25). Development branch: `codex/literature-mvp`.

## Merged-main acceptance

Built the baseline with Xcode before changing application source. Used two
isolated projects and an isolated Pi data root, with native Pi 0.84.3 and no
model credentials. Real GUI operations, not just filesystem assertions:

- Switch Project A → B and restore each saved native session. The displayed
  message and runtime cwd match that project; the other project's message clears.
- Index a fixture draft, open its content, publish the viewed version. Knowledge
  shows one reviewed card and zero drafts; the original recovery location is
  reported. The fixture explicitly states that it is not research evidence.
- Open a real generated figure in the global right sidebar and export PNG,
  TIFF and PDF through the GUI. PNG/TIFF: 2480 × 877 pixels, 300 DPI. PDF:
  595.2756 × 210.4724 points (210 × 74.25 mm). Poppler rendering confirms all
  three bars, axes and labels are present, not a blank page. Automated Figure
  tests independently verify content bounds across scales and rotations.
- Baseline: 71 Swift tests passed, including real native RPC workflow boundaries.

All test projects, sources and final image copies remain in ignored local build
directories; no user research library was changed or uploaded. The macOS save
panel initially treated full paths entered in its filename field as filenames;
the generated outputs were located and moved into the isolated acceptance folder
before content verification. Success was not inferred solely from the GUI label.

## Literature acceptance

- A real GUI search for public record `EXT_ID:32810481 AND SRC:MED` returned one
  record with authors, 2021 publication year, DOI, PMID, abstract and original/
  provider links. The Chinese result counts and provenance render correctly.
- No default selection. Clicking a record enables save. Saving updates the
  existing Knowledge file count; saving again reuses the same local source.
- Switching to Project B clears Project A's query, results and selected sources.
- Offline tests cover typed plans, query/year limits, missing metadata, identifier
  deduplication, retained retrieval provenance, concurrent/repeated imports,
  project/Global boundaries, forged selections, partial failure, HTTP/timeouts,
  response bounds, JSON protocol and source-linked draft-only summaries.
- Opt-in live provider test passed. Native Pi RPC invokes the actual registered
  plan/save/draft handlers, using the shared locked Knowledge environment.
- Swift tests cover package discovery, typed plans, late query/scope responses,
  manual-edit fencing and the real Swift → Python adapter.
- Strict release compilation, Xcode app build and ad-hoc signature verification
  passed. Existing Knowledge Core (33 tests), Knowledge and Figure plugin checks
  passed. Test environments are kept outside bundled resource directories.

## Explicit limitations

- The new XCUITest navigation case compiles. On this host its unsigned runner
  exited before bootstrap; an ad-hoc-signed retry reached the runner but timed
  out enabling macOS automation. **The XCUITest case did not execute and is not
  counted as passed.** Manual native GUI acceptance above was completed through
  the available computer-use interface. No system permission was changed.
- No paid LLM request was made. Actual native tools and GUI/bridge paths were
  exercised, but quality of a model's query translation or synthesis remains
  subject to the user's review. The UI discloses use of the current session/model.
- One retrieval provider, at most 50 records per search, metadata/abstracts only.
  No full-text downloading, systematic-review exhaustive pagination, model
  reranking, or automatic reviewed-card publication is claimed.
- The PR is submitted for independent architecture review; it is not merged by
  this development task. CI results are recorded on the PR's exact head commit.
