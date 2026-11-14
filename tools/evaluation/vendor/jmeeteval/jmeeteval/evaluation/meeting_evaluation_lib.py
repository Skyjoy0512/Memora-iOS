# coding=utf-8
# Copyright 2026 Nishika, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

"""jMeet-Eval: 会議関連指示の評価ライブラリ（拡張版）"""

import asyncio
import collections
import json
import time
from collections.abc import Callable
from datetime import datetime
from typing import Any, Coroutine, Dict, List

from pydantic import BaseModel, field_validator

from jmeeteval.core import meeting_instructions_registry as mi_registry
from jmeeteval.core.meeting_instructions import CheckFollowingResult
from jmeeteval.core.model import GenerateResults, MeetingInputExample, MeetingInputExamples


class EvaluationError(Exception):
    """評価不可の場合に発生する例外"""

    def __init__(self, instruction_id: str, error_message: str, id: str = None):
        self.instruction_id = instruction_id
        self.error_message = error_message
        self.id = id
        super().__init__(f"評価不可: instruction_id={instruction_id}, id={id}, error={error_message}")


class MeetingOutputExample(BaseModel):
    """会議評価の出力例"""

    id: str
    instruction_id_list: list[str]
    prompt: str
    response: str
    follow_all_instructions: bool | None  # None = 評価不可
    follow_instruction_list: list[float | None]  # None = 評価不可
    check_following_results: list[CheckFollowingResult]
    execution_time: float
    metadata: dict[str, Any] | None = None
    error_details: list[str] | None = None

    @field_validator("id", mode="before")
    @classmethod
    def convert_id_to_str(cls, v):
        return str(v)


class MeetingOutputExamples(BaseModel):
    examples: list[MeetingOutputExample]

    def __len__(self) -> int:
        return len(self.examples)


