import os
import string
from typing import Literal, Protocol

from openai import AsyncOpenAI
from pydantic import BaseModel, Field, model_validator

from jmeeteval.core.model import MeetingInputExample


def is_reasoning_model(model_name: str) -> bool:
    """gpt-5 / o シリーズなど、推論トークンを消費するモデルかを判定する。

    これらのモデルは `max_tokens` と `temperature != 1` を受け付けない（HTTP 400）。
    `openai/gpt-5-mini` のようにベンダ名が前置されるケースがあるため末尾要素で判定する。
    """
    name = model_name.lower().rsplit("/", 1)[-1]
    return name.startswith(("gpt-5", "o1", "o3", "o4"))


class RequestConfig(BaseModel):
    # 掲載ベースラインの測定条件（パイプライン既定 JMEETEVAL_MAX_TOKENS=32000）に合わせる
    max_tokens: int = 32000
    # 掲載ベースラインの測定条件（非reasoning系=0.7）に合わせる。
    # 同じ入力でも実行ごとに結果が変わるため、greedy decoding で再現性を
    # 優先したい場合は 0.0 を明示指定する。reasoning系（gpt-5/o系）には送信されない。
    temperature: float = 0.7
    # --- 推論モデル（gpt-5 / o系）専用。通常モデルでは使用しない ---
    reasoning_effort: str = Field(
        default="low",
        description="推論の深さ。推論トークンが応答予算を食い潰して空出力になるのを防ぐため既定は low。",
    )
    reasoning_max_completion_tokens: int = Field(
        default=32000,
        description=(
            "推論モデルの max_completion_tokens。推論トークンもこの予算から消費されるため、"
            "通常モデルの max_tokens より大きく取らないと本文が空（finish_reason=length）になる。"
        ),
    )


class ChunkConfig(BaseModel):
    chunk_size: int = Field(
        default=4000, description="Chunk size. The maximum chunk size may be up to chunk_size + min_chunk_size."
    )
    min_chunk_size: int = Field(
        default=500, description="Minimum chunk size. If the chunk size is below this, do not split."
    )
    overlap: int = Field(default=0, description="Overlap size. ")

    @model_validator(mode="after")
    def validate_overlap(self) -> "ChunkConfig":
        if self.overlap >= self.chunk_size:
            raise ValueError("overlap must be less than chunk_size")
        return self


def _chunking(prompt: str, chunk_config: ChunkConfig) -> list[str]:
    """promptをchunk_configに従って分割する

    Args:
        prompt: 分割対象のテキスト
        chunk_config: チャンク設定

    Returns:
        分割されたテキストのリスト
    """
    if len(prompt) <= chunk_config.chunk_size:
        return [prompt]

    chunks = []
    positions = []  # 各チャンクの開始位置を記録
    start = 0

    while start < len(prompt):
        # チャンクの終了位置を計算
        end = start + chunk_config.chunk_size

        if end >= len(prompt):
            # 最後のチャンク
            chunks.append(prompt[start:])
            positions.append(start)
            break
        else:
            chunks.append(prompt[start:end])
            positions.append(start)
            # 次のスタート位置を計算（オーバーラップを考慮）
            start = end - chunk_config.overlap

    # 最後のチャンクがmin_chunk_size未満の場合、前のチャンクと統合
    if len(chunks) > 1 and len(chunks[-1]) < chunk_config.min_chunk_size:
        chunks.pop()
        chunks.pop()
        positions.pop()
        last_start = positions.pop()
        chunks.append(prompt[last_start:])

    return chunks


class ResponseGeneratorResult(BaseModel):
    prompt_for_evaluation: str = Field(description="評価用のプロンプト")
    chunk_responses: list[str] = Field(description="各チャンクの生成結果")
    final_response: str = Field(description="最終生成結果")


class ResponseGeneratorProtocol(Protocol):
    async def generate_response(self, prompt: str, request_config: RequestConfig) -> ResponseGeneratorResult: ...


_DEFAULT_PROMPT_FORMAT = string.Template("""# 指示
${instruction}

# 入力テキスト
${text}
""")

