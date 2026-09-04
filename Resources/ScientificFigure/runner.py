#!/usr/bin/env python3
from __future__ import annotations

import contextlib
import io
import json
import math
import os
import re
import shutil
import sys
import traceback
import uuid
import warnings
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

os.environ.setdefault("MPLBACKEND", "Agg")

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import networkx as nx
import numpy as np
import pandas as pd
import seaborn as sns
from matplotlib.figure import Figure
from matplotlib.text import Text
from PIL import Image
from pypdf import PdfReader


DEFAULT_WIDTH_MM = 210.0
DEFAULT_HEIGHT_MM = 74.25
DEFAULT_DPI = 300
MAX_WIDTH_MM = 210.0
MAX_HEIGHT_MM = 148.5
MAX_ITERATIONS = 5

TABLE_EXTENSIONS = {
    ".csv",
    ".tsv",
    ".tab",
    ".txt",
    ".xlsx",
    ".xls",
    ".xlsm",
    ".xlsb",
    ".ods",
    ".parquet",
    ".feather",
    ".json",
    ".jsonl",
    ".pkl",
    ".pickle",
    ".npy",
    ".npz",
}

CAPABILITIES = {
    "inputExtensions": sorted(TABLE_EXTENSIONS),
    "outputFormats": ["png", "tiff", "pdf"],
    "defaultWidthMm": DEFAULT_WIDTH_MM,
    "defaultHeightMm": DEFAULT_HEIGHT_MM,
    "defaultDpi": DEFAULT_DPI,
    "maxWidthMm": MAX_WIDTH_MM,
    "maxHeightMm": MAX_HEIGHT_MM,
    "maxIterations": MAX_ITERATIONS,
    "libraries": [
        "numpy",
        "pandas",
        "scipy",
        "matplotlib",
        "seaborn",
        "plotnine",
        "pillow",
        "tifffile",
        "scikit-image",
        "statsmodels",
        "lifelines",
        "networkx",
    ],
    "plotFamilies": [
        "scatter",
        "line",
        "bar",
        "box",
        "violin",
        "histogram",
        "density",
        "heatmap",
        "volcano",
        "MA",
        "PCA",
        "UMAP",
        "enrichment-dotplot",
        "forest",
        "survival",
    ],
}


class FigureRequestError(RuntimeError):
    pass


def emit(payload: dict[str, Any]) -> None:
    encoded = json.dumps(
        payload,
        ensure_ascii=False,
        separators=(",", ":"),
        default=serializable,
    )
    sys.stdout.write(encoded + "\n")


def resolve_path(raw: str, cwd: Path) -> Path:
    path = Path(raw).expanduser()
    if not path.is_absolute():
        path = cwd / path
    return path.resolve()


def serializable(value: Any) -> Any:
    if value is None or isinstance(value, (str, int, float, bool)):
        if isinstance(value, float) and (math.isnan(value) or math.isinf(value)):
            return None
        return value
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, (np.integer,)):
        return int(value)
    if isinstance(value, (np.floating,)):
        number = float(value)
        return number if math.isfinite(number) else None
    if isinstance(value, (np.bool_,)):
        return bool(value)
    if isinstance(value, np.ndarray):
        return [serializable(item) for item in value.tolist()]
    if isinstance(value, (list, tuple, set)):
        return [serializable(item) for item in value]
    if isinstance(value, dict):
        return {str(key): serializable(item) for key, item in value.items()}
    if isinstance(value, pd.Timestamp):
        return value.isoformat()
    if pd.isna(value):
        return None
    return str(value)


