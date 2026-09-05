"""Portable source identities; SQLite is a disposable index, not their owner."""
from __future__ import annotations

import json
import os
import tempfile
import uuid
from collections import Counter
from pathlib import Path


class SourceIdentities:
    def __init__(self, root: Path, existing: list, file_hashes: dict[str, str]):
        self.path = root / '.source-identities.json'
        if self.path.is_symlink():
            raise ValueError('Source identity registry cannot be a symbolic link')
        self.records = {}
        if self.path.exists():
            value = json.loads(self.path.read_text(encoding='utf-8'))
            if value.get('version') != 1 or not isinstance(value.get('sources'), dict):
                raise ValueError('Unsupported source identity registry; preserve it and restore a valid copy')
            self.records = value['sources']
            for path, record in self.records.items():
                if not isinstance(path, str) or not isinstance(record, dict) or not all(
                    isinstance(record.get(key), str) and record[key] for key in ('id', 'contentHash')
                ):
                    raise ValueError('Invalid source identity registry; refusing to replace it')
        # Migration preserves IDs already cited by cards, including a rename
        # made before the first run of this version. Never discard this on rebuild.
        for row in existing:
            if row['category'] in ('sources', 'inbox'):
                self.records.setdefault(row['relative_path'], {
                    'id': row['id'], 'contentHash': row['content_hash'], 'previousPaths': [],
                })
        self.present_paths = set(file_hashes)
        self.new_hash_counts = Counter(digest for path, digest in file_hashes.items() if path not in self.records)

    def resolve(self, path: str, digest: str) -> str:
        if path in self.records:
            return self.records[path]['id']
        candidates = [old for old, record in self.records.items()
                      if old not in self.present_paths and record['contentHash'] == digest]
        # Equal bytes are not proof of which duplicate was moved. Only reuse
        # when both the missing original and new destination are unambiguous.
        if len(candidates) == 1 and self.new_hash_counts.get(digest) == 1:
            old = candidates[0]
            record = self.records.pop(old)
            record['previousPaths'] = list(dict.fromkeys([*record.get('previousPaths', []), old]))
            self.records[path] = record
            return record['id']
        return 'source-' + uuid.uuid4().hex

    def record(self, path: str, digest: str, source_id: str) -> None:
        self.records[path] = {
            **self.records.get(path, {}), 'id': source_id, 'contentHash': digest,
        }

    def save(self) -> None:
        if not self.records:
            return
        data = json.dumps({'version': 1, 'sources': self.records}, ensure_ascii=False, indent=2, sort_keys=True) + '\n'
        if self.path.exists() and self.path.read_text(encoding='utf-8') == data:
            return
        # Called while index_scope holds its SQLite writer lock. Replace only
        # this managed metadata file, never rewrite imported source bytes.
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=self.path.parent,
                                         prefix='.source-identities-', delete=False) as stream:
            temporary = Path(stream.name)
            try:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
                os.replace(temporary, self.path)
            finally:
                temporary.unlink(missing_ok=True)
