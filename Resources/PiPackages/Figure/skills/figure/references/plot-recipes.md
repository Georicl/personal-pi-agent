# Plot recipes

These are routing patterns, not fixed templates. Always adapt labels, scales, units, grouping, and uncertainty to the data.

## General figures

- Scatter: quantitative x and y; encode a small categorical variable with color or marker. Consider transparency only when overplotting is real.
- Line: ordered or temporal x; show independent units separately or summarize with an explicitly defined uncertainty interval.
- Bar: aggregated values, not hidden raw observations. State the summary and error definition.
- Box/violin: distributions across categories. Add raw observations when sample size permits.
- Histogram/density: one-dimensional distribution. Report bin or bandwidth choices.
- Heatmap: matrix-like values. Preserve a meaningful row/column order and label the color scale.

## Biological figures

- Volcano: x is effect size, y is negative log10 adjusted p-value. Statistical method and adjustment must already be confirmed.
- MA: x is mean abundance, y is log fold change. Distinguish filtered and significant points without hiding the remainder.
- PCA/UMAP: plot coordinates supplied by the input. Do not calculate embeddings silently when the user only asked to visualize existing coordinates.
- Enrichment dot plot: commonly map gene ratio or enrichment score to x, term to y, adjusted p-value to color, and count to size.
- Forest plot: show estimate, interval, null reference, and study/group labels. Do not infer missing intervals.
- Survival curve: requires explicit confirmation of estimator, censoring representation, group comparison, and confidence interval.

## Multi-panel figures

- Use shared legends when encodings are identical.
- Keep panel letters outside data regions.
- Align comparable axes and avoid duplicated labels.
- Do not shrink text below 6 pt merely to fit more panels.

## Color and typography

- Prefer colorblind-safe palettes.
- Never rely on color alone when categories must remain identifiable in print.
- Use sentence-case labels with units.
- Keep title, axis, tick, legend, and annotation hierarchy consistent.
- Avoid decorative 3D, gradients, shadows, and chartjunk in scientific results.
