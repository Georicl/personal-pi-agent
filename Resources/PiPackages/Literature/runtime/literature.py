"""Europe PMC adapter; files and Knowledge Core remain the source of truth."""
from __future__ import annotations

import fcntl
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Knowledge/runtime"))
import knowledge_core as knowledge

ENDPOINT = "https://www.ebi.ac.uk/europepmc/webservices/rest/search"
MAX_BYTES = 4 * 1024 * 1024


class LiteratureError(ValueError):
    pass


class PlainText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)

    def handle_starttag(self, tag, attrs):
        if tag in {"p", "br", "h4", "h3", "div"}:
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in {"p", "h4", "h3", "div"}:
            self.parts.append("\n")


def plain(value):
    parser = PlainText()
    parser.feed(str(value or ""))
    return "".join(parser.parts).strip()


def scope_for(request):
    cwd = Path(request["cwd"]).expanduser().resolve()
    pi_root = Path(request["piRoot"]).expanduser().resolve()
    payload = {"kind": "global"} if cwd == (pi_root / "chat").resolve() else {
        "kind": "project", "projectRoot": str(cwd)}
    return knowledge.KnowledgeScope.from_request(payload, pi_root), str(cwd)


def conditions(request):
    query = str(request.get("query") or "").strip()
    if not query or len(query) > 4000:
        raise LiteratureError("Query must contain 1–4000 characters")
    limit = int(request.get("limit", 20))
    if not 1 <= limit <= 50:
        raise LiteratureError("Result limit must be between 1 and 50")
    start, end = request.get("yearFrom"), request.get("yearTo")
    for year in (start, end):
        if year is not None and not 1000 <= int(year) <= 9999:
            raise LiteratureError("Year must contain four digits")
    if start is not None and end is not None and int(start) > int(end):
        raise LiteratureError("Start year must not exceed end year")
    start = int(start) if start is not None else None
    end = int(end) if end is not None else None
    effective = query
    if start is not None or end is not None:
        effective = f"({query}) AND FIRST_PDATE:[{int(start or 1000):04d}-01-01 TO {int(end or 9999):04d}-12-31]"
    return {"question": str(request.get("question") or "")[:8000],
            "query": query, "yearFrom": start, "yearTo": end, "limit": limit,
            "effectiveQuery": effective, "explanation": str(request.get("explanation") or "")[:8000],
            "requestId": request.get("requestId")}


def fetch(query, limit):
    url = ENDPOINT + "?" + urlencode({"query": query, "resultType": "core", "format": "json", "pageSize": limit})
    try:
        with urlopen(Request(url, headers={"User-Agent": "PersonalPi-Literature/0.1", "Accept": "application/json"}), timeout=25) as response:
            raw = response.read(MAX_BYTES + 1)
    except HTTPError as error:
        raise LiteratureError(f"Europe PMC returned HTTP {error.code}; revise the query or retry later") from error
    except (URLError, TimeoutError) as error:
        raise LiteratureError(f"Europe PMC unavailable: {error.reason if isinstance(error, URLError) else error}") from error
    if len(raw) > MAX_BYTES:
        raise LiteratureError("Europe PMC response exceeds 4 MiB; lower the result limit")
    payload = json.loads(raw)
    if not isinstance(payload.get("resultList", {}).get("result"), list) or "hitCount" not in payload:
        raise LiteratureError("Europe PMC returned an invalid search response")
    return payload