_REDUCE_PROMPT_FORMAT = string.Template("""# 指示
${reduce_instruction}

# オリジナルの指示
${original_instruction}

# 出力テキスト
${generated_text}

""")

_REFINE_PROMPT_FORMAT = string.Template("""# 指示
${refine_instruction}

# オリジナルの指示
${original_instruction}

# これまでの出力テキスト
${previous_output}

# 新しいテキスト
${current_text}
""")  # noqa: E501

REDUCE_INSTRUCTION = """複数の出力テキストを統合して、オリジナルの指示に従った結果として出力する。"""
REFINE_INSTRUCTION = """オリジナルの指示に従い、これまでの出力内容に新しいテキストの情報を反映して改訂する。"""


# AsyncOpenAI は内部に HTTP コネクションプールを持つため、アイテム毎に生成すると
# FD が枯渇する。プロセス内で 1 個を共有し、終了時に close_shared_client() で解放する。
_shared_client: AsyncOpenAI | None = None


def get_shared_client() -> AsyncOpenAI:
    global _shared_client
    if _shared_client is None:
        _shared_client = AsyncOpenAI(
            timeout=float(os.getenv("GENERATION_TIMEOUT", "120")),
            max_retries=int(os.getenv("GENERATION_MAX_RETRIES", "3")),
        )
    return _shared_client


async def close_shared_client() -> None:
    """共有クライアントを解放する（プロセス終了前に呼ぶ）"""
    global _shared_client
    if _shared_client is not None:
        await _shared_client.close()
        _shared_client = None


class DefaultMeetingResponseGenerator:
    def __init__(self, model_name: str, system_prompt: str | None = None):
        self.model_name = model_name
        self.system_prompt: str | None = system_prompt

    @property
    def openai_client(self) -> AsyncOpenAI:
        return get_shared_client()

    def _format_messages(self, system_prompt: str | None, user_content: str) -> list[dict[str, str]]:
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": user_content})
        return messages

    def _build_request_params(self, user_content: str, request_config: RequestConfig) -> dict:
        params: dict = {
            "model": self.model_name,
            "messages": self._format_messages(self.system_prompt, user_content),
        }
        if is_reasoning_model(self.model_name):
            # gpt-5 / o系: max_tokens と temperature!=1 は 400。推論トークンも予算から出る。
            params["max_completion_tokens"] = request_config.reasoning_max_completion_tokens
            params["reasoning_effort"] = request_config.reasoning_effort
        else:
            params["max_tokens"] = request_config.max_tokens
            params["temperature"] = request_config.temperature
        return params

    async def _request(self, user_content: str, request_config: RequestConfig) -> str:
        response = await self.openai_client.chat.completions.create(
            **self._build_request_params(user_content, request_config)
        )
        choice = response.choices[0]
        content = choice.message.content
        if content is None or not content.strip():
            # 空応答をそのまま返すとチェッカー毎に矛盾した採点（句点無し=合格 等）を受けるため、
            # 生成失敗として明示的に落とす。推論モデルでは予算切れが主因。
            raise RuntimeError(
                f"Empty response from {self.model_name} (finish_reason={choice.finish_reason}). "
                "推論モデルの場合は reasoning_max_completion_tokens の引き上げを検討。"
            )
        return content.strip()

    def get_prompt_for_evaluation(self, example: MeetingInputExample) -> str:
        return _DEFAULT_PROMPT_FORMAT.substitute(instruction=example.instruction_text, text=example.transcript)

    async def generate_response(
        self, example: MeetingInputExample, request_config: RequestConfig
    ) -> ResponseGeneratorResult:
        """Generate response using the default prompt format"""
        user_content = _DEFAULT_PROMPT_FORMAT.substitute(instruction=example.instruction_text, text=example.transcript)
        generated_text = await self._request(user_content, request_config)
        return ResponseGeneratorResult(
            prompt_for_evaluation=self.get_prompt_for_evaluation(example),
            chunk_responses=[generated_text],
            final_response=generated_text,
        )


