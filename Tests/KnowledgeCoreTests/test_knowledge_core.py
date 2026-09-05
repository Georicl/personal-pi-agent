"""Isolated behavior tests for the bundled Knowledge Core runtime."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import knowledge_core as core


def write_minimal_pdf(path: Path, text: str) -> None:
    escaped = text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    stream = f"BT /F1 12 Tf 72 720 Td ({escaped}) Tj ET".encode("latin-1")
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        (
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            b"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>"
        ),
        b"<< /Length " + str(len(stream)).encode("ascii") + b">>\nstream\n" + stream + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    data = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for number, body in enumerate(objects, start=1):
        offsets.append(len(data))
        data.extend(f"{number} 0 obj\n".encode("ascii"))
        data.extend(body)
        data.extend(b"\nendobj\n")
    xref_offset = len(data)
    data.extend(f"xref\n0 {len(objects) + 1}\n".encode("ascii"))
    data.extend(b"0000000000 65535 f \n")
    for offset in offsets[1:]:
        data.extend(f"{offset:010d} 00000 n \n".encode("ascii"))
    data.extend(
        (
            f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
            f"startxref\n{xref_offset}\n%%EOF\n"
        ).encode("ascii")
    )
    path.write_bytes(bytes(data))


class KnowledgeCoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.pi_root = self.root / "pi-root"
        self.project_root = self.root / "project"
        self.project_root.mkdir()
        self.global_scope = core.KnowledgeScope.from_request(
            {"kind": "global"}, str(self.pi_root)
        )
        self.project_scope = core.KnowledgeScope.from_request(
            {"kind": "project", "projectRoot": str(self.project_root)},
            str(self.pi_root),
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_scope_paths_keep_project_indexes_outside_repository(self) -> None:
        self.assertEqual(self.global_scope.knowledge_root, self.pi_root / "knowledge")
        self.assertEqual(
            self.global_scope.index_path,
            self.pi_root / "personal" / "knowledge" / "global.sqlite",
        )
        self.assertEqual(
            self.project_scope.knowledge_root,
            self.project_root / ".pi" / "knowledge",
        )
        self.assertTrue(
            self.project_scope.index_path.is_relative_to(
                self.pi_root / "personal" / "knowledge" / "projects"
            )
        )
        self.assertFalse(self.project_scope.index_path.is_relative_to(self.project_root))

    def test_initialize_creates_canonical_directories_and_schema(self) -> None:
        result = core.initialize_scope(self.global_scope)
        self.assertTrue(result["initialized"])
        self.assertEqual(result["schemaVersion"], 1)
        for name in core.KNOWLEDGE_DIRECTORIES:
            self.assertTrue((self.global_scope.knowledge_root / name).is_dir())
        status = core.scope_status(self.global_scope)
        self.assertEqual(status["counts"], {"documents": 0, "chunks": 0, "errors": 0})

    def test_inventory_reports_all_files_sizes_and_index_state(self) -> None:
        core.initialize_scope(self.project_scope)
        source = self.project_scope.knowledge_root / "sources" / "paper.txt"
        attachment = self.project_scope.knowledge_root / "attachments" / "table.csv"
        source.write_text("Indexed source material", encoding="utf-8")
        attachment.write_text("x,y\n1,2\n", encoding="utf-8")
        core.index_scope(self.project_scope)

        inventory = core.inventory_scope(self.project_scope)

        self.assertEqual(inventory["fileCount"], 2)
        self.assertEqual(
            inventory["totalBytes"], source.stat().st_size + attachment.stat().st_size
        )
        self.assertEqual(inventory["categories"]["sources"]["files"], 1)
        self.assertEqual(inventory["categories"]["attachments"]["files"], 1)
        files = {item["relativePath"]: item for item in inventory["files"]}
        self.assertIsNotNone(files["sources/paper.txt"]["index"])
        self.assertIsNone(files["attachments/table.csv"]["index"])
        self.assertFalse(files["attachments/table.csv"]["supported"])

    def test_inventory_counts_unclassified_files_and_marks_changed_sources(self) -> None:
        core.initialize_scope(self.project_scope)
        root = self.project_scope.knowledge_root
        source = root / "sources" / "paper.txt"
        source.write_text("Initial content", encoding="utf-8")
        core.index_scope(self.project_scope)
        source.write_text("Changed source content", encoding="utf-8")
        (root / "loose.md").write_text("Notes", encoding="utf-8")
        (root / ".hidden").write_text("ignored", encoding="utf-8")
        (root / "link.txt").symlink_to(source)
        snapshot = core.inventory_scope(self.project_scope)
        self.assertEqual(snapshot["fileCount"], 2)
        self.assertEqual(snapshot["totalBytes"], source.stat().st_size + 5)
        self.assertEqual(snapshot["categories"]["other"]["files"], 1)
        indexed = next(item for item in snapshot["files"] if item["category"] == "sources")
        self.assertTrue(indexed["index"]["stale"])

    def test_import_copies_without_overwriting_and_reports_partial_errors(self) -> None:
        source = self.root / "paper.txt"
        source.write_text("Original source evidence", encoding="utf-8")
        result = core.import_sources(self.project_scope, {"paths": [str(source)]})
        self.assertEqual(result["imported"], ["sources/paper.txt"])
        self.assertEqual(result["index"]["indexed"], 1)
        source.write_text("Changed input must not overwrite", encoding="utf-8")
        duplicate = core.import_sources(self.project_scope, {"paths": [str(source)]})
        self.assertEqual(duplicate["imported"], [])
        self.assertEqual(len(duplicate["failures"]), 1)
        self.assertEqual(
            (self.project_scope.knowledge_root / "sources/paper.txt").read_text(),
            "Original source evidence",
        )
        self.assertEqual(source.read_text(), "Changed input must not overwrite")

    def test_reindex_clears_stale_status_after_unchanged_content_is_resaved(self) -> None:
        core.initialize_scope(self.project_scope)
        source = self.project_scope.knowledge_root / "sources" / "paper.txt"
        source.write_text("Evidence", encoding="utf-8")
        core.index_scope(self.project_scope)
        stat = source.stat()
        os.utime(source, ns=(stat.st_atime_ns, stat.st_mtime_ns + 1_000_000_000))
        self.assertTrue(core.inventory_scope(self.project_scope)["files"][0]["index"]["stale"])
        result = core.index_scope(self.project_scope)
        self.assertEqual(result["unchanged"], 1)
        self.assertFalse(core.inventory_scope(self.project_scope)["files"][0]["index"]["stale"])

    def test_publish_rejects_a_draft_changed_since_indexing(self) -> None:
        captured = core.capture_record(self.project_scope, {
            "category": "drafts", "title": "Pending", "content": "User judgment", "sources": []
        })
        draft = Path(captured["path"])
        text = draft.read_text().replace("status: draft", "status: deprecated")
        draft.write_text(text)
        with self.assertRaisesRegex(core.KnowledgeCoreError, "changed since indexing"):
            core.publish_card(self.project_scope, {
                "documentId": captured["document"]["id"], "userConfirmed": True,
            })
        self.assertEqual(draft.read_text(), text)

    def test_rebuild_keeps_existing_database_readers_connected(self) -> None:
        core.initialize_scope(self.global_scope)
        source = self.global_scope.knowledge_root / "sources/paper.txt"
        source.write_text("Initial evidence", encoding="utf-8")
        core.index_scope(self.global_scope)
        reader = core.connect_scope(self.global_scope, create=False)
        try:
            self.assertEqual(reader.execute("SELECT text FROM chunks").fetchone()[0], "Initial evidence")
            source.write_text("Updated evidence", encoding="utf-8")
            core.index_scope(self.global_scope, rebuild=True)
            self.assertEqual(reader.execute("SELECT text FROM chunks").fetchone()[0], "Updated evidence")
        finally:
            reader.close()

    def test_incremental_index_search_and_removed_source_detection(self) -> None:
        core.initialize_scope(self.global_scope)
        source = self.global_scope.knowledge_root / "sources" / "integration.md"
        source.write_text(
            "# Batch correction\n\nSpatial transcriptomics integration must preserve biological signal.",
            encoding="utf-8",
        )

        first = core.index_scope(self.global_scope)
        self.assertEqual(first["indexed"], 1)
        self.assertEqual(first["failed"], 0)
        second = core.index_scope(self.global_scope)
        self.assertEqual(second["unchanged"], 1)

        search = core.search_scopes(
            {
                "query": "spatial transcriptomics",
                "piRoot": str(self.pi_root),
                "scopes": [{"kind": "global"}],
            }
        )
        self.assertEqual(len(search["results"]), 1)
        self.assertEqual(search["results"][0]["chunk"]["locator"], "Section: Batch correction")

        source.write_text(
            "# Batch correction\n\nSpatial transcriptomics integration needs auditable benchmarks.",
            encoding="utf-8",
        )
        updated = core.index_scope(self.global_scope)
        self.assertEqual(updated["updated"], 1)
        self.assertIn("auditable benchmarks", core.search_scopes(
            {
                "query": "auditable benchmarks",
                "piRoot": str(self.pi_root),
                "scopes": [{"kind": "global"}],
            }
        )["results"][0]["chunk"]["text"])

        source.unlink()
        removed = core.index_scope(self.global_scope)
        self.assertEqual(removed["removed"], 1)
        self.assertEqual(core.scope_status(self.global_scope)["counts"]["documents"], 0)

    def test_markdown_section_heading_is_searchable(self) -> None:
        core.initialize_scope(self.global_scope)
        source = self.global_scope.knowledge_root / "sources" / "integration.md"
        source.write_text(
            """---