def normalize(item, retrieved_at, query):
    if not isinstance(item, dict):
        return None
    source, source_id = str(item.get("source") or ""), str(item.get("id") or "")
    if not source or not source_id or not plain(item.get("title")):
        return None
    doi = re.sub(r"^(https?://(dx\.)?doi\.org/|doi:\s*)", "", str(item.get("doi") or "").strip(), flags=re.I).lower()
    pmid = str(item.get("pmid") or (source_id if source == "MED" else ""))
    pmcid = str(item.get("pmcid") or "").upper()
    identities = [f"epmc:{source}:{source_id}"]
    identities += [f"{key}:{value}" for key, value in [("doi", doi), ("pmid", pmid), ("pmcid", pmcid)] if value]
    source_url = f"https://europepmc.org/article/{quote(source, safe='')}/{quote(source_id, safe='')}"
    authors = [plain(a.get("fullName") or a.get("collectiveName"))
               for a in (item.get("authorList") or {}).get("author", []) or [] if isinstance(a, dict)]
    authors = [a for a in authors if a] or ([plain(item["authorString"])] if item.get("authorString") else [])
    full_text = [entry["url"] for entry in (item.get("fullTextUrlList") or {}).get("fullTextUrl", []) or []
                 if isinstance(entry, dict) and isinstance(entry.get("url"), str) and entry["url"].startswith("https://")]
    return {"id": identities[0], "identifiers": identities, "title": plain(item["title"]), "authors": authors,
            "year": str(item.get("pubYear") or ""), "doi": doi, "pmid": pmid, "pmcid": pmcid,
            "abstract": plain(item.get("abstractText")), "sourceURL": source_url,
            "originalURL": "https://doi.org/" + quote(doi, safe="/") if doi else (full_text[0] if full_text else source_url),
            "fullTextURLs": full_text, "provenance": [{"provider": "Europe PMC", "source": source,
                "recordId": source_id, "url": source_url, "retrievedAt": retrieved_at, "query": query}]}


def deduplicate(records):
    groups = []
    for record in records:
        if record is None:
            continue
        matches = [g for g in groups if set(g["identifiers"]) & set(record["identifiers"])]
        for previous in matches:
            groups.remove(previous)
            record["identifiers"] = list(dict.fromkeys(previous["identifiers"] + record["identifiers"]))
            record["provenance"] = previous["provenance"] + record["provenance"]
            record["fullTextURLs"] = list(dict.fromkeys(previous["fullTextURLs"] + record["fullTextURLs"]))
            for key in ["abstract", "doi", "pmid", "pmcid", "authors", "year"]:
                if not record[key]:
                    record[key] = previous[key]
        groups.append(record)
    return groups


def run_path(request, run_id):
    if not re.fullmatch(r"[0-9a-f]{32}", str(run_id)):
        raise LiteratureError("Invalid search run ID")
    return Path(request["piRoot"]).expanduser().resolve() / "personal/literature" / f"{run_id}.json"


def search(request, fetcher=fetch):
    scope, cwd = scope_for(request)
    plan = conditions(request)
    payload = fetcher(plan["effectiveQuery"], plan["limit"])
    now = knowledge.utc_now()
    raw = payload["resultList"]["result"][:plan["limit"]]
    records = deduplicate([normalize(item, now, plan["effectiveQuery"]) for item in raw])
    result = {"runId": uuid.uuid4().hex, "cwd": cwd, "scopeId": scope.scope_id,
              "provider": "Europe PMC", "retrievedAt": now, "plan": plan,
              "totalHits": int(payload["hitCount"]), "retrievedCount": len(raw), "records": records}
    destination = run_path(request, result["runId"])
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("x", encoding="utf-8") as stream:
        json.dump(result, stream, ensure_ascii=False)
    return result


def existing_sources(scope):
    found = {}
    for category, path in knowledge.discover_files(scope):
        if category != "sources" or path.suffix.lower() != ".md":
            continue
        metadata, _ = knowledge.parse_frontmatter(path.read_text(encoding="utf-8"))
        provenance = metadata.get("provenance", {})
        if provenance.get("kind") != "literature":
            continue
        for identity in provenance.get("record", {}).get("identifiers", []):
            found[identity] = {"sourceId": metadata["id"], "path": str(path), "title": metadata["title"], "reused": True}
    return found