class MeetingEvaluator:
    """会議指示の評価を行うメインクラス"""

    def __init__(self):
        self.instruction_registry = mi_registry.MEETING_INSTRUCTION_DICT

    # === 非同期評価メソッド ===

    async def evaluate_response_async(
        self, input_example: MeetingInputExample, prompt_for_evaluation: str, response: str
    ) -> MeetingOutputExample:
        """非同期版: 複数チェッカーを並列評価

        Args:
            input_example: 入力例
            response: 評価対象の応答テキスト

        Returns:
            MeetingOutputExample: 評価結果
        """
        start_time = time.time()

        # 全チェッカーのタスクを作成
        # document には「元の文字起こし」を渡す。プロンプト全文を渡すと ProportionChecker の
        # 分母が指示文ぶん膨張し、LLM judge のプロンプトにも評価指示文が二重に埋め込まれる。
        tasks: list[Coroutine[Any, Any, CheckFollowingResult]] = []
        for i, instruction_id in enumerate(input_example.instruction_id_list):
            kwargs = input_example.instruction_kwargs[i] if i < len(input_example.instruction_kwargs) else {}
            tasks.append(
                self._evaluate_single_async(
                    instruction_id,
                    input_example.transcript,
                    prompt_for_evaluation,
                    response,
                    kwargs,
                    id=input_example.id,
                )
            )

        # 並列実行（EvaluationError を例外として返し、パイプラインを継続させる）
        raw_results = await asyncio.gather(*tasks, return_exceptions=True)

        # 例外を CheckFollowingResult(score=None) に変換
        results = []
        for i, result in enumerate(raw_results):
            if isinstance(result, Exception):
                instruction_id = (
                    input_example.instruction_id_list[i] if i < len(input_example.instruction_id_list) else "unknown"
                )
                results.append(
                    CheckFollowingResult(
                        instruction_id=instruction_id,
                        score=None,
                        error_message=str(result),
                    )
                )
            else:
                results.append(result)

        # 結果を集約
        follow_instruction_list = []

        for result in results:
            if result.score is None:
                follow_instruction_list.append(None)
            else:
                follow_instruction_list.append(result.score)

        # follow_all計算
        # LLM judge は3回実行の平均を返すため、0.5以上（多数決パス）を指示遵守とみなす。
        # 1件でも評価不可(None)があれば「全指示を守ったか」は判定できないため None とする。
        # （Noneを単に除外すると、実質1指示しか検証していない例が「全遵守」として
        #   prompt-level 精度の分子に入り、値を押し上げてしまう）
        if any(r is None for r in follow_instruction_list) or not follow_instruction_list:
            follow_all_instructions = None
        else:
            follow_all_instructions = all(r >= 0.5 for r in follow_instruction_list)

        execution_time = time.time() - start_time

        return MeetingOutputExample(
            id=input_example.id,
            instruction_id_list=input_example.instruction_id_list,
            prompt=prompt_for_evaluation,
            response=response,
            follow_all_instructions=follow_all_instructions,
            follow_instruction_list=follow_instruction_list,
            execution_time=execution_time,
            metadata=input_example.metadata,
            check_following_results=results,
        )

    async def _evaluate_single_async(
        self,
        instruction_id: str,
        document: str,
        prompt: str,
        response: str,
        kwargs: Dict[str, Any],
        id: str = None,
    ) -> CheckFollowingResult:
        """単一指示の非同期評価

        Args:
            instruction_id: 指示ID
            document: 元の文字起こし（チェッカー・LLM judge の参照対象）
            prompt: 評価用プロンプト全文（指示＋文字起こし）
            response: 応答テキスト
            kwargs: 追加引数
            id: 入力例のID（エラーメッセージ用）

        Returns:
            CheckFollowingResult: 評価結果

        Raises:
            EvaluationError: 評価不可の場合
        """
        try:
            # 会議指示クラスを取得
            instruction_class = self.instruction_registry.get(instruction_id)
            if not instruction_class:
                raise EvaluationError(
                    instruction_id=instruction_id,
                    error_message=f"Unknown instruction ID: {instruction_id}",
                    id=id,
                )

            # インスタンスを作成
            instance = instruction_class(instruction_id)
            instance._cached_kwargs = {**kwargs, "prompt": prompt}

            result = await instance.check_following(document, response)

            # 評価不可（score=None）の場合は例外を投げる
            if result.score is None:
                raise EvaluationError(
                    instruction_id=instruction_id,
                    error_message=result.error_message or "評価不可",
                    id=id,
                )

            return result

        except EvaluationError:
            # EvaluationErrorはそのまま再送出
            raise
        except Exception as e:
            # その他の例外もEvaluationErrorとして投げる
            raise EvaluationError(
                instruction_id=instruction_id,
                error_message=f"Evaluation error: {str(e)}",
                id=id,
            )

    async def evaluate_batch_async_with_progress(
        self,
        input_examples: MeetingInputExamples,
        generate_results: GenerateResults,
        progress_callback: Callable[[int], None] | None = None,
    ) -> List[MeetingOutputExample]:
        """進捗コールバック付きの並列評価

        Args:
            input_examples: 入力例のリスト
            responses: 応答テキストのリスト
            progress_callback: 進捗コールバック関数 (current_count) -> None

        Returns:
            List[MeetingOutputExample]: 評価結果のリスト（順序保持）
        """
        completed = 0

        async def evaluate_with_progress(example: MeetingInputExample, prompt_for_evaluation: str, response: str):
            nonlocal completed
            result = await self.evaluate_response_async(example, prompt_for_evaluation, response)
            completed += 1
            if progress_callback:
                progress_callback(completed)
            return result

        tasks = [
            evaluate_with_progress(
                input_examples.get_example(generate_result.id),
                generate_result.prompt_for_evaluation,
                generate_result.response,
            )
            for generate_result in generate_results.results
        ]

        # asyncio.gatherはタスク順を保持するため、結果はgenerate_resultsと同順
        return await asyncio.gather(*tasks)


