import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location('capture_profile', Path(__file__).with_name('capture-simulator-profile.py'))
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


class SimulatorProfileCaptureChecks(unittest.TestCase):
    simulator = '00000000-0000-0000-0000-000000000001'
    image_uuid = '00000000-0000-0000-0000-000000000002'
    bundle = 'example.synthetic.memora'

    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix='memora-capture-check-')
        self.addCleanup(self.folder.cleanup)
        self.app = Path(self.folder.name) / 'Memora.app'
        self.app.mkdir()
        (self.app / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': self.bundle, 'CFBundleExecutable': 'Memora'}))
        self.output = Path(self.folder.name) / 'capture'
        self.device = {'udid': self.simulator, 'state': 'Booted', 'isAvailable': True, 'name': 'Synthetic iPhone'}
        self.jobs = f'123\t0\tUIKitApplication:{self.bundle}[synthetic]\n'
        self.installed_uuid = self.image_uuid
        self.installed_debug_uuid = self.image_uuid
        self.commands = []
        self.export_error = None

    def command(self, args, timeout=60):
        self.commands.append(args)
        if args[:4] == ['xcrun', 'simctl', 'list', 'devices']:
            return json.dumps({'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-27-0': [self.device]}})
        if args[:3] == ['xcrun', 'simctl', 'spawn']:
            return self.jobs
        if args[:3] == ['xcrun', 'simctl', 'get_app_container']:
            return str(Path(self.folder.name) / 'Installed.app')
        if args[:3] == ['xcrun', 'dwarfdump', '--uuid']:
            image_uuid = self.image_uuid if str(self.app) in args[-1] else self.installed_uuid
            if args[-1].endswith('.debug.dylib') and str(self.app) not in args[-1]:
                image_uuid = self.installed_debug_uuid
            return f'UUID: {image_uuid} (arm64) {args[-1]}'
        if args[:3] == ['xcrun', 'xctrace', 'export']:
            if self.export_error:
                raise self.export_error
            Path(args[-1]).write_text('<trace-query-result/>')
            return ''
        raise AssertionError(f'Unexpected command: {args}')

    def invoke(self, recorder=None):
        argv = ['capture', '--simulator', self.simulator, '--app', str(self.app),
                '--configuration', 'Release', '--output-dir', str(self.output), '--seconds', '5']
        with patch('sys.argv', argv), patch.object(capture, 'command', side_effect=self.command), \
             patch.object(capture.subprocess, 'run') as run, \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            run.return_value = subprocess.CompletedProcess([], 2, 'Recording failed\n', 'Unsupported instrument\n')
            if recorder:
                run.side_effect = recorder
            try:
                capture.main()
            finally:
                self.record_calls = run.call_args_list

    def assert_no_capture(self):
        self.assertEqual(self.record_calls, [])
        self.assertFalse(any(args[:3] == ['xcrun', 'xctrace', 'export'] for args in self.commands))

    def test_unavailable_or_wrong_simulator_does_not_attach(self):
        for key, value in [('state', 'Shutdown'), ('isAvailable', False),
                           ('udid', '00000000-0000-0000-0000-000000000003')]:
            original = self.device[key]
            with self.subTest(key=key):
                self.device[key] = value
                with self.assertRaises(SystemExit): self.invoke()
                self.assert_no_capture()
            self.device[key] = original

    def test_absent_ambiguous_or_stopped_app_does_not_attach(self):
        for jobs in ['', self.jobs + self.jobs, self.jobs.replace('123\t', '0\t'),
                     self.jobs.replace(self.bundle, self.bundle + '.other')]:
            with self.subTest(jobs=jobs):
                self.jobs = jobs
                with self.assertRaises(SystemExit): self.invoke()
                self.assert_no_capture()

    def test_installed_build_mismatch_does_not_attach(self):
        self.installed_uuid = '00000000-0000-0000-0000-000000000004'
        with self.assertRaises(SystemExit): self.invoke()
        self.assert_no_capture()
        self.assertFalse(self.output.exists())

    def test_missing_debug_code_image_does_not_attach(self):
        (self.app / 'Memora.debug.dylib').write_bytes(b'synthetic')
        with self.assertRaises(SystemExit): self.invoke()
        self.assert_no_capture()
        self.assertFalse(self.output.exists())

    def test_mismatched_debug_code_with_identical_launcher_does_not_attach(self):
        (self.app / 'Memora.debug.dylib').write_bytes(b'synthetic')
        installed = Path(self.folder.name) / 'Installed.app'
        installed.mkdir()
        (installed / 'Memora.debug.dylib').write_bytes(b'synthetic-other-build')
        self.installed_debug_uuid = '00000000-0000-0000-0000-000000000006'
        with self.assertRaises(SystemExit): self.invoke()
        self.assert_no_capture()
        self.assertFalse(self.output.exists())

    def test_repository_and_existing_outputs_are_preserved(self):
        self.output = Path(__file__).resolve().parents[2] / 'capture-must-not-be-created'
        with self.assertRaises(SystemExit): self.invoke()
        self.assert_no_capture()
        self.assertFalse(self.output.exists())
        self.output = Path(self.folder.name) / 'existing'
        self.output.mkdir()
        marker = self.output / 'keep.txt'
        marker.write_text('keep')
        with self.assertRaises(FileExistsError): self.invoke()
        self.assert_no_capture()
        self.assertEqual(marker.read_text(), 'keep')

    def test_record_failure_preserves_log_without_export_or_summary(self):
        with self.assertRaises(ValueError): self.invoke()
        record = self.record_calls[0].args[0]
        self.assertEqual(record[record.index('--device') + 1], self.simulator)
        self.assertEqual(record[record.index('--attach') + 1], '123')
        self.assertNotIn('--all-processes', record)
        self.assertNotIn('--launch', record)
        self.assertIn('Unsupported instrument', (self.output / 'record.log').read_text())
        self.assertFalse((self.output / 'summary.json').exists())
        self.assertFalse(any(args[:3] == ['xcrun', 'xctrace', 'export'] for args in self.commands))

    def test_record_timeout_preserves_partial_log_without_retry(self):
        def timeout(*args, **kwargs):
            raise subprocess.TimeoutExpired(args[0], kwargs['timeout'], output=b'partial stdout\n', stderr=b'partial stderr\n')
        with self.assertRaises(subprocess.TimeoutExpired): self.invoke(timeout)
        self.assertEqual(len(self.record_calls), 1)
        self.assertEqual((self.output / 'record.log').read_text(), 'partial stdout\npartial stderr\n')
        self.assertFalse((self.output / 'summary.json').exists())

    def test_successful_record_with_failed_or_empty_export_is_not_measurement(self):
        def success(*args, **kwargs):
            return subprocess.CompletedProcess(args[0], 0, 'Recording completed', '')
        self.export_error = subprocess.CalledProcessError(10, ['synthetic export'])
        with self.assertRaises(subprocess.CalledProcessError): self.invoke(success)
        self.assertFalse((self.output / 'summary.json').exists())
        self.output = Path(self.folder.name) / 'empty-export'
        self.export_error = None
        with self.assertRaises(ValueError): self.invoke(success)
        self.assertFalse((self.output / 'summary.json').exists())


if __name__ == '__main__':
    unittest.main()
