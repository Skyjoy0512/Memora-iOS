# coding=utf-8
"""評価側のスコアリング挙動のテスト

- チェッカー / LLM judge に渡す `document` が「元の文字起こし」であること
  （プロンプト全文を渡すと ProportionChecker の分母が指示文ぶん膨張する）
- `follow_all_instructions` が評価不可を含む場合に None になること
"""

import pytest

from jmeeteval.core.meeting_instructions import CheckFollowingResult
from jmeeteval.core.model import MeetingInputExample
from jmeeteval.evaluation.meeting_evaluation_lib import MeetingEvaluator, calculate_meeting_metrics

TRANSCRIPT = "本日の定例会議を開始します。売上は好調でした。"
# 指示文を大量に含む「プロンプト全文」。document に誤ってこちらが渡ると長さが大きく変わる
PROMPT = "# 指示\n" + "- 指示文がここに入る。\n" * 50 + f"\n# 入力テキスト\n{TRANSCRIPT}\n"


def make_example(instruction_ids, kwargs_list=None):
    return MeetingInputExample(
        id="test-1",
        instruction_id_list=instruction_ids,
        instruction_texts=["指示"] * len(instruction_ids),
        transcript=TRANSCRIPT,
        summarize_method="default",
        instruction_kwargs=kwargs_list or [{} for _ in instruction_ids],
    )


class SpyChecker:
    """check_following が受け取った document を記録するスタブ"""

    received_documents: list[str] = []
    score: float | None = 1.0

    def __init__(self, instruction_id):
        self.instruction_id = instruction_id
        self._cached_kwargs = None

    async def check_following(self, document: str, response: str) -> CheckFollowingResult:
        type(self).received_documents.append(document)
        return CheckFollowingResult(instruction_id=self.instruction_id, score=type(self).score)


def make_checker(score_value):
    """指定スコアを返すチェッカークラスを生成する"""

    class _Checker(SpyChecker):
        received_documents: list[str] = []
        score = score_value

    return _Checker


@pytest.fixture
def evaluator():
    return MeetingEvaluator()


class TestDocumentIsTranscript:
    """document には文字起こしを渡す"""

    async def test_checker_receives_transcript_not_full_prompt(self, evaluator):
        checker = make_checker(1.0)
        evaluator.instruction_registry = {"spy:one": checker}

        await evaluator.evaluate_response_async(make_example(["spy:one"]), PROMPT, "応答")

        assert checker.received_documents == [TRANSCRIPT]
        assert PROMPT not in checker.received_documents

    async def test_full_prompt_is_still_recorded_in_output(self, evaluator):
        """出力レコードには従来どおりプロンプト全文が残る"""
        evaluator.instruction_registry = {"spy:one": make_checker(1.0)}

        out = await evaluator.evaluate_response_async(make_example(["spy:one"]), PROMPT, "応答")

        assert out.prompt == PROMPT


class TestFollowAllInstructions:
    """評価不可が混ざった場合の follow_all"""

    async def test_all_followed_is_true(self, evaluator):
        evaluator.instruction_registry = {"spy:a": make_checker(1.0), "spy:b": make_checker(1.0)}

        out = await evaluator.evaluate_response_async(make_example(["spy:a", "spy:b"]), PROMPT, "応答")

        assert out.follow_instruction_list == [1.0, 1.0]
        assert out.follow_all_instructions is True

    async def test_one_violation_is_false(self, evaluator):
        evaluator.instruction_registry = {"spy:a": make_checker(1.0), "spy:b": make_checker(0.0)}

        out = await evaluator.evaluate_response_async(make_example(["spy:a", "spy:b"]), PROMPT, "応答")

        assert out.follow_all_instructions is False

    async def test_partial_null_yields_none_not_true(self, evaluator):
        """1件でも評価不可なら「全遵守」と断定できないので None

        None を単に除外すると、実質1指示しか検証していない例が prompt-level 精度の
        分子に入り、値を押し上げてしまう。
        """
        evaluator.instruction_registry = {"spy:a": make_checker(1.0), "spy:b": make_checker(None)}

        out = await evaluator.evaluate_response_async(make_example(["spy:a", "spy:b"]), PROMPT, "応答")

        assert out.follow_instruction_list == [1.0, None]
        assert out.follow_all_instructions is None

    async def test_all_null_yields_none(self, evaluator):
        evaluator.instruction_registry = {"spy:a": make_checker(None)}

        out = await evaluator.evaluate_response_async(make_example(["spy:a"]), PROMPT, "応答")

        assert out.follow_all_instructions is None

    async def test_unknown_instruction_becomes_null(self, evaluator):
        """未登録の指示IDは例外ではなく評価不可として扱う"""
        evaluator.instruction_registry = {"spy:a": make_checker(1.0)}

        out = await evaluator.evaluate_response_async(make_example(["spy:a", "spy:missing"]), PROMPT, "応答")

        assert out.follow_instruction_list == [1.0, None]
        assert out.follow_all_instructions is None


class TestMetricsBinarization:
    """LLM judge の平均スコア（部分点）の二値化"""

    def _output(self, evaluator_result):
        return calculate_meeting_metrics([evaluator_result])

    async def test_partial_score_below_half_counts_as_failure(self, evaluator):
        """3回中1回のみ合格(0.333)は不合格として数える"""
        evaluator.instruction_registry = {"spy:a": make_checker(1 / 3)}

        out = await evaluator.evaluate_response_async(make_example(["spy:a"]), PROMPT, "応答")
        metrics = self._output(out)

        assert metrics["instruction_level_strict_accuracy"] == 0.0
        assert metrics["successful_instructions"] == 0

    async def test_partial_score_above_half_counts_as_success(self, evaluator):
        """3回中2回合格(0.667)は合格として数える"""
        evaluator.instruction_registry = {"spy:a": make_checker(2 / 3)}

        out = await evaluator.evaluate_response_async(make_example(["spy:a"]), PROMPT, "応答")
        metrics = self._output(out)

        assert metrics["instruction_level_strict_accuracy"] == 1.0
        assert metrics["successful_instructions"] == 1

    async def test_null_is_excluded_from_denominator(self, evaluator):
        evaluator.instruction_registry = {"spy:a": make_checker(None)}

        out = await evaluator.evaluate_response_async(make_example(["spy:a"]), PROMPT, "応答")
        metrics = self._output(out)

        assert metrics["null_instructions"] == 1
        assert metrics["valid_instructions"] == 0
        assert metrics["instruction_level_strict_accuracy"] is None
