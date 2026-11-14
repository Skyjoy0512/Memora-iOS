# coding=utf-8
# Copyright 2026 Nishika, Inc.

"""OrderSpecificationLLMCheckerのテスト"""

from unittest.mock import AsyncMock, patch

import pytest

from jmeeteval.core.meeting_instructions import (
    CheckFollowingResult,
    LLMJudgeResult,
    LLMJudgeRuleChecker,
    OrderSpecificationLLMChecker,
)


class TestLLMJudgeRuleCheckerBuildEvaluationPrompt:
    """LLMJudgeRuleChecker._build_evaluation_promptのテスト"""

    def test_build_evaluation_prompt_default(self):
        """デフォルトの_build_evaluation_promptはresponseのみを含む"""
        checker = LLMJudgeRuleChecker(instruction_id="test_rule")
        checker._cached_kwargs = {"rule_description": "テストルール"}

        document = "元の文字起こしテキスト"
        response = "評価対象テキスト"

        prompt = checker._build_evaluation_prompt(document, response)

        # responseは含まれる
        assert "評価対象テキスト" in prompt
        # documentは含まれない
        assert "元の文字起こしテキスト" not in prompt


class TestOrderSpecificationLLMCheckerBuildEvaluationPrompt:
    """OrderSpecificationLLMChecker._build_evaluation_promptのテスト"""

    def test_build_evaluation_prompt_chronological_includes_document(self):
        """order_type=chronologicalの場合、documentを含むプロンプトを生成"""
        checker = OrderSpecificationLLMChecker(instruction_id="test_order")
        checker._cached_kwargs = {"order_type": "chronological"}

        document = "田中: おはようございます\n山田: おはようございます\n田中: 今日の議題は..."
        response = "1. 挨拶\n2. 議題の確認"

        prompt = checker._build_evaluation_prompt(document, response)

        # documentが含まれる
        assert "田中: おはようございます" in prompt
        assert "元の文字起こし（発言順序の参照用）" in prompt
        # responseも含まれる
        assert "1. 挨拶" in prompt
        assert "評価対象テキスト" in prompt

    def test_build_evaluation_prompt_default_is_chronological(self):
        """_cached_kwargsがNoneの場合、デフォルトでchronologicalとして動作"""
        checker = OrderSpecificationLLMChecker(instruction_id="test_order")
        checker._cached_kwargs = None

        document = "元のテキスト"
        response = "要約テキスト"

        prompt = checker._build_evaluation_prompt(document, response)

        # デフォルトはchronologicalなのでdocumentが含まれる
        assert "元のテキスト" in prompt
        assert "元の文字起こし（発言順序の参照用）" in prompt


class TestOrderSpecificationLLMCheckerCheckFollowing:
    """OrderSpecificationLLMChecker.check_followingの統合テスト"""

    @pytest.fixture
    def mock_llm_response(self):
        """LLMレスポンスをモック"""
        return '{"score": 1, "reason": "時系列順に並んでいます"}'

    @pytest.mark.asyncio
    async def test_check_following_chronological_uses_document(self, mock_llm_response):
        """chronologicalモードでcheck_followingがdocumentを使用することを確認"""
        checker = OrderSpecificationLLMChecker(instruction_id="test_order")
        checker._cached_kwargs = {"order_type": "chronological"}

        document = "A: 最初の発言\nB: 次の発言"
        response = "1. 最初の発言について\n2. 次の発言について"

        with patch("jmeeteval.core.meeting_instructions.get_global_client") as mock_get_client:
            mock_client = AsyncMock()
            mock_client.call.return_value = mock_llm_response
            mock_get_client.return_value = mock_client

            result = await checker.check_following(document, response)

            # LLMが呼び出されたことを確認
            assert mock_client.call.called
            # 呼び出されたプロンプトにdocumentが含まれることを確認
            called_prompt = mock_client.call.call_args[0][0]
            assert "A: 最初の発言" in called_prompt
            assert "元の文字起こし（発言順序の参照用）" in called_prompt

            # 結果の確認
            assert isinstance(result, CheckFollowingResult)
            assert result.instruction_id == "test_order"


class TestOrderSpecificationLLMCheckerGenerateInstruction:
    """OrderSpecificationLLMChecker.generate_instructionのテスト"""

    def test_generate_instruction_chronological(self):
        """chronologicalの指示文生成"""
        checker = OrderSpecificationLLMChecker(instruction_id="test_order")
        instruction = checker.generate_instruction(order_type="chronological")

        assert "発言順" in instruction or "時系列" in instruction

    def test_generate_instruction_invalid_order_type(self):
        """無効なorder_typeの場合はValueErrorが発生"""
        checker = OrderSpecificationLLMChecker(instruction_id="test_order")

        with pytest.raises(ValueError) as excinfo:
            checker.generate_instruction(order_type="unknown")

        assert "無効なorder_type" in str(excinfo.value)


class TestLLMJudgeResultParsing:
    """LLMJudgeRuleChecker._parse_llm_outputのテスト"""

    def test_parse_valid_json(self):
        """有効なJSONをパースできる"""
        checker = LLMJudgeRuleChecker(instruction_id="test_rule")
        llm_output = '{"score": 1, "reason": "ルールに従っています"}'

        result = checker._parse_llm_output(llm_output)

        assert isinstance(result, LLMJudgeResult)
        assert result.score == 1
        assert result.reason == "ルールに従っています"

    def test_parse_json_with_surrounding_text(self):
        """周囲にテキストがあってもJSONを抽出できる"""
        checker = LLMJudgeRuleChecker(instruction_id="test_rule")
        llm_output = '評価結果は以下の通りです：\n{"score": 0, "reason": "ルール違反です"}\n以上です。'

        result = checker._parse_llm_output(llm_output)

        assert isinstance(result, LLMJudgeResult)
        assert result.score == 0
        assert result.reason == "ルール違反です"

    def test_parse_invalid_json_returns_none(self):
        """無効なJSONの場合はNoneを返す"""
        checker = LLMJudgeRuleChecker(instruction_id="test_rule")
        llm_output = "これはJSONではありません"

        result = checker._parse_llm_output(llm_output)

        assert result is None
