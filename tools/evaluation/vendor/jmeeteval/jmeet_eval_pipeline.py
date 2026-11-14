#!/usr/bin/env python3
# coding=utf-8
# Copyright 2026 Nishika, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

"""jMeet-Eval: エンドツーエンド評価パイプライン

使用例:
    # デフォルト設定（全例を評価）
    uv run python jmeet_eval_pipeline.py --model gpt-5-mini

    # Hugging Faceデータセットから評価
    uv run python jmeet_eval_pipeline.py \
      --transcripts hf://<org>/<dataset-name> --model gpt-5-mini

    # 2例のみ評価
    uv run python jmeet_eval_pipeline.py --model gpt-5-mini --num_examples 2
"""

import argparse
import asyncio
import json
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List

from dotenv import load_dotenv
from openai import AsyncOpenAI

from jmeeteval.core import usage_tracker
from jmeeteval.core.async_llm_client import LLMConfig, close_global_client, use_judge
from jmeeteval.core.model import GenerateResult, GenerateResults, MeetingInputExamples
from jmeeteval.evaluation.format_results import format_eval_results
from jmeeteval.evaluation.meeting_evaluation_lib import (
    MeetingEvaluator,
    MeetingOutputExample,
    calculate_meeting_metrics,
)
from jmeeteval.generate.response_generator import is_reasoning_model


def _format_time(seconds: float) -> str:
    """秒を MM:SS 形式に変換"""
    m, s = divmod(int(seconds), 60)
    return f"{m:02d}:{s:02d}"


