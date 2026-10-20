#!/usr/bin/env python3
"""Compile the bring-your-own-key engine with a synthetic provider and run its checks.
No network beyond localhost, no real keys, no user content."""
from pathlib import Path
import json, socket, subprocess, sys, tempfile, time

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='tero-byok-') as folder:
    temp = Path(folder)
    sources = sorted((root / 'Sources/Core').glob('*.swift')) + [root / 'Sources/AI' / name for name in
        ['AIProvider.swift', 'AIGatewaySupport.swift', 'AIProviderClient.swift', 'LocalGateway.swift', 'CorrectionClient.swift']]
    sources = [p for p in sources if not p.stem.endswith(' 2')] + [root / 'Scripts/BYOKSmoke.swift']
    binary = temp / 'byok-smoke'
    subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library', '-module-name', 'BYOKSmoke',
                    '-module-cache-path', str(temp / 'cache'), '-o', str(binary), *map(str, sources)], check=True)
    # Command-line tools look up bundle resources next to the executable.
    (temp / 'Prompts.json').write_text((root / 'Resources/AI/Prompts.json').read_text())
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0)); port = probe.getsockname()[1]
    log = temp / 'requests.jsonl'
    server = subprocess.Popen([sys.executable, str(root / 'Scripts/byok_mock_provider.py'), str(port), str(log)])
    try:
        time.sleep(0.6)
        result = subprocess.run([str(binary), str(port)], timeout=120)
        requests = [json.loads(line) for line in log.read_text().splitlines()]
        bodies = [r['body'] for r in requests]
        # Shape checks: keys reach the right header, prompts are rendered, nothing is left as a placeholder.
        assert all('{{' not in json.dumps(b) for b in bodies), 'unrendered prompt placeholder'
        assert any(r['path'].endswith('/messages') and r['auth'] == 'sk-test' for r in requests), 'anthropic key header'
        assert any(r['path'].endswith('/responses') and r['auth'] == 'Bearer sk-test' for r in requests), 'openai bearer'
        assert any(b.get('response_format', {}).get('type') == 'json_object' for b in bodies), 'json mode fallback used'
        pdf_text = [b for b in bodies if 'Attached PDF' in json.dumps(b)]
        pdf_file = [b for b in bodies if 'input_file' in json.dumps(b)]
        assert pdf_text and 'Orion invoice' in json.dumps(pdf_text[0]), 'PDF text fallback'
        assert pdf_file, 'native PDF input for OpenAI'
        print(f'Request shapes OK ({len(requests)} synthetic provider calls)')
        sys.exit(result.returncode)
    finally:
        server.terminate()
