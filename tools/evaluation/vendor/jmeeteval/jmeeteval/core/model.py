import json
from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator

# =============================================================================
# 新フォーマット: 指示ファイル・文字起こしファイル分離形式
# =============================================================================


class InstructionEntry(BaseModel):
    """指示ファイルの1エントリ"""

    id: str
    instruction_key: str
    instruction_text: str
    instruction_kwargs: dict[str, Any] = Field(default_factory=dict)

    @field_validator("id", mode="before")
    @classmethod
    def convert_id_to_str(cls, v):
        return str(v)


class InstructionRegistry(BaseModel):
    """指示ファイル全体（複数のInstructionEntry）"""

    entries: list[InstructionEntry]
    _index: dict[str, InstructionEntry] = {}

    def model_post_init(self, __context):
        """エントリをIDでインデックス化"""
        object.__setattr__(self, "_index", {entry.id: entry for entry in self.entries})

    def get(self, instruction_id: str) -> InstructionEntry:
        """IDで指示を取得"""
        if instruction_id not in self._index:
            raise KeyError(f"Instruction ID '{instruction_id}' not found")
        return self._index[instruction_id]

    def __len__(self) -> int:
        return len(self.entries)

    @classmethod
    def load(cls, path: Path) -> "InstructionRegistry":
        """JSONLファイルから読み込む"""
        with path.open("r", encoding="utf-8") as f:
            entries = [InstructionEntry.model_validate_json(line.strip()) for line in f if line.strip()]
        return cls(entries=entries)


class TranscriptEntry(BaseModel):
    """文字起こしファイルの1エントリ"""

    id: str
    instruction_keys: list[str]
    transcript: str
    metadata: dict[str, Any] | None = None
    # 後方互換のため、summarize_method未指定のデータはdefaultにフォールバックする
    summarize_method: Literal["default", "map_reduce", "refine"] = Field(default="default")

    @field_validator("id", mode="before")
    @classmethod
    def convert_id_to_str(cls, v):
        return str(v)


class TranscriptExamples(BaseModel):
    """文字起こしファイル全体（複数のTranscriptEntry）"""

    entries: list[TranscriptEntry]

    def __len__(self) -> int:
        return len(self.entries)

    @classmethod
    def load(cls, path: Path) -> "TranscriptExamples":
        """JSONLファイルから読み込む"""
        with path.open("r", encoding="utf-8") as f:
            entries = [TranscriptEntry.model_validate_json(line.strip()) for line in f if line.strip()]
        return cls(entries=entries)


# =============================================================================
# 結合後フォーマット（評価システムで使用）
# =============================================================================


class MeetingInputExample(BaseModel):
    """会議評価の入力例（結合後フォーマット）"""

    id: str
    instruction_id_list: list[str]
    instruction_texts: list[str]
    transcript: str
    instruction_kwargs: list[dict[str, Any]]
    summarize_method: Literal["default", "map_reduce", "refine"]
    metadata: dict[str, Any] | None = None

    @field_validator("id", mode="before")
    @classmethod
    def convert_id_to_str(cls, v):
        return str(v)

    @field_validator("instruction_kwargs", mode="before")
    @classmethod
    def convert_kwargs_to_list(cls, v):
        """instruction_kwargsがdictの場合はlistに変換"""
        if isinstance(v, dict):
            return [v]
        return v

    @property
    def instruction_text(self) -> str:
        return "\n".join(f"- {text}" for text in self.instruction_texts)

    @property
    def prompt(self) -> str:
        return f"# 指示\n{self.instruction_text}\n\n# 入力テキスト\n{self.transcript}\n"

    @classmethod
    def from_transcript_and_instructions(
        cls,
        transcript_entry: TranscriptEntry,
        instruction_registry: InstructionRegistry,
    ) -> "MeetingInputExample":
        """文字起こしエントリと指示レジストリから結合して生成"""
        instruction_id_list = []
        instruction_kwargs = []
        instruction_texts = []

        for inst_key in transcript_entry.instruction_keys:
            inst = instruction_registry.get(inst_key)
            instruction_id_list.append(inst.instruction_key)
            instruction_kwargs.append(inst.instruction_kwargs)
            instruction_texts.append(inst.instruction_text)

        return cls(
            id=transcript_entry.id,
            instruction_id_list=instruction_id_list,
            instruction_texts=instruction_texts,
            transcript=transcript_entry.transcript,
            summarize_method=transcript_entry.summarize_method,
            instruction_kwargs=instruction_kwargs,
            metadata=transcript_entry.metadata,
        )


