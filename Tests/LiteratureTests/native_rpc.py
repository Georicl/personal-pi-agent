"""Actual Pi Extension runtime with isolated fixtures; no paid model requests."""
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import time

repo = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repo / 'Resources/PiPackages/Literature/runtime'))
import literature

with tempfile.TemporaryDirectory(prefix='personal-pi-literature-') as temporary:
    root = Path(temporary).resolve()
    project = root / 'project'
    project.mkdir()
    agent = root / 'pi/agent'
    agent.mkdir(parents=True)
    request = {'piRoot': str(root / 'pi'), 'cwd': str(project), 'query': 'CD4', 'limit': 10}
    snapshot = literature.search(request, lambda *_: {'hitCount': 1, 'resultList': {'result': [
        {'id': '123', 'source': 'MED', 'title': 'Native integration fixture', 'abstractText': 'Offline fixture evidence.'}
    ]}})
    (project / 'search-fixture.json').write_text(json.dumps(snapshot))
    env = {**os.environ, 'PERSONAL_PI_DATA_ROOT': str(root / 'pi'), 'PI_CODING_AGENT_DIR': str(agent),
           'PERSONAL_PI_KNOWLEDGE_ENVIRONMENT': str(root / 'managed')}
    process = subprocess.Popen(['pi', '--mode', 'rpc', '--offline', '--no-session', '--no-approve',
        '--extension', str(repo / 'Resources/PiPackages/Literature'),
        '--extension', str(repo / 'Tests/Fixtures/literature_extension.js')], cwd=project, env=env,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
    try:
        def send(value):
            process.stdin.write(json.dumps(value) + '\n')
            process.stdin.flush()
        send({'id': 'commands', 'type': 'get_commands'})
        deadline = time.monotonic() + 30
        response = None
        while time.monotonic() < deadline:
            readable, _, _ = select.select([process.stdout], [], [], 0.25)
            if readable:
                line = process.stdout.readline()
                if not line:
                    break
                value = json.loads(line)
                if value.get('id') == 'commands':
                    response = value
                    break
        assert response and response.get('success'), response
        assert 'literature' in {x['name'] for x in response['data']['commands']}, response
        send({'id': 'runtime', 'type': 'prompt', 'message': '/__literature_test'})
        deadline = time.monotonic() + 90
        result_path = project / 'native-result.json'
        while time.monotonic() < deadline and not result_path.exists():
            readable, _, _ = select.select([process.stdout], [], [], 0.25)
            if readable and not process.stdout.readline():
                break
        assert result_path.exists(), 'Native Literature handlers did not finish'
        results = json.loads(result_path.read_text())
        for name, result in results.items():
            assert not result.get('isError'), (name, result)
            assert result['details']['personalPiLiterature']['cwd'] == str(project)
        assert results['plan']['details']['personalPiLiterature']['kind'] == 'plan'
        assert len(results['saved']['details']['personalPiLiterature']['result']['saved']) == 1
        draft_path = Path(results['draft']['details']['personalPiLiterature']['result']['path'])
        assert '/drafts/' in str(draft_path) and 'status: draft' in draft_path.read_text()
        print('Native Pi Literature plan/save/draft tools passed; no model calls')
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
        diagnostics = process.stderr.read()
        assert 'Failed to load extension' not in diagnostics, diagnostics
