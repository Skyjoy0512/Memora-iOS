#!/usr/bin/env python3
"""評価結果をExcel貼り付け用TSV形式に整形・追記するスクリプト

使用例:
    # 単体実行
    uv run python format_results.py --input data/output/eval_results_xxx.json

    # 出力先を指定
    uv run python format_results.py --input data/output/eval_results_xxx.json --output results.tsv
"""

import argparse
import json
import os
from collections import defaultdict

# 全カテゴリ（列順）
ALL_CATEGORIES = [
    "writing_style",
    "formatting",
    "emphasis_rules",
    "annotation",
    "table_format",
    "output_constraint",
    "structural_granularity",
    "length_control",
    "template_filling",
    "json_output",
    "language_translation",
    "viewpoint_spec",
    "anonymization",
    "todo_rules",
    "notation_rules",
    "order_spec",
]

HEADER = ["model", "prompt", "Instruction"] + [f"{c}_accuracy" for c in ALL_CATEGORIES]


def _compute_category_breakdowns(data: dict) -> dict[str, tuple[float, int]]:
    """カテゴリごとの (success, total) を返す。

    metrics内のbreakdownを優先し、無いカテゴリはdetailsから集計する。
    """
    metrics = data["metrics"]
    result: dict[str, tuple[float, int]] = {}

    # 1. metricsのbreakdownから取得
    for cat in ALL_CATEGORIES:
        bd_key = f"{cat}_breakdown"
        if bd_key in metrics:
            parts = metrics[bd_key].split("/")
            success = float(parts[0])
            total = int(float(parts[1]))
            if total > 0:
                result[cat] = (success, total)

    # 2. breakdownが無いカテゴリをdetailsから集計
    missing = [c for c in ALL_CATEGORIES if c not in result]
    if missing and "details" in data:
        cat_success: dict[str, float] = defaultdict(float)
        cat_total: dict[str, int] = defaultdict(int)
        for detail in data["details"]:
            for i, inst_id in enumerate(detail["instruction_id_list"]):
                cat = inst_id.split(":")[0]
                if cat in missing:
                    score = detail["follow_instruction_list"][i]
                    # 本体メトリクス(meeting_evaluation_lib)と同様、評価不可(None)は
                    # 分母に入れない（0点扱いにしない）。0.5以上を遵守として二値化する。
                    if score is None:
                        continue
                    cat_total[cat] += 1
                    if score >= 0.5:
                        cat_success[cat] += 1
        for cat in missing:
            if cat_total[cat] > 0:
                result[cat] = (cat_success[cat], cat_total[cat])

    return result


def format_eval_results(eval_results_path: str, output_tsv: str = "results.tsv") -> str:
    """評価結果JSONをTSVに整形し、ファイルに追記する。

    Args:
        eval_results_path: eval_results_*.json のパス
        output_tsv: 出力TSVファイルパス

    Returns:
        追記したデータ行
    """
    with open(eval_results_path, encoding="utf-8") as f:
        data = json.load(f)

    metrics = data["metrics"]
    model = data.get("model", "unknown")

    # prompt / instruction level
    prompt_acc = metrics["prompt_level_strict_accuracy"]
    prompt_bd = metrics["prompt_level_breakdown"]
    inst_acc = metrics["instruction_level_strict_accuracy"]
    inst_bd = metrics["instruction_level_breakdown"]

    def _fmt(acc, breakdown):
        # 全件評価不可の場合、accuracyはNoneになる
        if acc is None:
            return f"-({breakdown})"
        return f"{acc * 100:.2f}%({breakdown})"

    row = [
        model,
        _fmt(prompt_acc, prompt_bd),
        _fmt(inst_acc, inst_bd),
    ]

    # カテゴリ別
    breakdowns = _compute_category_breakdowns(data)
    for cat in ALL_CATEGORIES:
        if cat in breakdowns:
            success, total = breakdowns[cat]
            acc = success / total * 100
            row.append(f"{acc:.2f}%({success}/{total})")
        else:
            row.append("-")

    data_line = "\t".join(row)

    # ファイル書き込み
    file_exists = os.path.exists(output_tsv)
    with open(output_tsv, "a", encoding="utf-8") as f:
        if not file_exists:
            f.write("\t".join(HEADER) + "\n")
        f.write(data_line + "\n")

    print(f"結果を追記: {output_tsv}")
    return data_line


def main():
    parser = argparse.ArgumentParser(description="評価結果をTSV形式に整形")
    parser.add_argument("--input", required=True, help="eval_results_*.json のパス")
    parser.add_argument("--output", default="results.tsv", help="出力TSVファイル (default: results.tsv)")
    args = parser.parse_args()

    format_eval_results(args.input, args.output)


if __name__ == "__main__":
    main()