title: Integration notes
---
## Batch correction

Preserve biological signal while combining samples.
""",
            encoding="utf-8",
        )
        core.index_scope(self.global_scope)

        search = core.search_scopes(
            {
                "query": "batch correction",
                "piRoot": str(self.pi_root),
                "scopes": [{"kind": "global"}],
            }
        )

        self.assertEqual(len(search["results"]), 1)
        self.assertEqual(search["results"][0]["chunk"]["heading"], "Batch correction")

    def test_global_and_project_search_are_merged_without_scope_leakage(self) -> None:
        core.initialize_scope(self.global_scope)
        core.initialize_scope(self.project_scope)
        (self.global_scope.knowledge_root / "sources" / "global.txt").write_text(
            "图神经网络可以编码邻接关系。", encoding="utf-8"
        )
        (self.project_scope.knowledge_root / "sources" / "project.txt").write_text(
            "空间转录组项目使用图神经网络分析组织结构。", encoding="utf-8"
        )
        core.index_scope(self.global_scope)
        core.index_scope(self.project_scope)

        project_only = core.search_scopes(
            {
                "query": "空间转录组",
                "piRoot": str(self.pi_root),
                "scopes": [
                    {"kind": "project", "projectRoot": str(self.project_root)}
                ],
            }
        )
        self.assertEqual(len(project_only["results"]), 1)
        self.assertTrue(project_only["results"][0]["document"]["scopeId"].startswith("project:"))

        merged = core.search_scopes(
            {
                "query": "图神经网络",
                "piRoot": str(self.pi_root),
                "scopes": [
                    {"kind": "project", "projectRoot": str(self.project_root)},
                    {"kind": "global"},
                    {"kind": "global"},
                ],
            }
        )
        self.assertEqual(len(merged["results"]), 2)
        self.assertTrue(merged["results"][0]["document"]["scopeId"].startswith("project:"))

    def test_reviewed_cards_are_structured_and_drafts_are_opt_in(self) -> None:
        core.initialize_scope(self.project_scope)
        cards = self.project_scope.knowledge_root / "cards"
        drafts = self.project_scope.knowledge_root / "drafts"
        cards.joinpath("graph-method.md").write_text(
            """---
