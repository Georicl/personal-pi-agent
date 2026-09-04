from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import sys
import uuid
from dataclasses import dataclass
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

import yaml
from pypdf import PdfReader


SCHEMA_VERSION = 1
SUPPORTED_SUFFIXES = {".md", ".markdown", ".txt", ".pdf"}
KNOWLEDGE_DIRECTORIES = ("inbox", "sources", "cards", "drafts", "attachments")
INDEXED_CATEGORIES = ("inbox", "sources", "cards", "drafts", "entries")
INVENTORY_CATEGORIES = (*KNOWLEDGE_DIRECTORIES, "entries")
MAX_FILE_BYTES = 50 * 1024 * 1024
MAX_EXTRACTED_CHARACTERS = 5_000_000
MAX_CHUNK_CHARACTERS = 4_000
CHUNK_OVERLAP_CHARACTERS = 240


class KnowledgeCoreError(ValueError):
    pass


@dataclass(frozen=True)
class KnowledgeScope:
    kind: str
    pi_root: Path
    project_root: Path | None
    knowledge_root: Path
    index_path: Path
    scope_id: str

    @classmethod
    def from_request(cls, value: dict[str, Any], pi_root_value: str | None = None) -> "KnowledgeScope":
        if not isinstance(value, dict):
            raise KnowledgeCoreError("scope must be an object")
        kind = str(value.get("kind") or "").strip().lower()
        if kind not in {"global", "project"}:
            raise KnowledgeCoreError("scope.kind must be global or project")

        pi_root = Path(pi_root_value or Path.home() / ".pi").expanduser().resolve()
        if kind == "global":
            return cls(
                kind="global",
                pi_root=pi_root,
                project_root=None,
                knowledge_root=pi_root / "knowledge",
                index_path=pi_root / "personal" / "knowledge" / "global.sqlite",
                scope_id="global",
            )

        raw_project_root = value.get("projectRoot")
        if not isinstance(raw_project_root, str) or not raw_project_root.strip():
            raise KnowledgeCoreError("project scope requires projectRoot")
        project_root = Path(raw_project_root).expanduser().resolve()
        digest = hashlib.sha256(str(project_root).encode("utf-8")).hexdigest()[:20]
        return cls(
            kind="project",
            pi_root=pi_root,
            project_root=project_root,
            knowledge_root=project_root / ".pi" / "knowledge",
            index_path=pi_root / "personal" / "knowledge" / "projects" / digest / "index.sqlite",
            scope_id=f"project:{digest}",
        )

    def as_dict(self) -> dict[str, Any]:
        return {
            "id": self.scope_id,
            "kind": self.kind,
            "knowledgeRoot": str(self.knowledge_root),
            "projectRoot": str(self.project_root) if self.project_root else None,
            "indexPath": str(self.index_path),
        }


@dataclass(frozen=True)
class ExtractedChunk:
    locator: str
    text: str
    heading: str | None = None
    page_number: int | None = None


@dataclass(frozen=True)
class ExtractedDocument:
    document_id: str
    title: str
    kind: str
    status: str
    card_type: str | None
    confidence: str | None
    tags: list[str]
    source_refs: list[dict[str, Any]]
    metadata: dict[str, Any]
    chunks: list[ExtractedChunk]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def json_safe(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(key): json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_safe(item) for item in value]
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    return str(value)


def stable_id(*parts: str, prefix: str) -> str:
    digest = hashlib.sha256("\0".join(parts).encode("utf-8")).hexdigest()[:24]
    return f"{prefix}-{digest}"


def ensure_scope_directories(scope: KnowledgeScope) -> None:
    for name in KNOWLEDGE_DIRECTORIES:
        (scope.knowledge_root / name).mkdir(parents=True, exist_ok=True)
    scope.index_path.parent.mkdir(parents=True, exist_ok=True)


def schema_text() -> str:
    return Path(__file__).with_name("schema.sql").read_text(encoding="utf-8")


def connect_scope(scope: KnowledgeScope, create: bool) -> sqlite3.Connection | None:
    if not scope.index_path.exists() and not create:
        return None
    if create:
        ensure_scope_directories(scope)
    connection = sqlite3.connect(scope.index_path)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute("PRAGMA journal_mode = WAL")
    if create:
        connection.executescript(schema_text())
        now = utc_now()
        connection.execute(
            """
            INSERT INTO scopes(id, kind, knowledge_root, project_root, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                kind = excluded.kind,
                knowledge_root = excluded.knowledge_root,
                project_root = excluded.project_root,
                updated_at = excluded.updated_at
            """,
            (
                scope.scope_id,
                scope.kind,
                str(scope.knowledge_root),
                str(scope.project_root) if scope.project_root else None,
                now,
                now,
            ),
        )
        connection.commit()
    return connection


