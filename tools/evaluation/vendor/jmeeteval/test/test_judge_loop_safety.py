# coding=utf-8
# Copyright 2026 Nishika, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

"""判定クライアントのイベントループ安全性のテスト

ClientSession は生成時のイベントループに束縛される。(キー, 設定) だけを
キーにキャッシュすると、2 回目の asyncio.run（同一プロセスからの再評価）で
死んだセッションを引き当て、全 judge 呼び出しが失敗し無言で全件
「評価不可」になる。ループが変わったらクライアントを作り直すことを保証する。
"""

import asyncio
import contextlib

from jmeeteval.core.async_llm_client import (
    LLMConfig,
    close_global_client,
    get_global_client,
    use_judge,
)


def _get_client_in_new_loop():
    async def inner():
        with use_judge("key-A", LLMConfig(model="m")):
            return await get_global_client()

    return asyncio.run(inner())


def test_new_event_loop_gets_fresh_usable_client():
    """asyncio.run をまたいだら別クライアント（死んだセッションを再利用しない）"""
    first = _get_client_in_new_loop()
    try:
        second = _get_client_in_new_loop()

        assert first is not second
        assert second._session is not None
        assert not second._session.closed
    finally:
        with contextlib.suppress(Exception):
            asyncio.run(close_global_client())
        with contextlib.suppress(Exception):
            asyncio.run(first.close())


def test_same_loop_reuses_client():
    """同一ループ内では従来どおり使い回す（接続の無駄打ちを防ぐ）"""

    async def inner():
        with use_judge("key-A", LLMConfig(model="m")):
            a = await get_global_client()
            b = await get_global_client()
        try:
            return a is b
        finally:
            await close_global_client()

    assert asyncio.run(inner())
