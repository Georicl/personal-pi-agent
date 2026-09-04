# Quality checklist

The runner performs deterministic checks, but the agent remains responsible for scientific interpretation.

## Deterministic checks

- PNG, TIFF, and PDF are readable when generated; PDF has the requested physical page size.
- PNG/TIFF pixel dimensions and embedded DPI metadata match physical size and DPI.
- Width is at most 210 mm and height at most 148.5 mm.
- The raster preview is not empty or nearly uniform.
- Text and legends are not clipped by the canvas.
- Font sizes below 6 pt are reported.
- Exported formats are registered in the artifact manifest.

## Agent visual review

- The plot answers the stated question.
- Encodings match the variables and sample unit.
- Labels, units, legends, scales, and panel order are unambiguous.
- Dense points, labels, and annotations remain readable.
- Colors remain distinguishable and work in grayscale where necessary.
- Error bars and intervals are defined.
- Statistical marks correspond exactly to a confirmed method.
- No transformation, filtering, or aggregation is hidden.

## Completion

Pass only when deterministic validation succeeds and visual review finds no defect. After five attempts, return the latest preview and move the task to user review.
