"""API呼び出しのトークン使用量を集計するモジュール（コスト計算は非対応、トークン数のみ）"""

from collections import defaultdict
from dataclasses import dataclass


@dataclass
class ModelUsage:
    prompt_tokens: int = 0
    completion_tokens: int = 0
    total_tokens: int = 0
    call_count: int = 0


_usage: dict[str, ModelUsage] = defaultdict(ModelUsage)


def record(model: str, prompt_tokens: int, completion_tokens: int) -> None:
    """モデルごとのトークン使用量を加算する

    asyncio はシングルスレッドで動作するため、await を挟まないこの加算処理に
    ロックは不要。
    """
    usage = _usage[model]
    usage.prompt_tokens += prompt_tokens
    usage.completion_tokens += completion_tokens
    usage.total_tokens += prompt_tokens + completion_tokens
    usage.call_count += 1


def get_summary() -> dict[str, dict]:
    """モデルごとの累積トークン使用量を返す"""
    return {
        model: {
            "prompt_tokens": usage.prompt_tokens,
            "completion_tokens": usage.completion_tokens,
            "total_tokens": usage.total_tokens,
            "call_count": usage.call_count,
        }
        for model, usage in _usage.items()
    }


def reset() -> None:
    """集計をリセットする（実行単位で独立集計したい場合に使用）"""
    _usage.clear()


def format_summary() -> str:
    """人間可読なサマリー文字列を生成する"""
    if not _usage:
        return "API使用量: 記録なし"

    lines = ["=== API使用量（トークン数） ==="]
    for model, usage in _usage.items():
        lines.append(
            f"  {model}: "
            f"呼び出し {usage.call_count}回 | "
            f"prompt {usage.prompt_tokens:,} | "
            f"completion {usage.completion_tokens:,} | "
            f"合計 {usage.total_tokens:,} トークン"
        )
    return "\n".join(lines)
