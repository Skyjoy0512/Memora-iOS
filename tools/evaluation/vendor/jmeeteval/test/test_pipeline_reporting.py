# coding=utf-8
"""パイプラインのレポート出力のテスト

生成失敗は評価対象から除外されるため、そのぶん採点の母数が縮む。
母数の縮小が結果に必ず残ること、および評価対象0件でも落ちないことを保証する。
"""

import pytest

from jmeet_eval_pipeline import JMeetEvalPipeline


@pytest.fixture
def pipeline(tmp_path):
    return JMeetEvalPipeline(model="test-model", output_dir=str(tmp_path / "out"))


def read_summary(pipeline) -> str:
    with open(pipeline.summary_file, encoding="utf-8") as f:
        return f.read()


BASE_METRICS = {
    "prompt_level_strict_accuracy": 0.5,
    "prompt_level_breakdown": "1/2",
    "instruction_level_strict_accuracy": 0.75,
    "instruction_level_breakdown": "3/4",
    "valid_prompts": 2,
    "total_prompts": 2,
    "null_prompts": 0,
    "valid_instructions": 4,
    "total_instructions": 4,
    "null_instructions": 0,
}


def make_eval_results(metrics=None, generation=None):
    return {
        "timestamp": "2026-07-20T00:00:00",
        "model": "test-model",
        "judge_model": "gpt-5-mini",
        "num_examples": 2,
        "generation": generation or {"attempted": 2, "succeeded": 2, "failed": 0, "failed_ids": []},
        "metrics": metrics if metrics is not None else dict(BASE_METRICS),
        "details": [],
    }


class TestGenerationFailureVisibility:
    """生成失敗による母数縮小が隠れないこと"""

    def test_summary_reports_generation_failures(self, pipeline):
        results = make_eval_results(
            generation={"attempted": 10, "succeeded": 7, "failed": 3, "failed_ids": ["1", "2", "3"]}
        )

        pipeline.generate_summary(results)
        summary = read_summary(pipeline)

        assert "生成成功: 7/10" in summary
        assert "母数から除外" in summary

    def test_summary_omits_line_when_no_failures(self, pipeline):
        pipeline.generate_summary(make_eval_results())

        assert "生成成功" not in read_summary(pipeline)

    def test_judge_model_is_recorded(self, pipeline):
        pipeline.generate_summary(make_eval_results())

        assert "採点モデル: gpt-5-mini" in read_summary(pipeline)


class TestDegradedSummary:
    """メトリクスが算出できない場合でも落ちない"""

    def test_no_output_examples_does_not_crash(self, pipeline):
        """生成が全滅すると評価対象が0件になり、metrics が error だけになる"""
        results = make_eval_results(
            metrics={"error": "No output examples provided"},
            generation={"attempted": 2, "succeeded": 0, "failed": 2, "failed_ids": ["1", "2"]},
        )

        pipeline.generate_summary(results)
        summary = read_summary(pipeline)

        assert "評価対象が0件" in summary
        assert "生成成功: 0/2" in summary

    def test_null_accuracy_is_rendered_as_na(self, pipeline):
        """全件評価不可だと精度が None になる（書式化で落ちない）"""
        metrics = dict(BASE_METRICS)
        metrics["prompt_level_strict_accuracy"] = None
        metrics["instruction_level_strict_accuracy"] = None

        pipeline.generate_summary(make_eval_results(metrics=metrics))
        summary = read_summary(pipeline)

        assert "評価不可 (N/A)" in summary


class TestReasoningConfig:
    """推論モデル向け生成パラメータの既定値と環境変数"""

    def test_defaults(self, pipeline):
        assert pipeline.reasoning_effort == "low"
        assert pipeline.reasoning_max_completion_tokens == 32000

    def test_env_override(self, tmp_path, monkeypatch):
        monkeypatch.setenv("JMEETEVAL_REASONING_EFFORT", "minimal")
        monkeypatch.setenv("JMEETEVAL_REASONING_MAX_COMPLETION_TOKENS", "2000")

        p = JMeetEvalPipeline(model="gpt-5-mini", output_dir=str(tmp_path / "out2"))

        assert p.reasoning_effort == "minimal"
        assert p.reasoning_max_completion_tokens == 2000
