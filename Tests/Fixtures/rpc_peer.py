"""Offline RPC peer. Never loads Pi configuration, credentials or providers."""
import json
import os
import sys
import time

for line in sys.stdin:
    request = json.loads(line)
    kind = request['type']
    if kind == 'get_state':
        if os.path.basename(os.getcwd()) == 'slow':
            time.sleep(0.35)
        result = {'sessionId': 'fixture', 'isStreaming': False}
    elif kind == 'get_commands':
        result = {'commands': []}
    elif kind == 'get_messages' and os.path.basename(os.getcwd()) == 'exit':
        sys.exit(7)
    else:
        continue  # Intentionally exercise client timeout/cancellation.
    response = json.dumps({'type': 'response', 'id': request['id'], 'success': True, 'data': result})
    sys.stdout.write(response[:12])
    sys.stdout.flush()
    time.sleep(0.005)
    sys.stdout.write(response[12:] + '\n')
    sys.stdout.flush()
    if os.path.basename(os.getcwd()) == 'blocked':
        time.sleep(10)