class JMeetEvalPipeline:
    """jMeet-Eval評価パイプライン"""

    def __init__(
        self,
        model: str = "gpt-5-mini",
        verbose: bool = False,
        transcripts_path: str = "data/transcripts.jsonl",
        instructions_path: str | None = "data/instructions.jsonl",
        output_dir: str = "data/output",
        max_concurrent: int = 10,
        api_key: str | None = None,
        judge_model: str | None = None,
        judge_max_concurrent: int | None = None,
        judge_timeout: int | None = None,
    ):
        """
        Args:
            model: 使用するモデル名
            verbose: 詳細ログ出力
            transcripts_path: 文字起こしファイルパス or hf://...
            instructions_path: 指示ファイルパス（ローカルの場合は必須）
            output_dir: 出力ディレクトリ
            max_concurrent: 応答生成の最大同時実行数
            api_key: API キー。None なら環境変数 OPENAI_API_KEY を使う。
                複数の利用者がそれぞれのキーで実行する UI から使う場合は必ず明示指定すること
                （環境変数に書き込むとプロセス全体で共有され、他の利用者のキーで実行されうる）
            judge_model: 採点モデル。None なら環境変数 LLM_JUDGE_MODEL
            judge_max_concurrent: 採点の同時実行数
            judge_timeout: 採点のタイムアウト秒
        """
        self.model = model
        self.verbose = verbose
        self.transcripts_path = transcripts_path
        self.instructions_path = instructions_path
        self.output_dir = os.path.abspath(output_dir)
        self.max_concurrent = max_concurrent
        self.api_key = api_key or os.environ.get("OPENAI_API_KEY")

        judge_kwargs = {}
        if judge_model:
            judge_kwargs["model"] = judge_model
        if judge_max_concurrent:
            judge_kwargs["max_concurrent"] = judge_max_concurrent
        if judge_timeout:
            judge_kwargs["timeout"] = judge_timeout
        self.judge_config = LLMConfig(**judge_kwargs)

        # 生成の長さ予算。length_control:proportion 等は原文の 40〜60%（数千字）を要求するため、
        # 予算が小さいと出力が短く切られ構造的に達成不能になる。非reasoning系は max_tokens、
        # reasoning系(gpt-5/o系)は推論トークンも消費する max_completion_tokens を使うので、両方を
        # 大きめの既定にする。
        self.max_tokens = int(os.environ.get("JMEETEVAL_MAX_TOKENS", "32000"))
        # 掲載ベースラインは temperature=0.7 で測定。指示単位で 20% 程度ぶれ、単一実行の結果である。
        # ※reasoning系(gpt-5/o系)は temperature を受け付けない(HTTP 400)ため送信されず、この値は無効。
        self.temperature = float(os.environ.get("JMEETEVAL_TEMPERATURE", "0.7"))
        self.reasoning_effort = os.environ.get("JMEETEVAL_REASONING_EFFORT", "low")
        self.reasoning_max_completion_tokens = int(os.environ.get("JMEETEVAL_REASONING_MAX_COMPLETION_TOKENS", "32000"))

        # 生成に失敗した (id, 例外) の一覧。評価結果に母数の縮小として記録する。
        self.generation_failures: List[tuple] = []

        # 出力ディレクトリ作成
        os.makedirs(self.output_dir, exist_ok=True)

        # タイムスタンプ付き出力ファイル名
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.response_file = os.path.join(self.output_dir, f"responses_{timestamp}.json")
        self.eval_results_file = os.path.join(self.output_dir, f"eval_results_{timestamp}.json")
        self.summary_file = os.path.join(self.output_dir, f"summary_{timestamp}.txt")
        self.usage_file = os.path.join(self.output_dir, f"usage_{timestamp}.json")

    def load_input_data(self, num_examples: int = -1) -> MeetingInputExamples:
        """入力データの読み込み

        Args:
            num_examples: 読み込む例の数（-1で全て）

        Returns:
            MeetingInputExamples
        """
        print("\n=== 入力データ読み込み ===")

        all_inputs = MeetingInputExamples.load_auto(
            transcripts_path=self.transcripts_path,
            instructions_path=self.instructions_path,
        )

        # 指定数のみ取得
        if num_examples == -1 or num_examples >= len(all_inputs):
            inputs = all_inputs
        else:
            inputs = all_inputs.get_range(0, num_examples)

        print(f"読み込んだ例: {len(inputs)}/{len(all_inputs)}")

        if self.verbose:
            for ex in inputs.examples:
                print(f"\nID {ex.id}: {len(ex.instruction_id_list)} instructions")
                print(f"Instructions: {', '.join(ex.instruction_id_list)}")

        return inputs

    def generate_responses(self, inputs: MeetingInputExamples) -> GenerateResults:
        """応答生成（非同期並列）

        Args:
            inputs: 入力例

        Returns:
            GenerateResults
        """
        print("\n=== 応答生成開始 ===")
        print(f"モデル: {self.model}")
        print(f"同時実行数: {self.max_concurrent}")

        start_time = time.time()
        total = len(inputs)

        api_key = self.api_key
        if not api_key:
            raise RuntimeError(
                "API キーが指定されていません。環境変数 OPENAI_API_KEY を設定するか、"
                "JMeetEvalPipeline(api_key=...) で渡してください。"
            )
        base_url = os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1")

        async def _generate_all():
            client = AsyncOpenAI(
                api_key=api_key,
                base_url=base_url,
                timeout=int(os.environ.get("GENERATION_TIMEOUT", "120")),
            )
            semaphore = asyncio.Semaphore(self.max_concurrent)
            results = [None] * total
            failures: List[tuple] = []
            completed = 0

            async def _generate_one(index: int, example):
                nonlocal completed
                async with semaphore:
                    max_retries = int(os.environ.get("GENERATION_MAX_RETRIES", "3"))
                    last_error = None

                    for attempt in range(max_retries):
                        try:
                            params = {
                                "model": self.model,
                                "messages": [
                                    {
                                        "role": "system",
                                        "content": "あなたは会議関連タスクの専門家です。与えられた指示に従って正確に回答し、指定された制約を必ず守ってください。会議の形式、構造、内容について適切な知識を活用してください。",  # noqa: E501
                                    },
                                    {"role": "user", "content": example.prompt},
                                ],
                            }
                            if is_reasoning_model(self.model):
                                # gpt-5 / o系は max_tokens と temperature!=1 が400。
                                # 推論トークンも予算から出るため通常より大きく確保しないと本文が空になる。
                                params["max_completion_tokens"] = self.reasoning_max_completion_tokens
                                params["reasoning_effort"] = self.reasoning_effort
                            else:
                                # thinking 系(Qwen3等)は推論トークンも max_tokens から出るため、
                                # 4000 だと思考の途中で切れる。閉じ </think> が無いと下の除去正規表現が
                                # 効かず、思考テキストがそのまま答案として採点されてしまう。
                                params["max_tokens"] = self.max_tokens
                                params["temperature"] = self.temperature

                            resp = await client.chat.completions.create(**params)
                            response_text = (resp.choices[0].message.content or "").strip()
                            # Qwen3等のthinkingタグを除去
                            response_text = re.sub(r"<think>.*?</think>", "", response_text, flags=re.DOTALL).strip()
                            # 空応答は生成失敗として扱う。そのまま流すとチェッカー毎に矛盾した採点
                            # （句点無し=合格 / 文字数0=合格 / LLM judge=不合格）を受けてしまう。
                            if not response_text:
                                raise RuntimeError(
                                    f"空応答 (finish_reason={resp.choices[0].finish_reason})。"
                                    "推論モデルの場合は JMEETEVAL_REASONING_MAX_COMPLETION_TOKENS の引き上げを検討。"
                                )
                            if resp.usage is not None:
                                usage_tracker.record(
                                    self.model,
                                    resp.usage.prompt_tokens,
                                    resp.usage.completion_tokens,
                                )
                            results[index] = GenerateResult(
                                id=example.id,
                                prompt_for_evaluation=example.prompt,
                                response=response_text,
                            )
                            break  # 成功
                        except Exception as e:
                            last_error = e
                            if attempt < max_retries - 1:
                                wait = 5 * (2**attempt)  # 5s, 10s, 20s ...
                                print(
                                    f"\n  [リトライ {attempt + 1}/{max_retries - 1}] "
                                    f"ID {example.id} ({wait}s 待機): {type(e).__name__}",
                                    flush=True,
                                )
                                await asyncio.sleep(wait)
                    else:
                        # 全リトライ失敗。空応答で評価に流すと「モデルが指示を守れなかった」と
                        # 区別できなくなるため、結果に含めず失敗として記録する。
                        print(f"\nエラー ID {example.id} ({max_retries}回失敗): {last_error}", flush=True)
                        failures.append((example.id, last_error))

                    completed += 1
                    elapsed = time.time() - start_time
                    if completed > 0:
                        eta = (elapsed / completed) * (total - completed)
                        print(
                            f"\r応答生成: {completed}/{total} ({completed * 100 // total}%)"
                            f" | 経過: {_format_time(elapsed)} | 残り: {_format_time(eta)}",
                            end="",
                            flush=True,
                        )

            tasks = [_generate_one(i, ex) for i, ex in enumerate(inputs.examples)]
            try:
                await asyncio.gather(*tasks)
            finally:
                await client.close()
            return [r for r in results if r is not None], failures

        results, failures = asyncio.run(_generate_all())
        self.generation_failures = failures

        if failures:
            print(f"\n[警告] 生成失敗: {len(failures)}/{total} 件（評価対象から除外）")
            for item_id, exc in failures:
                print(f"    ID {item_id}: {type(exc).__name__}: {exc}")
            failed_ids_path = Path(self.response_file).with_name(f"{Path(self.response_file).stem}_failed_ids.txt")
            failed_ids_path.write_text("\n".join(str(i) for i, _ in failures), encoding="utf-8")
            print(f"    失敗IDの一覧: {failed_ids_path}")

        generate_results = GenerateResults(
            model_name=self.model,
            dataset_name=Path(self.transcripts_path).name,
            results=results,
        )

        # 応答をファイルに保存
        generate_results.save(Path(self.response_file))

        generation_time = time.time() - start_time
        print(f"\n応答生成完了: {generation_time:.2f}秒")
        print(f"応答を保存: {self.response_file}")

        return generate_results

    def regenerate_missing(
        self, inputs: MeetingInputExamples, base_responses_file: str
    ) -> GenerateResults:
        """既存の応答ファイルに欠けている id だけを生成し、マージした応答を返す。

        生成が失敗した例（空応答やタイムアウト）は応答ファイルに残らないため、そのぶん
        採点の母数が縮む。モデルごとに落ちる件数が違うと、スコアが同じ母数で比較できなく
        なる。モデル全体を回し直さずに、欠けている id だけを同じ設定で生成し直すための経路。

        Args:
            inputs: 入力例（全件）
            base_responses_file: 既存の応答ファイルパス

        Returns:
            既存 + 再生成をマージした GenerateResults
        """
        base = GenerateResults.load(Path(base_responses_file))
        have = {r.id for r in base.results}
        missing = [ex for ex in inputs.examples if ex.id not in have]

        print("\n=== 欠損応答の再生成 ===")
        print(f"既存の応答: {base_responses_file} ({len(base.results)}件)")
        print(f"入力: {len(inputs)}件 / 欠損: {len(missing)}件")

        if not missing:
            print("欠けている応答はありません。既存の応答をそのまま使います。")
            self.response_file = base_responses_file
            return base

        print(f"再生成する ID: {', '.join(str(ex.id) for ex in missing)}")
        subset = inputs.model_copy(update={"examples": missing})

        # generate_responses は self.response_file に「再生成分だけ」を書き出す。
        # このあと同じパスをマージ結果で上書きする（失敗IDの一覧は残る）。
        regenerated = self.generate_responses(subset)

        by_id = {r.id: r for r in base.results}
        by_id.update({r.id: r for r in regenerated.results})
        merged = GenerateResults(
            model_name=base.model_name,
            dataset_name=base.dataset_name,
            # 入力の並び順に揃える（既存ファイルの順序に依存しない）
            results=[by_id[ex.id] for ex in inputs.examples if ex.id in by_id],
        )
        merged.save(Path(self.response_file))

        still_missing = len(inputs) - len(merged.results)
        print(f"\nマージ後の応答: {len(merged.results)}/{len(inputs)}件")
        if still_missing:
            print(f"[警告] {still_missing}件は再生成しても取得できず、母数は縮んだままです。")
        print(f"マージ済みの応答を保存: {self.response_file}")

        return merged

    def evaluate_responses(
        self,
        inputs: MeetingInputExamples,
        generate_results: GenerateResults,
        failed_as_zero: bool = False,
    ) -> Dict:
        """応答評価（非同期並列）

        Args:
            inputs: 入力例
            generate_results: 生成結果
            failed_as_zero: 応答が無い例を不合格(0点)として母数に含める

        Returns:
            評価結果の辞書
        """
        print("\n=== 評価開始 ===")

        # judge 呼び出しにはAPIキーが必須。未設定のまま採点に進むと judge が全件401で
        # 「評価不可」になり、全件0点相当のまま正常終了してしまう（無言の全滅）。
        # --responses-file 経路は生成側のキー検証(generate_responses)を通らないため、
        # ここで明示的に検証して即エラーにする。
        if not self.api_key:
            raise RuntimeError(
                "APIキーが設定されていません。judge による採点には API キーが必要です。"
                "環境変数 OPENAI_API_KEY か JMeetEvalPipeline(api_key=...) で渡してください。"
            )

        evaluator = MeetingEvaluator()
        start_time = time.time()
        total = len(generate_results)

        def _print_progress(current: int):
            elapsed = time.time() - start_time
            if current > 0:
                eta = (elapsed / current) * (total - current)
                print(
                    f"\r評価: {current}/{total} ({current * 100 // total}%)"
                    f" | 経過: {_format_time(elapsed)} | 残り: {_format_time(eta)}",
                    end="",
                    flush=True,
                )

        async def _evaluate_all():
            # このパイプラインのキー・設定で採点する。プロセス全体を書き換えないため、
            # 別のキーで並行実行されても混ざらない。
            with use_judge(self.api_key, self.judge_config):
                try:
                    return await evaluator.evaluate_batch_async_with_progress(
                        input_examples=inputs,
                        generate_results=generate_results,
                        progress_callback=_print_progress,
                    )
                finally:
                    # ClientSession はこのイベントループに束縛されるため、
                    # ループを抜ける前に解放する（次回実行での再利用事故を防ぐ）
                    await close_global_client()

        outputs = asyncio.run(_evaluate_all())

        # メトリクス計算
        metrics = calculate_meeting_metrics(outputs)

        details = [
            {
                "id": output.id,
                "instruction_id_list": output.instruction_id_list,
                "follow_all_instructions": output.follow_all_instructions,
                "follow_instruction_list": output.follow_instruction_list,
                "error_details": output.error_details,
                # 指示ごとの判定内訳。LLM judge の判定理由を残さないと
                # 「なぜその点数なのか」を後から検証できない。
                "checks": [
                    {
                        "instruction_id": check.instruction_id,
                        "score": check.score,
                        "error_message": check.error_message,
                        "judges": [
                            {"score": judge.score, "reason": judge.reason} for judge in (check.judges or [])
                        ],
                    }
                    for check in output.check_following_results
                ],
            }
            for output in outputs
        ]

        zero_details: List[Dict] = []
        if failed_as_zero:
            zero_details = self._zero_details_for_unanswered(
                inputs,
                {str(r.id) for r in generate_results.results},
                "生成失敗: 応答が得られなかったため不合格として集計",
            )
        if zero_details:
            print(
                f"\n応答なしを不合格として集計: {len(zero_details)}件 "
                f"({', '.join(d['id'] for d in zero_details)})"
            )
            by_id = {str(d["id"]): d for d in details}
            by_id.update({str(d["id"]): d for d in zero_details})
            details = [by_id[str(ex.id)] for ex in inputs.examples if str(ex.id) in by_id]
            # 応答が無い分の execution_time は存在しない。0 を混ぜると最小値が 0 になって
            # 実測に見えるため、性能統計は実際に採点した分だけの値を残す。
            perf = metrics.get("performance_stats")
            metrics = calculate_meeting_metrics(self._outputs_for_metrics(details))
            metrics["performance_stats"] = perf

        evaluation_time = time.time() - start_time
        print(f"\n評価完了: {evaluation_time:.2f}秒")

        # 結果を保存
        eval_results = {
            "timestamp": datetime.now().isoformat(),
            "model": self.model,
            "num_examples": len(inputs),
            # 生成失敗をどう扱ったかを必ず残す。母数が違うスコアが並んだときに
            # 「除外されたのか、不合格として数えたのか」を後から判別できないため。
            "generation": {
                "attempted": len(inputs),
                "succeeded": len(generate_results),
                "failed": len(self.generation_failures),
                "failed_ids": [str(i) for i, _ in self.generation_failures],
                "failed_counted_as_zero": bool(failed_as_zero),
            },
            "judge_model": self.judge_config.model,
            # 応答本文は responses ファイル側にある。後から突き合わせられるよう参照を残す。
            "responses_file": os.path.basename(self.response_file),
            "metrics": metrics,
            "details": details,
        }

        with open(self.eval_results_file, "w", encoding="utf-8") as f:
            json.dump(eval_results, f, ensure_ascii=False, indent=2)

        print(f"評価結果を保存: {self.eval_results_file}")

        return eval_results

    @staticmethod
    def _zero_details_for_unanswered(
        inputs: MeetingInputExamples, answered_ids: set, reason: str
    ) -> List[Dict]:
        """応答が得られなかった例を「全指示に従えなかった」として集計に含める。

        生成失敗を採点対象から外すと、その例だけ母数から消える。長考で予算を使い切って
        答えを出せないモデルほど、答えられなかった問題が採点されずに有利になる。
        「予算内に答えを出せなかった＝指示に従えなかった」と扱って母数に残す。

        judge は呼ばない（採点する応答が存在しないため）。
        """
        details = []
        for ex in inputs.examples:
            if str(ex.id) in answered_ids:
                continue
            details.append(
                {
                    "id": str(ex.id),
                    "instruction_id_list": list(ex.instruction_id_list),
                    "follow_all_instructions": False,
                    "follow_instruction_list": [0.0] * len(ex.instruction_id_list),
                    "error_details": [reason],
                    "checks": [],
                    # 判定によるものではなく応答欠落によるものだと後から分かるようにする
                    "unanswered": True,
                }
            )
        return details

    @staticmethod
    def _outputs_for_metrics(details: List[Dict]) -> List[MeetingOutputExample]:
        """保存済みの details からメトリクス計算用のオブジェクトを組み立てる。

        calculate_meeting_metrics が見るのは follow_all_instructions /
        follow_instruction_list / instruction_id_list / error_details / execution_time だけで、
        prompt・response・check_following_results は参照しない（それらは別の
        シリアライズ関数が使う）。保存されていない execution_time だけは復元できないため、
        性能統計は呼び出し側で元の値に差し替える。
        """
        return [
            MeetingOutputExample(
                id=d["id"],
                instruction_id_list=d["instruction_id_list"],
                prompt="",
                response="",
                follow_all_instructions=d["follow_all_instructions"],
                follow_instruction_list=d["follow_instruction_list"],
                check_following_results=[],
                execution_time=0.0,
                error_details=d.get("error_details"),
            )
            for d in details
        ]

    def judge_missing(
        self,
        inputs: MeetingInputExamples,
        generate_results: GenerateResults,
        base_eval_file: str,
        failed_as_zero: bool = False,
        rejudge_ids: List[str] | None = None,
    ) -> Dict:
        """既存の評価結果に無い id だけを採点し、マージした評価結果を返す。

        欠損応答を作り直したあとにモデル全体を採点し直すと、判定済みの分まで judge を
        呼ぶことになる（1件あたり指示数×3回）。既存の判定は id 単位で独立しているので、
        足りない id だけを採点して合流させれば足りる。

        Args:
            inputs: 入力例（全件）
            generate_results: 応答（マージ済み）
            base_eval_file: 流用する既存の eval_results_*.json
            failed_as_zero: 応答が無い例を不合格(0点)として母数に含める
            rejudge_ids: 流用せず採点し直す id。チェッカーを直したときに使う。

        Returns:
            マージ後の評価結果の辞書
        """
        with open(base_eval_file, encoding="utf-8") as f:
            base = json.load(f)
        base_details = base.get("details", [])

        rejudge = {str(i) for i in (rejudge_ids or [])}
        if rejudge:
            before = len(base_details)
            base_details = [d for d in base_details if str(d["id"]) not in rejudge]
            print(f"採点し直す ID: {', '.join(sorted(rejudge))}（流用対象から除外: {before - len(base_details)}件）")

        judged_ids = {str(d["id"]) for d in base_details}

        pending = [r for r in generate_results.results if str(r.id) not in judged_ids]

        print("\n=== 差分採点 ===")
        print(f"流用する評価結果: {base_eval_file} ({len(base_details)}件)")
        print(f"応答: {len(generate_results)}件 / 未採点: {len(pending)}件")

        base_nulls = sum(
            1 for d in base_details for s in d.get("follow_instruction_list", []) if s is None
        )
        print(f"流用元の評価不可: {base_nulls}件")

        new_details: List[Dict] = []
        if pending:
            pending_ids = {str(r.id) for r in pending}
            print(f"採点する ID: {', '.join(sorted(pending_ids))}")
            sub_inputs = inputs.model_copy(
                update={"examples": [ex for ex in inputs.examples if str(ex.id) in pending_ids]}
            )
            sub_results = GenerateResults(
                model_name=generate_results.model_name,
                dataset_name=generate_results.dataset_name,
                results=pending,
            )
            # evaluate_responses は self.eval_results_file に「差分だけ」を書く。
            # このあと同じパスをマージ結果で上書きする。
            new_details = self.evaluate_responses(sub_inputs, sub_results).get("details", [])
        else:
            print("未採点の応答はありません。既存の判定だけで集計し直します。")

        answered = {str(r.id) for r in generate_results.results}

        zero_details: List[Dict] = []
        if failed_as_zero:
            zero_details = self._zero_details_for_unanswered(
                inputs, answered, "生成失敗: 応答が得られなかったため不合格として集計"
            )
            if zero_details:
                print(
                    f"応答なしを不合格として集計: {len(zero_details)}件 "
                    f"({', '.join(d['id'] for d in zero_details)})"
                )

        # 入力の並び順でマージする
        by_id = {str(d["id"]): d for d in base_details}
        by_id.update({str(d["id"]): d for d in new_details})
        by_id.update({str(d["id"]): d for d in zero_details})
        merged_details = [by_id[str(ex.id)] for ex in inputs.examples if str(ex.id) in by_id]

        metrics = calculate_meeting_metrics(self._outputs_for_metrics(merged_details))
        # execution_time は details に保存されていないので復元できない。
        # 0 埋めの数字を残すと実測値に見えてしまうため、元の値を引き継ぐ。
        metrics["performance_stats"] = base.get("metrics", {}).get("performance_stats")

        missing_ids = [str(ex.id) for ex in inputs.examples if str(ex.id) not in answered]

        eval_results = {
            "timestamp": datetime.now().isoformat(),
            "model": self.model,
            "num_examples": len(inputs),
            "generation": {
                "attempted": len(inputs),
                "succeeded": len(generate_results),
                "failed": len(missing_ids),
                "failed_ids": missing_ids,
                # 生成失敗を母数から外したか、不合格として残したか。
                # これを書き残さないと、件数の違うスコアが並んだときに判別できない。
                "failed_counted_as_zero": bool(failed_as_zero),
            },
            "judge_model": self.judge_config.model,
            "responses_file": os.path.basename(self.response_file),
            # 何を流用して何を足したのかを残す。全件採点の結果と取り違えないため。
            "judge_merge": {
                "base_eval_results": os.path.basename(base_eval_file),
                "reused": len(base_details),
                "newly_judged": len(new_details),
                "newly_judged_ids": sorted(str(d["id"]) for d in new_details),
                "rejudged_ids": sorted(rejudge),
                "note": "performance_stats は流用元の値。execution_time は details に保存されないため再計算できない。",
            },
            "metrics": metrics,
            "details": merged_details,
        }

        with open(self.eval_results_file, "w", encoding="utf-8") as f:
            json.dump(eval_results, f, ensure_ascii=False, indent=2)

        nulls = sum(
            1 for d in merged_details for s in d.get("follow_instruction_list", []) if s is None
        )
        print(f"\nマージ後: {len(merged_details)}件 / 評価不可 {nulls}件")
        print(f"評価結果を保存: {self.eval_results_file}")

        return eval_results

    def generate_summary(self, eval_results: Dict) -> None:
        """評価サマリーの生成

        Args:
            eval_results: 評価結果の辞書
        """
        print("\n=== サマリー生成 ===")

        metrics = eval_results["metrics"]

        def _pct(value) -> str:
            """精度は評価不可のとき None になりうるので、そのまま書式化せず明示する"""
            return f"{value:.2%}" if isinstance(value, (int, float)) else "評価不可 (N/A)"

        # 生成が全滅した場合など、評価対象が0件だとメトリクスが計算されない
        if "error" in metrics:
            gen = eval_results.get("generation") or {}
            summary_text = "\n".join(
                [
                    "=" * 60,
                    "jMeet-Eval 評価サマリー",
                    "=" * 60,
                    f"実行日時: {eval_results['timestamp']}",
                    f"使用モデル: {eval_results['model']}",
                    f"採点モデル: {eval_results.get('judge_model', '-')}",
                    "",
                    f"[エラー] 評価対象が0件のためメトリクスを算出できません: {metrics['error']}",
                    f"生成成功: {gen.get('succeeded', '?')}/{gen.get('attempted', '?')}"
                    f" (生成失敗: {gen.get('failed', '?')})",
                    "=" * 60,
                ]
            )
            with open(self.summary_file, "w", encoding="utf-8") as f:
                f.write(summary_text)
            print(summary_text)
            return

        summary_lines = [
            "=" * 60,
            "jMeet-Eval 評価サマリー",
            "=" * 60,
            f"実行日時: {eval_results['timestamp']}",
            f"使用モデル: {eval_results['model']}",
            f"採点モデル: {eval_results.get('judge_model', '-')}",
            f"評価例数: {eval_results['num_examples']}",
            *(
                [f"生成成功: {gen['succeeded']}/{gen['attempted']} (生成失敗 {gen['failed']} 件は採点の母数から除外)"]
                if (gen := eval_results.get("generation")) and gen["failed"]
                else []
            ),
            "",
            "【全体メトリクス】",
            f"プロンプトレベル精度: {_pct(metrics['prompt_level_strict_accuracy'])} ({metrics['prompt_level_breakdown']})",  # noqa: E501
            f"指示レベル精度: {_pct(metrics['instruction_level_strict_accuracy'])} ({metrics['instruction_level_breakdown']})",  # noqa: E501
            "",
            "【詳細統計】",
            f"評価対象プロンプト数: {metrics['valid_prompts']}/{metrics['total_prompts']} (評価不可: {metrics['null_prompts']})",  # noqa: E501
            f"評価対象指示数: {metrics['valid_instructions']}/{metrics['total_instructions']} (評価不可: {metrics['null_instructions']})",  # noqa: E501
            "",
            "【カテゴリ別精度】",
        ]

        # カテゴリ別精度
        category_metrics = [
            (k, v)
            for k, v in metrics.items()
            if k.endswith("_accuracy") and not k.startswith(("prompt_level", "instruction_level"))
        ]

        for category, accuracy in sorted(category_metrics):
            category_name = category.replace("_accuracy", "")
            summary_lines.append(f"{category_name}: {accuracy:.2%}")

        # エラーパターン分析
        error_count = sum(1 for detail in eval_results["details"] if detail["follow_all_instructions"] is False)
        null_count = sum(1 for detail in eval_results["details"] if detail["follow_all_instructions"] is None)

        summary_lines.extend(
            [
                "",
                "【エラー分析】",
                f"失敗例数: {error_count}/{eval_results['num_examples']}",
                f"評価不可例数: {null_count}/{eval_results['num_examples']}",
                "",
            ]
        )

        # Null統計の詳細
        if metrics.get("null_statistics", {}).get("instruction_null_details"):
            summary_lines.append("評価不可の指示詳細:")
            for inst_id, count in metrics["null_statistics"]["instruction_null_details"].items():
                summary_lines.append(f"  {inst_id}: {count}回")
            summary_lines.append("")

        # 失敗した例の詳細
        if error_count > 0:
            summary_lines.append("失敗した例:")
            for detail in eval_results["details"]:
                if detail["follow_all_instructions"] is False:
                    summary_lines.append(f"  ID {detail['id']}: {detail['instruction_id_list']}")

        # 評価不可の例の詳細
        if null_count > 0:
            summary_lines.append("評価不可の例:")
            for detail in eval_results["details"]:
                if detail["follow_all_instructions"] is None:
                    summary_lines.append(f"  ID {detail['id']}: {detail['instruction_id_list']}")

        summary_lines.extend(
            [
                "",
                "=" * 60,
                f"応答ファイル: {self.response_file}",
                f"評価結果ファイル: {self.eval_results_file}",
                f"サマリーファイル: {self.summary_file}",
                "=" * 60,
            ]
        )

        # サマリーを保存
        summary_text = "\n".join(summary_lines)
        with open(self.summary_file, "w", encoding="utf-8") as f:
            f.write(summary_text)

        # コンソールに出力
        print(summary_text)

    def _save_usage_summary(self) -> None:
        """API使用量（トークン数）をコンソール出力し、JSONファイルに保存する"""
        print(f"\n{usage_tracker.format_summary()}")
        with open(self.usage_file, "w", encoding="utf-8") as f:
            json.dump(usage_tracker.get_summary(), f, ensure_ascii=False, indent=2)
        print(f"使用量を保存: {self.usage_file}")

    def run(
        self,
        num_examples: int = -1,
        responses_file: str | None = None,
        generate_only: bool = False,
        regen_missing: str | None = None,
        judge_missing: str | None = None,
        failed_as_zero: bool = False,
        rejudge_ids: List[str] | None = None,
    ) -> Dict:
        """パイプライン実行

        Args:
            num_examples: 評価する例の数（-1で全て）
            responses_file: 既存の応答ファイルパス。指定時は応答生成をスキップ。
            generate_only: True の場合、応答生成のみ実行し評価はスキップ（judge API不要）。
            regen_missing: 既存の応答ファイルパス。欠けている id だけを生成し直してマージする。
            judge_missing: 既存の評価結果パス。まだ採点されていない id だけを採点してマージする。
            failed_as_zero: 応答が得られなかった例を不合格(0点)として母数に含める。
            rejudge_ids: judge_missing 使用時、流用せず採点し直す id。

        Returns:
            評価結果の辞書（generate_only=True の場合は空の辞書）
        """
        print(f"\n{'=' * 60}")
        print("jMeet-Eval Pipeline 開始")
        print(f"{'=' * 60}")

        total_start_time = time.time()

        try:
            # 1. データ読み込み
            inputs = self.load_input_data(num_examples)

            # 2. 応答生成（非同期並列）または既存ファイルから読み込み
            if regen_missing:
                generate_results = self.regenerate_missing(inputs, regen_missing)
            elif responses_file:
                print(f"\n=== 応答ファイルを読み込み: {responses_file} ===")
                generate_results = GenerateResults.load(Path(responses_file))
                print(f"読み込んだ応答: {len(generate_results.results)}件")
                self.response_file = responses_file
            else:
                generate_results = self.generate_responses(inputs)

            if generate_only:
                total_time = time.time() - total_start_time
                print(f"\n--generate_only 指定のため評価をスキップします。総実行時間: {total_time:.2f}秒")
                self._save_usage_summary()
                return {}

            # 3. 評価実行（非同期並列）
            if judge_missing:
                eval_results = self.judge_missing(
                    inputs,
                    generate_results,
                    judge_missing,
                    failed_as_zero=failed_as_zero,
                    rejudge_ids=rejudge_ids,
                )
            else:
                eval_results = self.evaluate_responses(
                    inputs, generate_results, failed_as_zero=failed_as_zero
                )

            # 4. サマリー生成
            self.generate_summary(eval_results)

            # 5. TSV結果ファイルに追記
            tsv_path = os.path.join(self.output_dir, "results.tsv")
            format_eval_results(self.eval_results_file, tsv_path)

            total_time = time.time() - total_start_time
            print(f"\n総実行時間: {total_time:.2f}秒")

            self._save_usage_summary()

            return eval_results

        except Exception as e:
            print(f"\nパイプライン実行中にエラーが発生しました: {e}")
            raise


