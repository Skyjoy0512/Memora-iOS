import asyncio
import importlib.util
from pathlib import Path
import socket
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('offline', Path(__file__).parents[1] / 'jmeeteval_offline.py')
OFFLINE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(OFFLINE)


class OfficialOfflineTests(unittest.TestCase):
    def test_pinned_data_and_categories(self):
        _, instructions, records, categories = OFFLINE.load_data()
        self.assertEqual(len(records), 197)
        self.assertEqual(len(categories), 16)
        self.assertTrue(all(key in instructions for r in records for key in r['instruction_keys']))

    def test_official_rules_and_unassessed_judges(self):
        _, instructions, records, _ = OFFLINE.load_data()
        selected = next(r for r in records if any(instructions[k]['instruction_key'] in OFFLINE.RULES for k in r['instruction_keys']))
        with patch.object(socket.socket, 'connect', OFFLINE.denied), patch.object(socket, 'getaddrinfo', OFFLINE.denied):
            result = asyncio.run(OFFLINE.evaluate([{'id': selected['id'], 'response': '検証用。'}], instructions, records))
        self.assertTrue(any(r['status'] == 'evaluated' for r in result))
        for r in result:
            if r['checker'] not in OFFLINE.RULES:
                self.assertEqual(r['status'], 'notEvaluated')
                self.assertIsNone(r['score'])

    def test_unknown_and_duplicate_rejected(self):
        _, instructions, records, _ = OFFLINE.load_data()
        with self.assertRaises(ValueError):
            asyncio.run(OFFLINE.evaluate([{'id': 'invalid', 'response': ''}], instructions, records))
        r = {'id': records[0]['id'], 'response': ''}
        with self.assertRaises(ValueError):
            asyncio.run(OFFLINE.evaluate([r, r], instructions, records))