id: card-graph-method
title: Graph construction
type: method
status: reviewed
confidence: high
tags: [graph, spatial]
sources:
  - source_id: source-paper-1
    locator: Methods, page 4
---
# Graph construction

Radius graphs encode local tissue neighborhoods.
""",
            encoding="utf-8",
        )
        drafts.joinpath("pending.md").write_text(
            """---
id: card-pending
title: Pending hypothesis
type: hypothesis
status: draft
confidence: low
tags: [pending]
sources: []
---
# Pending hypothesis

Draft-only-evidence should require explicit inclusion.
""",
            encoding="utf-8",
        )
        result = core.index_scope(self.project_scope)
        self.assertEqual(result["indexed"], 2)

        reviewed = core.search_scopes(
            {
                "query": "local tissue neighborhoods",
                "piRoot": str(self.pi_root),
                "scopes": [
                    {"kind": "project", "projectRoot": str(self.project_root)}
                ],
            }
        )
        self.assertEqual(reviewed["results"][0]["document"]["id"], "card-graph-method")
        card = core.get_document(self.project_scope, "card-graph-method")
        self.assertEqual(card["document"]["confidence"], "high")
        self.assertEqual(card["document"]["sources"][0]["source_id"], "source-paper-1")

        hidden_draft = core.search_scopes(
            {
                "query": "Draft-only-evidence",
                "piRoot": str(self.pi_root),
                "scopes": [
                    {"kind": "project", "projectRoot": str(self.project_root)}
                ],
            }
        )
        self.assertEqual(hidden_draft["results"], [])
        visible_draft = core.search_scopes(
            {
                "query": "Draft-only-evidence",
                "piRoot": str(self.pi_root),
                "includeDrafts": True,
                "scopes": [
                    {"kind": "project", "projectRoot": str(self.project_root)}
                ],
            }
        )
        self.assertEqual(visible_draft["results"][0]["document"]["id"], "card-pending")

    def test_legacy_entries_remain_searchable_with_draft_filtering(self) -> None:
        core.initialize_scope(self.global_scope)
        entries = self.global_scope.knowledge_root / "entries"
        entries.mkdir()
        entries.joinpath("reviewed.md").write_text(
            """---