def load_table(raw_path: str | Path, **options: Any) -> Any:
    path = Path(raw_path).expanduser().resolve()
    if not path.is_file():
        raise FigureRequestError(f"Data file does not exist: {path}")
    suffix = path.suffix.lower()
    if suffix not in TABLE_EXTENSIONS:
        raise FigureRequestError(
            f"Unsupported table format {suffix or '(none)'}. "
            f"Supported: {', '.join(sorted(TABLE_EXTENSIONS))}"
        )

    if suffix in {".csv", ".tsv", ".tab", ".txt"}:
        separator = options.pop("sep", None)
        if separator is None:
            separator = "\t" if suffix in {".tsv", ".tab"} else None
        if separator is None:
            return pd.read_csv(path, sep=None, engine="python", **options)
        return pd.read_csv(path, sep=separator, **options)
    if suffix in {".xlsx", ".xls", ".xlsm", ".xlsb", ".ods"}:
        return pd.read_excel(path, **options)
    if suffix == ".parquet":
        return pd.read_parquet(path, **options)
    if suffix == ".feather":
        return pd.read_feather(path, **options)
    if suffix in {".json", ".jsonl"}:
        if suffix == ".jsonl":
            options.setdefault("lines", True)
        return pd.read_json(path, **options)
    if suffix in {".pkl", ".pickle"}:
        return pd.read_pickle(path, **options)
    if suffix == ".npy":
        array = np.load(path, allow_pickle=False)
        if array.dtype.names:
            return pd.DataFrame.from_records(array)
        if array.ndim == 1:
            return pd.DataFrame({"value": array})
        if array.ndim == 2:
            return pd.DataFrame(array)
        return array
    if suffix == ".npz":
        archive = np.load(path, allow_pickle=False)
        return {key: archive[key] for key in archive.files}
    raise FigureRequestError(f"Unsupported table format: {suffix}")


def inspect_object(value: Any) -> dict[str, Any]:
    if isinstance(value, pd.DataFrame):
        visible_columns = list(value.columns[:100])
        dtypes = {str(column): str(value[column].dtype) for column in visible_columns}
        missing = {
            str(column): int(value[column].isna().sum())
            for column in visible_columns
            if value[column].isna().any()
        }
        sample = [
            {str(key): serializable(item) for key, item in row.items()}
            for row in value.head(5).to_dict(orient="records")
        ]
        numeric = value.select_dtypes(include=[np.number])
        numeric_ranges = {}
        for column in numeric.columns[:50]:
            series = numeric[column].dropna()
            if not series.empty:
                numeric_ranges[str(column)] = {
                    "min": serializable(series.min()),
                    "max": serializable(series.max()),
                }
        return {
            "kind": "dataframe",
            "rows": int(value.shape[0]),
            "columns": int(value.shape[1]),
            "columnNames": [str(column) for column in visible_columns],
            "columnsTruncated": value.shape[1] > len(visible_columns),
            "dtypes": dtypes,
            "missing": missing,
            "numericRanges": numeric_ranges,
            "sample": sample,
        }
    if isinstance(value, np.ndarray):
        return {
            "kind": "ndarray",
            "shape": list(value.shape),
            "dtype": str(value.dtype),
            "sample": serializable(value.reshape(-1)[:20]),
        }
    if isinstance(value, dict):
        visible_keys = list(value.keys())[:100]
        return {
            "kind": "mapping",
            "keys": [str(key) for key in visible_keys],
            "keysTruncated": len(value) > len(visible_keys),
            "items": {str(key): inspect_object(value[key]) for key in visible_keys},
        }
    return {"kind": type(value).__name__, "value": serializable(value)}


def inspect_file(path: Path) -> dict[str, Any]:
    details: dict[str, Any] = {
        "path": str(path),
        "name": path.name,
        "extension": path.suffix.lower(),
        "bytes": path.stat().st_size,
    }
    if path.suffix.lower() in {".xlsx", ".xls", ".xlsm", ".xlsb", ".ods"}:
        with contextlib.suppress(Exception):
            details["sheetNames"] = pd.ExcelFile(path).sheet_names
    details["data"] = inspect_object(load_table(path))
    return details


def sanitize_identifier(raw: str | None) -> str:
    if raw:
        cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", raw).strip("-._")
        if cleaned:
            return cleaned[:80]
    return str(uuid.uuid4())


def positive_number(value: Any, default: float, name: str) -> float:
    if value is None:
        return default
    try:
        number = float(value)
    except (TypeError, ValueError) as error:
        raise FigureRequestError(f"{name} must be a number") from error
    if not math.isfinite(number) or number <= 0:
        raise FigureRequestError(f"{name} must be greater than zero")
    return number


