# coding=utf-8
# Copyright 2026 Nishika, Inc.

"""WritingStyleLLMCheckerのテスト"""

from unittest.mock import AsyncMock, patch

import pytest

from jmeeteval.core.meeting_instructions import (
    CheckFollowingResult,
    WritingStyleLLMChecker,
)


class TestWritingStyleLLMCheckerGenerateInstruction:
    """WritingStyleLLMChecker.generate_instructionのテスト"""

    def test_generate_instruction_desu_masu(self):
        """です・ます調の指示文生成"""
        checker = WritingStyleLLMChecker(instruction_id="test_style")
        instruction = checker.generate_instruction(style_type="desu_masu")

        assert "です・ます調" in instruction
        assert "評価基準" in instruction

    def test_generate_instruction_de_aru(self):
        """である調の指示文生成"""
        checker = WritingStyleLLMChecker(instruction_id="test_style")
        instruction = checker.generate_instruction(style_type="de_aru")

        assert "である調" in instruction
        assert "評価基準" in instruction

    def test_generate_instruction_invalid_style_type(self):
        """無効なstyle_typeの場合はValueErrorが発生"""
        checker = WritingStyleLLMChecker(instruction_id="test_style")

        with pytest.raises(ValueError) as excinfo:
            checker.generate_instruction(style_type="unknown")

        assert "無効なstyle_type" in str(excinfo.value)


class TestWritingStyleLLMCheckerGetInstructionArgs:
    """WritingStyleLLMChecker.get_instruction_argsのテスト"""

    def test_get_instruction_args(self):
        """get_instruction_argsが正しい引数定義を返す"""
        checker = WritingStyleLLMChecker(instruction_id="test_style")
        args = checker.get_instruction_args()

        assert "style_type" in args
        assert args["style_type"]["type"] == "str"
        assert args["style_type"]["default"] == "desu_masu"
        assert "desu_masu" in args["style_type"]["choices"]
        assert "de_aru" in args["style_type"]["choices"]


class TestWritingStyleLLMCheckerCheckFollowing:
    """WritingStyleLLMChecker.check_followingの統合テスト"""

    @pytest.fixture
    def mock_llm_response_pass(self):
        """合格のLLMレスポンスをモック"""
        return '{"score": 1, "reason": "文体が統一されています"}'

    @pytest.fixture
    def mock_llm_response_fail(self):
        """不合格のLLMレスポンスをモック"""
        return '{"score": 0, "reason": "文体が混在しています"}'

    @pytest.mark.asyncio
    async def test_check_following_desu_masu_pass(self, mock_llm_response_pass):
        """です・ます調のチェックで合格の場合"""
        checker = WritingStyleLLMChecker(instruction_id="test_style")
        checker._cached_kwargs = {"style_type": "desu_masu"}

        document = "会議の議事録"
        response = "本日の会議では重要な決定がありました。参加者は全員同意しています。"

        with patch("jmeeteval.core.meeting_instructions.get_global_client") as mock_get_client:
            mock_client = AsyncMock()
            mock_client.call.return_value = mock_llm_response_pass
            mock_get_client.return_value = mock_client

            result = await checker.check_following(document, response)

            assert mock_client.call.called
            assert isinstance(result, CheckFollowingResult)
            assert result.instruction_id == "test_style"
            assert result.score == 1.0
            assert len(result.judges) == 3

    @pytest.mark.asyncio
    async def test_check_following_de_aru_fail(self, mock_llm_response_fail):
        """である調のチェックで不合格の場合"""
        checker = WritingStyleLLMChecker(instruction_id="test_style")
        checker._cached_kwargs = {"style_type": "de_aru"}

        document = "会議の議事録"
        response = "本日の会議では重要な決定があった。しかし参加者は同意しています。"

        with patch("jmeeteval.core.meeting_instructions.get_global_client") as mock_get_client:
            mock_client = AsyncMock()
            mock_client.call.return_value = mock_llm_response_fail
            mock_get_client.return_value = mock_client

            result = await checker.check_following(document, response)

            assert mock_client.call.called
            assert isinstance(result, CheckFollowingResult)
            assert result.instruction_id == "test_style"
            assert result.score == 0.0

    @pytest.mark.asyncio
    async def test_check_following_uses_response_only(self, mock_llm_response_pass):
        """check_followingがresponseのみを評価に使用することを確認"""
        checker = WritingStyleLLMChecker(instruction_id="test_style")
        checker._cached_kwargs = {"style_type": "desu_masu"}

        document = "元の文字起こしテキスト"
        response = "評価対象のテキストです。"

        with patch("jmeeteval.core.meeting_instructions.get_global_client") as mock_get_client:
            mock_client = AsyncMock()
            mock_client.call.return_value = mock_llm_response_pass
            mock_get_client.return_value = mock_client

            await checker.check_following(document, response)

            called_prompt = mock_client.call.call_args[0][0]
            # responseは含まれる
            assert "評価対象のテキストです" in called_prompt
            # documentは含まれない（文体チェックは出力テキストのみで評価）
            assert "元の文字起こしテキスト" not in called_prompt


class TestWritingStyleLLMCheckerBuildEvaluationPrompt:
    """WritingStyleLLMChecker._build_evaluation_promptのテスト"""

    def test_build_evaluation_prompt_includes_response(self):
        """_build_evaluation_promptがresponseを含むことを確認"""
        checker = WritingStyleLLMChecker(instruction_id="test_style")
        checker._cached_kwargs = {"style_type": "desu_masu"}

        document = "元のテキスト"
        response = "評価対象テキストです。"

        prompt = checker._build_evaluation_prompt(document, response)

        assert "評価対象テキストです" in prompt

    def test_build_evaluation_prompt_excludes_document(self):
        """_build_evaluation_promptがdocumentを含まないことを確認"""
        checker = WritingStyleLLMChecker(instruction_id="test_style")
        checker._cached_kwargs = {"style_type": "desu_masu"}

        document = "元の文字起こしテキスト"
        response = "評価対象テキストです。"

        prompt = checker._build_evaluation_prompt(document, response)

        assert "元の文字起こしテキスト" not in prompt
