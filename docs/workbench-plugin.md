# Research workbench: preview and revision

The workbench is a local downstream research interface: retrieve and read evidence,
edit text, analyze existing result tables, visualize and synthesize. Pi remains the
only model/tool loop. This first increment implements the artifact review loop;
it does not introduce upstream bioinformatics execution, a scheduler, a separate
model client or an autonomous multi-agent service.

## Implemented loop

1. Pi calls `workbench_publish_text` to create a requested Markdown output, or the
   user imports an existing Markdown/TXT file into the right sidebar.
2. The sidebar previews source text or rendered Markdown, and displays figure
   outputs through the existing Figure renderer. Text files are bounded to 200 KB.
3. Select exact text in source view, or drag a rectangle on a figure, and add a
   comment. “Add selection to chat” creates a removable composer card; it does not
   send a model request. Several comments can be sent together, up to eight.
4. On send, references carry the project, artifact ID, exact version, content
   identity, comment and selection. Text anchors use UTF-16 offsets plus the quoted
   text. Figure regions use normalized coordinates from the top-left. A marked
   PNG thumbnail accompanies each figure reference through Pi's native `images` RPC
   field. An explicitly text-only model cannot send image review attachments.
5. Text revision reads the exact base and publishes a new version. Figure revision
   reads the retained plotting recipe and renders a new version. The user can
   compare text additions/removals or inspect the prior figure below the current one.

The model handles interpretation and wording; the plugin enforces version creation,
base identity and conflict rejection. Text sources/quotes are reference data, not
instructions. Existing sources and unrelated content are preserved. Ordinary chat
does not require an artifact. A source reference is a path, document ID or URL;
semantic claim-to-evidence checking is still the model/user's responsibility.

## Ownership and interfaces

- `Resources/PiPackages/Workbench/runtime.mjs`: dependency-free Node storage and
  import/read/publish/list operations, shared by GUI and the Pi Extension.
- `extensions/index.js`: `workbench_publish_text`, `workbench_read_text`, `/workbench`.
- `WorkbenchStore`: current-project text catalog; generation checks reject late
  results from another project. Existing FigureArtifactStore retains figure ownership.
- `WorkbenchSidebarView`: renderer selection, import/export, preview and comments.
- `AppState`: composer attachments, project draft isolation, submission and errors.
- `PiRPCClient`: typed text-artifact tool details and native image message fields.

No Skill is needed to drive this revision loop. Pi packages do not inject Swift UI;
the compiled application supplies the text and figure renderers declared in manifests.

Text outputs live in `<cwd>/.pi/artifacts/texts/<artifactId>/v000001/`:

```text
document.md       # exact editable source snapshot, never overwritten by the plugin
artifact.json     # version, parent, project/session, title, content hash, source refs
```

Revisions require the latest `baseVersion` and matching `baseHash`. The plugin verifies
the actual source bytes before using the base. Concurrent writers use one series lock
and publish a complete version directory. A stale comment is not silently applied
to a different version. A crash during saving can leave `.writing`; that error is
shown rather than automatically deleting a lock that might belong to another process.
Imports copy the selected file; they do not alter it. Exports create independent files.

Figure outputs now include `revision.json` containing plotting code, parameters and
input paths. The minimal recipe is retained regardless of the diagnostic work-file
setting. Data files remain external references, so changing input data can change
subsequent renders. Logs and extra source/request copies remain opt-in. Legacy figures
without a recipe remain viewable/exportable; faithful source revision may require the
original plotting code and data. Initial generation allows five attempts. A new user
review from the latest version starts another cycle with `reviewId` and
`reviewBaseVersion`, permitting five attempts and rejecting competing stale reviews.

## Validation

- `node --test Tests/WorkbenchTests/runtime.test.mjs`: imports, independent source
  copies, immutable versions, stale/modified base rejection, concurrency and scope.
- `bash scripts/check-workbench-plugin.sh`: adds actual offline Pi tool registration
  and publish/read/revise handlers, without model credentials.
- `swift test --filter WorkbenchTests`: Unicode selections, image coordinates,
  content identity, scope, diffs, event decoding and the real Node adapter.
- XCUITest `testTextSelectionReviewAndVersionComparison` and
  `testFigureRegionReviewToChat`: native selection/drag, composer cards and comparison.

UI tests use isolated read-only text fixtures and no Node/model process. Native backend
and RPC tests separately exercise actual storage and tool execution. Model interpretation
quality is distinct from these deterministic checks.

## Next capability boundaries

The next work can compose Literature, Knowledge, downstream analysis and report
generation around these artifact/version interfaces. DOCX layout-preserving editing,
PDF annotations, semantic figure-element selection, and automatic updates to all
dependent report paragraphs are not part of this first increment.
