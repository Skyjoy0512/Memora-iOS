# coding=utf-8
# Copyright 2026 Nishika, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

"""jMeet-Eval: 会議関連指示のレジストリ"""

# 基底クラス
# ルールベースChecker
# LLM as a Judge Checker
from jmeeteval.core.meeting_instructions import (
    AnonymizationLLMChecker,
    BeginningNoteLLMChecker,
    BulletPointsLLMChecker,
    CharacterLimitChecker,
    EmphasisRulesLLMChecker,
    EndingNoteLLMChecker,
    EnglishTranslationLLMChecker,
    FillerRemovalLLMChecker,
    JapaneseSummaryLLMChecker,
    JsonFormatLLMChecker,
    LLMJudgeRuleChecker,
    MarkdownTableLLMChecker,
    MeetingInstruction,
    NoEndingPhraseLLMChecker,
    NoPunctuationChecker,
    NumberFormatChecker,
    OrderSpecificationLLMChecker,
    OutputConstraintLLMChecker,
    PersonNotationLLMChecker,
    ProportionChecker,
    QAFormatLLMChecker,
    RequiredItemsLLMChecker,
    SentenceLimitChecker,
    StructuralGranularityLLMChecker,
    StructuredSectionsLLMChecker,
    TemplateFillingLLMChecker,
    TodoAssignmentLLMChecker,
    ViewpointSpecificationLLMChecker,
    WritingStyleLLMChecker,
)

# 会議関連指示のカテゴリ定義
_OUTPUT_CONSTRAINT = "output_constraint:"
_LANGUAGE_TRANSLATION = "language_translation:"
_LENGTH_CONTROL = "length_control:"
_ANNOTATION = "annotation:"
_TEMPLATE_FILLING = "template_filling:"
_FORMATTING = "formatting:"
_STRUCTURAL_GRANULARITY = "structural_granularity:"
_EMPHASIS_RULES = "emphasis_rules:"
_JSON_OUTPUT = "json_output:"
_WRITING_STYLE = "writing_style:"
_TABLE_FORMAT = "table_format:"

# LLM as a Judge関連カテゴリ
_NOTATION_RULES = "notation_rules:"
_TODO_RULES = "todo_rules:"
_VIEWPOINT_SPEC = "viewpoint_spec:"
_ORDER_SPEC = "order_spec:"
_ANONYMIZATION = "anonymization:"

# =============================================================================
# 会議関連指示のレジストリ
# =============================================================================

MEETING_INSTRUCTION_DICT: dict[str, type[MeetingInstruction]] = {
    # -------------------------------------------------------------------------
    # ルールベース Checker（正規表現・文字列処理による評価）
    # -------------------------------------------------------------------------
    # 分量指定関連（Length Control）
    _LENGTH_CONTROL + "character_limit": CharacterLimitChecker,
    _LENGTH_CONTROL + "proportion": ProportionChecker,
    _LENGTH_CONTROL + "sentence_limit": SentenceLimitChecker,
    # 出力制約関連（Output Constraints）
    _OUTPUT_CONSTRAINT + "no_punctuation": NoPunctuationChecker,
    # 文体・敬語関連（Writing Style）
    _WRITING_STYLE + "number_format": NumberFormatChecker,
    # -------------------------------------------------------------------------
    # LLM as a Judge Checker（LLMによる評価）
    # -------------------------------------------------------------------------
    # 出力制約関連（Output Constraints）
    _OUTPUT_CONSTRAINT + "filler_removal": FillerRemovalLLMChecker,
    _OUTPUT_CONSTRAINT + "no_ending_phrase": NoEndingPhraseLLMChecker,
    _OUTPUT_CONSTRAINT + "only_minutes": OutputConstraintLLMChecker,
    _OUTPUT_CONSTRAINT + "advanced_filter": OutputConstraintLLMChecker,
    # 言語指定・翻訳関連（Language and Translation）
    _LANGUAGE_TRANSLATION + "japanese_summary": JapaneseSummaryLLMChecker,
    _LANGUAGE_TRANSLATION + "english_translation": EnglishTranslationLLMChecker,
    # 付記関連（Annotations）
    _ANNOTATION + "ending_note": EndingNoteLLMChecker,
    _ANNOTATION + "beginning_note": BeginningNoteLLMChecker,
    # テンプレート充填関連（Template Filling）
    _TEMPLATE_FILLING + "template": TemplateFillingLLMChecker,
    # 箇条書き・フォーマット関連（Formatting）
    _FORMATTING + "bullet_points": BulletPointsLLMChecker,
    _FORMATTING + "structured_sections": StructuredSectionsLLMChecker,
    _FORMATTING + "qa_format": QAFormatLLMChecker,
    _FORMATTING + "required_items": RequiredItemsLLMChecker,
    # 構成粒度指定関連（Structural Granularity）
    _STRUCTURAL_GRANULARITY + "topics_paragraphs": StructuralGranularityLLMChecker,
    # 強調規則関連（Emphasis Rules）
    _EMPHASIS_RULES + "bold_tag": EmphasisRulesLLMChecker,
    # JSON出力関連（JSON Output）
    _JSON_OUTPUT + "json_format": JsonFormatLLMChecker,
    # 文体・敬語関連（Writing Style）
    _WRITING_STYLE + "writing_style": WritingStyleLLMChecker,
    # 表形式関連（Table Format）
    _TABLE_FORMAT + "markdown_table": MarkdownTableLLMChecker,
    # 汎用LLM評価
    _WRITING_STYLE + "laaj": LLMJudgeRuleChecker,
    # 表記ルール関連（Notation Rules）
    _NOTATION_RULES + "person_notation": PersonNotationLLMChecker,
    # ToDo記載ルール関連（Todo Rules）
    _TODO_RULES + "assignment": TodoAssignmentLLMChecker,
    # 観点指定関連（Viewpoint Specification）
    _VIEWPOINT_SPEC + "focus": ViewpointSpecificationLLMChecker,
    # 順序指定関連（Order Specification）
    _ORDER_SPEC + "arrangement": OrderSpecificationLLMChecker,
    # 匿名化・マスキング関連（Anonymization）
    _ANONYMIZATION + "privacy": AnonymizationLLMChecker,
    _ANONYMIZATION + "company_names": AnonymizationLLMChecker,
}

# 利用可能な指示IDのリスト
AVAILABLE_INSTRUCTION_IDS = list(MEETING_INSTRUCTION_DICT.keys())


# 全カテゴリの定義
MEETING_CATEGORIES = {
    "output_constraint": _OUTPUT_CONSTRAINT,
    "language_translation": _LANGUAGE_TRANSLATION,
    "length_control": _LENGTH_CONTROL,
    "annotation": _ANNOTATION,
    "template_filling": _TEMPLATE_FILLING,
    "formatting": _FORMATTING,
    "structural_granularity": _STRUCTURAL_GRANULARITY,
    "emphasis_rules": _EMPHASIS_RULES,
    "json_output": _JSON_OUTPUT,
    "writing_style": _WRITING_STYLE,
    "table_format": _TABLE_FORMAT,
    "notation_rules": _NOTATION_RULES,
    "todo_rules": _TODO_RULES,
    "viewpoint_spec": _VIEWPOINT_SPEC,
    "order_spec": _ORDER_SPEC,
    "anonymization": _ANONYMIZATION,
}