def validate_size(width_mm: float, height_mm: float, dpi: int) -> None:
    if width_mm > MAX_WIDTH_MM:
        raise FigureRequestError(f"widthMm must not exceed {MAX_WIDTH_MM:g}")
    if height_mm > MAX_HEIGHT_MM:
        raise FigureRequestError(f"heightMm must not exceed {MAX_HEIGHT_MM:g}")
    if dpi < 72 or dpi > 1200:
        raise FigureRequestError("dpi must be between 72 and 1200")


def artist_issues(fig: Figure) -> tuple[list[str], list[str], list[dict[str, Any]]]:
    errors: list[str] = []
    warnings_out: list[str] = []
    checks: list[dict[str, Any]] = []
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    figure_box = fig.bbox
    clipped: list[str] = []
    tiny_text: list[str] = []
    out_of_view_tick_labels: set[int] = set()

    # Matplotlib creates labels for locator ticks just outside the visible axis
    # interval. Their artists report off-canvas bounds even though the renderer
    # clips them intentionally, so they are not publication-layout failures.
    for axes in fig.axes:
        for axis in (axes.xaxis, axes.yaxis):
            lower, upper = sorted(axis.get_view_interval())
            tolerance = max(abs(upper - lower) * 1e-9, 1e-12)
            for tick in [*axis.get_major_ticks(), *axis.get_minor_ticks()]:
                location = tick.get_loc()
                if location < lower - tolerance or location > upper + tolerance:
                    out_of_view_tick_labels.update((id(tick.label1), id(tick.label2)))

    for artist in fig.findobj(match=Text):
        text = artist.get_text().strip()
        if not text or not artist.get_visible():
            continue
        if artist.get_fontsize() < 6:
            tiny_text.append(text[:60])
        if id(artist) in out_of_view_tick_labels:
            continue
        with contextlib.suppress(Exception):
            box = artist.get_window_extent(renderer=renderer)
            tolerance = 2.0
            if (
                box.x0 < figure_box.x0 - tolerance
                or box.y0 < figure_box.y0 - tolerance
                or box.x1 > figure_box.x1 + tolerance
                or box.y1 > figure_box.y1 + tolerance
            ):
                clipped.append(text[:60])

    if clipped:
        errors.append("Text or annotations extend outside the figure canvas: " + ", ".join(clipped[:8]))
    if tiny_text:
        warnings_out.append("Text smaller than 6 pt: " + ", ".join(tiny_text[:8]))

    checks.append({"name": "artist-clipping", "passed": not clipped, "count": len(clipped)})
    checks.append({"name": "minimum-font-size", "passed": not tiny_text, "count": len(tiny_text)})
    return errors, warnings_out, checks


