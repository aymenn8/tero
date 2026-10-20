#!/usr/bin/env python3
"""One local release: immutable source snapshot → signed DMG → Apple → GitHub.
No provider/user data or credentials are collected. Secrets stay in Keychain.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import plistlib
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def run(args, *, cwd=ROOT, capture=True):
    result = subprocess.run([str(x) for x in args], cwd=cwd, text=True,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None)
    if result.returncode:
        # Never print subprocess environment or credentials.
        raise RuntimeError(f'{args[0]} failed: {(result.stderr or "see command output").strip()}')
    return result.stdout or ''


def json_run(args):
    return json.loads(run(args))


def save(path, value):
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(value, indent=2) + '\n')
    temp.replace(path)


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def next_version(latest, initial):
    if latest is None:
        return initial
    match = re.fullmatch(r'v?(\d+)\.(\d+)\.(\d+)', latest)
    if not match:
        raise RuntimeError('Latest release tag is not a supported version.')
    major, minor, patch = map(int, match.groups())
    return f'{major}.{minor}.{patch + 1}'


def release_view(repo, tag):
    # Only a real 404 means absent; outages/auth failures must never create a duplicate.
    result = subprocess.run(['gh', 'api', f'repos/{repo}/releases/tags/{tag}'],
                            text=True, capture_output=True)
    if result.returncode == 0:
        return json.loads(result.stdout)
    if 'HTTP 404' in result.stderr:
        return None
    raise RuntimeError('Cannot inspect GitHub release: ' + result.stderr.strip())


def wait_for_apple(state, path, artifact, profile, poll=30, timeout=7200):
    job = state.setdefault('notary', {})
    digest = sha(artifact)
    if job.get('sha256') and job['sha256'] != digest:
        raise RuntimeError('DMG changed after submission; refusing to reuse Apple approval.')
    if not job.get('id'):
        print('Sending signed DMG to Apple…', flush=True)
        submission = json_run(['xcrun', 'notarytool', 'submit', artifact,
                               '--keychain-profile', profile, '--output-format', 'json'])
        job.update(id=submission['id'], sha256=digest)
        save(path, state)  # Persist before waiting: interrupted runs resume this exact job.
    deadline = time.monotonic() + timeout
    while True:
        info = json_run(['xcrun', 'notarytool', 'info', job['id'],
                         '--keychain-profile', profile, '--output-format', 'json'])
        status = info['status']
        if status == 'Accepted':
            log = json_run(['xcrun', 'notarytool', 'log', job['id'],
                            '--keychain-profile', profile])
            save(path.parent / 'notary-log.json', log)
            job['accepted'] = True
            save(path, state)
            return
        if status != 'In Progress':
            run(['xcrun', 'notarytool', 'log', job['id'], '--keychain-profile', profile,
                 path.parent / 'notary-log.json'])
            raise RuntimeError('Apple rejected the release. See notary-log.json; nothing was published.')
        if time.monotonic() >= deadline:
            raise RuntimeError('Apple is still processing. Run the same command to resume; no resubmission.')
        print('Apple is processing the release…', flush=True)
        time.sleep(poll)


def upload_and_publish(config, state, path, artifacts):
    repo, tag = config['repository'], 'v' + state['version']
    release = release_view(repo, tag)
    if release and not release['draft']:
        # Never overwrite an already published artifact/version.
        manifest_asset = next((a for a in release['assets'] if a['name'] == 'release.json'), None)
        if not manifest_asset:
            raise RuntimeError('Published version exists without the expected manifest; refusing overwrite.')
        manifest = json_run(['gh', 'api', manifest_asset['url'], '-H', 'Accept: application/octet-stream'])
        if manifest.get('commit') != state['commit'] or manifest.get('sha256') != state['final_sha256']:
            raise RuntimeError('Published version belongs to another build; refusing overwrite.')
        state['published'] = True
        save(path, state)
        return
    if not release:
        run(['gh', 'release', 'create', tag, '--repo', repo, '--draft',
             '--title', 'Tero ' + state['version'], '--notes-file', path.parent / 'CHANGELOG.md'])
    # Draft uploads may safely resume. Nothing becomes public until every asset is present.
    run(['gh', 'release', 'upload', tag, *artifacts, '--repo', repo, '--clobber'])
    run(['gh', 'release', 'edit', tag, '--repo', repo, '--draft=false', '--latest',
         '--notes-file', path.parent / 'CHANGELOG.md'])
    state['published'] = True
    save(path, state)


def prepare_appcast(config, state, output, tools):
    """Use Sparkle's official generator; never hand-edit a signed feed."""
    account = config['sparkle_account']
    public_key = run([tools / 'generate_keys', '--account', account, '-p']).strip()
    expected = plistlib.loads((ROOT / 'Configuration/Info.plist').read_bytes())['SUPublicEDKey']
    if public_key != expected:
        raise RuntimeError('Sparkle signing key does not match the public key embedded in Tero.')
    prefix = f'https://github.com/{config["repository"]}/releases/download/v{state["version"]}/'
    updates = output / 'updates'
    updates.mkdir(exist_ok=True)
    shutil.copyfile(output / 'Tero.dmg', updates / 'Tero.dmg')
    shutil.copyfile(output / 'CHANGELOG.md', updates / 'Tero.md')
    run([tools / 'generate_appcast', '--account', account,
         '--download-url-prefix', prefix, '--link', config['website'],
         '--embed-release-notes', '--maximum-deltas', '0', '--maximum-versions', '1', updates])
    appcast = updates / 'appcast.xml'
    tree = ET.parse(appcast)
    item = tree.find('./channel/item')
    namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    enclosure = item.find('enclosure') if item is not None else None
    if (item is None or enclosure is None
        or item.findtext(namespace + 'version') != str(state['build'])
        or enclosure.get('url') != prefix + 'Tero.dmg'
        or int(enclosure.get('length', '0')) != (output / 'Tero.dmg').stat().st_size
        or not enclosure.get(namespace + 'edSignature')):
        raise RuntimeError('Generated Sparkle feed does not match this notarized release.')
    run([tools / 'sign_update', '--account', account, '--verify', output / 'Tero.dmg',
         enclosure.get(namespace + 'edSignature')])
    run([tools / 'sign_update', '--account', account, '--verify', appcast])
    return appcast


