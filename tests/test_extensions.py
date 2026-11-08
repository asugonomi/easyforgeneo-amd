import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

PACKAGE = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location('extension_setup', PACKAGE / 'scripts/extensions.py')
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class ExtensionTests(unittest.TestCase):
    def test_catalog_is_pinned_and_matches_upstream_count(self):
        catalog = setup.read_json(PACKAGE / 'extensions.json')
        setup.validate_catalog(catalog)
        self.assertEqual(len(catalog['extensions']), 14)
        for name in ('../escape', 'bad/name', 'good;evil'):
            with self.assertRaises(ValueError):
                setup.validate_catalog({'extensions': [dict(catalog['extensions'][0], name=name)]})

    def test_preserves_preferences_and_disabled_extensions(self):
        config = {'theme': 'Dark', 'disabled_extensions': ['mine']}
        setup.add_default_disabled(config)
        setup.add_default_disabled(config)
        self.assertEqual(config, {'theme': 'Dark', 'disabled_extensions': ['mine', 'model-keyword']})

    def test_rocm_local_version_stays_pinned(self):
        self.assertEqual(setup.freeze_constraints([{'name': 'torch', 'version': '2.14.0+rocm10.1.0'}]),
                         'torch==2.14.0+rocm10.1.0\n')

    def test_entry_points_have_real_powershell_path(self):
        for path in PACKAGE.glob('*.bat'):
            data = path.read_bytes()
            self.assertIn(b'WindowsPowerShell\\v1.0\\powershell.exe', data, path.name)
            self.assertFalse(any(byte < 32 and byte not in (9, 10, 13) for byte in data), path.name)

    def test_failed_dependencies_do_not_activate_and_retry_succeeds(self):
        with tempfile.TemporaryDirectory() as tmp:
            parent = Path(tmp)
            root = parent / 'runtime'
            (root / 'forge-neo').mkdir(parents=True)
            (root / 'temp').mkdir()
            ext = dict(name='example', url='https://github.com/example/example.git', commit='a'*40)
            (parent / 'extensions.json').write_text(json.dumps({'extensions': [ext]}))
            config = root / 'forge-neo/config.json'
            config.write_text('{"theme":"Dark"}')
            fail = True

            def fake_run(args, capture=False):
                args = list(map(str, args))
                if args[:2] == ['git', 'init']:
                    Path(args[2]).mkdir()
                if 'rev-parse' in args:
                    return ext['commit']
                if 'diff' in args:
                    return ''
                if '--format=json' in args:
                    return '[{"name":"torch","version":"2.14.0+rocm10.1.0"}]'
                if '--dry-run' in args and fail:
                    raise subprocess.CalledProcessError(1, args)

            with patch.dict(os.environ, {'GIT_PYTHON_GIT_EXECUTABLE':'git'}), patch.object(setup, 'run', fake_run):
                with self.assertRaises(subprocess.CalledProcessError):
                    setup.install(root)
                self.assertFalse((root / 'extensions-complete.json').exists())
                self.assertFalse((root / 'forge-neo/extensions/example').exists())
                self.assertEqual(json.loads(config.read_text()), {'theme':'Dark'})
                fail = False
                setup.install(root)
                self.assertTrue((root / 'extensions-complete.json').exists())
                setup.install(root)  # completed install is idempotent
                self.assertEqual(json.loads(config.read_text())['theme'], 'Dark')

    def test_unmanaged_existing_extension_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            parent = Path(tmp)
            root = parent / 'runtime'
            target = root / 'forge-neo/extensions/example'
            target.mkdir(parents=True)
            (target / 'keep.txt').write_text('keep')
            (parent / 'extensions.json').write_text(json.dumps({'extensions': [
                dict(name='example', url='https://github.com/example/example.git', commit='a'*40)]}))
            with patch.dict(os.environ, {'GIT_PYTHON_GIT_EXECUTABLE':'git'}), patch.object(setup, 'run') as run:
                with self.assertRaises(RuntimeError):
                    setup.install(root)
                run.assert_not_called()
            self.assertEqual((target / 'keep.txt').read_text(), 'keep')


if __name__ == '__main__':
    unittest.main()