id: legacy-reviewed
title: Legacy reviewed card
type: concept
status: reviewed
confidence: medium
sources: []
---

Legacy reviewed evidence remains discoverable.
""",
            encoding="utf-8",
        )
        entries.joinpath("draft.md").write_text(
            """---
id: legacy-draft
title: Legacy draft card
type: hypothesis
status: draft
confidence: low
sources: []
---

Legacy tentative evidence stays hidden by default.
""",
            encoding="utf-8",
        )
        result = core.index_scope(self.global_scope)
        self.assertEqual(result["indexed"], 2)

        reviewed = core.search_scopes(
            {
                "query": "reviewed evidence",
                "piRoot": str(self.pi_root),
                "scopes": [{"kind": "global"}],
            }
        )
        self.assertEqual(reviewed["results"][0]["document"]["id"], "legacy-reviewed")

        hidden_draft = core.search_scopes(
            {
                "query": "tentative evidence",
                "piRoot": str(self.pi_root),
                "scopes": [{"kind": "global"}],
            }
        )
        self.assertEqual(hidden_draft["results"], [])
        visible_draft = core.search_scopes(
            {
                "query": "tentative evidence",
                "piRoot": str(self.pi_root),
                "includeDrafts": True,
                "scopes": [{"kind": "global"}],
            }
        )
        self.assertEqual(visible_draft["results"][0]["document"]["id"], "legacy-draft")

    def test_moving_a_card_with_the_same_id_reindexes_in_one_run(self) -> None:
        core.initialize_scope(self.global_scope)
        cards = self.global_scope.knowledge_root / "cards"
        original = cards / "original.md"
        moved = cards / "renamed.md"
        card = """---
id: stable-card
title: Stable card
type: concept
status: reviewed
sources: []
---