def main():
    """メイン関数"""
    parser = argparse.ArgumentParser(description="jMeet-Eval エンドツーエンド評価パイプライン")

    parser.add_argument(
        "--model",
        type=str,
        default="gpt-5-mini",
        help="使用するモデル名（OPENAI_BASE_URLのOpenAI互換エンドポイントで利用可能なモデル）",
    )

    parser.add_argument("--num_examples", type=int, default=-1, help="評価する例の数（-1で全て、デフォルト: 全て）")

    parser.add_argument("--verbose", action="store_true", help="詳細ログを出力")

    parser.add_argument(
        "--transcripts",
        type=str,
        default="data/transcripts.jsonl",
        help="文字起こしファイル (transcripts.jsonl or hf://username/dataset)",
    )

    parser.add_argument(
        "--instructions",
        type=str,
        default="data/instructions.jsonl",
        help="指示ファイル (instructions.jsonl) ※ローカルファイルの場合は必須",
    )

    parser.add_argument(
        "--output_dir",
        type=str,
        default="data/output",
        help="出力ディレクトリ (default: data/output)",
    )

    parser.add_argument(
        "--max_concurrent",
        type=int,
        default=10,
        help="応答生成の最大同時実行数 (default: 10)",
    )

    parser.add_argument(
        "--responses-file",
        type=str,
        default=None,
        help="既存の応答ファイルパス。指定時は応答生成をスキップして評価のみ実行。",
    )

    parser.add_argument(
        "--generate_only",
        action="store_true",
        help="応答生成のみ実行し評価をスキップ（judge APIが利用不可な場合に使用）。",
    )

    parser.add_argument(
        "--regen-missing",
        type=str,
        default=None,
        help=(
            "既存の応答ファイルパス。そこに欠けている id だけを生成し直し、"
            "マージした応答で評価する（生成失敗で縮んだ母数を戻すため）。"
        ),
    )

    parser.add_argument(
        "--judge-missing",
        type=str,
        default=None,
        help=(
            "既存の評価結果ファイル(eval_results_*.json)のパス。そこに無い id だけを採点し、"
            "既存の判定と合流させて集計し直す（応答を足したあとの再採点を差分で済ませるため）。"
        ),
    )

    parser.add_argument(
        "--failed-as-zero",
        action="store_true",
        help=(
            "応答が得られなかった例を不合格(0点)として母数に含める。"
            "既定では採点対象から外れるため、答えを出せなかった例が母数から消えて"
            "モデル間でスコアの母数が揃わなくなる。"
        ),
    )

    parser.add_argument(
        "--rejudge-ids",
        type=str,
        default=None,
        help=(
            "--judge-missing 使用時、既存の判定を流用せず採点し直す id（カンマ区切り）。"
            "チェッカーを直したあと、影響を受けた例だけを測り直すため。"
        ),
    )

    args = parser.parse_args()

    if args.rejudge_ids and not args.judge_missing:
        parser.error("--rejudge-ids には --judge-missing が必要です。")
    if args.regen_missing and args.responses_file:
        parser.error("--regen-missing と --responses-file は同時に指定できません。")
    if args.judge_missing and args.generate_only:
        parser.error("--judge-missing と --generate_only は同時に指定できません。")
    if args.judge_missing and not (args.responses_file or args.regen_missing):
        parser.error("--judge-missing には --responses-file か --regen-missing が必要です。")

    load_dotenv()

    # パイプライン実行
    pipeline = JMeetEvalPipeline(
        model=args.model,
        verbose=args.verbose,
        transcripts_path=args.transcripts,
        instructions_path=args.instructions,
        output_dir=args.output_dir,
        max_concurrent=args.max_concurrent,
    )

    try:
        pipeline.run(
            num_examples=args.num_examples,
            responses_file=args.responses_file,
            generate_only=args.generate_only,
            regen_missing=args.regen_missing,
            judge_missing=args.judge_missing,
            failed_as_zero=args.failed_as_zero,
            rejudge_ids=[i.strip() for i in args.rejudge_ids.split(",") if i.strip()]
            if args.rejudge_ids
            else None,
        )
    except KeyboardInterrupt:
        print("\n\n処理が中断されました。")
        sys.exit(1)
    except Exception as e:
        print(f"\n\nエラー: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
