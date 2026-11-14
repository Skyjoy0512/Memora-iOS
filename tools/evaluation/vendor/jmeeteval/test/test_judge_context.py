# coding=utf-8
"""判定クライアントのキー分離のテスト

複数の利用者がそれぞれ自分の API キーを入力する UI から使われるため、
キーがプロセス全体で共有されてはならない（利用者Aのキーで利用者Bの
リクエストが実行・課金される）。
"""

import asyncio

import pytest

from jmeeteval.core.async_llm_client import (
    LLMConfig,
    close_global_client,
    get_global_client,
    use_judge,
)


@pytest.fixture(autouse=True)
async def _cleanup():
    yield
    await close_global_client()


class TestKeyIsolation:
    async def test_uses_key_from_context(self):
        with use_judge("key-A", LLMConfig(model="model-A")):
            client = await get_global_client()

        assert client.api_key == "key-A"
        assert client.config.model == "model-A"

    async def test_concurrent_users_do_not_share_keys(self):
        """同時実行しても互いのキーが混ざらない"""

        async def worker(key: str, model: str):
            with use_judge(key, LLMConfig(model=model)):
                await asyncio.sleep(0.01)  # 他タスクへ切り替わる隙を作る
                client = await get_global_client()
                return client.api_key, client.config.model

        results = await asyncio.gather(
            worker("key-A", "gpt-4.1"),
            worker("key-B", "gpt-5-mini"),
            worker("key-C", "gpt-4o"),
        )

        assert results == [("key-A", "gpt-4.1"), ("key-B", "gpt-5-mini"), ("key-C", "gpt-4o")]

    async def test_same_settings_reuse_one_client(self):
        """同じキー・設定ならクライアントを使い回す（接続の無駄打ちを防ぐ）"""
        with use_judge("key-A", LLMConfig(model="m")):
            first = await get_global_client()
        with use_judge("key-A", LLMConfig(model="m")):
            second = await get_global_client()

        assert first is second

    async def test_different_keys_get_different_clients(self):
        with use_judge("key-A", LLMConfig(model="m")):
            a = await get_global_client()
        with use_judge("key-B", LLMConfig(model="m")):
            b = await get_global_client()

        assert a is not b
        assert (a.api_key, b.api_key) == ("key-A", "key-B")

    async def test_context_is_restored_after_block(self):
        """ブロックを抜けたら元に戻る（入れ子でも壊れない）"""
        with use_judge("outer", LLMConfig(model="m")):
            with use_judge("inner", LLMConfig(model="m")):
                inner = await get_global_client()
            outer = await get_global_client()

        assert inner.api_key == "inner"
        assert outer.api_key == "outer"

    async def test_falls_back_to_env(self, monkeypatch):
        """use_judge の外では環境変数を使う（CLI 実行の経路）"""
        monkeypatch.setenv("OPENAI_API_KEY", "env-key")

        client = await get_global_client(LLMConfig(model="m"))

        assert client.api_key == "env-key"

    async def test_errors_without_key(self, monkeypatch):
        monkeypatch.delenv("OPENAI_API_KEY", raising=False)

        with pytest.raises(ValueError, match="OPENAI_API_KEY"):
            await get_global_client(LLMConfig(model="m"))