def calculate_meeting_metrics(output_examples: List[MeetingOutputExample]) -> Dict[str, Any]:
    """会議評価メトリクスを計算（拡張版）"""
    if not output_examples:
        return {"error": "No output examples provided"}

    total_prompts = len(output_examples)

    # None値を除外して基本メトリクスを計算
    valid_prompt_results = [
        ex.follow_all_instructions for ex in output_examples if ex.follow_all_instructions is not None
    ]
    if valid_prompt_results:
        prompt_level_success_count = sum(valid_prompt_results)
        prompt_level_valid_count = len(valid_prompt_results)
        prompt_level_accuracy = prompt_level_success_count / prompt_level_valid_count
    else:
        prompt_level_accuracy = None
        prompt_level_success_count = 0
        prompt_level_valid_count = 0

    # 指示レベルの詳細統計
    instruction_results = []
    instruction_stats = collections.defaultdict(lambda: {"total": 0, "passed": 0, "null": 0})
    category_results = collections.defaultdict(list)

    # Null指示の統計
    null_instruction_count = 0
    total_instruction_count = 0

    # 実行時間統計
    execution_times = [ex.execution_time for ex in output_examples]

    for example in output_examples:
        for i, instruction_id in enumerate(example.instruction_id_list):
            score = example.follow_instruction_list[i]
            total_instruction_count += 1

            # Noneでない結果のみを集計
            if score is not None:
                # LLM judgeは3回実行の平均スコア（1/3, 2/3等）を返すため、
                # 0.5以上（多数決パス）を遵守として二値化する
                is_following = score >= 0.5
                instruction_results.append(is_following)
                instruction_stats[instruction_id]["total"] += 1
                if is_following:
                    instruction_stats[instruction_id]["passed"] += 1

                # カテゴリ別の結果を記録（Noneでない場合のみ）
                for cat_name, cat_prefix in mi_registry.MEETING_CATEGORIES.items():
                    if instruction_id.startswith(cat_prefix):
                        category_results[cat_name].append(is_following)
                        break
            else:
                # Null（評価不可）の場合
                instruction_stats[instruction_id]["null"] += 1
                null_instruction_count += 1

    # 指示レベル精度（Noneを除外して計算）
    if instruction_results:
        instruction_level_success_count = sum(instruction_results)
        instruction_level_valid_count = len(instruction_results)
        instruction_level_accuracy = instruction_level_success_count / instruction_level_valid_count
    else:
        instruction_level_accuracy = None
        instruction_level_success_count = 0
        instruction_level_valid_count = 0

    # カテゴリ別精度計算
    category_accuracies = {}
    category_breakdowns = {}
    for category, results in category_results.items():
        if results:
            success_count = sum(results)
            total_count = len(results)
            category_accuracies[f"{category}_accuracy"] = success_count / total_count
            category_breakdowns[f"{category}_breakdown"] = f"{success_count}/{total_count}"
        else:
            category_accuracies[f"{category}_accuracy"] = 0
            category_breakdowns[f"{category}_breakdown"] = "0/0"

    # 指示別成功率
    instruction_success_rates = {}
    for inst_id, stats in instruction_stats.items():
        if stats["total"] > 0:
            instruction_success_rates[inst_id] = stats["passed"] / stats["total"]

    # 複雑度別の分析
    complexity_analysis = analyze_by_complexity(output_examples)

    # エラー分析
    error_analysis = analyze_errors(output_examples)

    return {
        # 基本メトリクス
        "prompt_level_strict_accuracy": prompt_level_accuracy,
        "prompt_level_breakdown": f"{prompt_level_success_count}/{prompt_level_valid_count}",
        "instruction_level_strict_accuracy": instruction_level_accuracy,
        "instruction_level_breakdown": f"{instruction_level_success_count}/{instruction_level_valid_count}",
        # カテゴリ別メトリクス
        **category_accuracies,
        **category_breakdowns,
        # 詳細統計
        "total_prompts": total_prompts,
        "valid_prompts": prompt_level_valid_count,
        "successful_prompts": prompt_level_success_count,
        "null_prompts": total_prompts - prompt_level_valid_count,
        "total_instructions": total_instruction_count,
        "valid_instructions": instruction_level_valid_count,
        "successful_instructions": instruction_level_success_count,
        "null_instructions": null_instruction_count,
        "instruction_success_rates": instruction_success_rates,
        # Null統計
        "null_statistics": {
            "null_prompt_percentage": (total_prompts - prompt_level_valid_count) / total_prompts * 100,
            "null_instruction_percentage": (
                null_instruction_count / total_instruction_count * 100 if total_instruction_count else 0
            ),
            "instruction_null_details": {
                inst_id: stats["null"] for inst_id, stats in instruction_stats.items() if stats["null"] > 0
            },
        },
        # 複雑度分析
        "complexity_analysis": complexity_analysis,
        # エラー分析
        "error_analysis": error_analysis,
        # パフォーマンス統計
        "performance_stats": {
            "avg_execution_time": sum(execution_times) / len(execution_times),
            "min_execution_time": min(execution_times),
            "max_execution_time": max(execution_times),
        },
        # タイムスタンプ
        "evaluation_timestamp": datetime.now().isoformat(),
    }


