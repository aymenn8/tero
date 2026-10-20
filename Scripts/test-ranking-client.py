from pathlib import Path
import tempfile,subprocess
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='tero-ranking-client-') as folder:
    temp=Path(folder);sources=[]
    for index,path in enumerate(sorted((root/'Sources/Core').glob('*.swift'))+[root/'Sources/AI/RankingClient.swift',root/'Scripts/RankingClientSmoke.swift']):
        target=temp/f'{index}-{path.name}';target.write_text(path.read_text());sources.append(str(target))
    binary=temp/'ranking-client'
    subprocess.run(['swiftc','-module-cache-path',str(temp/'modules'),'-swift-version','6','-parse-as-library',*sources,'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=15)
