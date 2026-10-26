import copy
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

from simulator_profile_summary import summarize


class SimulatorProfileSummaryChecks(unittest.TestCase):
    image_uuid = '802E7CEB-5E51-39ED-9884-0DA761F6CC7F'

    def fixture(self):
        root = ET.Element('trace-query-result')
        node = ET.SubElement(root, 'node')
        schema = ET.SubElement(node, 'schema', name='time-profile')
        for name in ['time', 'thread', 'process', 'core', 'thread-state', 'weight', 'stack']:
            ET.SubElement(ET.SubElement(schema, 'col'), 'mnemonic').text = name
        first = ET.SubElement(node, 'row')
        ET.SubElement(first, 'sample-time').text = '1000000000'
        ET.SubElement(first, 'thread', id='t', fmt='Main Thread (0x1) (Memora, pid: 1)')
        ET.SubElement(first, 'process', id='p', fmt='Memora (1)')
        ET.SubElement(first, 'core').text = '1'
        ET.SubElement(first, 'thread-state', id='s', fmt='Running')
        ET.SubElement(first, 'weight', id='w').text = '2000000'
        stack = ET.SubElement(first, 'tagged-backtrace', id='stack')
        frame = ET.SubElement(stack, 'frame', name='HomeView.body.getter', id='f')
        ET.SubElement(frame, 'binary', name='Memora', UUID=self.image_uuid)
        ET.SubElement(stack, 'frame', ref='f')  # Recursion must not double weight.
        second = ET.SubElement(node, 'row')
        ET.SubElement(second, 'sample-time').text = '3000000000'
        ET.SubElement(second, 'thread', ref='t')
        ET.SubElement(second, 'process', ref='p')
        ET.SubElement(second, 'core').text = '2'
        ET.SubElement(second, 'thread-state', ref='s')
        ET.SubElement(second, 'weight', ref='w')
        ET.SubElement(second, 'tagged-backtrace', ref='stack')
        return root

    def run_summary(self, root, uuids=None):
        with tempfile.TemporaryDirectory(prefix='memora-profile-check-') as folder:
            path = Path(folder) / 'samples.xml'
            path.write_bytes(ET.tostring(root))
            return summarize(path, 'Memora', uuids if uuids is not None else [self.image_uuid])

    def test_reference_resolution_and_weights(self):
        result = self.run_summary(self.fixture())
        self.assertEqual(result['samples'], 2)
        self.assertEqual(result['main_thread_sample_weight_ms'], 4)
        self.assertEqual(result['top_app_inclusive'][0]['sample_weight_ms'], 4)
        self.assertEqual(result['sample_span_seconds'], 2)
        self.assertEqual(result['app_symbolication'], 'named')
        self.assertNotIn('fps', result)

    def test_empty_and_wrong_schema_rejected(self):
        root = self.fixture()
        for row in root.findall('.//row'):
            root.find('node').remove(row)
        with self.assertRaises(ValueError): self.run_summary(root)

    def test_debug_code_image_is_owned_and_requires_its_own_uuid(self):
        root = self.fixture()
        binary = root.find('.//binary')
        binary.set('name', 'Memora.debug.dylib')
        debug_uuid = '00000000-0000-0000-0000-000000000005'
        binary.set('UUID', debug_uuid)
        with self.assertRaises(ValueError): self.run_summary(root)
        result = self.run_summary(root, [self.image_uuid, debug_uuid])
        self.assertEqual(result['app_binary_uuids'], [debug_uuid])
        self.assertEqual(result['app_symbolication'], 'named')
        root = self.fixture(); root.find('.//schema').set('name', 'time-sample')
        with self.assertRaises(ValueError): self.run_summary(root)

    def test_identity_and_broken_references_rejected(self):
        with self.assertRaises(ValueError): self.run_summary(self.fixture(), ['00000000-0000-0000-0000-000000000000'])
        with self.assertRaises(ValueError): self.run_summary(self.fixture(), [])
        for target, attribute, value in [('.//thread[@ref]', 'ref', 'missing'),
                                         ('.//process[@id]', 'fmt', 'Other (2)'),
                                         ('.//weight[@id]', 'id', 't')]:
            root = self.fixture(); root.find(target).set(attribute, value)
            with self.assertRaises(ValueError): self.run_summary(root)
        root = self.fixture(); root.find('.//thread[@id]').set('ref', 't')
        with self.assertRaises(ValueError): self.run_summary(root)

    def test_missing_and_ambiguous_stacks_are_reported(self):
        root = self.fixture()
        root.find('.//frame[@id]').set('name', '<deduplicated_symbol>')
        result = self.run_summary(root)
        self.assertEqual(result['app_symbolication'], 'partial')
        self.assertEqual(result['ambiguous_app_sample_weight_ms'], 4)
        self.assertEqual(result['top_app_inclusive'], [])
        root = self.fixture(); row = root.findall('.//row')[1]
        row.remove(row[-1]); ET.SubElement(row, 'sentinel')
        result = self.run_summary(root)
        self.assertEqual(result['missing_backtrace_sample_weight_ms'], 2)
        self.assertEqual(result['app_symbolication'], 'partial')

    def test_invalid_weights_and_mixed_runs_rejected(self):
        for value in ['-1', '0', '9999999999999999999999', 'NaN']:
            root = self.fixture(); root.find('.//weight[@id]').text = value
            with self.assertRaises(ValueError): self.run_summary(root)
        root = self.fixture(); root.append(copy.deepcopy(root.find('node')))
        with self.assertRaises(ValueError): self.run_summary(root)


if __name__ == '__main__':
    unittest.main()
