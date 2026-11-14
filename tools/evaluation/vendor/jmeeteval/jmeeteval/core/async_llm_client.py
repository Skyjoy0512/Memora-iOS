# coding=utf-8
# Copyright 2026 Nishika, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

"""jMeet-Eval: 非同期LLMクライアント

LLM as a Judgeの高速化のための非同期APIクライアント。
セマフォによる同時実行数制限とリトライロジックを提供。
"""

import asyncio
import contextlib
import contextvars
import os
from dataclasses import dataclass, field
from typing import Optional

import aiohttp

from jmeeteval.core import usage_tracker


def _default_llm_base_url() -> str:
    # LLM_JUDGE_BASE_URL / OPENAI_BASE_URL のどちらもベースURL（例: https://.../v1）で
    # 指定でき、末尾に /chat/completions を自動補完する。既に /chat/completions で
    # 終わっている場合はそのまま使う（フルパス指定との後方互換）。
    base = os.getenv("LLM_JUDGE_BASE_URL") or os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1")
    base = base.rstrip("/")
    if base.endswith("/chat/completions"):
        return base
    return f"{base}/chat/completions"


def _default_llm_model() -> str:
    return os.getenv("LLM_JUDGE_MODEL", "gpt-5-mini")


def _default_llm_max_concurrent() -> int:
    return int(os.getenv("LLM_JUDGE_MAX_CONCURRENT", "10"))


def _default_llm_timeout() -> int:
    return int(os.getenv("LLM_JUDGE_TIMEOUT", "30"))


class RateLimitError(Exception):
    def __init__(self, message: str, retry_after: Optional[float] = None):
        super().__init__(message)
        self.retry_after = retry_after


@dataclass
class LLMConfig:
    """LLM設定"""

    model: str = field(default_factory=_default_llm_model)
    max_concurrent: int = field(default_factory=_default_llm_max_concurrent)
    timeout: int = field(default_factory=_default_llm_timeout)
    max_retries: int = 5
    temperature: Optional[float] = None  # None = モデルのデフォルトを使用（gpt-5系は0.0非対応）
    base_url: str = field(default_factory=_default_llm_base_url)
    num_evaluations: int = 3
    early_exit: bool = True


class AsyncLLMClient:
    """非同期LLMクライアント

    使用例:
        async with AsyncLLMClient() as client:
            result = await client.call("プロンプト")
    """

    def __init__(self, config: Optional[LLMConfig] = None):
        self.config = config or LLMConfig()
        # キーは get_global_client() が文脈に応じて差し替える。
        # 直接生成された場合のフォールバックとして環境変数を見る。
        self.api_key = os.getenv("OPENAI_API_KEY")

        self._session: Optional[aiohttp.ClientSession] = None
        self._semaphore: Optional[asyncio.Semaphore] = None

    async def __aenter__(self) -> "AsyncLLMClient":
        """コンテキストマネージャー開始"""
        await self._ensure_session()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """コンテキストマネージャー終了"""
        await self.close()

    async def _ensure_session(self):
        """セッションの初期化"""
        if self._session is None:
            import ssl

            import certifi

            # SSL コンテキストを作成（certifiのCA証明書を使用）
            ssl_context = ssl.create_default_context(cafile=certifi.where())
            connector = aiohttp.TCPConnector(ssl=ssl_context)

            timeout = aiohttp.ClientTimeout(total=self.config.timeout)
            self._session = aiohttp.ClientSession(timeout=timeout, connector=connector)
            self._semaphore = asyncio.Semaphore(self.config.max_concurrent)

    async def close(self):
        """セッションのクローズ"""
        if self._session:
            await self._session.close()
            self._session = None
            self._semaphore = None

    async def call(self, prompt: str) -> str:
        """非同期LLM呼び出し（セマフォ制御付き）

        Args:
            prompt: LLMへのプロンプト

        Returns:
            LLMからの応答テキスト
        """
        await self._ensure_session()
        async with self._semaphore:
            return await self._call_with_retry(prompt)

    async def _call_with_retry(self, prompt: str) -> str:
        """リトライ付きLLM呼び出し"""
        last_error = None

        for attempt in range(self.config.max_retries):
            try:
                return await self._single_call(prompt)
            except RateLimitError as e:
                last_error = e
                wait = e.retry_after if e.retry_after else 10 * (2**attempt)
                await asyncio.sleep(wait)
            except Exception as e:
                last_error = e
                if attempt < self.config.max_retries - 1:
                    await asyncio.sleep(0.5 * (2**attempt))

        # 全リトライ消費後: 例外を再送出してスコアを None（評価不可）にする
        raise last_error

    async def _single_call(self, prompt: str) -> str:
        """単一のAPI呼び出し"""
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        payload = {
            "model": self.config.model,
            "messages": [{"role": "user", "content": prompt}],
        }
        if self.config.temperature is not None:
            payload["temperature"] = self.config.temperature

        async with self._session.post(
            self.config.base_url,
            headers=headers,
            json=payload,
        ) as response:
            if response.status == 429:
                retry_after = response.headers.get("Retry-After")
                wait = float(retry_after) if retry_after else None
                error_text = await response.text()
                raise RateLimitError(f"Rate limit: {error_text[:100]}", retry_after=wait)
            if response.status != 200:
                error_text = await response.text()
                raise Exception(f"API error {response.status}: {error_text[:100]}")

            data = await response.json()
            usage = data.get("usage", {})
            usage_tracker.record(
                self.config.model,
                usage.get("prompt_tokens", 0),
                usage.get("completion_tokens", 0),
            )
            return data["choices"][0]["message"]["content"]

    async def call_batch(self, prompts: list[str]) -> list[str]:
        """複数プロンプトの並列呼び出し

        Args:
            prompts: プロンプトのリスト

        Returns:
            応答のリスト（順序保持）
        """
        tasks = [self.call(prompt) for prompt in prompts]
        return await asyncio.gather(*tasks)