def raster_issues(
    png_path: Path,
    tiff_path: Path | None,
    width_mm: float,
    height_mm: float,
    dpi: int,
) -> tuple[list[str], list[str], list[dict[str, Any]], dict[str, Any]]:
    errors: list[str] = []
    warnings_out: list[str] = []
    checks: list[dict[str, Any]] = []
    expected_width = round(width_mm / 25.4 * dpi)
    expected_height = round(height_mm / 25.4 * dpi)
    metadata: dict[str, Any] = {
        "expectedPixels": {"width": expected_width, "height": expected_height}
    }

    with Image.open(png_path) as image:
        width, height = image.size
        metadata["pngPixels"] = {"width": width, "height": height}
        png_dpi = image.info.get("dpi")
        png_dpi_ok = bool(
            png_dpi
            and abs(float(png_dpi[0]) - dpi) < 1
            and abs(float(png_dpi[1]) - dpi) < 1
        )
        metadata["pngDpi"] = (
            [float(png_dpi[0]), float(png_dpi[1])]
            if png_dpi
            else None
        )
        if not png_dpi_ok:
            errors.append(f"PNG DPI metadata does not report {dpi} DPI")
        resolution_ok = abs(width - expected_width) <= 2 and abs(height - expected_height) <= 2
        if not resolution_ok:
            errors.append(
                f"PNG dimensions {width}×{height} do not match expected "
                f"{expected_width}×{expected_height} pixels"
            )
        array = np.asarray(image.convert("RGB"), dtype=np.float32)
        channel_std = float(array.std())
        nonwhite_fraction = float(np.mean(np.any(array < 250, axis=2)))
        metadata["visualMetrics"] = {
            "channelStd": round(channel_std, 4),
            "nonWhiteFraction": round(nonwhite_fraction, 6),
        }
        if channel_std < 1.0 or nonwhite_fraction < 0.0005:
            errors.append("Raster preview is empty or nearly uniform")
        elif nonwhite_fraction < 0.01:
            warnings_out.append("Raster preview contains very little visible content")
        checks.append({"name": "pixel-dimensions", "passed": resolution_ok})
        checks.append({"name": "png-dpi", "passed": png_dpi_ok})
        checks.append(
            {
                "name": "non-empty-preview",
                "passed": channel_std >= 1.0 and nonwhite_fraction >= 0.0005,
            }
        )

    if tiff_path:
        try:
            with Image.open(tiff_path) as image:
                tiff_ok = (
                    image.size == (width, height)
                    and abs(image.width - expected_width) <= 2
                    and abs(image.height - expected_height) <= 2
                )
                metadata["tiffPixels"] = {"width": image.width, "height": image.height}
                tiff_dpi = image.info.get("dpi")
                tiff_dpi_ok = bool(
                    tiff_dpi
                    and abs(float(tiff_dpi[0]) - dpi) < 1
                    and abs(float(tiff_dpi[1]) - dpi) < 1
                )
                metadata["tiffDpi"] = (
                    [float(tiff_dpi[0]), float(tiff_dpi[1])]
                    if tiff_dpi
                    else None
                )
                if not tiff_ok:
                    errors.append("TIFF pixel dimensions differ from the validated PNG")
                if not tiff_dpi_ok:
                    errors.append(f"TIFF DPI metadata does not report {dpi} DPI")
                checks.append({"name": "tiff-readable", "passed": tiff_ok})
                checks.append({"name": "tiff-dpi", "passed": tiff_dpi_ok})
        except Exception as error:
            errors.append(f"TIFF is not readable: {error}")
            checks.append({"name": "tiff-readable", "passed": False})

    return errors, warnings_out, checks, metadata


def pdf_issues(
    pdf_path: Path | None,
    width_mm: float,
    height_mm: float,
) -> tuple[list[str], list[dict[str, Any]], dict[str, Any]]:
    if pdf_path is None:
        return [], [], {}
    errors: list[str] = []
    checks: list[dict[str, Any]] = []
    metadata: dict[str, Any] = {}
    try:
        reader = PdfReader(pdf_path)
        readable = len(reader.pages) == 1
        checks.append({"name": "pdf-readable", "passed": readable})
        if not readable:
            errors.append("PDF must contain exactly one readable page")
            return errors, checks, metadata
        page = reader.pages[0]
        actual_width = float(page.mediabox.width)
        actual_height = float(page.mediabox.height)
        expected_width = width_mm / 25.4 * 72
        expected_height = height_mm / 25.4 * 72
        size_ok = (
            abs(actual_width - expected_width) <= 0.5
            and abs(actual_height - expected_height) <= 0.5
        )
        metadata["pdfPoints"] = {
            "width": round(actual_width, 4),
            "height": round(actual_height, 4),
        }
        checks.append({"name": "pdf-page-size", "passed": size_ok})
        if not size_ok:
            errors.append(
                "PDF page dimensions do not match the requested physical size"
            )
    except Exception as error:
        errors.append(f"PDF is not readable: {error}")
        checks.append({"name": "pdf-readable", "passed": False})
    return errors, checks, metadata


