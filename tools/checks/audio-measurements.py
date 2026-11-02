#!/usr/bin/env python3
"""Local numeric audio metrics only; never print transcripts, file paths or raw errors."""
import argparse
import json
import math
import pathlib
import re
import statistics
import sys
import unicodedata

KINDS = {"recording", "recordingFinalization", "liveTranscription", "recordedTranscription", "sourceExtraction", "cloudTranscription",
         "speakerAnalysis", "voiceActivity", "quality", "summary"}
ENGINES = {"appleSpeech", "openAIWhisper", "deepgramNova3", "fluidSpeaker", "silero", "onDeviceSummary", "cloudSummary"}
STAGES = {"queue", "snapshot", "exportAudio", "modelPreparation", "recognition", "upload", "decode", "quality", "vad", "diarization", "summary", "verification", "persistence"}
STATES = {"running", "success", "empty", "failed", "cancelled", "unavailable", "interrupted", "deferred"}


class MeasurementArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        self.exit(2, "Invalid measurement arguments. Use --help for local file and numeric options.\n")


def number(value, positive=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError("invalid numeric metric")
    if value < 0 or (positive and value == 0):
        raise ValueError("invalid numeric range")
    return value


def bounded_read(path, limit):
    with pathlib.Path(path).open("rb") as file:
        data = file.read(limit + 1)
    if len(data) > limit:
        raise ValueError("input limit exceeded")
    return data.decode("utf-8")


def summarize(reports):
    if not isinstance(reports, list) or len(reports) > 12:
        raise ValueError("invalid report envelope")
    results = []
    stage_rtfs = {}
    for index, item in enumerate(reports):
        if item.get("schemaVersion") != 1:
            raise ValueError("unknown schema")
        environment = item["environment"]
        environment_key = tuple(environment[key] for key in ("hardware", "osVersion", "build", "isSimulator"))
        if any(not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9._,-]{1,64}", value)
               for value in environment_key[:3]) or not isinstance(environment_key[3], bool):
            raise ValueError("invalid environment")
        inspect_signal = item["includesSignalInspection"]
        if not isinstance(inspect_signal, bool):
            raise ValueError("invalid configuration")
        kind, state, engine = item["kind"], item["outcome"], item.get("engine")
        if kind not in KINDS or state not in STATES or (engine is not None and engine not in ENGINES):
            raise ValueError("unknown metric kind")
        wall = number(item["wallSeconds"])
        audio = number(item["audioSeconds"], positive=True) if "audioSeconds" in item else None
        reused = number(item["reusedChunks"])
        completed = number(item["completedChunks"])
        settled = state in {"success", "empty"}
        completion_rtf = wall / audio if settled and audio and kind not in {"recording", "liveTranscription"} else None
        totals = item.get("totals", {})
        if not isinstance(totals, dict) or any(key not in STAGES for key in totals):
            raise ValueError("unknown stage")
        stages = {}
        for stage, total in totals.items():
            seconds = number(total["wallSeconds"])
            processed = number(total["audioSeconds"])
            successful_wall = number(total["successfulWallSeconds"])
            successful_audio = number(total["successfulAudioSeconds"])
            successful_calls = number(total["successfulCalls"])
            calls = number(total["calls"])
            if successful_wall > seconds or successful_audio > processed or successful_calls > calls:
                raise ValueError("invalid completed stage metric")
            rtf = successful_wall / successful_audio if successful_audio else None
            stages[stage] = dict(calls=calls, wallSeconds=seconds, plannedAudioSeconds=processed,
                                 successfulCalls=successful_calls, successfulAudioSeconds=successful_audio,
                                 successfulWallSeconds=successful_wall, rtf=rtf)
            if settled and rtf is not None:
                key = (environment_key, inspect_signal, kind, engine or "unreported", stage, "resumed" if reused else "fresh")
                stage_rtfs.setdefault(key, []).append(rtf)
        samples = item.get("samples", [])
        if not isinstance(samples, list) or len(samples) > 256:
            raise ValueError("invalid samples")
        peak = number(item["sampledPeakFootprintBytes"]) if "sampledPeakFootprintBytes" in item else None
        first = item.get("firstBatteryFraction")
        last = item.get("lastBatteryFraction")
        for battery in (first, last):
            if battery is not None and not 0 <= number(battery) <= 1:
                raise ValueError("invalid battery metric")
        results.append(dict(trace=index + 1, environment=dict(zip(("hardware", "osVersion", "build", "isSimulator"), environment_key)), includesSignalInspection=inspect_signal,
                            kind=kind, engine=engine, state=state, wallSeconds=wall,
                            audioSeconds=audio, reusedChunks=reused, completedChunks=completed,
                            completionRTF=completion_rtf, freshEndToEndRTF=completion_rtf if not reused else None,
                            sampledPeakMiB=peak / (1024 * 1024) if peak is not None else None,
                            batteryChangePercentagePoints=(last - first) * 100 if first is not None and last is not None else None,
                            maximumThermalState=number(item.get("maximumThermalState", 0)), stages=stages))
    aggregates = []
    for (environment_key, inspect_signal, kind, engine, stage, mode), values in sorted(stage_rtfs.items()):
        ordered = sorted(values)
        aggregates.append(dict(environment=dict(zip(("hardware", "osVersion", "build", "isSimulator"), environment_key)),
                               includesSignalInspection=inspect_signal, kind=kind, engine=engine, stage=stage, mode=mode, runs=len(values),
                               medianRTF=statistics.median(values), p95RTF=ordered[max(0, math.ceil(len(values) * .95) - 1)]))
    return dict(schemaVersion=1, traces=results, stageAggregates=aggregates,
                caveat="Sampled app footprint and whole-device battery/thermal metrics; interrupted runs are not throughput samples; resumed and fresh runs stay separate.")


