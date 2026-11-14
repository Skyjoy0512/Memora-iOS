# coding=utf-8
# Copyright 2026 Nishika, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

"""jMeet-Eval: 会議関連指示の評価メイン（IFEval構造準拠）"""

import asyncio
import json
import os
import time
from pathlib import Path
from typing import Sequence

from absl import app, flags, logging

from jmeeteval.core.async_llm_client import close_global_client
from jmeeteval.core.model import GenerateResults, MeetingInputExamples
from jmeeteval.evaluation.meeting_evaluation_lib import (
    MeetingEvaluator,
    MeetingOutputExample,
    calculate_meeting_metrics,
    generate_evaluation_report,
    write_meeting_results,
)

_INPUT_DATA = flags.DEFINE_string(
    "input_data", None, "jMeet-Eval入力データ (transcripts.jsonl or hf://username/dataset)", required=True
)

_INSTRUCTIONS = flags.DEFINE_string(
    "instructions", None, "指示ファイルのパス (instructions.jsonl) ※ローカルファイルの場合は必須"
)

_INPUT_RESPONSE_DATA = flags.DEFINE_string(
    "input_response_data", None, "jMeet-Eval入力応答データへのパス", required=True
)

_OUTPUT_DIR = flags.DEFINE_string(
    "output_dir",
    None,
    "jMeet-Eval推論と評価結果の出力ディレクトリ",
    required=True,
)


def format_time(seconds):
    """秒を MM:SS 形式に変換"""
    m, s = divmod(int(seconds), 60)
    return f"{m:02d}:{s:02d}"


def print_progress(current, total, start_time):
    """進捗を表示"""
    elapsed = time.time() - start_time
    if current > 0:
        eta = (elapsed / current) * (total - current)
        print(
            f"\r進捗: {current}/{total} ({current * 100 // total}%) | 経過: {format_time(elapsed)} | 残り: {format_time(eta)}",  # noqa: E501
            end="",
            flush=True,
        )
    else:
        print(f"\r進捗: {current}/{total} (0%) | 経過: {format_time(elapsed)}", end="", flush=True)


async def run_async_evaluation(
    evaluator: MeetingEvaluator,
    input_examples: MeetingInputExamples,
    generate_results: GenerateResults,
) -> list[MeetingOutputExample]:
    start_time = time.time()
    total = len(generate_results)
    try:
        results = await evaluator.evaluate_batch_async_with_progress(
            input_examples,
            generate_results,
            progress_callback=lambda current: print_progress(current, total, start_time),
        )
        return results
    finally:
        await close_global_client()
        eval_time = time.time() - start_time
        logging.info(f"評価完了: {format_time(eval_time)} ({eval_time:.2f}秒)")


def main(argv: Sequence[str]) -> None:
    if len(argv) > 1:
        raise app.UsageError("引数が多すぎます。")

    # 出力ディレクトリを作成
    os.makedirs(_OUTPUT_DIR.value, exist_ok=True)

    # 入力データを読み込み
    logging.info("jMeet-Eval入力データを読み込み中...")
    input_examples = MeetingInputExamples.load_auto(
        transcripts_path=_INPUT_DATA.value,
        instructions_path=_INSTRUCTIONS.value,
    )
    logging.info(f"読み込み完了: {len(input_examples)}件の入力データ")

    # 応答データを読み込み
    logging.info("応答データを読み込み中...")
    generate_results = GenerateResults.load(Path(_INPUT_RESPONSE_DATA.value))
    logging.info(f"読み込み完了: {len(generate_results)}件の応答データ")

    # 評価器を初期化
    evaluator = MeetingEvaluator()

    # 非同期並列評価
    logging.info("jMeet-Eval評価を実行中（非同期モード）...")
    outputs = asyncio.run(run_async_evaluation(evaluator, input_examples, generate_results))

    # メトリクス計算
    logging.info("メトリクスを計算中...")
    metrics = calculate_meeting_metrics(outputs)

    # 結果をファイルに出力
    results_file = os.path.join(_OUTPUT_DIR.value, "jmeet_eval_results.jsonl")
    write_meeting_results(outputs, results_file)

    # メトリクスを出力
    metrics_file = os.path.join(_OUTPUT_DIR.value, "jmeet_metrics.json")

    with open(metrics_file, "w", encoding="utf-8") as f:
        json.dump(metrics, f, ensure_ascii=False, indent=2)

    # 詳細レポートを生成
    report_file = os.path.join(_OUTPUT_DIR.value, "jmeet_evaluation_report.json")
    generate_evaluation_report(metrics, report_file)

    # 結果を表示
    def _acc(value) -> str:
        """全件評価不可のとき精度は None になりうる。そのまま :.3f すると
        TypeError で落ちるため、数値以外は '-' を表示する。"""
        return f"{value:.3f}" if isinstance(value, (int, float)) else "-"

    logging.info("=== jMeet-Eval 評価結果 ===")
    logging.info(
        f"プロンプトレベル精度: {_acc(metrics['prompt_level_strict_accuracy'])} ({metrics['prompt_level_breakdown']})"
    )
    logging.info(
        f"指示レベル精度: {_acc(metrics['instruction_level_strict_accuracy'])} ({metrics['instruction_level_breakdown']})"  # noqa: E501
    )

    # 詳細統計
    logging.info("=== 詳細統計 ===")
    logging.info(
        f"評価対象プロンプト数: {metrics['valid_prompts']}/{metrics['total_prompts']} (評価不可: {metrics['null_prompts']})"  # noqa: E501
    )
    logging.info(
        f"評価対象指示数: {metrics['valid_instructions']}/{metrics['total_instructions']} (評価不可: {metrics['null_instructions']})"  # noqa: E501
    )

    # Null統計の詳細
    if metrics.get("null_statistics", {}).get("instruction_null_details"):
        logging.info("評価不可の指示詳細:")
        for inst_id, count in metrics["null_statistics"]["instruction_null_details"].items():
            logging.info(f"  {inst_id}: {count}回")

    logging.info("=== カテゴリ別精度 ===")
    for key, value in metrics.items():
        if key.endswith("_accuracy") and not key.startswith(("prompt_", "instruction_")):
            # カテゴリ名を取得してbreakdownを探す
            category = key.replace("_accuracy", "")
            breakdown = metrics.get(f"{category}_breakdown", "")
            logging.info(f"{key}: {value:.3f} ({breakdown})")

    logging.info(f"詳細結果: {results_file}")
    logging.info(f"メトリクス: {metrics_file}")
    logging.info(f"評価レポート: {report_file}")


if __name__ == "__main__":
    app.run(main)
