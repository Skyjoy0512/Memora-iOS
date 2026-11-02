import importlib.util
import pathlib
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("audio_measurements", pathlib.Path(__file__).with_name("audio-measurements.py"))
metrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metrics)


class AudioMeasurementChecks(unittest.TestCase):
    def test_cer_preserves_negation_and_numbers(self):
        exact = metrics.quality("承認しない。150万円", "承認しない。150万円", 3600, 360)
        changed = metrics.quality("承認しない。150万円", "承認した。150万円")
        self.assertEqual(exact["cer"], 0)
        self.assertEqual(exact["rtf"], .1)
        self.assertGreater(changed["cer"], 0)
        self.assertGreater(metrics.quality("150", "１５０")["cer"], 0)

    def test_alignment_empty_unicode_and_word_errors(self):
        self.assertEqual(metrics.quality("が", "か\u3099")["cer"], 0)
        self.assertIsNone(metrics.quality("", "発言")["cer"])
        self.assertEqual(metrics.quality("one two three", "one three")["wer"], 1 / 3)
        self.assertEqual(metrics.distance("abc", "axc"), 1)

    def test_partial_and_resumed_are_not_fresh_throughput(self):
        base = dict(schemaVersion=1, environment=dict(hardware="iPhone99,1", osVersion="27.2.0", build="1-1", isSimulator=False),
                    includesSignalInspection=False, kind="recordedTranscription", outcome="success", engine="appleSpeech", wallSeconds=30,
                    audioSeconds=3600, reusedChunks=3, completedChunks=4,
                    totals={"recognition": dict(calls=1, wallSeconds=6, audioSeconds=60,
                                              successfulCalls=1, successfulWallSeconds=6, successfulAudioSeconds=60)})
        result = metrics.summarize([base, dict(base, outcome="failed")])
        self.assertIsNone(result["traces"][0]["freshEndToEndRTF"])
        self.assertEqual(result["traces"][0]["stages"]["recognition"]["rtf"], .1)
        self.assertIsNone(result["traces"][1]["completionRTF"])
        self.assertEqual(result["stageAggregates"][0]["runs"], 1)

        mixed = metrics.summarize([base, dict(base, includesSignalInspection=True)])
        self.assertEqual(len(mixed["stageAggregates"]), 2)
        partial_stage = dict(base, totals={"recognition": dict(calls=2, wallSeconds=36, audioSeconds=960,
                            successfulCalls=1, successfulWallSeconds=6, successfulAudioSeconds=60)})
        self.assertEqual(metrics.summarize([partial_stage])["traces"][0]["stages"]["recognition"]["rtf"], .1)

    def test_invalid_and_path_text_never_becomes_metric(self):
        with self.assertRaises(ValueError):
            metrics.summarize([dict(schemaVersion=1, environment=dict(hardware="private/path", osVersion="27", build="1", isSimulator=False),
                                        includesSignalInspection=False, kind="PRIVATE_CONTENT", outcome="success")])
        with self.assertRaises(ValueError):
            metrics.quality("a", "b", 0, 1)
        with self.assertRaises(ValueError):
            metrics.quality("a", "b", 60)
        with self.assertRaises(ValueError):
            metrics.distance("a" * 6000, "b" * 6000)

    def test_cli_redacts_input_and_argument_errors(self):
        command = [sys.executable, "-B", str(pathlib.Path(metrics.__file__))]
        argument = subprocess.run(command + ["quality", "PRIVATE_PATH", "PRIVATE_PATH", "--audio-seconds", "PRIVATE_VALUE"],
                                  capture_output=True, text=True)
        self.assertEqual(argument.returncode, 2)
        self.assertNotIn("PRIVATE", argument.stderr)
        with tempfile.TemporaryDirectory() as directory:
            source = pathlib.Path(directory) / "PRIVATE_CONTENT.json"
            source.write_text('[{"schemaVersion":1,"environment":{"hardware":"PRIVATE/PATH"}}]')
            invalid = subprocess.run(command + ["report", str(source)], capture_output=True, text=True)
            self.assertEqual(invalid.returncode, 2)
            self.assertNotIn("PRIVATE", invalid.stderr)
            self.assertEqual(invalid.stdout, "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
