PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS schema_info (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

INSERT INTO schema_info(key, value)
VALUES ('schema_version', '1')
ON CONFLICT(key) DO UPDATE SET value = excluded.value;

CREATE TABLE IF NOT EXISTS scopes (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL CHECK(kind IN ('global', 'project')),
    knowledge_root TEXT NOT NULL,
    project_root TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS documents (
    rowid INTEGER PRIMARY KEY AUTOINCREMENT,
    id TEXT NOT NULL UNIQUE,
    scope_id TEXT NOT NULL REFERENCES scopes(id) ON DELETE CASCADE,
    relative_path TEXT NOT NULL,
    category TEXT NOT NULL CHECK(category IN ('inbox', 'sources', 'cards', 'drafts', 'entries')),
    kind TEXT NOT NULL,
    title TEXT NOT NULL,
    status TEXT NOT NULL,
    card_type TEXT,
    confidence TEXT,
    tags_json TEXT NOT NULL DEFAULT '[]',
    source_refs_json TEXT NOT NULL DEFAULT '[]',
    metadata_json TEXT NOT NULL DEFAULT '{}',
    content_hash TEXT NOT NULL,
    size_bytes INTEGER NOT NULL,
    modified_ns INTEGER NOT NULL,
    indexed_at TEXT NOT NULL,
    error TEXT,
    UNIQUE(scope_id, relative_path)
);

CREATE INDEX IF NOT EXISTS documents_scope_category_idx
ON documents(scope_id, category, status);

CREATE TABLE IF NOT EXISTS chunks (
    rowid INTEGER PRIMARY KEY AUTOINCREMENT,
    id TEXT NOT NULL UNIQUE,
    document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    ordinal INTEGER NOT NULL,
    locator TEXT NOT NULL,
    heading TEXT,
    page_number INTEGER,
    title TEXT NOT NULL,
    tags TEXT NOT NULL DEFAULT '',
    text TEXT NOT NULL,
    text_hash TEXT NOT NULL,
    UNIQUE(document_id, ordinal)
);

CREATE INDEX IF NOT EXISTS chunks_document_idx ON chunks(document_id, ordinal);

CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
    text,
    title,
    tags,
    content='chunks',
    content_rowid='rowid',
    tokenize='trigram'
);

CREATE TRIGGER IF NOT EXISTS chunks_after_insert AFTER INSERT ON chunks BEGIN
    INSERT INTO chunks_fts(rowid, text, title, tags)
    VALUES (new.rowid, new.text, new.title, new.tags);
END;

CREATE TRIGGER IF NOT EXISTS chunks_after_delete AFTER DELETE ON chunks BEGIN
    INSERT INTO chunks_fts(chunks_fts, rowid, text, title, tags)
    VALUES ('delete', old.rowid, old.text, old.title, old.tags);
END;

CREATE TRIGGER IF NOT EXISTS chunks_after_update AFTER UPDATE ON chunks BEGIN
    INSERT INTO chunks_fts(chunks_fts, rowid, text, title, tags)
    VALUES ('delete', old.rowid, old.text, old.title, old.tags);
    INSERT INTO chunks_fts(rowid, text, title, tags)
    VALUES (new.rowid, new.text, new.title, new.tags);
END;

CREATE TABLE IF NOT EXISTS indexing_runs (
    id TEXT PRIMARY KEY,
    scope_id TEXT NOT NULL,
    action TEXT NOT NULL,
    started_at TEXT NOT NULL,
    finished_at TEXT NOT NULL,
    indexed_count INTEGER NOT NULL,
    updated_count INTEGER NOT NULL,
    unchanged_count INTEGER NOT NULL,
    removed_count INTEGER NOT NULL,
    failed_count INTEGER NOT NULL,
    details_json TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS indexing_runs_scope_time_idx
ON indexing_runs(scope_id, finished_at DESC);
