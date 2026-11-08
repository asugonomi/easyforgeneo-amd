import importlib.util
from pathlib import Path
import unittest
import tempfile

spec = importlib.util.spec_from_file_location('runtime', Path(__file__).parents[1]/'scripts/runtime.py')
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class DeviceSelectionTests(unittest.TestCase):
    def test_extension_activation_and_safe_mode_keep_installers_disabled(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.assertIn('--disable-extra-extensions', runtime.launch_command(root, 7865))
            (root / 'extensions-complete.json').write_text('{}')
            self.assertNotIn('--disable-extra-extensions', runtime.launch_command(root, 7865))
            command = runtime.launch_command(root, 7865, safe_mode=True)
            self.assertIn('--disable-extra-extensions', command)
            self.assertIn('--skip-install', command)
            self.assertIn('--skip-prepare-environment', command)

    def test_windows_and_hip_name_normalization(self):
        gpu = dict(index=1, name='AMD Radeon RX 7900 XTX', arch='gfx1100')
        self.assertEqual(runtime.choose_device([gpu], dict(gpuName='Radeon (TM) RX 7900 XTX', arch='gfx1100')), gpu)

    def test_wrong_arch_rejected(self):
        with self.assertRaises(RuntimeError):
            runtime.choose_device([dict(index=0, name='AMD Radeon RX 7900 XTX', arch='gfx1200')],
                                  dict(gpuName='AMD Radeon RX 7900 XTX', arch='gfx1100'))

    def test_ambiguous_devices_rejected(self):
        gpu = dict(index=0, name='AMD Radeon RX 9070 XT', arch='gfx1201')
        with self.assertRaises(RuntimeError):
            runtime.choose_device([gpu, dict(gpu, index=1)], dict(gpuName=gpu['name'], arch='gfx1201'))

    def test_nvidia_not_selected(self):
        with self.assertRaises(RuntimeError):
            runtime.choose_device([dict(index=0,name='NVIDIA GeForce RTX 4070',arch='')],
                                  dict(gpuName='AMD Radeon RX 9070 XT',arch='gfx1201'))


if __name__ == '__main__':
    unittest.main()
