#!/usr/bin/env python3
# coding=utf-8

"""
jMeet-Eval: 会議特化AIモデルの応答を生成してinput_response_data.jsonlを作成するスクリプト

使用例:
# ローカルファイル（新フォーマット：指示ファイル + 文字起こしファイル）
python generate_meeting_responses.py \
  --transcripts=data/transcripts.jsonl \
  --instructions=data/instructions.jsonl \
  --output=data/jmeet_response_data.jsonl \
  --model=gpt-5-mini

# Hugging Faceデータセットから読み込む場合（分割フォーマット）
python generate_meeting_responses.py \
  --transcripts=hf://<org>/<dataset-name> \
  --output=data/jmeet_response_data.json \
  --model=gpt-5-mini

サポートするモデル:
- OPENAI_BASE_URL で指定した OpenAI 互換エンドポイント（OpenAI API / vLLM / Ollama 等）で
  利用可能な任意のモデル
"""

import argparse
import asyncio
import logging
import sys
from pathlib import Path

from jmeeteval.core.model import GenerateResult, GenerateResults, MeetingInputExample, MeetingInputExamples
from jmeeteval.generate.response_generator import RequestConfig, ResponseGeneratorFactory, close_shared_client

# ログ設定
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)


async def process_item(
    item: MeetingInputExample,
    model_name: str,
    request_config: RequestConfig,
    index: int,
    total: int,
    semaphore: asyncio.Semaphore,
) -> GenerateResult:
    """個別アイテムを処理する非同期関数"""
    async with semaphore:
        try:
            logger.info(f"処理中 ({index + 1}/{total}) ID: {item.id}")

            generator = ResponseGeneratorFactory.create_generator(model_name, item.summarize_method)
            result = await generator.generate_response(item, request_config)

            logger.info(f"✅ 完了 ID {item.id}: {len(result.final_response)}文字の会議応答を生成")

            return GenerateResult(
                id=item.id, prompt_for_evaluation=result.prompt_for_evaluation, response=result.final_response
            )
        except Exception as e:
            logger.error(f"❌ 失敗 ID {item.id}: {e}")
            raise