def initialize_scope(scope: KnowledgeScope) -> dict[str, Any]:
    connection = connect_scope(scope, create=True)
    assert connection is not None
    try:
        version_row = connection.execute(
            "SELECT value FROM schema_info WHERE key = 'schema_version'"
        ).fetchone()
    finally:
        connection.close()
    return {
        "scope": scope.as_dict(),
        "initialized": True,
        "schemaVersion": int(version_row["value"]) if version_row else SCHEMA_VERSION,
        "directories": [str(scope.knowledge_root / name) for name in KNOWLEDGE_DIRECTORIES],
    }


def file_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def read_text(path: Path) -> str:
    raw = path.read_bytes()
    if len(raw) > MAX_FILE_BYTES:
        raise KnowledgeCoreError(f"file exceeds {MAX_FILE_BYTES} bytes")
    for encoding in ("utf-8-sig", "utf-8", "utf-16", "latin-1"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    raise KnowledgeCoreError("text encoding is unsupported")


def parse_frontmatter(text: str) -> tuple[dict[str, Any], str]:
    if not text.startswith("---"):
        return {}, text
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, text
    closing_index = next(
        (index for index, line in enumerate(lines[1:], start=1) if line.strip() == "---"),
        None,
    )
    if closing_index is None:
        raise KnowledgeCoreError("Markdown frontmatter is not closed")
    parsed = yaml.safe_load("\n".join(lines[1:closing_index])) or {}
    if not isinstance(parsed, dict):
        raise KnowledgeCoreError("Markdown frontmatter must be an object")
    return json_safe(parsed), "\n".join(lines[closing_index + 1 :]).strip()


def validate_card_metadata(metadata: dict[str, Any], category: str) -> None:
    required = ("id", "title", "type", "status", "sources")
    missing = [key for key in required if key not in metadata]
    if missing:
        raise KnowledgeCoreError(
            f"{category} knowledge card is missing frontmatter fields: {', '.join(missing)}"
        )
    if not isinstance(metadata["id"], str) or not metadata["id"].strip():
        raise KnowledgeCoreError("knowledge card id must be a non-empty string")
    if not isinstance(metadata["title"], str) or not metadata["title"].strip():
        raise KnowledgeCoreError("knowledge card title must be a non-empty string")
    if not isinstance(metadata["type"], str) or not metadata["type"].strip():
        raise KnowledgeCoreError("knowledge card type must be a non-empty string")
    if metadata["status"] not in {"draft", "reviewed", "deprecated"}:
        raise KnowledgeCoreError("knowledge card status must be draft, reviewed, or deprecated")
    if category == "cards" and metadata["status"] == "draft":
        raise KnowledgeCoreError("draft knowledge cards must be stored in drafts/")
    if category == "drafts" and metadata["status"] != "draft":
        raise KnowledgeCoreError("files in drafts/ must use status: draft")
    confidence = metadata.get("confidence")
    if confidence is not None and confidence not in {"unknown", "low", "medium", "high"}:
        raise KnowledgeCoreError("knowledge card confidence must be unknown, low, medium, or high")
    if not isinstance(metadata["sources"], list):
        raise KnowledgeCoreError("knowledge card sources must be a list")
    for source in metadata["sources"]:
        if (
            not isinstance(source, dict)
            or not isinstance(source.get("source_id"), str)
            or not source["source_id"].strip()
        ):
            raise KnowledgeCoreError("each knowledge card source requires a non-empty source_id")


def chunk_long_text(
    text: str,
    locator: str,
    heading: str | None = None,
    page_number: int | None = None,
) -> list[ExtractedChunk]:
    normalized = re.sub(r"[ \t]+", " ", text).strip()
    if not normalized:
        return []
    if len(normalized) > MAX_EXTRACTED_CHARACTERS:
        raise KnowledgeCoreError("extracted text exceeds the safety limit")
    chunks: list[ExtractedChunk] = []
    start = 0
    part = 1
    while start < len(normalized):
        end = min(len(normalized), start + MAX_CHUNK_CHARACTERS)
        if end < len(normalized):
            boundary = normalized.rfind("\n", start, end)
            if boundary <= start + MAX_CHUNK_CHARACTERS // 2:
                boundary = normalized.rfind(". ", start, end)
            if boundary > start:
                end = boundary + 1
        chunk_text = normalized[start:end].strip()
        if chunk_text:
            part_locator = locator if part == 1 and end == len(normalized) else f"{locator}, part {part}"
            chunks.append(
                ExtractedChunk(
                    locator=part_locator,
                    text=chunk_text,
                    heading=heading,
                    page_number=page_number,
                )
            )
        if end >= len(normalized):
            break
        start = max(start + 1, end - CHUNK_OVERLAP_CHARACTERS)
        part += 1
    return chunks


def markdown_chunks(body: str) -> list[ExtractedChunk]:
    sections: list[tuple[str, list[str]]] = []
    heading = "Document"
    lines: list[str] = []
    for line in body.splitlines():
        match = re.match(r"^#{1,6}\s+(.+?)\s*$", line)
        if match:
            if "\n".join(lines).strip():
                sections.append((heading, lines))
            heading = match.group(1).strip()
            lines = []
        else:
            lines.append(line)
    if "\n".join(lines).strip():
        sections.append((heading, lines))
    if not sections and body.strip():
        sections.append(("Document", [body]))

    chunks: list[ExtractedChunk] = []
    for section_heading, section_lines in sections:
        chunks.extend(
            chunk_long_text(
                "\n".join(section_lines),
                f"Section: {section_heading}",
                heading=section_heading,
            )
        )
    return chunks


def text_chunks(body: str) -> list[ExtractedChunk]:
    paragraphs = [part.strip() for part in re.split(r"\n\s*\n", body) if part.strip()]
    if not paragraphs:
        return []
    return chunk_long_text("\n\n".join(paragraphs), "Text")


def pdf_chunks(path: Path) -> tuple[dict[str, Any], list[ExtractedChunk]]:
    reader = PdfReader(str(path), strict=False)
    if reader.is_encrypted:
        try:
            reader.decrypt("")
        except Exception as error:  # pragma: no cover - depends on encrypted fixture
            raise KnowledgeCoreError("encrypted PDF cannot be read") from error
    metadata: dict[str, Any] = {}
    if reader.metadata:
        if reader.metadata.title:
            metadata["title"] = str(reader.metadata.title)
        if reader.metadata.author:
            metadata["authors"] = [str(reader.metadata.author)]
    chunks: list[ExtractedChunk] = []
    extracted_characters = 0
    for page_number, page in enumerate(reader.pages, start=1):
        page_text = page.extract_text() or ""
        extracted_characters += len(page_text)
        if extracted_characters > MAX_EXTRACTED_CHARACTERS:
            raise KnowledgeCoreError("extracted PDF text exceeds the safety limit")
        chunks.extend(
            chunk_long_text(
                page_text,
                f"Page {page_number}",
                page_number=page_number,
            )
        )
    return metadata, chunks


def normalize_tags(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        values = [value]
    elif isinstance(value, list):
        values = value
    else:
        raise KnowledgeCoreError("tags must be a string or list")
    return list(dict.fromkeys(str(item).strip() for item in values if str(item).strip()))


def extract_document(
    scope: KnowledgeScope,
    path: Path,
    category: str,
) -> ExtractedDocument:
    relative_path = path.relative_to(scope.knowledge_root).as_posix()
    fallback_id = stable_id(scope.scope_id, relative_path, prefix="source")
    suffix = path.suffix.lower()
    metadata: dict[str, Any] = {}

    if suffix == ".pdf":
        pdf_metadata, chunks = pdf_chunks(path)
        metadata.update(pdf_metadata)
        body_title = None
    else:
        text = read_text(path)
        if suffix in {".md", ".markdown"}:
            metadata, body = parse_frontmatter(text)
            chunks = markdown_chunks(body)
            first_heading = re.search(r"^#\s+(.+?)\s*$", body, flags=re.MULTILINE)
            body_title = first_heading.group(1).strip() if first_heading else None
        else:
            body = text
            chunks = text_chunks(body)
            body_title = None

    if category in {"cards", "drafts", "entries"}:
        validate_card_metadata(metadata, category)

    document_id = str(metadata.get("id") or fallback_id).strip()
    title = str(metadata.get("title") or body_title or path.stem).strip()
    tags = normalize_tags(metadata.get("tags"))
    source_refs = metadata.get("sources") or []
    if not isinstance(source_refs, list):
        raise KnowledgeCoreError("sources must be a list")

    default_status = {
        "inbox": "inbox",
        "sources": "active",
        "cards": "reviewed",
        "drafts": "draft",
        "entries": "draft",
    }[category]
    kind = (
        "knowledge-card"
        if category in {"cards", "drafts", "entries"}
        else suffix.removeprefix(".")
    )
    return ExtractedDocument(
        document_id=document_id,
        title=title,
        kind=kind,
        status=str(metadata.get("status") or default_status),
        card_type=str(metadata.get("type")) if metadata.get("type") is not None else None,
        confidence=(
            str(metadata.get("confidence")) if metadata.get("confidence") is not None else None
        ),
        tags=tags,
        source_refs=json_safe(source_refs),
        metadata=json_safe(metadata),
        chunks=chunks,
    )


def discover_files(scope: KnowledgeScope) -> list[tuple[str, Path]]:
    discovered: list[tuple[str, Path]] = []
    for category in INDEXED_CATEGORIES:
        category_root = scope.knowledge_root / category
        if not category_root.exists() or category_root.is_symlink():
            continue
        for path in category_root.rglob("*"):
            if path.is_symlink() or not path.is_file() or path.suffix.lower() not in SUPPORTED_SUFFIXES:
                continue
            relative_parts = path.relative_to(category_root).parts
            if any(part.startswith(".") for part in relative_parts):
                continue
            discovered.append((category, path))
    return sorted(discovered, key=lambda item: item[1].as_posix().lower())


def discover_inventory_files(scope: KnowledgeScope) -> list[tuple[str, Path]]:
    discovered: list[tuple[str, Path]] = []
    for category in INVENTORY_CATEGORIES:
        category_root = scope.knowledge_root / category
        if not category_root.exists() or category_root.is_symlink():
            continue
        for path in category_root.rglob("*"):
            if path.is_symlink() or not path.is_file():
                continue
            relative_parts = path.relative_to(category_root).parts
            if any(part.startswith(".") for part in relative_parts):
                continue
            discovered.append((category, path))
    return sorted(discovered, key=lambda item: item[1].as_posix().lower())


def inventory_scope(scope: KnowledgeScope, limit: int = 500) -> dict[str, Any]:
    if not 1 <= limit <= 5_000:
        raise KnowledgeCoreError("inventory limit must be between 1 and 5000")
    connection = connect_scope(scope, create=False)
    initialized = connection is not None
    indexed: dict[str, sqlite3.Row] = {}
    latest_run: dict[str, Any] | None = None
    if connection is not None:
        try:
            rows = connection.execute(
                """
                SELECT d.id, d.relative_path, d.title, d.status, d.error,
                       COUNT(c.id) AS chunk_count
                FROM documents d
                LEFT JOIN chunks c ON c.document_id = d.id
                WHERE d.scope_id = ?
                GROUP BY d.id
                """,
                (scope.scope_id,),
            ).fetchall()
            indexed = {row["relative_path"]: row for row in rows}
            latest = connection.execute(
                """
                SELECT id, action, finished_at FROM indexing_runs
                WHERE scope_id = ? ORDER BY finished_at DESC LIMIT 1
                """,
                (scope.scope_id,),
            ).fetchone()
            latest_run = dict(latest) if latest else None
        finally:
            connection.close()

    category_totals = {
        category: {"files": 0, "bytes": 0} for category in INVENTORY_CATEGORIES
    }
    items: list[dict[str, Any]] = []
    total_bytes = 0
    discovered = discover_inventory_files(scope)
    for category, path in discovered:
        stat = path.stat()
        relative_path = path.relative_to(scope.knowledge_root).as_posix()
        total_bytes += stat.st_size
        category_totals[category]["files"] += 1
        category_totals[category]["bytes"] += stat.st_size
        if len(items) >= limit:
            continue
        record = indexed.get(relative_path)
        items.append(
            {
                "relativePath": relative_path,
                "category": category,
                "name": path.name,
                "extension": path.suffix.lower(),
                "sizeBytes": stat.st_size,
                "modifiedAt": datetime.fromtimestamp(
                    stat.st_mtime, timezone.utc
                ).isoformat().replace("+00:00", "Z"),
                "supported": path.suffix.lower() in SUPPORTED_SUFFIXES,
                "index": (
                    {
                        "documentId": record["id"],
                        "title": record["title"],
                        "status": record["status"],
                        "chunks": record["chunk_count"],
                        "error": record["error"],
                    }
                    if record
                    else None
                ),
            }
        )
    return {
        "scope": scope.as_dict(),
        "initialized": initialized,
        "fileCount": len(discovered),
        "totalBytes": total_bytes,
        "categories": category_totals,
        "files": items,
        "truncated": len(discovered) > limit,
        "latestRun": latest_run,
    }


def insert_document(
    connection: sqlite3.Connection,
    scope: KnowledgeScope,
    path: Path,
    category: str,
    extracted: ExtractedDocument,
    digest: str,
    stat: os.stat_result,
) -> None:
    relative_path = path.relative_to(scope.knowledge_root).as_posix()
    connection.execute(
        "DELETE FROM documents WHERE scope_id = ? AND relative_path = ?",
        (scope.scope_id, relative_path),
    )
    connection.execute(
        """
        INSERT INTO documents(
            id, scope_id, relative_path, category, kind, title, status,
            card_type, confidence, tags_json, source_refs_json, metadata_json,
            content_hash, size_bytes, modified_ns, indexed_at, error
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
        """,
        (
            extracted.document_id,
            scope.scope_id,
            relative_path,
            category,
            extracted.kind,
            extracted.title,
            extracted.status,
            extracted.card_type,
            extracted.confidence,
            json.dumps(extracted.tags, ensure_ascii=False),
            json.dumps(extracted.source_refs, ensure_ascii=False),
            json.dumps(extracted.metadata, ensure_ascii=False, sort_keys=True),
            digest,
            stat.st_size,
            stat.st_mtime_ns,
            utc_now(),
        ),
    )
    tags_text = " ".join(extracted.tags)
    for ordinal, chunk in enumerate(extracted.chunks):
        text_digest = hashlib.sha256(chunk.text.encode("utf-8")).hexdigest()
        chunk_id = stable_id(extracted.document_id, str(ordinal), text_digest, prefix="chunk")
        searchable_title = " ".join(
            part for part in (extracted.title, chunk.heading) if part
        )
        connection.execute(
            """
            INSERT INTO chunks(
                id, document_id, ordinal, locator, heading, page_number,
                title, tags, text, text_hash
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                chunk_id,
                extracted.document_id,
                ordinal,
                chunk.locator,
                chunk.heading,
                chunk.page_number,
                searchable_title,
                tags_text,
                chunk.text,
                text_digest,
            ),
        )


def insert_failed_document(
    connection: sqlite3.Connection,
    scope: KnowledgeScope,
    path: Path,
    category: str,
    digest: str,
    stat: os.stat_result,
    error: Exception,
) -> None:
    relative_path = path.relative_to(scope.knowledge_root).as_posix()
    document_id = stable_id(scope.scope_id, relative_path, prefix="source")
    connection.execute(
        "DELETE FROM documents WHERE scope_id = ? AND relative_path = ?",
        (scope.scope_id, relative_path),
    )
    connection.execute(
        """
        INSERT INTO documents(
            id, scope_id, relative_path, category, kind, title, status,
            tags_json, source_refs_json, metadata_json, content_hash,
            size_bytes, modified_ns, indexed_at, error
        ) VALUES (?, ?, ?, ?, ?, ?, ?, '[]', '[]', '{}', ?, ?, ?, ?, ?)
        """,
        (
            document_id,
            scope.scope_id,
            relative_path,
            category,
            path.suffix.lower().removeprefix(".") or "unknown",
            path.stem,
            "invalid",
            digest,
            stat.st_size,
            stat.st_mtime_ns,
            utc_now(),
            str(error),
        ),
    )


def remove_index_files(index_path: Path) -> None:
    for suffix in ("", "-wal", "-shm"):
        candidate = Path(f"{index_path}{suffix}")
        if candidate.exists():
            candidate.unlink()


def index_scope(scope: KnowledgeScope, rebuild: bool = False) -> dict[str, Any]:
    started_at = utc_now()
    if rebuild:
        remove_index_files(scope.index_path)
    connection = connect_scope(scope, create=True)
    assert connection is not None
    counts = {"indexed": 0, "updated": 0, "unchanged": 0, "removed": 0, "failed": 0}
    failures: list[dict[str, str]] = []
    try:
        existing_rows = connection.execute(
            "SELECT id, relative_path, content_hash, error FROM documents WHERE scope_id = ?",
            (scope.scope_id,),
        ).fetchall()
        existing = {row["relative_path"]: row for row in existing_rows}
        discovered = discover_files(scope)
        discovered_paths = {
            path.relative_to(scope.knowledge_root).as_posix() for _, path in discovered
        }
        removed_paths = sorted(set(existing) - discovered_paths)
        for relative_path in removed_paths:
            connection.execute(
                "DELETE FROM documents WHERE scope_id = ? AND relative_path = ?",
                (scope.scope_id, relative_path),
            )
        counts["removed"] = len(removed_paths)

        for category, path in discovered:
            relative_path = path.relative_to(scope.knowledge_root).as_posix()
            stat = path.stat()
            if stat.st_size > MAX_FILE_BYTES:
                digest = hashlib.sha256(
                    f"oversize:{stat.st_size}:{stat.st_mtime_ns}".encode("utf-8")
                ).hexdigest()
            else:
                digest = file_hash(path)
            previous = existing.get(relative_path)
            if previous and previous["content_hash"] == digest:
                counts["unchanged"] += 1
                continue
            if stat.st_size > MAX_FILE_BYTES:
                error = KnowledgeCoreError(f"file exceeds {MAX_FILE_BYTES} bytes")
                insert_failed_document(connection, scope, path, category, digest, stat, error)
                counts["failed"] += 1
                failures.append({"path": relative_path, "error": str(error)})
                continue
            try:
                extracted = extract_document(scope, path, category)
                insert_document(connection, scope, path, category, extracted, digest, stat)
                counts["updated" if previous else "indexed"] += 1
            except Exception as error:
                insert_failed_document(connection, scope, path, category, digest, stat, error)
                counts["failed"] += 1
                failures.append({"path": relative_path, "error": str(error)})

        finished_at = utc_now()
        run_id = str(uuid.uuid4())
        connection.execute(
            """
            INSERT INTO indexing_runs(
                id, scope_id, action, started_at, finished_at,
                indexed_count, updated_count, unchanged_count,
                removed_count, failed_count, details_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                run_id,
                scope.scope_id,
                "rebuild" if rebuild else "index",
                started_at,
                finished_at,
                counts["indexed"],
                counts["updated"],
                counts["unchanged"],
                counts["removed"],
                counts["failed"],
                json.dumps({"failures": failures}, ensure_ascii=False),
            ),
        )
        connection.commit()
        return {
            "scope": scope.as_dict(),
            "runId": run_id,
            "action": "rebuild" if rebuild else "index",
            **counts,
            "failures": failures,
        }
    finally:
        connection.close()


def decode_json_list(value: str) -> list[Any]:
    parsed = json.loads(value)
    return parsed if isinstance(parsed, list) else []


def document_from_row(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "scopeId": row["scope_id"],
        "relativePath": row["relative_path"],
        "category": row["category"],
        "kind": row["kind"],
        "title": row["title"],
        "status": row["status"],
        "type": row["card_type"],
        "confidence": row["confidence"],
        "tags": decode_json_list(row["tags_json"]),
        "sources": decode_json_list(row["source_refs_json"]),
        "contentHash": row["content_hash"],
        "indexedAt": row["indexed_at"],
        "error": row["error"],
    }


def scope_status(scope: KnowledgeScope) -> dict[str, Any]:
    connection = connect_scope(scope, create=False)
    if connection is None:
        return {
            "scope": scope.as_dict(),
            "initialized": False,
            "counts": {"documents": 0, "chunks": 0, "errors": 0},
        }
    try:
        row = connection.execute(
            """
            SELECT
                COUNT(*) AS documents,
                SUM(CASE WHEN error IS NOT NULL THEN 1 ELSE 0 END) AS errors
            FROM documents WHERE scope_id = ?
            """,
            (scope.scope_id,),
        ).fetchone()
        chunks = connection.execute(
            """
            SELECT COUNT(*) AS count FROM chunks
            JOIN documents ON documents.id = chunks.document_id
            WHERE documents.scope_id = ?
            """,
            (scope.scope_id,),
        ).fetchone()["count"]
        latest = connection.execute(
            """
            SELECT id, action, finished_at FROM indexing_runs
            WHERE scope_id = ? ORDER BY finished_at DESC LIMIT 1
            """,
            (scope.scope_id,),
        ).fetchone()
        return {
            "scope": scope.as_dict(),
            "initialized": True,
            "counts": {
                "documents": row["documents"] or 0,
                "chunks": chunks,
                "errors": row["errors"] or 0,
            },
            "latestRun": dict(latest) if latest else None,
        }
    finally:
        connection.close()


def search_terms(query: str) -> list[str]:
    terms = re.findall(r"[\w\-]+", query.lower(), flags=re.UNICODE)
    return list(dict.fromkeys(term for term in terms if term))


def fts_query(query: str) -> str | None:
    terms = [term for term in search_terms(query) if len(term) >= 3]
    if not terms:
        return None
    escaped = [term.replace('"', '""') for term in terms]
    return " AND ".join(f'"{term}"' for term in escaped)


def search_one_scope(
    scope: KnowledgeScope,
    query: str,
    limit: int,
    include_drafts: bool,
    include_inbox: bool,
    include_deprecated: bool,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    connection = connect_scope(scope, create=False)
    if connection is None:
        return {"scope": scope.as_dict(), "initialized": False, "error": "index not initialized"}, []
    categories = ["sources", "cards", "entries"]
    if include_drafts:
        categories.append("drafts")
    if include_inbox:
        categories.append("inbox")
    placeholders = ",".join("?" for _ in categories)
    status_clauses = []
    if not include_deprecated:
        status_clauses.append("AND d.status != 'deprecated'")
    if not include_drafts:
        status_clauses.append("AND d.status != 'draft'")
    status_clause = "\n".join(status_clauses)
    match_query = fts_query(query)
    try:
        if match_query:
            rows = connection.execute(
                f"""
                SELECT d.*, c.id AS chunk_id, c.locator, c.heading, c.page_number,
                       c.text, bm25(chunks_fts, 1.0, 3.0, 2.0) AS fts_rank
                FROM chunks_fts
                JOIN chunks c ON c.rowid = chunks_fts.rowid
                JOIN documents d ON d.id = c.document_id
                WHERE chunks_fts MATCH ?
                  AND d.scope_id = ?
                  AND d.category IN ({placeholders})
                  AND d.error IS NULL
                  {status_clause}
                ORDER BY fts_rank ASC
                LIMIT ?
                """,
                [match_query, scope.scope_id, *categories, limit * 4],
            ).fetchall()
        else:
            needle = f"%{query.lower()}%"
            parameters = [scope.scope_id, *categories, needle, needle, needle, limit * 4]
            rows = connection.execute(
                f"""
                SELECT d.*, c.id AS chunk_id, c.locator, c.heading, c.page_number,
                       c.text, 0.0 AS fts_rank
                FROM chunks c
                JOIN documents d ON d.id = c.document_id
                WHERE d.scope_id = ?
                  AND d.category IN ({placeholders})
                  AND d.error IS NULL
                  {status_clause}
                  AND (lower(c.text) LIKE ? OR lower(c.title) LIKE ? OR lower(c.tags) LIKE ?)
                LIMIT ?
                """,
                parameters,
            ).fetchall()

        terms = search_terms(query)
        per_document: dict[str, int] = {}
        results: list[dict[str, Any]] = []
        for row in rows:
            if per_document.get(row["id"], 0) >= 3:
                continue
            per_document[row["id"]] = per_document.get(row["id"], 0) + 1
            haystack = " ".join(
                [
                    row["title"],
                    row["heading"] or "",
                    row["text"],
                    " ".join(decode_json_list(row["tags_json"])),
                ]
            ).lower()
            title = row["title"].lower()
            matched = sum(1 for term in terms if term in haystack)
            title_matches = sum(1 for term in terms if term in title)
            scope_bonus = 0.2 if scope.kind == "project" else 0.0
            reviewed_bonus = 0.15 if row["category"] == "cards" and row["status"] == "reviewed" else 0.0
            score = matched + title_matches * 2 + scope_bonus + reviewed_bonus
            results.append(
                {
                    "score": round(score, 4),
                    "document": document_from_row(row),
                    "chunk": {
                        "id": row["chunk_id"],
                        "locator": row["locator"],
                        "heading": row["heading"],
                        "pageNumber": row["page_number"],
                        "text": row["text"],
                    },
                }
            )
        results.sort(key=lambda item: (-item["score"], item["document"]["title"].lower()))
        return {"scope": scope.as_dict(), "initialized": True, "error": None}, results[:limit]
    finally:
        connection.close()


def search_scopes(request: dict[str, Any]) -> dict[str, Any]:
    query = str(request.get("query") or "").strip()
    if not query:
        raise KnowledgeCoreError("search query is required")
    raw_scopes = request.get("scopes")
    if not isinstance(raw_scopes, list) or not raw_scopes:
        raise KnowledgeCoreError("search requires at least one scope")
    limit = int(request.get("limit") or 20)
    if not 1 <= limit <= 100:
        raise KnowledgeCoreError("search limit must be between 1 and 100")
    statuses: list[dict[str, Any]] = []
    combined: list[dict[str, Any]] = []
    seen_scope_ids: set[str] = set()
    for raw_scope in raw_scopes:
        scope = KnowledgeScope.from_request(raw_scope, request.get("piRoot"))
        if scope.scope_id in seen_scope_ids:
            continue
        seen_scope_ids.add(scope.scope_id)
        status, results = search_one_scope(
            scope,
            query,
            limit,
            bool(request.get("includeDrafts", False)),
            bool(request.get("includeInbox", False)),
            bool(request.get("includeDeprecated", False)),
        )
        statuses.append(status)
        combined.extend(results)
    combined.sort(
        key=lambda item: (
            -item["score"],
            0 if item["document"]["scopeId"].startswith("project:") else 1,
            item["document"]["title"].lower(),
        )
    )
    return {"query": query, "results": combined[:limit], "scopes": statuses}


def get_document(scope: KnowledgeScope, document_id: str) -> dict[str, Any]:
    connection = connect_scope(scope, create=False)
    if connection is None:
        raise KnowledgeCoreError("knowledge index is not initialized")
    try:
        row = connection.execute(
            "SELECT * FROM documents WHERE scope_id = ? AND id = ?",
            (scope.scope_id, document_id),
        ).fetchone()
        if row is None:
            raise KnowledgeCoreError("knowledge document was not found")
        chunks = connection.execute(
            """
            SELECT id, ordinal, locator, heading, page_number, text, text_hash
            FROM chunks WHERE document_id = ? ORDER BY ordinal
            """,
            (document_id,),
        ).fetchall()
        return {
            "document": document_from_row(row),
            "chunks": [
                {
                    "id": chunk["id"],
                    "ordinal": chunk["ordinal"],
                    "locator": chunk["locator"],
                    "heading": chunk["heading"],
                    "pageNumber": chunk["page_number"],
                    "text": chunk["text"],
                    "textHash": chunk["text_hash"],
                }
                for chunk in chunks
            ],
        }
    finally:
        connection.close()


def markdown_record(metadata: dict[str, Any], content: str) -> str:
    frontmatter = yaml.safe_dump(
        json_safe(metadata),
        allow_unicode=True,
        sort_keys=False,
        default_flow_style=False,
    ).strip()
    return f"---\n{frontmatter}\n---\n\n{content.strip()}\n"


def filename_slug(title: str) -> str:
    normalized = re.sub(r"[^\w-]+", "-", title.strip().lower(), flags=re.UNICODE)
    normalized = re.sub(r"-{2,}", "-", normalized).strip("-_")
    return (normalized or "knowledge")[:80].rstrip("-_")


def capture_record(scope: KnowledgeScope, request: dict[str, Any]) -> dict[str, Any]:
    category = str(request.get("category") or "drafts").strip().lower()
    if category not in {"inbox", "sources", "drafts"}:
        raise KnowledgeCoreError("capture category must be inbox, sources, or drafts")
    title = str(request.get("title") or "").strip()
    content = request.get("content")
    if not title:
        raise KnowledgeCoreError("capture title is required")
    if not isinstance(content, str) or not content.strip():
        raise KnowledgeCoreError("capture content is required")
    tags = normalize_tags(request.get("tags"))
    sources = request.get("sources") or []
    if not isinstance(sources, list):
        raise KnowledgeCoreError("capture sources must be a list")
    now = utc_now()
    record_id = (
        f"card-{uuid.uuid4().hex}"
        if category == "drafts"
        else f"source-{uuid.uuid4().hex}"
    )
    metadata: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "id": record_id,
        "title": title,
        "status": "draft" if category == "drafts" else ("inbox" if category == "inbox" else "active"),
        "created_at": now,
        "updated_at": now,
        "sources": json_safe(sources),
        "tags": tags,
    }
    if category == "drafts":
        metadata["type"] = str(request.get("type") or "note").strip()
        metadata["confidence"] = str(request.get("confidence") or "unknown").strip().lower()
        validate_card_metadata(metadata, category)

    ensure_scope_directories(scope)
    destination = scope.knowledge_root / category / (
        f"{filename_slug(title)}-{record_id.rsplit('-', 1)[-1][:8]}.md"
    )
    with destination.open("x", encoding="utf-8") as stream:
        stream.write(markdown_record(metadata, content))
    indexed = index_scope(scope)
    document = get_document(scope, record_id)
    return {
        "scope": scope.as_dict(),
        "path": str(destination),
        "relativePath": destination.relative_to(scope.knowledge_root).as_posix(),
        "index": indexed,
        **document,
    }


def publish_card(scope: KnowledgeScope, request: dict[str, Any]) -> dict[str, Any]:
    if request.get("userConfirmed") is not True:
        raise KnowledgeCoreError("publishing requires explicit user confirmation")
    document_id = str(request.get("documentId") or "").strip()
    if not document_id:
        raise KnowledgeCoreError("publish requires documentId")
    connection = connect_scope(scope, create=False)
    if connection is None:
        raise KnowledgeCoreError("knowledge index is not initialized")
    try:
        row = connection.execute(
            """
            SELECT relative_path, category, status FROM documents
            WHERE scope_id = ? AND id = ? AND error IS NULL
            """,
            (scope.scope_id, document_id),
        ).fetchone()
    finally:
        connection.close()
    if row is None:
        raise KnowledgeCoreError("draft knowledge card was not found")
    if row["category"] not in {"drafts", "entries"} or row["status"] != "draft":
        raise KnowledgeCoreError("only a draft knowledge card can be published")

    source = (scope.knowledge_root / row["relative_path"]).resolve()
    knowledge_root = scope.knowledge_root.resolve()
    if not source.is_relative_to(knowledge_root) or source.suffix.lower() not in {".md", ".markdown"}:
        raise KnowledgeCoreError("draft path is outside the knowledge root or is not Markdown")
    metadata, content = parse_frontmatter(read_text(source))
    metadata["status"] = "reviewed"
    metadata["updated_at"] = utc_now()
    validate_card_metadata(metadata, "cards")

    destination = scope.knowledge_root / "cards" / source.name
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        with destination.open("x", encoding="utf-8") as stream:
            stream.write(markdown_record(metadata, content))
    except FileExistsError as error:
        raise KnowledgeCoreError(f"published card already exists: {destination.name}") from error
    try:
        source.unlink()
    except Exception:
        destination.unlink(missing_ok=True)
        raise

    indexed = index_scope(scope)
    document = get_document(scope, document_id)
    return {
        "scope": scope.as_dict(),
        "path": str(destination),
        "relativePath": destination.relative_to(scope.knowledge_root).as_posix(),
        "index": indexed,
        **document,
    }


def handle_request(request: dict[str, Any]) -> dict[str, Any]:
    action = str(request.get("action") or "").strip().lower()
    if action == "search":
        return search_scopes(request)
    scope = KnowledgeScope.from_request(request.get("scope") or {}, request.get("piRoot"))
    if action == "initialize":
        return initialize_scope(scope)
    if action == "status":
        return scope_status(scope)
    if action == "inventory":
        return inventory_scope(scope, int(request.get("limit") or 500))
    if action == "index":
        return index_scope(scope, rebuild=False)
    if action == "rebuild":
        return index_scope(scope, rebuild=True)
    if action == "get":
        document_id = str(request.get("documentId") or "").strip()
        if not document_id:
            raise KnowledgeCoreError("get requires documentId")
        return get_document(scope, document_id)
    if action == "capture":
        return capture_record(scope, request)
    if action == "publish":
        return publish_card(scope, request)
    raise KnowledgeCoreError(f"unsupported knowledge action: {action or '<empty>'}")


def main() -> int:
    try:
        request = json.load(sys.stdin)
        if not isinstance(request, dict):
            raise KnowledgeCoreError("request must be a JSON object")
        result = handle_request(request)
        print(json.dumps({"success": True, **result}, ensure_ascii=False))
        return 0
    except Exception as error:
        print(
            json.dumps(
                {"success": False, "error": str(error), "errorType": type(error).__name__},
                ensure_ascii=False,
            )
        )
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
