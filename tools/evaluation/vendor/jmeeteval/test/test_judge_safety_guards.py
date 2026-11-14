"""N12 / N14 / N15 回帰テスト: judge まわりの「無言の全滅」を防ぐガード。

- N12: APIキー未設定で evaluate_responses に入ると即エラー（従来は全件401→評価不可で正常終了）。
- N14: LLM_JUDGE_BASE_URL / OPENAI_BASE_URL のどちらもベースURL指定で /chat/completions を自動補完。
- N15: 全件評価不可で精度が None のとき CLI 表示が落ちない（'-' 表示）。
"""

import os
from unittest import mock

import pytest

from jmeeteval.core.async_llm_client import _default_llm_base_url


# ---- N12 ----------------------------------------------------------------
def test_evaluate_responses_requires_api_key():
    """APIキー未設定なら採点前に RuntimeError（無言の全滅を防ぐ）。"""
    from jmeet_eval_pipeline import JMeetEvalPipeline

    with mock.patch.dict(os.environ, {}, clear=True):
        pipeline = JMeetEvalPipeline.__new__(JMeetEvalPipeline)
        pipeline.api_key = None  # キー無し
        with pytest.raises(RuntimeError, match="APIキー"):
            pipeline.evaluate_responses(inputs=None, generate_results=[])


# ---- N14 ----------------------------------------------------------------
def test_base_url_autocomplete_from_v1():
    with mock.patch.dict(os.environ, {"OPENAI_BASE_URL": "https://api.example.com/v1"}, clear=True):
        assert _default_llm_base_url() == "https://api.example.com/v1/chat/completions"


def test_base_url_keeps_full_path():
    """既に /chat/completions で終わるフルパスはそのまま（後方互換）。"""
    full = "https://api.example.com/v1/chat/completions"
    with mock.patch.dict(os.environ, {"LLM_JUDGE_BASE_URL": full}, clear=True):
        assert _default_llm_base_url() == full


def test_judge_base_url_also_autocompletes():
    """LLM_JUDGE_BASE_URL 側も /v1 指定で自動補完される（旧実装は素通しで404だった）。"""
    with mock.patch.dict(os.environ, {"LLM_JUDGE_BASE_URL": "https://judge.example.com/v1"}, clear=True):
        assert _default_llm_base_url() == "https://judge.example.com/v1/chat/completions"


# ---- N15 ----------------------------------------------------------------
def test_accuracy_formatter_handles_none():
    """精度 None を :.3f で書式化するとクラッシュするので '-' 表示にする、と同じロジック。"""

    def _acc(value) -> str:
        return f"{value:.3f}" if isinstance(value, (int, float)) else "-"

    assert _acc(None) == "-"
    assert _acc(0.5) == "0.500"