Stable identity survives a file move.
"""
        original.write_text(card, encoding="utf-8")
        core.index_scope(self.global_scope)
        original.rename(moved)

        result = core.index_scope(self.global_scope)

        self.assertEqual(result["removed"], 1)
        self.assertEqual(result["indexed"], 1)
        document = core.get_document(self.global_scope, "stable-card")["document"]
        self.assertEqual(document["relativePath"], "cards/renamed.md")

    def test_capture_and_confirmed_publish_preserve_card_identity(self) -> None:
        captured = core.capture_record(
            self.project_scope,
            {
                "category": "drafts",
                "title": "Graph neighborhood principle",
                "type": "concept",
                "confidence": "medium",
                "sources": [
                    {"source_id": "source-paper-1", "locator": "Methods, page 4"}
                ],
                "tags": ["graph", "spatial"],
                "content": "## Source facts\n\nRadius graphs encode local neighborhoods.",
            },
        )
        document_id = captured["document"]["id"]
        self.assertEqual(captured["document"]["status"], "draft")
        self.assertTrue(Path(captured["path"]).is_file())
        self.assertEqual(
            core.search_scopes(
                {
                    "query": "local neighborhoods",
                    "piRoot": str(self.pi_root),
                    "scopes": [
                        {"kind": "project", "projectRoot": str(self.project_root)}
                    ],
                }
            )["results"],
            [],
        )

        with self.assertRaisesRegex(core.KnowledgeCoreError, "explicit user confirmation"):
            core.publish_card(
                self.project_scope,
                {"documentId": document_id, "userConfirmed": False},
            )
        published = core.publish_card(
            self.project_scope,
            {"documentId": document_id, "userConfirmed": True},
        )

        self.assertEqual(published["document"]["id"], document_id)
        self.assertEqual(published["document"]["status"], "reviewed")
        self.assertEqual(published["document"]["category"], "cards")
        self.assertTrue(Path(published["path"]).is_file())
        self.assertEqual(
            core.search_scopes(
                {
                    "query": "local neighborhoods",
                    "piRoot": str(self.pi_root),
                    "scopes": [
                        {"kind": "project", "projectRoot": str(self.project_root)}
                    ],
                }
            )["results"][0]["document"]["id"],
            document_id,
        )

    def test_invalid_card_is_audited_but_not_searchable(self) -> None:
        core.initialize_scope(self.global_scope)
        invalid = self.global_scope.knowledge_root / "cards" / "invalid.md"
        invalid.write_text("# Missing frontmatter\n\nThis must not become trusted knowledge.", encoding="utf-8")
        result = core.index_scope(self.global_scope)
        self.assertEqual(result["failed"], 1)
        self.assertIn("missing frontmatter fields", result["failures"][0]["error"])
        status = core.scope_status(self.global_scope)
        self.assertEqual(status["counts"]["errors"], 1)
        unchanged = core.index_scope(self.global_scope)
        self.assertEqual(unchanged["unchanged"], 1)
        self.assertEqual(unchanged["failed"], 0)
        search = core.search_scopes(
            {
                "query": "trusted knowledge",
                "piRoot": str(self.pi_root),
                "scopes": [{"kind": "global"}],
            }
        )
        self.assertEqual(search["results"], [])

    def test_oversized_sources_are_rejected_before_content_is_loaded(self) -> None:
        core.initialize_scope(self.global_scope)
        source = self.global_scope.knowledge_root / "sources" / "large.txt"
        source.write_text("0123456789ABCDEF", encoding="utf-8")
        original_limit = core.MAX_FILE_BYTES
        core.MAX_FILE_BYTES = 8
        try:
            first = core.index_scope(self.global_scope)
            self.assertEqual(first["failed"], 1)
            self.assertIn("file exceeds 8 bytes", first["failures"][0]["error"])
            second = core.index_scope(self.global_scope)
            self.assertEqual(second["unchanged"], 1)
        finally:
            core.MAX_FILE_BYTES = original_limit

    def test_pdf_pages_preserve_page_locators(self) -> None:
        core.initialize_scope(self.global_scope)
        pdf = self.global_scope.knowledge_root / "sources" / "paper.pdf"
        write_minimal_pdf(pdf, "Spatial transcriptomics PDF evidence")
        result = core.index_scope(self.global_scope)
        self.assertEqual(result["indexed"], 1)
        search = core.search_scopes(
            {
                "query": "PDF evidence",
                "piRoot": str(self.pi_root),
                "scopes": [{"kind": "global"}],
            }
        )
        self.assertEqual(search["results"][0]["chunk"]["pageNumber"], 1)
        self.assertEqual(search["results"][0]["chunk"]["locator"], "Page 1")

    def test_json_runner_protocol_and_rebuild(self) -> None:
        request = {
            "action": "initialize",
            "piRoot": str(self.pi_root),
            "scope": {"kind": "global"},
        }
        process = subprocess.run(
            [sys.executable, str(Path(core.__file__))],
            input=json.dumps(request),
            text=True,
            capture_output=True,
            check=True,
        )
        response = json.loads(process.stdout)
        self.assertTrue(response["success"])
        source = self.global_scope.knowledge_root / "sources" / "rebuild.txt"
        source.write_text("Rebuildable derived index", encoding="utf-8")
        core.index_scope(self.global_scope)
        rebuilt = core.index_scope(self.global_scope, rebuild=True)
        self.assertEqual(rebuilt["indexed"], 1)
        self.assertEqual(core.scope_status(self.global_scope)["counts"]["documents"], 1)


if __name__ == "__main__":
    unittest.main()