def distance(reference, hypothesis):
    if reference == hypothesis:
        return 0
    if len(reference) * len(hypothesis) > 25_000_000:
        raise ValueError("split into aligned short excerpts before comparing")
    if len(hypothesis) > len(reference):
        reference, hypothesis = hypothesis, reference
    previous = list(range(len(hypothesis) + 1))
    for i, left in enumerate(reference, 1):
        current = [i]
        for j, right in enumerate(hypothesis, 1):
            current.append(min(current[-1] + 1, previous[j] + 1, previous[j - 1] + (left != right)))
        previous = current
    return previous[-1]


def quality(reference, hypothesis, audio_seconds=None, elapsed_seconds=None):
    if (audio_seconds is None) != (elapsed_seconds is None):
        raise ValueError("audio and elapsed durations must be paired")
    reference = unicodedata.normalize("NFC", reference)
    hypothesis = unicodedata.normalize("NFC", hypothesis)
    chars = re.sub(r"\s", "", reference)
    predicted = re.sub(r"\s", "", hypothesis)
    words, predicted_words = reference.split(), hypothesis.split()
    char_errors, word_errors = distance(chars, predicted), distance(words, predicted_words)
    return dict(referenceCharacters=len(chars), hypothesisCharacters=len(predicted), characterEdits=char_errors,
                cer=char_errors / len(chars) if chars else None,
                referenceWords=len(words), wordEdits=word_errors, wer=word_errors / len(words) if words else None,
                rtf=number(elapsed_seconds) / number(audio_seconds, positive=True)
                if audio_seconds is not None and elapsed_seconds is not None else None,
                normalization="NFC; CER removes whitespace; punctuation, digits and case retained; WER tokenization is whitespace. Use CER for unsegmented Japanese.")


def main():
    parser = MeasurementArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    report = commands.add_parser("report")
    report.add_argument("metrics_json")
    comparison = commands.add_parser("quality")
    comparison.add_argument("reference")
    comparison.add_argument("hypothesis")
    comparison.add_argument("--audio-seconds", type=float)
    comparison.add_argument("--elapsed-seconds", type=float)
    args = parser.parse_args()
    try:
        if args.command == "report":
            result = summarize(json.loads(bounded_read(args.metrics_json, 2 * 1024 * 1024),
                                          parse_constant=lambda _: (_ for _ in ()).throw(ValueError("invalid number"))))
        else:
            result = quality(bounded_read(args.reference, 256 * 1024), bounded_read(args.hypothesis, 256 * 1024),
                             args.audio_seconds, args.elapsed_seconds)
        print(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False))
    except (OSError, ValueError, TypeError, KeyError):
        print("Measurement input could not be validated. Use bounded UTF-8 files and aligned short excerpts. No input content is included in this error.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