async def main():
    parser = argparse.ArgumentParser(
        description="jMeet-Eval: 会議特化AIモデルの応答を生成してinput_response_data.jsonlを作成",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用例:
  # ローカルファイル（新フォーマット：指示ファイル + 文字起こしファイル）
  python generate_meeting_responses.py \\
    --transcripts=data/transcripts.jsonl \\
    --instructions=data/instructions.jsonl \\
    --output=data/jmeet_response_data.jsonl \\
    --model=gpt-5-mini

  # Hugging Faceデータセットから応答生成（分割フォーマット）
  python generate_meeting_responses.py \\
    --transcripts=hf://<org>/<dataset-name> \\
    --output=data/jmeet_response_data.json \\
    --model=gpt-5-mini

環境変数:
  OPENAI_API_KEY    - OpenAI APIキー
  OPENAI_BASE_URL   - OpenAI APIベースURL
        """,
    )

    parser.add_argument(
        "--transcripts", required=True, help="文字起こしファイル (transcripts.jsonl or hf://username/dataset)"
    )
    parser.add_argument(
        "--instructions", default=None, help="指示ファイル (instructions.jsonl) ※ローカルファイルの場合は必須"
    )
    parser.add_argument("--output", required=True, help="出力ファイル (input_response_data.jsonl)")
    parser.add_argument("--model", required=True, help="使用するモデル名（OpenAI互換エンドポイントで利用可能なモデル）")
    parser.add_argument("--max_items", type=int, default=None, help="処理する最大項目数 (default: 全件)")
    parser.add_argument("--start_from", type=int, default=0, help="開始項目番号 (default: 0)")
    parser.add_argument("--max_tokens", type=int, default=32000, help="生成の最大トークン数 (default: 32000)")
    parser.add_argument(
        "--temperature",
        type=float,
        default=0.7,
        help="生成の温度パラメータ (default: 0.7 = 掲載ベースラインの測定条件。再現性重視なら0.0を指定)",
    )
    parser.add_argument("--concurrency", type=int, default=5, help="並列実行数 (default: 5)")
    parser.add_argument(
        "--reasoning_effort",
        default="low",
        choices=["minimal", "low", "medium", "high"],
        help="推論モデル(gpt-5/o系)の推論の深さ (default: low)",
    )
    parser.add_argument(
        "--reasoning_max_completion_tokens",
        type=int,
        default=32000,
        help="推論モデル(gpt-5/o系)の最大完了トークン数。推論トークン込みの予算 (default: 32000)",
    )

    args = parser.parse_args()
    output_path = Path(args.output)
    if not output_path.parent.exists():
        output_path.parent.mkdir(parents=True, exist_ok=True)

    # 1. 入力データを読み込み
    logger.info("=== jMeet-Eval 応答生成開始 ===")
    meeting_inputs = MeetingInputExamples.load_auto(
        transcripts_path=args.transcripts,
        instructions_path=args.instructions,
    )

    # 処理範囲を制限（--start_from は --max_items の指定有無に関わらず効く）
    if args.start_from or args.max_items is not None:
        if args.start_from >= len(meeting_inputs):
            parser.error(f"--start_from={args.start_from} は全{len(meeting_inputs)}件の範囲外です")
        if args.max_items is None:
            end_index = len(meeting_inputs)
        else:
            if args.max_items <= 0:
                parser.error(f"--max_items は1以上を指定してください（指定値: {args.max_items}）")
            end_index = min(args.start_from + args.max_items, len(meeting_inputs))
        meeting_inputs = meeting_inputs.get_range(args.start_from, end_index)
        logger.info(f"処理範囲: {args.start_from} - {end_index - 1} ({len(meeting_inputs)}件)")

    total_items = len(meeting_inputs)
    request_config = RequestConfig(
        max_tokens=args.max_tokens,
        temperature=args.temperature,
        reasoning_effort=args.reasoning_effort,
        reasoning_max_completion_tokens=args.reasoning_max_completion_tokens,
    )

    # 2. 全てのアイテムを並列処理（並列数を制限）
    semaphore = asyncio.Semaphore(args.concurrency)
    logger.info(f"並列実行数: {args.concurrency}")

    tasks = [
        process_item(item, args.model, request_config, i, total_items, semaphore)
        for i, item in enumerate(meeting_inputs.examples)
    ]

    try:
        results = await asyncio.gather(*tasks, return_exceptions=True)
    finally:
        await close_shared_client()

    # 3. エラーと成功を分離
    successful_results = []
    failures: list[tuple[str, BaseException]] = []
    for item, result in zip(meeting_inputs.examples, results):
        if isinstance(result, BaseException):
            failures.append((item.id, result))
        else:
            successful_results.append(result)

    # 4. 結果を保存
    generate_results = GenerateResults(
        model_name=args.model, dataset_name=Path(args.transcripts).name, results=successful_results
    )
    generate_results.save(output_path)

    logger.info("=== jMeet-Eval 応答生成完了 ===")
    logger.info(f"成功:{len(successful_results)}/{total_items}")
    logger.info(f"出力ファイル: {output_path}")

    if failures:
        # 欠損したまま「成功」扱いで後段に流さないよう、内容をログに残し非ゼロ終了する
        logger.error(f"失敗:{len(failures)}/{total_items}")
        for item_id, exc in failures:
            logger.error(f"  失敗 ID {item_id}: {type(exc).__name__}: {exc}")
        failed_ids_path = output_path.with_name(f"{output_path.stem}_failed_ids.txt")
        failed_ids_path.write_text("\n".join(item_id for item_id, _ in failures), encoding="utf-8")
        logger.error(f"失敗IDの一覧: {failed_ids_path}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
