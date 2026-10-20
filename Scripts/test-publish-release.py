import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('publish', Path(__file__).with_name('publish-release.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_appcast_rejects_wrong_build_or_download_before_publication(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            (folder/'Tero.dmg').write_bytes(b'fixture')
            (folder/'CHANGELOG.md').write_text('- Fixture')
            tools = folder/'tools'
            expected = release.plistlib.loads((release.ROOT/'Configuration/Info.plist').read_bytes())['SUPublicEDKey']
            def fake(args):
                if str(args[0]).endswith('generate_keys'):
                    return expected
                (folder/'updates/appcast.xml').write_text('<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>999</sparkle:version><enclosure url="https://wrong.test/update.dmg" length="7" sparkle:edSignature="fixture"/></item></channel></rss>')
                return ''
            with patch.object(release,'run',side_effect=fake) as command:
                with self.assertRaises(RuntimeError):
                    release.prepare_appcast({'repository':'owner/assets','sparkle_account':'fixture','website':'https://example.test'}, {'version':'0.0.1','build':1},folder,tools)
                self.assertEqual(command.call_count,2)

    def test_sparkle_private_key_must_match_embedded_public_key(self):
        with tempfile.TemporaryDirectory() as folder:
            with patch.object(release,'run',return_value='wrong public key') as command:
                with self.assertRaises(RuntimeError):
                    release.prepare_appcast({'sparkle_account':'fixture'}, {}, Path(folder), Path(folder))
                self.assertEqual(command.call_count,1)

    def test_versions(self):
        self.assertEqual(release.next_version(None, '0.0.1'), '0.0.1')
        self.assertEqual(release.next_version('v0.0.9', '0.0.1'), '0.0.10')
        with self.assertRaises(RuntimeError):
            release.next_version('unexpected', '0.0.1')

    def test_notarization_resumes_existing_job_without_resubmitting(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            artifact = folder / 'Tero.dmg'
            artifact.write_bytes(b'signed fixture')
            state = {'notary': {'id': 'existing-job', 'sha256': release.sha(artifact)}}
            responses = [{'status': 'In Progress'}, {'status': 'Accepted'}, {'issues': []}]
            calls = []
            def fake(args):
                calls.append(args)
                return responses.pop(0)
            with patch.object(release, 'json_run', side_effect=fake), patch.object(release.time, 'sleep'):
                release.wait_for_apple(state, folder / 'state.json', artifact, 'fixture')
            self.assertTrue(state['notary']['accepted'])
            self.assertFalse(any('submit' in args for args in calls))
            self.assertEqual(json.loads((folder / 'state.json').read_text())['notary']['id'], 'existing-job')

    def test_approval_cannot_be_reused_for_modified_artifact(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            artifact = folder / 'Tero.dmg'
            artifact.write_bytes(b'changed fixture')
            state = {'notary': {'id': 'existing-job', 'sha256': 'wrong'}}
            with patch.object(release, 'json_run') as provider:
                with self.assertRaises(RuntimeError):
                    release.wait_for_apple(state, folder / 'state.json', artifact, 'fixture')
                provider.assert_not_called()

    def test_rejection_never_approves_or_publishes(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            artifact = folder / 'Tero.dmg'
            artifact.write_bytes(b'fixture')
            state = {'notary': {'id': 'existing-job', 'sha256': release.sha(artifact)}}
            with patch.object(release, 'json_run', return_value={'status': 'Invalid'}), patch.object(release, 'run'):
                with self.assertRaises(RuntimeError):
                    release.wait_for_apple(state, folder / 'state.json', artifact, 'fixture')
            self.assertFalse(state['notary'].get('accepted'))

    def test_apple_job_is_saved_before_wait(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            artifact = folder / 'Tero.dmg'
            artifact.write_bytes(b'fixture')
            state = {}
            with patch.object(release, 'json_run', side_effect=[{'id': 'new-job'}, KeyboardInterrupt()]):
                with self.assertRaises(KeyboardInterrupt):
                    release.wait_for_apple(state, folder / 'state.json', artifact, 'fixture')
            self.assertEqual(json.loads((folder / 'state.json').read_text())['notary']['id'], 'new-job')

    def test_publish_happens_after_all_uploads(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'state.json'
            state = {'version':'0.0.1','commit':'a'*40,'final_sha256':'b'*64}
            commands = []
            with patch.object(release, 'release_view', return_value=None), patch.object(release, 'run', side_effect=lambda args:commands.append(args) or ''):
                release.upload_and_publish({'repository':'owner/assets'}, state, path, ['Tero.dmg','release.json'])
            self.assertIn('--draft', commands[0])
            self.assertEqual(commands[1][1:3], ['release','upload'])
            self.assertIn('--draft=false', commands[2])
            self.assertTrue(state['published'])

    def test_failed_upload_never_publishes(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'state.json'
            state = {'version':'0.0.1','commit':'a'*40,'final_sha256':'b'*64}
            with patch.object(release, 'release_view', return_value={'draft':True}), patch.object(release, 'run', side_effect=RuntimeError('upload interrupted')) as command:
                with self.assertRaises(RuntimeError):
                    release.upload_and_publish({'repository':'owner/assets'}, state, path, ['Tero.dmg'])
            self.assertEqual(command.call_count, 1)
            self.assertFalse(state.get('published'))

    def test_existing_public_version_is_immutable(self):
        with tempfile.TemporaryDirectory() as folder:
            state = {'version':'0.0.1','commit':'a'*40,'final_sha256':'b'*64}
            public = {'draft':False,'assets':[{'name':'release.json','url':'https://api.github.com/fixture'}]}
            with patch.object(release, 'release_view', return_value=public), patch.object(release, 'json_run', return_value={'commit':'another','sha256':'b'*64}), patch.object(release, 'run') as mutate:
                with self.assertRaises(RuntimeError):
                    release.upload_and_publish({'repository':'owner/assets'}, state, Path(folder)/'state.json', [])
                mutate.assert_not_called()


if __name__ == '__main__':
    unittest.main()
