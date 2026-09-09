# Workbench preview and revision acceptance

Date: 2026-09-09 (Asia/Shanghai). Base: `e1db632`, fetched from `origin/main`.
Branch: `codex/artifact-review-loop`. Literature PR #26 remains independent.

## Observed native GUI behavior

Built the application with Xcode, then launched it with `PERSONAL_PI_UI_TESTING=1`
and an isolated data root under `.build/workbench-acceptance`. Source files and
two versions each of a Markdown report and a generated bar chart are test fixtures,
explicitly not research evidence. No model credentials or user library were used.

Using native app accessibility and screenshots:

- Opened the shared right sidebar; Chinese text/figure controls, import and export
  actions, and current version selectors were visible.
- Selected the exact Chinese sentence in text source view, entered a comment and
  added it to the composer. The composer showed title, v2, quoted sentence and comment.
- Enabled comparison; it showed the removed v1 sentence and added v2 sentence while
  preserving surrounding text.
- Switched to figures, dragged a rectangle over the plot and entered a second comment.
  The red selection rectangle was visible, and the add-to-chat action became enabled.
- Added the figure comment. Both the text and figure comments remained in the same
  composer, without starting a model request.
- Enabled figure comparison. The current green-bar version and prior orange-bar
  version were both visible, with the current selection retained.

## Automated evidence

The repository includes dedicated Swift, Node and native Pi checks listed in
`docs/workbench-plugin.md`. They cover source copies, exact versions, stale edits,
concurrent saves, Unicode selections, image coordinates/encoding, RPC image fields,
project draft isolation, real Node import/read and real offline Pi publish/read/revise.
Figure checks render revised PNG/TIFF/PDF output, verify the old bytes remain intact,
and enforce five attempts per user-review cycle.

The two new XCUITest cases compiled, but their initial execution failed because macOS
reported loss of the application accessibility connection and missing UI-testing
authorization. They are not recorded as passing. The interaction evidence above is
from separate native computer-use verification. The final build/test/CI results are
recorded in the PR on its exact head.

## Interpretation

These checks verify the GUI, references, source storage, tool calls and actual figure
regeneration. They do not measure a paid model's interpretation of arbitrary comments.
Text selection is exact in Markdown source view; rendered preview is a reading mode.
DOCX/PDF annotation and a complete literature-to-report orchestration layer are later
increments, not claimed by this change.
