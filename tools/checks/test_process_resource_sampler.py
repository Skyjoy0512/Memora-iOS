"""Validate host-only sampling, including Mach ticks versus ps CPU seconds."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ProcessResourceSamplerChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix='memora-process-check-', dir=os.environ.get('MEMORA_CHECK_TMPDIR'))
        cls.binary = str(Path(cls.scratch.name) / 'sample')
        subprocess.run(['swiftc', str(ROOT / 'tools/sample-process-resources.swift'), '-o', cls.binary], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def test_self_sample_has_explicit_host_scope_and_units(self):
        value = json.loads(subprocess.check_output([self.binary, 'self'], text=True))
        self.assertIn('not iPhone', value['scope'])
        self.assertGreater(value['residentBytes'], 0)
        self.assertGreater(value['timebaseNumerator'], 0)
        self.assertGreater(value['timebaseDenominator'], 0)
        for kind in ['user', 'system']:
            expected = value[kind + 'CpuAbsoluteTicks'] * value['timebaseNumerator'] / value['timebaseDenominator'] / 1e9
            self.assertAlmostEqual(value[kind + 'CpuSeconds'], expected)

    def test_cpu_unit_conversion_agrees_with_independent_ps(self):
        # Own child only; the sampler never signals or modifies another app.
        child = subprocess.Popen([sys.executable, '-c',
            'import sys\nfor _ in range(50): sum(range(1000000))\nprint("ready", flush=True)\nsys.stdin.read()'],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(child.stdout.readline().strip(), 'ready')
            value = json.loads(subprocess.check_output([self.binary, str(child.pid)], text=True))
            raw = subprocess.check_output(['/bin/ps', '-p', str(child.pid), '-o', 'time='], text=True).strip()
            minutes, seconds = map(float, raw.split(':'))
            native = minutes * 60 + seconds
            self.assertGreater(native, 0.05)
            self.assertLess(abs(value['userCpuSeconds'] + value['systemCpuSeconds'] - native), 0.05)
        finally:
            child.communicate(input='done', timeout=5)

    def test_invalid_targets_fail_without_sample_output(self):
        for target in ['0', '-1', 'not-a-pid', '2147483647']:
            result = subprocess.run([self.binary, target], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '')


if __name__ == '__main__':
    unittest.main()
