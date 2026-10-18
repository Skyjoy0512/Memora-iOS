"""Exercise failure boundaries with real temporary Git repos and stub model/build calls."""
import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import run as runner


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir='/Volumes/WorkspaceSSD/Development/Temp')
        self.root = Path(self.temp.name) / 'original'
        self.root.mkdir()
        for args in (['init', '-q'], ['config', 'user.name', 'Test'],
                     ['config', 'user.email', 'test@localhost']):
            subprocess.run(['git', *args], cwd=self.root, check=True)
        (self.root / 'docs').mkdir()
        (self.root / 'docs/base.md').write_text('baseline\n')
        subprocess.run(['git', 'add', '.'], cwd=self.root, check=True)
        subprocess.run(['git', 'commit', '-qm', 'base'], cwd=self.root, check=True)
        self.real_command = runner.command
        self.calls = 0

    def tearDown(self):
        self.temp.cleanup()

    def execute(self, reviews, *, apply=False, outside=False, worker_error=False, build_fail=False):
        def model(prompt, shape, cwd, run, label):
            if label == 'plan':
                return {'tasks': ['Write bounded documentation'], 'acceptance': ['Document exists']}
            return reviews.pop(0)

        def command(args, cwd, log=None, **kwargs):
            if args[0] == runner.WORKER:
                self.assertEqual(kwargs['env']['PWD'], str(cwd))
                config = json.loads(kwargs['env']['OPENCODE_CONFIG_CONTENT'])
                self.assertEqual(config['permission']['edit']['docs/change.md'], 'allow')
                self.assertEqual(config['permission']['*'], 'deny')
                self.calls += 1
                (cwd / 'docs/change.md').write_text(f'change {self.calls}\n')
                if outside:
                    (cwd / 'docs/unrelated.md').write_text('forbidden\n')
                log.write_text(json.dumps({'type': 'error' if worker_error else 'text'}) + '\n')
                return ''
            if args[0] == 'git':
                return self.real_command(args, cwd, log, **kwargs)
            if log:
                log.write_text('simulated validation\n')
            if build_fail and 'build.py' in ' '.join(args):
                raise RuntimeError('simulated build failure')
            return ''

        argv = ['run.py', '--task', 'Document change', '--allow-file', 'docs/change.md']
        if apply:
            argv.append('--apply')
        with patch.object(runner, 'ROOT', self.root), patch.object(runner, 'SSD', Path(self.temp.name) / 'runs'), \
             patch.object(runner, 'codex', model), patch.object(runner, 'command', command), \
             patch.object(sys, 'argv', argv), contextlib.redirect_stdout(io.StringIO()):
            runner.main()

    def test_two_repairs_then_apply(self):
        self.execute([{'passed': False, 'findings': ['fix']}, {'passed': False, 'findings': ['fix']},
                      {'passed': True, 'findings': []}], apply=True)
        self.assertEqual(self.calls, 3)
        self.assertEqual((self.root / 'docs/change.md').read_text(), 'change 3\n')

    def test_rejection_stops_at_three_and_preserves_original(self):
        with self.assertRaisesRegex(RuntimeError, 'two repairs'):
            self.execute([{'passed': False, 'findings': ['fix']} for _ in range(3)], apply=True)
        self.assertEqual(self.calls, 3)
        self.assertFalse((self.root / 'docs/change.md').exists())

    def test_outside_scope_stops_before_review(self):
        with self.assertRaisesRegex(RuntimeError, 'Out-of-scope'):
            self.execute([], outside=True)
        self.assertFalse((self.root / 'docs/unrelated.md').exists())

    def test_worker_event_error_is_not_success(self):
        with self.assertRaisesRegex(RuntimeError, 'Worker returned an error'):
            self.execute([], worker_error=True)

    def test_build_failure_overrides_passing_review(self):
        with self.assertRaisesRegex(RuntimeError, 'two repairs'):
            self.execute([{'passed': True, 'findings': []} for _ in range(3)], build_fail=True, apply=True)
        self.assertFalse((self.root / 'docs/change.md').exists())

    def test_dirty_original_untouched(self):
        (self.root / 'docs/base.md').write_text('user edit\n')
        with self.assertRaisesRegex(RuntimeError, 'dirty'):
            self.execute([])
        self.assertEqual((self.root / 'docs/base.md').read_text(), 'user edit\n')

    def test_control_and_ui_paths_blocked(self):
        for name in ('../outside', 'AGENTS.md', 'App/ProminentTabBar.swift', 'tools/supervisor/run.py', 'docs/*.md'):
            with self.assertRaises(RuntimeError):
                runner.valid_paths([name], False)


if __name__ == '__main__':
    unittest.main()
