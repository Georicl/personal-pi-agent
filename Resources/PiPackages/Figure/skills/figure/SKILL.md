---
name: figure
description: Create, inspect, validate, iteratively revise, preview, and export publication-quality figures from tabular, Excel, NumPy, or pandas data. Use whenever the user asks to create or revise a chart, plot, visualization, or figure.
compatibility: Requires the Personal Pi Figure extension, uv, and Python 3.11-3.14.
---

# Figure

Use this workflow whenever the user asks to create or revise a figure. The explicit `/figure` command activates the same workflow without relying on automatic Skill selection.

## Non-negotiable rules

- Never change source data to improve appearance or significance.
- Never overwrite an input data file.
- Do not silently choose or run a statistical test. Explain the proposed method and obtain user confirmation first.
- Treat PDF as vector output when the plotting backend supports it. DPI applies to PNG/TIFF and raster elements, not the PDF page itself.
- Default size is 210 × 74.25 mm. Width must not exceed 210 mm and height must not exceed 148.5 mm.
- Default raster resolution is 300 DPI.
- Keep only generated image files by default. Retain source code, request JSON, logs, or validation files only when the user explicitly asks.
- Iterate at most five times. If the fifth result still fails, stop and ask the user how to proceed.

## Required workflow

1. Identify every input file and the requested scientific message.
2. Call figure_inspect_data for each data source before plotting.
3. Choose a general plot grammar based on variables and intended comparison. Read references/library-routing.md and references/plot-recipes.md when needed.
4. If significance markers, survival comparisons, fitted models, confidence intervals derived from a model, correlations with p-values, or any inferential statistic is requested:
   - state the candidate method, assumptions, groups, sample unit, correction, and expected annotation;
   - wait for explicit user confirmation;
   - pass statisticalAnalysis with the confirmed method to the render tool.
5. Call figure_render with a complete Python body that assigns the final Matplotlib Figure to a variable named fig.
6. Read every validation error and warning. When the current model supports images, inspect the returned preview as well.
7. Revise the plotting code and call figure_render again with the same figureId and the next iteration.
8. Stop when deterministic validation passes and no visible defect remains, or after iteration five.
9. Report the final figure and formats. Do not expose temporary scripts or logs unless requested.

## Python execution contract

The render tool supplies these names to the submitted Python body:

- data_paths: absolute input paths.
- datasets: loaded objects in the same order as data_paths.
- data: the first loaded object, or None.
- load_table(path, **options): the shared table loader.
- np, pd, plt, sns.
- width_mm, height_mm, dpi.

The code must assign a Matplotlib Figure to fig. Create the figure at the supplied physical dimensions with `figsize=(width_mm / 25.4, height_mm / 25.4)` before applying `tight_layout` or other layout logic. It may create multi-panel layouts and may call other installed plotting libraries, but final export always passes through the validated Matplotlib figure.

For Plotnine, build the grammar object and assign `fig = plot.draw()`; then set the returned Matplotlib Figure to the requested physical size before validation.

Example:

~~~python
fig, ax = plt.subplots(figsize=(width_mm / 25.4, height_mm / 25.4))
sns.scatterplot(data=data, x="x", y="y", hue="group", ax=ax)
ax.set_xlabel("X measurement")
ax.set_ylabel("Y measurement")
~~~

## Iteration behavior

- Reuse figureId across revisions so the GUI groups versions together.
- Set iteration from 1 through 5.
- Fix errors before cosmetic warnings.
- Do not claim success when validation.passed is false.
- If a warning is scientifically intentional, explain it rather than repeatedly changing the data representation.

## Documentation lookup

Call figure_library_docs when an API or format is uncertain. Prefer official library documentation and record the library/topic used in the reasoning. Do not invent unsupported parameters.

## References

- references/library-routing.md
- references/plot-recipes.md
- references/quality-checklist.md