class MeetingInputExamples(BaseModel):
    """結合後の入力例コレクション"""

    examples: list[MeetingInputExample]

    def __len__(self) -> int:
        return len(self.examples)

    def get_example(self, id: str) -> MeetingInputExample:
        """IDで例を取得"""
        for example in self.examples:
            if example.id == id:
                return example
        raise ValueError(f"ID {id} not found")

    def get_range(self, start: int, end: int) -> "MeetingInputExamples":
        """範囲を取得"""
        return self.model_copy(update={"examples": self.examples[start:end]})

    @classmethod
    def load_from_split_files(
        cls,
        instructions_path: Path | str,
        transcripts_path: Path | str,
    ) -> "MeetingInputExamples":
        """指示ファイルと文字起こしファイルから結合して読み込む

        Args:
            instructions_path: 指示ファイルのパス（instructions.jsonl）
            transcripts_path: 文字起こしファイルのパス（transcripts.jsonl）

        Returns:
            MeetingInputExamples
        """
        instructions_path = Path(instructions_path)
        transcripts_path = Path(transcripts_path)
        instruction_registry = InstructionRegistry.load(instructions_path)
        transcript_examples = TranscriptExamples.load(transcripts_path)

        examples = [
            MeetingInputExample.from_transcript_and_instructions(
                transcript_entry=entry,
                instruction_registry=instruction_registry,
            )
            for entry in transcript_examples.entries
        ]

        return cls(examples=examples)

    @classmethod
    def load_from_hf(cls, dataset_name: str) -> "MeetingInputExamples":
        """Hugging Faceデータセットから読み込む（分割フォーマット）

        Args:
            dataset_name: データセット名（例: "<org>/<dataset-name>"）

        Returns:
            MeetingInputExamples
        """
        try:
            from huggingface_hub import hf_hub_download
        except ImportError:
            raise ImportError(
                "Hugging Faceデータセットを使用するには 'huggingface_hub' パッケージが必要です: uv add huggingface_hub"
            )

        # JSONLファイルを直接ダウンロード
        instructions_path = hf_hub_download(
            repo_id=dataset_name,
            filename="data/instructions.jsonl",
            repo_type="dataset",
        )
        transcripts_path = hf_hub_download(
            repo_id=dataset_name,
            filename="data/transcripts.jsonl",
            repo_type="dataset",
        )

        return cls.load_from_split_files(
            instructions_path=instructions_path,
            transcripts_path=transcripts_path,
        )

    @classmethod
    def load_auto(
        cls,
        transcripts_path: str,
        instructions_path: str | None = None,
    ) -> "MeetingInputExamples":
        """ローカルファイルまたはHugging Faceデータセットから自動で読み込む

        Args:
            transcripts_path: 文字起こしファイルのパス または "hf://username/dataset_name" 形式
            instructions_path: 指示ファイルのパス（ローカルファイルの場合は必須）

        Returns:
            MeetingInputExamples
        """
        if transcripts_path.startswith("hf://"):
            dataset_name = transcripts_path[5:]  # "hf://" を除去
            return cls.load_from_hf(dataset_name)
        else:
            if instructions_path is None:
                raise ValueError("ローカルファイルの場合は instructions_path が必須です")
            return cls.load_from_split_files(
                instructions_path=Path(instructions_path),
                transcripts_path=Path(transcripts_path),
            )


class GenerateResult(BaseModel):
    """生成結果の1エントリ"""

    id: str
    prompt_for_evaluation: str
    response: str

    @field_validator("id", mode="before")
    @classmethod
    def convert_id_to_str(cls, v):
        return str(v)


class GenerateResults(BaseModel):
    model_name: str
    dataset_name: str
    results: list[GenerateResult] = Field(default_factory=list)

    def __len__(self) -> int:
        return len(self.results)

    def save(self, path: Path) -> None:
        with path.open("w", encoding="utf-8") as f:
            json.dump(self.model_dump(), f, ensure_ascii=False, indent=2)

    @classmethod
    def load(cls, path: Path) -> "GenerateResults":
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        # key → id 変換（後方互換性）
        for result in data.get("results", []):
            if "key" in result and "id" not in result:
                result["id"] = result.pop("key")
        return cls.model_validate(data)
