# coding=utf-8
"""応答生成のリクエストパラメータ・クライアント共有・空応答検出のテスト

gpt-5 / o系は `max_tokens` と `temperature != 1` を受け付けない（HTTP 400）ため、
モデル種別ごとに送信パラメータが切り替わることを保証する。
"""

from types import SimpleNamespace

import pytest

from jmeeteval.generate import response_generator as rg
from jmeeteval.generate.response_generator import (
    DefaultMeetingResponseGenerator,
    RequestConfig,
    ResponseGeneratorFactory,
    close_shared_client,
    is_reasoning_model,
)


class FakeCompletions:
    """chat.completions.create の記録用スタブ"""

    def __init__(self, content: str = "生成された議事録です。", finish_reason: str = "stop"):
        self.content = content
        self.finish_reason = finish_reason
        self.calls: list[dict] = []

    async def create(self, **kwargs):
        self.calls.append(kwargs)
        return SimpleNamespace(
            choices=[
                SimpleNamespace(
                    message=SimpleNamespace(content=self.content),
                    finish_reason=self.finish_reason,
                )
            ],
            usage=None,
        )


class FakeClient:
    def __init__(self, completions: FakeCompletions):
        self.chat = SimpleNamespace(completions=completions)
        self.closed = False

    async def close(self):
        self.closed = True


@pytest.fixture
def fake_completions(monkeypatch):
    """共有クライアントをスタブに差し替える"""
    completions = FakeCompletions()
    monkeypatch.setattr(rg, "_shared_client", FakeClient(completions))
    return completions


class TestIsReasoningModel:
    """推論モデル判定"""

    @pytest.mark.parametrize(
        "model",
        ["gpt-5", "gpt-5-mini", "openai/gpt-5-mini", "o1", "o1-preview", "o3-mini", "o4-mini"],
    )
    def test_reasoning_models(self, model):
        assert is_reasoning_model(model) is True

    @pytest.mark.parametrize(
        "model",
        ["gpt-4o", "gpt-4.1", "gpt-4o-mini", "google/gemma-3-4b-it", "Qwen/Qwen3-4B"],
    )
    def test_non_reasoning_models(self, model):
        assert is_reasoning_model(model) is False


class TestRequestParams:
    """モデル種別ごとの送信パラメータ"""

    def test_reasoning_model_omits_max_tokens_and_temperature(self):
        """gpt-5系には max_completion_tokens / reasoning_effort を送り、400になる項目は送らない"""
        params = DefaultMeetingResponseGenerator("gpt-5-mini")._build_request_params("要約して", RequestConfig())

        assert params["max_completion_tokens"] == 32000
        assert params["reasoning_effort"] == "low"
        assert "max_tokens" not in params
        assert "temperature" not in params

    def test_normal_model_uses_max_tokens_and_temperature(self):
        """通常モデルは従来どおり max_tokens / temperature を送る"""
        params = DefaultMeetingResponseGenerator("gpt-4o")._build_request_params("要約して", RequestConfig())

        assert params["max_tokens"] == 32000
        # 掲載ベースラインの測定条件（非reasoning系=0.7）に合わせる
        assert params["temperature"] == 0.7
        assert "max_completion_tokens" not in params
        assert "reasoning_effort" not in params

    def test_reasoning_params_are_configurable(self):
        config = RequestConfig(reasoning_effort="minimal", reasoning_max_completion_tokens=2000)
        params = DefaultMeetingResponseGenerator("o3-mini")._build_request_params("x", config)

        assert params["reasoning_effort"] == "minimal"
        assert params["max_completion_tokens"] == 2000

    def test_system_prompt_is_sent(self):
        """system_prompt が API 経路にも反映される（ローカルHF経路との条件差をなくす）"""
        gen = DefaultMeetingResponseGenerator("gpt-4o", system_prompt="あなたは会議の専門家です。")
        messages = gen._build_request_params("要約して", RequestConfig())["messages"]

        assert [m["role"] for m in messages] == ["system", "user"]
        assert messages[0]["content"] == "あなたは会議の専門家です。"

    def test_system_prompt_absent_by_default(self):
        messages = DefaultMeetingResponseGenerator("gpt-4o")._build_request_params("x", RequestConfig())["messages"]
        assert [m["role"] for m in messages] == ["user"]


class TestEmptyResponseHandling:
    """空応答の扱い"""

    async def test_empty_content_raises(self, fake_completions):
        """空応答は生成失敗として送出する（チェッカー毎に矛盾採点されるのを防ぐ）"""
        fake_completions.content = ""
        fake_completions.finish_reason = "length"

        with pytest.raises(RuntimeError, match="Empty response"):
            await DefaultMeetingResponseGenerator("gpt-5-mini")._request("x", RequestConfig())

    async def test_whitespace_only_content_raises(self, fake_completions):
        fake_completions.content = "   \n  "

        with pytest.raises(RuntimeError, match="Empty response"):
            await DefaultMeetingResponseGenerator("gpt-4o")._request("x", RequestConfig())

    async def test_none_content_raises(self, fake_completions):
        fake_completions.content = None

        with pytest.raises(RuntimeError, match="Empty response"):
            await DefaultMeetingResponseGenerator("gpt-4o")._request("x", RequestConfig())

    async def test_normal_content_is_returned_stripped(self, fake_completions):
        fake_completions.content = "  議事録本文  "

        result = await DefaultMeetingResponseGenerator("gpt-4o")._request("x", RequestConfig())

        assert result == "議事録本文"


class TestClientSharing:
    """コネクションプールのリーク防止"""

    async def test_generators_share_one_client(self, fake_completions):
        """アイテム毎にクライアントを作らない（FD枯渇の防止）"""
        a = DefaultMeetingResponseGenerator("gpt-4o")
        b = DefaultMeetingResponseGenerator("gpt-4.1")

        assert a.openai_client is b.openai_client

    def test_factory_reuses_generator_per_model_and_method(self):
        ResponseGeneratorFactory._cache.clear()

        first = ResponseGeneratorFactory.create_generator("gpt-4o", "default")
        second = ResponseGeneratorFactory.create_generator("gpt-4o", "default")
        other_model = ResponseGeneratorFactory.create_generator("gpt-4.1", "default")

        assert first is second
        assert first is not other_model

    async def test_close_shared_client_releases_it(self, monkeypatch):
        client = FakeClient(FakeCompletions())
        monkeypatch.setattr(rg, "_shared_client", client)

        await close_shared_client()

        assert client.closed is True
        assert rg._shared_client is None
