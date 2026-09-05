import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'Resources/PiPackages/Literature/runtime'))
import literature as lit


def item(identity='123', **changes):
    return {'id': identity, 'source': 'MED', 'pmid': identity, 'doi': '10.1234/Test',
            'title': 'T <i>cell</i> response', 'pubYear': '2024',
            'authorList': {'author': [{'fullName': 'Researcher A'}]},
            'abstractText': '<h4>Methods</h4><p>Measured CD4 T cells.</p>', **changes}


class LiteratureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.project = self.root / 'project'
        self.project.mkdir()
        self.request = {'piRoot': str(self.root / 'pi'), 'cwd': str(self.project), 'query': '"T cell" AND CD4', 'limit': 10}

    def tearDown(self):
        self.temporary.cleanup()

    def search(self, records=None):
        return lit.search(self.request, lambda query, limit: {'hitCount': 100, 'resultList': {'result': records or [item()]}})

    def save(self, search):
        return lit.save({**self.request, 'runId': search['runId'], 'recordIds': [r['id'] for r in search['records']]})

    def test_plan_has_no_disk_or_network_side_effects(self):
        with patch.object(lit, 'fetch', side_effect=AssertionError('network')):
            plan = lit.handle_request({**self.request, 'action': 'plan', 'yearFrom': 2020, 'yearTo': 2025})
        self.assertIn('FIRST_PDATE:[2020-01-01 TO 2025-12-31]', plan['result']['effectiveQuery'])
        self.assertFalse((self.root / 'pi').exists())

    def test_rejects_invalid_conditions(self):
        for fields in [{'query': ''}, {'limit': 51}, {'yearFrom': 2026, 'yearTo': 2020}, {'yearFrom': 20}]:
            with self.subTest(fields=fields), self.assertRaises((ValueError, lit.LiteratureError)):
                lit.conditions({**self.request, **fields})

    def test_normalization_preserves_facts_and_missing_values(self):
        record = lit.normalize(item(), 'now', 'query')
        self.assertEqual(record['title'], 'T cell response')
        self.assertEqual(record['doi'], '10.1234/test')
        self.assertIn('Methods', record['abstract'])
        self.assertIn('Methods\n', record['abstract'])
        missing = lit.normalize(item('PMC1', source='PMC', pmid='', doi='', abstractText='', authorList={}, pubYear=''), 'now', 'q')
        for key in ['doi', 'pmid', 'abstract', 'year']:
            self.assertEqual(missing[key], '')
        self.assertEqual(missing['authors'], [])
        self.assertEqual(missing['sourceURL'], 'https://europepmc.org/article/PMC/PMC1')
        nulls = lit.normalize(item(authorList=None, fullTextUrlList=None, abstractText=None), 'now', 'q')
        self.assertEqual(nulls['authors'], [])
        self.assertEqual(nulls['abstract'], '')

    def test_identifier_dedup_transitively_merges_provenance_not_titles(self):
        records = [item('1', doi='10.1/a'), item('2', doi='10.1/b'), item('1', doi='https://doi.org/10.1/B')]
        deduped = lit.deduplicate([lit.normalize(x, 'now', 'q') for x in records])
        self.assertEqual(len(deduped), 1)
        self.assertEqual(len(deduped[0]['provenance']), 3)
        self.assertIn('doi:10.1/a', deduped[0]['identifiers'])
        records = [item('1', doi=''), item('2', doi='')]
        self.assertEqual(len(lit.deduplicate([lit.normalize(x, 'now', 'q') for x in records])), 2)

    def test_search_snapshot_bound_to_scope_and_actual_query(self):
        search = self.search()
        snapshot = json.loads(lit.run_path(self.request, search['runId']).read_text())
        self.assertEqual(snapshot['cwd'], str(self.project))
        self.assertEqual(snapshot['plan']['effectiveQuery'], self.request['query'])
        self.assertEqual(snapshot['totalHits'], 100)
        self.assertEqual(snapshot['retrievedCount'], 1)
        self.assertTrue(snapshot['records'][0]['provenance'][0]['retrievedAt'].endswith('Z'))

    def test_capture_reuses_knowledge_and_preserves_provenance(self):
        search = self.search()
        saved = self.save(search)['saved'][0]
        scope, _ = lit.scope_for(self.request)
        document = lit.knowledge.get_document(scope, saved['sourceId'])
        self.assertEqual(document['document']['category'], 'sources')
        self.assertEqual(document['document']['metadata']['provenance']['runId'], search['runId'])
        self.assertIn('metadata/abstract', Path(saved['path']).read_text().lower())
        again = self.save(self.search())['saved'][0]
        self.assertTrue(again['reused'])
        self.assertEqual(saved['sourceId'], again['sourceId'])
        self.assertEqual(len(list((scope.knowledge_root / 'sources').glob('*.md'))), 1)

    def test_concurrent_imports_reuse_one_source(self):
        search = self.search()
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            outputs = list(pool.map(lambda _: self.save(search), range(2)))
        self.assertEqual(outputs[0]['saved'][0]['sourceId'], outputs[1]['saved'][0]['sourceId'])

    def test_wrong_project_and_forged_selection_cannot_write(self):
        search = self.search()
        for override in [{'cwd': str(self.root / 'other')}, {'recordIds': ['invented']}, {'runId': '../private'}]:
            request = {**self.request, 'runId': search['runId'], 'recordIds': [search['records'][0]['id']], **override}
            with self.subTest(override=override), self.assertRaises(lit.LiteratureError):
                lit.save(request)
        self.assertFalse((self.root / 'other').exists())
        self.assertFalse((self.project / '.pi/knowledge').exists())

    def test_global_chat_saves_only_global_sources(self):
        self.request['cwd'] = str(self.root / 'pi/chat')
        saved = self.save(self.search())['saved'][0]
        self.assertTrue(saved['path'].startswith(str(self.root / 'pi/knowledge/sources')))
        self.assertFalse((self.root / 'pi/chat/.pi/knowledge').exists())

    def test_draft_has_local_citations_and_cannot_publish(self):
        saved = self.save(self.search())['saved'][0]
        draft = lit.draft({**self.request, 'title': 'Synthesis', 'content': 'Source facts differ from inference.', 'sourceIds': [saved['sourceId']]})
        scope, _ = lit.scope_for(self.request)
        document = lit.knowledge.get_document(scope, draft['sourceId'])['document']
        self.assertEqual(document['status'], 'draft')
        self.assertEqual(document['category'], 'drafts')
        self.assertIn(saved['sourceId'], Path(draft['path']).read_text())
        with self.assertRaises(lit.knowledge.KnowledgeCoreError):
            lit.draft({**self.request, 'cwd': str(self.root / 'other'), 'title': 'bad', 'content': 'bad', 'sourceIds': [saved['sourceId']]})

    def test_partial_save_reports_failure_instead_of_total_success(self):
        search = self.search([item('1', doi='10.1/a'), item('2', doi='10.1/b')])
        capture = lit.knowledge.capture_record
        def fail_second(scope, request):
            if request['provenance']['record']['pmid'] == '2':
                raise OSError('Disk fixture error')
            return capture(scope, request)
        with patch.object(lit.knowledge, 'capture_record', side_effect=fail_second):
            result = self.save(search)
        self.assertEqual(len(result['saved']), 1)
        self.assertEqual(len(result['failures']), 1)

    def test_http_timeout_oversize_and_invalid_response_are_errors(self):
        for error in [lit.HTTPError(lit.ENDPOINT, 429, 'rate limit', {}, None), lit.URLError('offline'), TimeoutError('timeout')]:
            with self.subTest(error=error), patch.object(lit, 'urlopen', side_effect=error), self.assertRaises(lit.LiteratureError):
                lit.fetch('T cell', 1)
        for raw in [b'{}', b'x' * (lit.MAX_BYTES + 1)]:
            with patch.object(lit, 'urlopen') as opened:
                opened.return_value.__enter__.return_value.read.return_value = raw
                with self.assertRaises(lit.LiteratureError):
                    lit.fetch('T cell', 1)

    def test_json_bridge_and_error_envelope(self):
        response = subprocess.run([sys.executable, str(Path(lit.__file__))], input=json.dumps({**self.request, 'action': 'plan'}), capture_output=True, text=True, check=True)
        self.assertTrue(json.loads(response.stdout)['success'])
        response = subprocess.run([sys.executable, str(Path(lit.__file__))], input='{}', capture_output=True, text=True, check=True)
        self.assertFalse(json.loads(response.stdout)['success'])

    @unittest.skipUnless(os.getenv('PERSONAL_PI_TEST_LITERATURE_LIVE') == '1', 'opt-in public API check')
    def test_live_provider(self):
        search = lit.search({**self.request, 'query': 'EXT_ID:32810481 AND SRC:MED', 'limit': 1})
        self.assertEqual(search['totalHits'], 1)
        self.assertEqual(search['records'][0]['pmid'], '32810481')
        self.assertTrue(search['records'][0]['abstract'])
        self.assertEqual(len(self.save(search)['saved']), 1)


if __name__ == '__main__':
    unittest.main()