def build_installer(app, output, snapshot, workspace):
    # Packaging tools stay outside the app and are set up automatically once.
    environment = workspace / 'packaging-tools'
    python = environment / 'bin/python'
    requirements = snapshot / 'Scripts/release-requirements.txt'
    fingerprint = environment / 'requirements.sha256'
    if not python.exists():
        run([sys.executable, '-m', 'venv', environment])
    expected = sha(requirements)
    if not fingerprint.exists() or fingerprint.read_text() != expected:
        run([python, '-m', 'pip', 'install', '--disable-pip-version-check', '-r', requirements])
        fingerprint.write_text(expected)
    run([python, snapshot / 'Scripts/create-installer-dmg.py', '--app', app,
         '--output', output / 'Tero.dmg', '--root', snapshot])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', help='Optional explicit version; otherwise patch increments automatically.')
    parser.add_argument('--check', action='store_true', help='Check prerequisites; never build or publish.')
    parser.add_argument('--config', type=Path, default=ROOT / 'Configuration/release.json')
    args = parser.parse_args()
    config = json.loads(args.config.read_text())
    origin = urllib.parse.urlparse(config['website'])
    if origin.scheme != 'https' or not origin.hostname or origin.username or origin.password or origin.path not in ('', '/') or origin.query or origin.fragment:
        raise RuntimeError('Release website must be a public HTTPS origin.')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', config['repository']):
        raise RuntimeError('Invalid release repository.')
    if not config['developer_id'].startswith('Developer ID Application:'):
        raise RuntimeError('Distribution requires Developer ID Application signing.')
    for tool in ['git', 'gh', 'xcodebuild', 'xcrun', 'codesign', 'hdiutil', 'ditto']:
        if not shutil.which(tool):
            raise RuntimeError('Missing release tool: ' + tool)
    identities = run(['security', 'find-identity', '-v', '-p', 'codesigning'])
    if config['developer_id'] not in identities:
        raise RuntimeError('Install the configured Developer ID Application certificate in Keychain.')
    run(['gh', 'auth', 'status'])
    run(['xcrun', 'notarytool', 'history', '--keychain-profile', config['notary_profile'],
         '--output-format', 'json'])
    if args.check:
        print('Apple signing, notarization and GitHub credentials are ready.')
        return
    if run(['git', 'diff', '--name-only', 'HEAD']).strip():
        raise RuntimeError('Commit tracked changes before releasing; releases use an immutable committed snapshot.')
    # Keep source/builds outside cloud-managed Documents to avoid Finder metadata
    # breaking code signatures and stalled filesystem reads during Xcode builds.
    workspace_id = hashlib.sha256(str(ROOT).encode()).hexdigest()[:12]
    folder = Path.home() / 'Library/Application Support/Tero Releases' / workspace_id
    folder.mkdir(parents=True, exist_ok=True)
    with (folder / 'lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('A release is already running on this Mac.')
        pointer = folder / 'active.json'
        state = json.loads(pointer.read_text()) if pointer.exists() else None
        head = run(['git', 'rev-parse', 'HEAD']).strip()
        if state and not state.get('published'):
            if args.version and args.version != state['version']:
                raise RuntimeError('Finish the pending release before choosing another version.')
            if state['repository'] != config['repository']:
                raise RuntimeError('Release repository changed during a pending release.')
            print('Resuming Tero ' + state['version'], flush=True)
        else:
            # Public asset-only repository: no source code is uploaded.
            repo = config['repository']
            result = subprocess.run(['gh', 'api', 'repos/' + repo], text=True, capture_output=True)
            if result.returncode:
                if 'HTTP 404' not in result.stderr:
                    raise RuntimeError('Cannot inspect release repository: ' + result.stderr.strip())
                run(['gh', 'repo', 'create', repo, '--public', '--add-readme',
                     '--description', 'Official Tero for Mac downloads and release notes.'])
            elif json.loads(result.stdout)['private']:
                raise RuntimeError('Download repository must be public; its visibility will not be changed automatically.')
            # Retrieve the real latest endpoint, treating first-release 404 explicitly.
            result = subprocess.run(['gh', 'api', f'repos/{repo}/releases/latest'], text=True, capture_output=True)
            if result.returncode and 'HTTP 404' not in result.stderr:
                raise RuntimeError('Cannot inspect latest release: ' + result.stderr.strip())
            latest = json.loads(result.stdout) if result.returncode == 0 else None
            previous = None
            if latest:
                asset = next((a for a in latest['assets'] if a['name'] == 'release.json'), None)
                if not asset:
                    raise RuntimeError('Latest release is missing release.json.')
                previous = json_run(['gh', 'api', asset['url'], '-H', 'Accept: application/octet-stream'])
                if previous['commit'] == head:
                    print('This commit is already published. Nothing to do.')
                    return
            version = args.version or next_version(latest['tag_name'] if latest else None, config['initial_version'])
            if not re.fullmatch(r'\d+\.\d+\.\d+', version):
                raise RuntimeError('Version must be major.minor.patch.')
            if latest and tuple(map(int, version.split('.'))) <= tuple(map(int, latest['tag_name'].lstrip('v').split('.'))):
                raise RuntimeError('Version must be newer than the published release.')
            if release_view(repo, 'v' + version):
                raise RuntimeError('Version already exists. Refusing to replace it.')
            state = {'version': version, 'build': (previous['build'] + 1) if previous else 1,
                     'commit': head, 'previous_commit': previous['commit'] if previous else None,
                     'repository': repo, 'published': False}
            save(pointer, state)
        output = folder / ('v' + state['version'])
        output.mkdir(exist_ok=True)
        state_path = output / 'state.json'
        if state_path.exists():
            state = json.loads(state_path.read_text())
        save(state_path, state)
        try:
            if not state.get('built'):
                snapshot = output / 'source'
                snapshot.mkdir(exist_ok=True)
                archive = output / 'source.tar'
                run(['git', 'archive', '--format=tar', '--output', archive, state['commit']])
                run(['tar', '-xf', archive, '-C', snapshot])
                code_range = (state['previous_commit'] + '..' if state['previous_commit'] else '') + state['commit']
                subjects = run(['git', 'log', '--no-merges', '--format=%s', code_range]).splitlines()
                prepared = snapshot / 'Docs/Releases' / (state['version'] + '.md')
                notes = prepared.read_text() if prepared.exists() else '# Tero ' + state['version'] + '\n\n' + '\n'.join('- ' + s for s in subjects) + '\n'
                (output / 'CHANGELOG.md').write_text(notes)
                app_archive = output / 'Tero.xcarchive'
                print('Building signed universal Tero…', flush=True)
                with (output / 'build.log').open('w') as log:
                    cmd = ['xcodebuild', '-project', 'Tero.xcodeproj', '-scheme', 'Tero', '-configuration', 'Production',
                           '-destination', 'generic/platform=macOS', '-archivePath', str(app_archive),
                           '-derivedDataPath', str(folder / 'DerivedData'), 'archive',
                           'TERO_WEBSITE_URL=' + config['website'], 'CODE_SIGN_STYLE=Manual',
                           'CODE_SIGN_IDENTITY=' + config['developer_id'], 'DEVELOPMENT_TEAM=' + config['team'],
                           'MARKETING_VERSION=' + state['version'], 'CURRENT_PROJECT_VERSION=' + str(state['build']),
                           'ARCHS=arm64 x86_64', 'ONLY_ACTIVE_ARCH=NO', 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO']
                    if subprocess.run(cmd, cwd=snapshot, stdout=log, stderr=subprocess.STDOUT).returncode:
                        raise RuntimeError('Build failed. See ' + str(output / 'build.log'))
                # Export re-signs Sparkle's nested helper services for Developer ID.
                run(['xcodebuild', '-exportArchive', '-archivePath', app_archive,
                     '-exportPath', output / 'export', '-exportOptionsPlist', snapshot / 'Configuration/ExportOptions.plist'])
                app = output / 'export/Tero.app'
                run(['codesign', '--verify', '--deep', '--strict', app])
                print('Creating branded drag-to-install DMG…', flush=True)
                build_installer(app, output, snapshot, folder)
                dmg = output / 'Tero.dmg'
                run(['codesign', '--sign', config['developer_id'], '--timestamp', dmg])
                state['built'] = True
                state['built_sha256'] = sha(dmg)
                save(state_path, state)
            dmg = output / 'Tero.dmg'
            if state.get('stapling') and not state.get('stapled'):
                try:
                    run(['xcrun', 'stapler', 'validate', dmg])
                    run(['codesign', '--verify', '--strict', dmg])
                    state.update(stapled=True, final_sha256=sha(dmg))
                    save(state_path, state)
                except RuntimeError:
                    pass
            if not state.get('stapled'):
                if sha(dmg) != state['built_sha256']:
                    raise RuntimeError('Signed DMG changed; refusing notarization.')
                wait_for_apple(state, state_path, dmg, config['notary_profile'])
                state['stapling'] = True
                save(state_path, state)
                run(['xcrun', 'stapler', 'staple', dmg])
                run(['xcrun', 'stapler', 'validate', dmg])
                run(['codesign', '--verify', '--strict', dmg])
                state['final_sha256'] = sha(dmg)
                state['stapled'] = True
                save(state_path, state)
            if sha(dmg) != state['final_sha256']:
                raise RuntimeError('Final notarized DMG changed; refusing publication.')
            run(['xcrun', 'stapler', 'validate', dmg])
            manifest = {key: state[key] for key in ['version', 'build', 'commit', 'final_sha256']}
            manifest['sha256'] = manifest.pop('final_sha256')
            manifest['download'] = f'https://github.com/{config["repository"]}/releases/download/v{state["version"]}/Tero.dmg'
            save(output / 'release.json', manifest)
            (output / 'SHA256SUMS.txt').write_text(state['final_sha256'] + '  Tero.dmg\n')
            candidates = list((folder / 'DerivedData').glob('SourcePackages/artifacts/*/*/bin/generate_appcast'))
            if len(candidates) != 1:
                raise RuntimeError('Cannot find pinned Sparkle publishing tools in the release build.')
            appcast = prepare_appcast(config, state, output, candidates[0].parent)
            upload_and_publish(config, state, state_path,
                               [dmg, output / 'release.json', output / 'SHA256SUMS.txt', appcast])
            print('Published Tero ' + state['version'] + '\n' + manifest['download'])
        finally:
            save(pointer, state)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        print('Release stopped: ' + str(error), file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print('\nRelease interrupted. Run the same command to resume.', file=sys.stderr)
        sys.exit(130)