# === 判定クライアントの管理 ===
#
# 複数の利用者がそれぞれ自分の API キーを入力する UI から使われるため、
# キーをプロセス全体で共有してはならない（利用者Aのキーで利用者Bの
# リクエストが実行・課金されてしまう）。
#
# 現在の judge 設定は ContextVar に持たせる。asyncio のタスクごとに
# 独立して伝播するため、同時実行しても互いに影響しない。
# クライアント本体は (キー, モデル, 接続先) をキーにしたキャッシュから引く。

_judge_context: contextvars.ContextVar[Optional["JudgeSettings"]] = contextvars.ContextVar(
    "jmeeteval_judge_context", default=None
)
# 値は (生成時のイベントループ, クライアント)。ClientSession / Semaphore は
# 生成時のループに束縛されるため、別ループ（asyncio.run の再実行など）から
# 使うと死んだセッションへの post で全 judge 呼び出しが失敗する。取得時に
# ループが変わっていたら作り直すことでこれを防ぐ。
_client_cache: dict[tuple[str, str, str, int, int], tuple[asyncio.AbstractEventLoop, AsyncLLMClient]] = {}


@dataclass(frozen=True)
class JudgeSettings:
    """1回の評価で使う judge の設定（API キーを含む）"""

    api_key: str
    config: LLMConfig

    def cache_key(self) -> tuple[str, str, str, int, int]:
        return (
            self.api_key,
            self.config.model,
            self.config.base_url,
            self.config.max_concurrent,
            self.config.timeout,
        )


@contextlib.contextmanager
def use_judge(api_key: str, config: Optional[LLMConfig] = None):
    """このブロックの中で使う judge のキーと設定を指定する

    使用例:
        with use_judge(api_key, LLMConfig(model="gpt-5-mini")):
            await evaluator.evaluate_batch_async_with_progress(...)
    """
    token = _judge_context.set(JudgeSettings(api_key=api_key, config=config or LLMConfig()))
    try:
        yield
    finally:
        _judge_context.reset(token)


async def get_global_client(config: Optional[LLMConfig] = None) -> AsyncLLMClient:
    """現在のコンテキストに対応する判定クライアントを返す

    `use_judge()` で囲まれていない場合は、環境変数 `OPENAI_API_KEY` を使う
    （CLI からの実行はこの経路）。
    """
    settings = _judge_context.get()
    if settings is None:
        api_key = os.getenv("OPENAI_API_KEY")
        if not api_key:
            raise ValueError("OPENAI_API_KEY 環境変数が設定されていません")
        settings = JudgeSettings(api_key=api_key, config=config or LLMConfig())

    key = settings.cache_key()
    loop = asyncio.get_running_loop()
    client: Optional[AsyncLLMClient] = None
    if (entry := _client_cache.get(key)) is not None:
        cached_loop, cached_client = entry
        session = cached_client._session
        if cached_loop is loop and session is not None and not session.closed:
            client = cached_client
        else:
            # 別ループ生成 or 解放済みのクライアントは使えないため作り直す
            _client_cache.pop(key, None)
    if client is None:
        client = AsyncLLMClient(settings.config)
        client.api_key = settings.api_key
        await client._ensure_session()
        _client_cache[key] = (loop, client)
    return client


async def close_global_client():
    """判定クライアントをすべて解放する"""
    for _loop, client in list(_client_cache.values()):
        await client.close()
    _client_cache.clear()
