# coding=utf-8
"""NumberFormatChecker の単体テスト"""

import pytest

from jmeeteval.core.meeting_instructions import NumberFormatChecker


class TestNumberFormatChecker:
    """NumberFormatChecker のテストクラス"""

    @pytest.fixture
    def zenkaku_checker(self):
        """全角数字チェッカーのフィクスチャ"""
        checker = NumberFormatChecker("writing_style:number_format")
        checker._cached_kwargs = {"format_type": "zenkaku"}
        return checker

    @pytest.fixture
    def hankaku_checker(self):
        """半角数字チェッカーのフィクスチャ"""
        checker = NumberFormatChecker("writing_style:number_format")
        checker._cached_kwargs = {"format_type": "hankaku"}
        return checker

    # === 全角数字チェック (format_type="zenkaku") ===

    @pytest.mark.asyncio
    async def test_zenkaku_only_zenkaku_success(self, zenkaku_checker):
        """全角数字のみ含む場合は成功"""
        result = await zenkaku_checker.check_following("", "会議は１０時から開始です。参加者は５名でした。")
        assert result.score == 1.0

    @pytest.mark.asyncio
    async def test_zenkaku_only_hankaku_failure(self, zenkaku_checker):
        """半角数字のみ含む場合は失敗"""
        result = await zenkaku_checker.check_following("", "会議は10時から開始です。参加者は5名でした。")
        assert result.score == 0.0

    @pytest.mark.asyncio
    async def test_zenkaku_mixed_failure(self, zenkaku_checker):
        """全角と半角が混在する場合は失敗"""
        result = await zenkaku_checker.check_following("", "会議は１０時から開始です。参加者は5名でした。")
        assert result.score == 0.0

    @pytest.mark.asyncio
    async def test_zenkaku_no_numbers_pass(self, zenkaku_checker):
        """数字が含まれない場合は違反なしとして合格

        この指示は「数値を書け」ではなく「書くなら統一しろ」という条件付きの制約。
        評価不可(None)にするとその指示が母数から消え、数値を落とした応答ほど
        採点対象が減って有利になるため、合格として扱う。
        """
        result = await zenkaku_checker.check_following("", "会議は午前中に開始です。")
        assert result.score == 1.0
        assert "数値が含まれていない" in result.error_message

    # === 半角数字チェック (format_type="hankaku") ===

    @pytest.mark.asyncio
    async def test_hankaku_only_hankaku_success(self, hankaku_checker):
        """半角数字のみ含む場合は成功"""
        result = await hankaku_checker.check_following("", "会議は10時から開始です。参加者は5名でした。")
        assert result.score == 1.0

    @pytest.mark.asyncio
    async def test_hankaku_only_zenkaku_failure(self, hankaku_checker):
        """全角数字のみ含む場合は失敗"""
        result = await hankaku_checker.check_following("", "会議は１０時から開始です。参加者は５名でした。")
        assert result.score == 0.0

    @pytest.mark.asyncio
    async def test_hankaku_mixed_failure(self, hankaku_checker):
        """全角と半角が混在する場合は失敗"""
        result = await hankaku_checker.check_following("", "会議は10時から開始です。参加者は５名でした。")
        assert result.score == 0.0

    @pytest.mark.asyncio
    async def test_hankaku_no_numbers_pass(self, hankaku_checker):
        """数字が含まれない場合は違反なしとして合格"""
        result = await hankaku_checker.check_following("", "会議は午前中に開始です。")
        assert result.score == 1.0
        assert "数値が含まれていない" in result.error_message

    # === 無効なformat_type ===

    @pytest.mark.asyncio
    async def test_invalid_format_type_none(self):
        """無効なformat_typeの場合はNone"""
        checker = NumberFormatChecker("writing_style:number_format")
        checker._cached_kwargs = {"format_type": "invalid"}
        result = await checker.check_following("", "会議は10時から開始です。")
        assert result.score is None
        assert "無効なformat_type" in result.error_message

    # === generate_instruction ===

    def test_generate_instruction_zenkaku(self):
        """全角指定の指示文生成"""
        checker = NumberFormatChecker("writing_style:number_format")
        instruction = checker.generate_instruction(format_type="zenkaku")
        assert "全角" in instruction

    def test_generate_instruction_hankaku(self):
        """半角指定の指示文生成"""
        checker = NumberFormatChecker("writing_style:number_format")
        instruction = checker.generate_instruction(format_type="hankaku")
        assert "半角" in instruction

    def test_generate_instruction_default(self):
        """デフォルトの指示文生成"""
        checker = NumberFormatChecker("writing_style:number_format")
        instruction = checker.generate_instruction()
        assert "統一" in instruction

    # === get_instruction_args ===

    def test_get_instruction_args(self):
        """引数情報の取得"""
        checker = NumberFormatChecker("writing_style:number_format")
        args = checker.get_instruction_args()
        assert "format_type" in args
        assert args["format_type"]["default"] == "zenkaku"
        assert "zenkaku" in args["format_type"]["choices"]
        assert "hankaku" in args["format_type"]["choices"]