class MapReduceResponseGenerator(DefaultMeetingResponseGenerator):
    """Generate responses using MapReduce"""

    def __init__(self, model_name: str, reduce_instruction: str, chunk_config: ChunkConfig):
        super().__init__(model_name)
        self.chunk_config = chunk_config
        self.reduce_instruction = reduce_instruction

    async def _reduce(self, instruction: str, generated_texts: list[str], request_config: RequestConfig) -> str:
        user_content = _REDUCE_PROMPT_FORMAT.substitute(
            reduce_instruction=self.reduce_instruction,
            original_instruction=instruction,
            generated_text="\n\n".join(generated_texts),
        )
        generated_text = await self._request(user_content, request_config)
        return generated_text

    async def generate_response(
        self, example: MeetingInputExample, request_config: RequestConfig
    ) -> ResponseGeneratorResult:
        chunks = _chunking(example.transcript, self.chunk_config)
        if len(chunks) == 1:
            raise ValueError("Chunk size is 1. MapReduce cannot be used.")

        chunk_responses = []
        for chunk in chunks:
            # generate response for each chunk
            user_content = _DEFAULT_PROMPT_FORMAT.substitute(instruction=example.instruction_text, text=chunk)
            generated_text = await self._request(user_content, request_config)
            chunk_responses.append(generated_text)

        # reduce the generated texts
        reduced_text = await self._reduce(example.instruction_text, chunk_responses, request_config)
        return ResponseGeneratorResult(
            prompt_for_evaluation=self.get_prompt_for_evaluation(example),
            chunk_responses=chunk_responses,
            final_response=reduced_text,
        )


class RefineResponseGenerator(DefaultMeetingResponseGenerator):
    """Generate responses using Refine"""

    def __init__(self, model_name: str, refine_instruction: str, chunk_config: ChunkConfig):
        super().__init__(model_name)
        self.chunk_config = chunk_config
        self.refine_instruction = refine_instruction

    async def _refine(
        self, instruction: str, previous_output: str, chunk_texts: list[str], request_config: RequestConfig
    ) -> str:
        for current_text in chunk_texts:
            user_content = _REFINE_PROMPT_FORMAT.substitute(
                refine_instruction=self.refine_instruction,
                original_instruction=instruction,
                previous_output=previous_output,
                current_text=current_text,
            )
            previous_output = await self._request(user_content, request_config)
        return previous_output

    async def generate_response(
        self, example: MeetingInputExample, request_config: RequestConfig
    ) -> ResponseGeneratorResult:
        chunks = _chunking(example.transcript, self.chunk_config)
        if len(chunks) == 1:
            raise ValueError("Chunk size is 1. Refine cannot be used.")

        initial_output = await self._request(
            _DEFAULT_PROMPT_FORMAT.substitute(instruction=example.instruction_text, text=chunks[0]),
            request_config,
        )
        refined_output = await self._refine(example.instruction_text, initial_output, chunks[1:], request_config)
        return ResponseGeneratorResult(
            prompt_for_evaluation=self.get_prompt_for_evaluation(example),
            chunk_responses=chunks,
            final_response=refined_output,
        )


ResponseGenerator = DefaultMeetingResponseGenerator | MapReduceResponseGenerator | RefineResponseGenerator


class ResponseGeneratorFactory:
    # ジェネレータは状態を持たない（設定のみ）ので (model, method) 単位で使い回す
    _cache: dict[tuple[str, str], ResponseGenerator] = {}

    @classmethod
    def create_generator(
        cls, model_name: str, summarize_method: Literal["default", "map_reduce", "refine"]
    ) -> ResponseGenerator:
        key = (model_name, summarize_method)
        if key not in cls._cache:
            cls._cache[key] = cls._build_generator(model_name, summarize_method)
        return cls._cache[key]

    @staticmethod
    def _build_generator(
        model_name: str, summarize_method: Literal["default", "map_reduce", "refine"]
    ) -> ResponseGenerator:
        if summarize_method == "default":
            return DefaultMeetingResponseGenerator(model_name)
        elif summarize_method == "map_reduce":
            return MapReduceResponseGenerator(
                model_name,
                REDUCE_INSTRUCTION,
                ChunkConfig(),
            )
        elif summarize_method == "refine":
            return RefineResponseGenerator(
                model_name,
                REFINE_INSTRUCTION,
                ChunkConfig(),
            )
        else:
            raise ValueError(f"Invalid summarize method: {summarize_method}")
