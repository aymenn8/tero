"""Real AX capture from a disposable synthetic app, using signed Tero Dev.
Stop normal Tero first. No user apps, clipboard content or provider calls are used.
"""
from pathlib import Path
import json
import os
import plistlib
import signal
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[1]
tero = Path('/tmp/tero-p0-build/Build/Products/Development/Tero Dev.app')
with tempfile.TemporaryDirectory(prefix='tero-selection-') as directory:
    temp = Path(directory)
    bundle = temp / 'Selection fixture.app'
    contents = bundle / 'Contents'
    binary = contents / 'MacOS' / 'SelectionFixture'
    binary.parent.mkdir(parents=True)
    (contents / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'com.tero.selection-fixture',
        'CFBundleExecutable': 'SelectionFixture', 'CFBundleName': 'Selection fixture',
        'CFBundlePackageType': 'APPL', 'NSPrincipalClass': 'NSApplication',
    }))
    subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library',
                    '-module-cache-path', str(temp / 'cache'),
                    str(root / 'Scripts/SelectionCaptureFixture.swift'), '-o', str(binary)], check=True)
    subprocess.run(['codesign', '--sign', '-', str(bundle)], check=True, capture_output=True)
    scenarios = ['slow-editable', 'slow-reading', 'transient', 'empty', 'secure', 'unsupported', 'split-focus', 'web-reading', 'range-reading', 'prewarmed-editable']
    requested = sys.argv[1:] or scenarios
    if any(scenario not in scenarios for scenario in requested):
        raise ValueError('Unknown selection fixture scenario')
    for scenario in requested:
        ready = temp / (scenario + '.ready')
        with (temp / (scenario + '.log')).open('w') as log:
            host_pid = None
            subprocess.run(['open', '-n', str(bundle), '--args', scenario, str(ready)], check=True,
                           stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 8
                while not ready.exists() and time.monotonic() < deadline:
                    time.sleep(.05)
                if not ready.exists():
                    raise RuntimeError('Synthetic host did not become ready: ' + scenario)
                state = json.loads(ready.read_text())
                host_pid = state['pid']
                if not state['active'] or not state['key']:
                    raise RuntimeError('Synthetic host did not acquire focus: ' + scenario)
                output = temp / (scenario + '.result')
                errors = temp / (scenario + '.errors')
                # LaunchServices attributes AX access to the signed bundle, like normal Tero.
                result = subprocess.run(['open', '-n', '-W', '-g', '--stdout', str(output),
                                         '--stderr', str(errors), str(tero), '--args',
                                         '--test-selection-fixture', str(host_pid), scenario],
                                        capture_output=True, text=True, timeout=20)
                report = output.read_text() if output.exists() else ''
                print(report.strip(), flush=True)
                if result.returncode or 'PASS: selection fixture ' + scenario not in report:
                    raise RuntimeError('Capture fixture failed: ' + scenario + '\n' + ready.read_text() + '\n' + result.stderr)
            finally:
                if host_pid is not None:
                    try:
                        os.kill(host_pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
