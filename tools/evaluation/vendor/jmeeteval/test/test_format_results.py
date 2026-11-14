"""N10 回帰テスト: TSVフォールバック集計が評価不可(None)を分母に算入しないこと。

`_compute_category_breakdowns` の details フォールバック経路で、score=None（評価不可）を
0点扱いで分母に入れると、judge 全滅カテゴリが「0.00%」と誤表示される（N10）。
本体メトリクス(meeting_evaluation_lib) と同様、None は分母から除外し、有効0件は結果に含めない
（TSV では "-" 表示）ことを検証する。
"""

from jmeeteval.evaluation.format_results import _compute_category_breakdowns


def test_category_breakdown_excludes_none_from_denominator():
    # metrics に breakdown を置かない → 全カテゴリが details フォールバック経由になる
    data = {
        "metrics": {},
        "details": [
            {
                "instruction_id_list": ["writing_style:number_format", "annotation:ending_note"],
                "follow_instruction_list": [1.0, None],
            },
            {
                "instruction_id_list": ["writing_style:number_format", "annotation:ending_note"],
                "follow_instruction_list": [None, None],
            },
        ],
    }

    result = _compute_category_breakdowns(data)

    # writing_style: [1.0, None] → None は分母除外 → 1/1（旧バグなら 1/2 になる）
    assert result["writing_style"] == (1.0, 1)

    # annotation: [None, None] → 有効0件 → 結果に含めない（TSVでは "-"）
    assert "annotation" not in result
