# coding=utf-8
"""SentenceLimitChecker の単体テスト"""

import pytest

from jmeeteval.core.meeting_instructions import SentenceLimitChecker


class TestSentenceLimitChecker:
    """SentenceLimitChecker のテストクラス"""

    @pytest.fixture
    def checker(self):
        """チェッカーのフィクスチャ"""
        return SentenceLimitChecker("format:sentence_limit")

    # === generate_instruction ===

    def test_generate_instruction_max_sentences_only(self, checker):
        """max_sentencesのみ指定"""
        instruction = checker.generate_instruction(max_sentences=3)
        assert instruction == "3文以内で記載してください。"

    def test_generate_instruction_sentence_length_only(self, checker):
        """sentence_lengthのみ指定"""
        instruction = checker.generate_instruction(sentence_length=100)
        assert instruction == "1文は100文字以内にしてください。"

    def test_generate_instruction_both_raises(self, checker):
        """両方指定の場合はValueError"""
        with pytest.raises(ValueError, match="同時に指定できません"):
            checker.generate_instruction(max_sentences=5, sentence_length=50)

    def test_generate_instruction_none_raises(self, checker):
        """両方未指定の場合はValueError"""
        with pytest.raises(ValueError, match="いずれかを指定してください"):
            checker.generate_instruction()

    # === check_following: 文数チェック ===

    @pytest.fixture
    def max_sentences_checker(self, checker):
        """max_sentences=3のチェッカー"""
        checker._cached_kwargs = {"max_sentences": 3}
        return checker

    @pytest.mark.asyncio
    async def test_max_sentences_within_limit(self, max_sentences_checker):
        """文数が制限内"""
        result = await max_sentences_checker.check_following("", "文1。文2。文3。")
        assert result.score == 1.0

    @pytest.mark.asyncio
    async def test_max_sentences_exceed_limit(self, max_sentences_checker):
        """文数が制限超過"""
        result = await max_sentences_checker.check_following("", "文1。文2。文3。文4。")
        assert result.score == 0.0

    @pytest.mark.asyncio
    async def test_max_sentences_empty(self, max_sentences_checker):
        """空文字"""
        result = await max_sentences_checker.check_following("", "")
        assert result.score == 1.0

    # === check_following: 文字数チェック ===

    @pytest.fixture
    def sentence_length_checker(self, checker):
        """sentence_length=10のチェッカー"""
        checker._cached_kwargs = {"sentence_length": 10}
        return checker

    @pytest.mark.asyncio
    async def test_sentence_length_within_limit(self, sentence_length_checker):
        """各文が制限内"""
        result = await sentence_length_checker.check_following("", "短い文。これも短い。")
        assert result.score == 1.0

    @pytest.mark.asyncio
    async def test_sentence_length_exceed_limit(self, sentence_length_checker):
        """文が制限超過"""
        result = await sentence_length_checker.check_following("", "これは10文字を超える長い文です。")
        assert result.score == 0.0

    # === check_following: 両方指定（エラー） ===

    @pytest.fixture
    def both_checker(self, checker):
        """両方指定のチェッカー"""
        checker._cached_kwargs = {"max_sentences": 3, "sentence_length": 20}
        return checker

    @pytest.mark.asyncio
    async def test_both_returns_none_score(self, both_checker):
        """両方指定の場合はscore=Noneを返す"""
        result = await both_checker.check_following("", "短い文1。短い文2。短い文3。")
        assert result.score is None
        assert result.error_message == "max_sentences と sentence_length は同時に指定できません。"

    # === check_following: 未指定（エラー） ===

    @pytest.fixture
    def no_limit_checker(self, checker):
        """制限未指定のチェッカー"""
        checker._cached_kwargs = {}
        return checker

    @pytest.mark.asyncio
    async def test_no_args_returns_none_score(self, no_limit_checker):
        """引数なしの場合はscore=Noneを返す"""
        result = await no_limit_checker.check_following("", "文1。文2。文3。")
        assert result.score is None
        assert result.error_message == "max_sentences または sentence_length のいずれかを指定してください。"

    # === check_following: 文分割パターン ===

    @pytest.mark.asyncio
    async def test_split_by_period(self, max_sentences_checker):
        """句点で分割"""
        result = await max_sentences_checker.check_following("", "文1。文2。文3。文4。")
        assert result.score == 0.0  # 4文 > 3文

    @pytest.mark.asyncio
    async def test_split_by_exclamation(self, max_sentences_checker):
        """感嘆符で分割"""
        result = await max_sentences_checker.check_following("", "文1！文2！文3！文4！")
        assert result.score == 0.0  # 4文 > 3文

    @pytest.mark.asyncio
    async def test_split_by_question(self, max_sentences_checker):
        """疑問符で分割"""
        result = await max_sentences_checker.check_following("", "文1？文2？文3？文4？")
        assert result.score == 0.0  # 4文 > 3文

    @pytest.mark.asyncio
    async def test_split_by_newline(self, max_sentences_checker):
        """改行で分割"""
        result = await max_sentences_checker.check_following("", "文1\n文2\n文3\n文4")
        assert result.score == 0.0  # 4文 > 3文

    @pytest.mark.asyncio
    async def test_split_by_half_width_exclamation(self, max_sentences_checker):
        """半角感嘆符で分割"""
        result = await max_sentences_checker.check_following("", "文1!文2!文3!文4!")
        assert result.score == 0.0  # 4文 > 3文

    @pytest.mark.asyncio
    async def test_split_by_half_width_question(self, max_sentences_checker):
        """半角疑問符で分割"""
        result = await max_sentences_checker.check_following("", "文1?文2?文3?文4?")
        assert result.score == 0.0  # 4文 > 3文

    # === check_following: 箇条書きパターン ===

    @pytest.mark.asyncio
    async def test_bullet_list(self, max_sentences_checker):
        """箇条書き（改行で分割）"""
        result = await max_sentences_checker.check_following("", "- 項目1\n- 項目2\n- 項目3\n- 項目4")
        assert result.score == 0.0  # 4行 > 3文

    @pytest.mark.asyncio
    async def test_numbered_list(self, max_sentences_checker):
        """番号付きリスト（改行で分割）"""
        result = await max_sentences_checker.check_following("", "1. 項目1\n2. 項目2\n3. 項目3")
        assert result.score == 1.0  # 3行 = 3文

    # === get_instruction_args ===

    def test_get_instruction_args(self, checker):
        """引数情報の取得"""
        args = checker.get_instruction_args()
        assert "max_sentences" in args
        assert args["max_sentences"]["default"] is None
        assert "sentence_length" in args
        assert args["sentence_length"]["default"] is None