def export_images(
    fig: Figure,
    work_dir: Path,
    width_mm: float,
    height_mm: float,
    dpi: int,
) -> tuple[dict[str, Path], list[str]]:
    files: dict[str, Path] = {}
    warnings_out: list[str] = []
    fig.set_size_inches(width_mm / 25.4, height_mm / 25.4, forward=True)
    fig.patch.set_facecolor("white")
    fig.canvas.draw()

    pdf_path = work_dir / "figure.pdf"
    png_path = work_dir / "figure.png"
    tiff_path = work_dir / "figure.tiff"

    try:
        fig.savefig(pdf_path, format="pdf", facecolor="white", transparent=False)
        files["pdf"] = pdf_path
    except Exception as error:
        warnings_out.append(f"PDF export failed: {error}")

    fig.savefig(
        png_path,
        format="png",
        dpi=dpi,
        facecolor="white",
        transparent=False,
    )
    files["png"] = png_path

    try:
        with Image.open(png_path) as image:
            image.convert("RGB").save(
                tiff_path,
                format="TIFF",
                compression="tiff_lzw",
                dpi=(dpi, dpi),
            )
        files["tiff"] = tiff_path
    except Exception as error:
        warnings_out.append(f"TIFF export failed: {error}")

    return files, warnings_out


def next_iteration(figure_root: Path, requested: Any) -> int:
    existing = []
    if figure_root.is_dir():
        for child in figure_root.iterdir():
            match = re.fullmatch(r"v(\d{3})", child.name)
            if match:
                existing.append(int(match.group(1)))
    inferred = max(existing, default=0) + 1
    if requested is None:
        iteration = inferred
    else:
        try:
            iteration = int(requested)
        except (TypeError, ValueError) as error:
            raise FigureRequestError("iteration must be an integer") from error
        iteration = max(iteration, inferred)
    if iteration < 1 or iteration > MAX_ITERATIONS:
        raise FigureRequestError(
            f"Automatic figure revision is limited to {MAX_ITERATIONS} iterations"
        )
    return iteration