def save(request):
    scope, cwd = scope_for(request)
    snapshot = json.loads(run_path(request, request.get("runId")).read_text(encoding="utf-8"))
    if snapshot["scopeId"] != scope.scope_id or snapshot["cwd"] != cwd:
        raise LiteratureError("Search belongs to another project; search again in the current scope")
    selected = request.get("recordIds")
    if not isinstance(selected, list) or not selected or len(selected) > 50:
        raise LiteratureError("Select between 1 and 50 records")
    by_id = {r["id"]: r for r in snapshot["records"]}
    if any(key not in by_id for key in selected):
        raise LiteratureError("Selected record is absent from this search snapshot")
    knowledge.ensure_scope_directories(scope)
    saved, failures = [], []
    # Serialize GUI and Pi imports in this scope. No secondary identity database.
    with (scope.knowledge_root / ".literature.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        knowledge.index_scope(scope)
        known = existing_sources(scope)
        for record_id in dict.fromkeys(selected):
            record = by_id[record_id]
            prior = next((known[key] for key in record["identifiers"] if key in known), None)
            if prior:
                saved.append({**prior, "recordId": record_id})
                continue
            try:
                content = f"# Bibliographic record\n\n{record['title']}\n\nAuthors: {'; '.join(record['authors']) or 'Unavailable'}\nYear: {record['year'] or 'Unavailable'}\nDOI: {record['doi'] or 'Unavailable'}\nPMID: {record['pmid'] or 'Unavailable'}\nPMCID: {record['pmcid'] or 'Unavailable'}\nOriginal: {record['originalURL']}\n\n# Abstract — source text\n\n{record['abstract'] or 'No abstract supplied by provider.'}\n\n# Retrieval provenance\n\nProvider: Europe PMC\nRetrieved: {snapshot['retrievedAt']}\nQuery: {snapshot['plan']['effectiveQuery']}\nRun: {snapshot['runId']}\n\nMetadata/abstract only; full text has not been read. This is not model synthesis.\n"
                captured = knowledge.capture_record(scope, {"category": "sources", "title": record["title"], "content": content,
                    "sources": [{"source_id": record["sourceURL"], "locator": "Bibliographic metadata and abstract"}],
                    "provenance": {"kind": "literature", "runId": snapshot["runId"], "record": record}})
                entry = {"recordId": record_id, "sourceId": captured["document"]["id"], "path": captured["path"], "title": record["title"], "reused": False}
                saved.append(entry)
                for key in record["identifiers"]:
                    known[key] = {**entry, "reused": True}
            except Exception as error:
                failures.append({"recordId": record_id, "error": str(error)})
    return {"saved": saved, "failures": failures, "runId": snapshot["runId"]}


def draft(request):
    scope, _ = scope_for(request)
    source_ids = request.get("sourceIds")
    if not isinstance(source_ids, list) or not 1 <= len(source_ids) <= 50:
        raise LiteratureError("Summary requires 1–50 saved local sources")
    refs = []
    for identity in dict.fromkeys(source_ids):
        document = knowledge.get_document(scope, identity)["document"]
        if document["category"] != "sources":
            raise LiteratureError("Summary references must be saved sources in the current scope")
        refs.append({"source_id": identity, "locator": "Abstract — source text"})
    content = str(request.get("content") or "").strip()
    if not content or len(content) > 100_000:
        raise LiteratureError("Summary content must contain 1–100000 characters")
    captured = knowledge.capture_record(scope, {"category": "drafts", "type": "literature-summary", "confidence": "unknown",
        "title": request.get("title"), "content": "# Model synthesis — unreviewed\n\n" + content + "\n\n# Evidence boundary\n\nBased on retrieved metadata/abstracts only. Full text was not read; conclusions require review.\n",
        "sources": refs, "provenance": {"kind": "literature-summary", "evidenceLevel": "metadata-and-abstract"}})
    return {"sourceId": captured["document"]["id"], "path": captured["path"]}


def handle_request(request):
    action = request.get("action")
    _, cwd = scope_for(request)
    if action == "plan":
        result = conditions(request)
    elif action == "search":
        result = search(request)
    elif action == "save":
        result = save(request)
    elif action == "draft":
        result = draft(request)
    else:
        raise LiteratureError("Unknown Literature action")
    return {"schemaVersion": 1, "kind": {"save": "saved"}.get(action, action), "cwd": cwd, "result": result}


if __name__ == "__main__":
    try:
        print(json.dumps({"success": True, **handle_request(json.load(sys.stdin))}, ensure_ascii=False))
    except Exception as error:
        print(json.dumps({"success": False, "error": str(error)}, ensure_ascii=False))
