"""Scoped native Calendar request checks. Synthetic HTTP only; no gateway or Apple writes."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='tero-planning-request-') as directory:
    temporary = Path(directory)
    binary = temporary / 'fixture'
    subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library',
                    '-module-cache-path', str(temporary / 'cache'),
                    str(root / 'Sources/AI/CorrectionClient.swift'),
                    *map(str, sorted((root / 'Sources/Core').glob('*.swift'))),
                    str(root / 'Scripts/PlanningRequestFixture.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