def render(request: dict[str, Any]) -> dict[str, Any]:
    cwd = Path(request.get("cwd") or os.getcwd()).expanduser().resolve()
    raw_paths = request.get("dataPaths") or []
    if request.get("dataPath"):
        raw_paths = [request["dataPath"], *raw_paths]
    data_paths = [resolve_path(str(item), cwd) for item in raw_paths]
    for path in data_paths:
        if not path.is_file():
            raise FigureRequestError(f"Data file does not exist: {path}")

    width_mm = positive_number(request.get("widthMm"), DEFAULT_WIDTH_MM, "widthMm")
    height_mm = positive_number(request.get("heightMm"), DEFAULT_HEIGHT_MM, "heightMm")
    try:
        dpi = int(request.get("dpi") or DEFAULT_DPI)
    except (TypeError, ValueError) as error:
        raise FigureRequestError("dpi must be an integer") from error
    validate_size(width_mm, height_mm, dpi)

    code = request.get("code")
    if not isinstance(code, str) or not code.strip():
        raise FigureRequestError("code is required and must assign a Matplotlib Figure to fig")

    artifact_root = resolve_path(
        str(request.get("artifactRoot") or ".pi/artifacts/figures"),
        cwd,
    )
    figure_id = sanitize_identifier(request.get("figureId"))
    title = str(request.get("title") or "Scientific figure").strip() or "Scientific figure"
    figure_root = artifact_root / figure_id
    iteration = next_iteration(figure_root, request.get("iteration"))
    version_dir = figure_root / f"v{iteration:03d}"
    version_namespace = uuid.uuid5(uuid.NAMESPACE_URL, str(version_dir))
    version_id = f"{figure_id}-v{iteration:03d}-{version_namespace.hex[:12]}"
    work_dir = figure_root / f".work-{uuid.uuid4()}"
    keep_work_files = bool(request.get("keepWorkFiles", False))
    work_dir.mkdir(parents=True, exist_ok=False)

    try:
        datasets = [load_table(path) for path in data_paths]
        namespace: dict[str, Any] = {
            "__name__": "__personal_pi_figure__",
            "data_paths": [str(path) for path in data_paths],
            "datasets": datasets,
            "data": datasets[0] if datasets else None,
            "load_table": load_table,
            "np": np,
            "pd": pd,
            "plt": plt,
            "sns": sns,
            "nx": nx,
            "width_mm": width_mm,
            "height_mm": height_mm,
            "dpi": dpi,
        }
        captured_stdout = io.StringIO()
        captured_stderr = io.StringIO()
        runtime_warnings: list[str] = []
        plt.close("all")
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            with contextlib.redirect_stdout(captured_stdout), contextlib.redirect_stderr(captured_stderr):
                exec(compile(code, "<personal-pi-scientific-figure>", "exec"), namespace, namespace)
            runtime_warnings.extend(str(item.message) for item in caught)

        fig = namespace.get("fig")
        if not isinstance(fig, Figure):
            raise FigureRequestError("Python code must assign the final Matplotlib Figure to fig")

        fig.set_size_inches(width_mm / 25.4, height_mm / 25.4, forward=True)
        fig.patch.set_facecolor("white")
        artist_errors, artist_warnings, checks = artist_issues(fig)
        files, export_warnings = export_images(fig, work_dir, width_mm, height_mm, dpi)
        if "png" not in files:
            raise FigureRequestError("PNG preview could not be generated")

        raster_errors, raster_warnings, raster_checks, raster_metadata = raster_issues(
            files["png"],
            files.get("tiff"),
            width_mm,
            height_mm,
            dpi,
        )
        checks.extend(raster_checks)
        pdf_errors, pdf_checks, pdf_metadata = pdf_issues(
            files.get("pdf"),
            width_mm,
            height_mm,
        )
        checks.extend(pdf_checks)
        raster_metadata.update(pdf_metadata)

        errors = artist_errors + raster_errors + pdf_errors
        warning_messages = [
            *artist_warnings,
            *raster_warnings,
            *export_warnings,
            *runtime_warnings[:10],
        ]
        score = max(0, 100 - 20 * len(errors) - 4 * len(warning_messages))
        validation = {
            "passed": not errors,
            "score": score,
            "errors": errors,
            "warnings": warning_messages,
            "checks": checks,
            "metadata": raster_metadata,
        }

        version_dir.mkdir(parents=True, exist_ok=False)
        output_files = []
        for output_format, source in files.items():
            destination = version_dir / f"figure.{output_format}"
            shutil.move(str(source), destination)
            output_files.append({"format": output_format, "path": str(destination)})

        if keep_work_files:
            (version_dir / "source.py").write_text(code, encoding="utf-8")
            (version_dir / "request.json").write_text(
                json.dumps(request, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            (version_dir / "validation.json").write_text(
                json.dumps(validation, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            logs = captured_stdout.getvalue() + captured_stderr.getvalue()
            if logs:
                (version_dir / "runtime.log").write_text(logs, encoding="utf-8")

        preview_path = next(
            item["path"] for item in output_files if item["format"] == "png"
        )
        manifest = {
            "schemaVersion": 1,
            "kind": "scientific-figure",
            "id": version_id,
            "figureId": figure_id,
            "version": iteration,
            "title": title,
            "sessionId": request.get("sessionId"),
            "cwd": str(cwd),
            "createdAt": datetime.now(timezone.utc).isoformat(),
            "previewPath": preview_path,
            "files": output_files,
            "widthMm": width_mm,
            "heightMm": height_mm,
            "dpi": dpi,
            "validation": validation,
            "intermediatesRetained": keep_work_files,
        }
        return {"success": True, "artifact": manifest}
    finally:
        plt.close("all")
        if work_dir.exists():
            shutil.rmtree(work_dir, ignore_errors=True)


def main() -> int:
    try:
        request = json.load(sys.stdin)
        action = request.get("action")
        if action == "capabilities":
            emit({"success": True, "capabilities": CAPABILITIES})
            return 0
        if action == "inspect":
            cwd = Path(request.get("cwd") or os.getcwd()).expanduser().resolve()
            path = resolve_path(str(request.get("dataPath") or ""), cwd)
            if not path.is_file():
                raise FigureRequestError(f"Data file does not exist: {path}")
            emit({"success": True, "inspection": inspect_file(path)})
            return 0
        if action == "render":
            emit(render(request))
            return 0
        raise FigureRequestError(f"Unknown action: {action}")
    except Exception as error:
        emit(
            {
                "success": False,
                "error": str(error),
                "errorType": type(error).__name__,
                "traceback": traceback.format_exc(limit=8),
            }
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