def analyze_by_complexity(output_examples: List[MeetingOutputExample]) -> Dict[str, Any]:
    """複雑度別の分析（Null値を考慮）"""
    complexity_groups = {"single_instruction": [], "double_instruction": [], "multiple_instruction": []}

    for example in output_examples:
        num_instructions = len(example.instruction_id_list)
        # Noneでない場合のみ追加
        if example.follow_all_instructions is not None:
            if num_instructions == 1:
                complexity_groups["single_instruction"].append(example.follow_all_instructions)
            elif num_instructions == 2:
                complexity_groups["double_instruction"].append(example.follow_all_instructions)
            else:
                complexity_groups["multiple_instruction"].append(example.follow_all_instructions)

    analysis = {}
    total_valid = sum(len(results) for results in complexity_groups.values())

    for group_name, results in complexity_groups.items():
        if results:
            analysis[group_name] = {
                "count": len(results),
                "accuracy": sum(results) / len(results),
                "percentage": len(results) / total_valid * 100 if total_valid > 0 else 0,
            }
        else:
            analysis[group_name] = {"count": 0, "accuracy": None, "percentage": 0}

    return analysis


def analyze_errors(output_examples: List[MeetingOutputExample]) -> Dict[str, Any]:
    """エラーパターンの分析"""
    error_patterns = collections.defaultdict(int)
    error_by_instruction = collections.defaultdict(list)

    for example in output_examples:
        if example.error_details:
            for error in example.error_details:
                # エラーパターンを抽出
                if "Expected format" in error:
                    error_patterns["format_mismatch"] += 1
                elif "Unknown instruction" in error:
                    error_patterns["unknown_instruction"] += 1
                elif "error" in error.lower():
                    error_patterns["execution_error"] += 1
                else:
                    error_patterns["other"] += 1

                # 指示別エラー記録
                inst_id = error.split(":")[0]
                error_by_instruction[inst_id].append(error)

    return {
        "error_patterns": dict(error_patterns),
        "total_errors": sum(error_patterns.values()),
        "most_common_error": max(error_patterns.items(), key=lambda x: x[1])[0] if error_patterns else None,
        "instructions_with_most_errors": sorted(
            [(inst, len(errors)) for inst, errors in error_by_instruction.items()], key=lambda x: x[1], reverse=True
        )[:5],
    }


def write_meeting_results(
    output_examples: List[MeetingOutputExample], output_filename: str, include_metadata: bool = True
):
    """会議評価結果をJSONLファイルに出力（拡張版）"""
    with open(output_filename, "w", encoding="utf-8") as f:
        for example in output_examples:
            result = {
                "id": example.id,
                "instruction_id_list": example.instruction_id_list,
                "prompt": example.prompt,
                "response": example.response,
                "check_following_results": [result.model_dump() for result in example.check_following_results],
                "follow_all_instructions": example.follow_all_instructions,
                "follow_instruction_list": example.follow_instruction_list,
                "execution_time": example.execution_time,
            }

            if include_metadata:
                if example.metadata:
                    result["metadata"] = example.metadata
                if example.error_details:
                    result["error_details"] = example.error_details

            f.write(json.dumps(result, ensure_ascii=False) + "\n")


def generate_evaluation_report(metrics: Dict[str, Any], output_file: str):
    """詳細な評価レポートを生成"""
    report = {
        "summary": {
            "prompt_accuracy": metrics["prompt_level_strict_accuracy"],
            "instruction_accuracy": metrics["instruction_level_strict_accuracy"],
            "total_evaluated": metrics["total_prompts"],
        },
        "category_performance": {
            cat: metrics.get(f"{cat}_accuracy", 0) for cat in mi_registry.MEETING_CATEGORIES.keys()
        },
        "complexity_breakdown": metrics.get("complexity_analysis", {}),
        "error_summary": metrics.get("error_analysis", {}),
        "performance": metrics.get("performance_stats", {}),
        "detailed_instruction_rates": metrics.get("instruction_success_rates", {}),
        "timestamp": metrics.get("evaluation_timestamp"),
    }

    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
