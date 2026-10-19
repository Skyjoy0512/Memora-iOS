#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-motion-loading.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
python3 tools/checks/check-motion-policy.py
python3 -B -m unittest discover -s tools/checks -p 'test_simulator_profile_*.py'
swiftc App/MemoraLoadingState.swift App/MemoraLoadingPolicy.swift App/MemoraLoadSnapshot.swift App/JournalCalendarRequest.swift tools/checks/LoadingPolicyChecks.swift -o "$check_dir/loading"
"$check_dir/loading"
swiftc App/MemoraLoadingState.swift App/MemoraLoadSnapshot.swift App/ProjectSourceText.swift App/ProjectSourceFiles.swift App/ProjectSourceTextReader.swift App/ProjectSourceTextRequest.swift App/ProjectSourceTextLoader.swift tools/checks/ProjectSourceTextLoaderChecks.swift -o "$check_dir/source-loader"
"$check_dir/source-loader"
swiftc App/ConversationScrollState.swift tools/checks/ConversationScrollChecks.swift -o "$check_dir/scroll"
"$check_dir/scroll"
swiftc App/MarkdownBlock.swift App/SourcedMarkdownBlock.swift App/MarkdownFence.swift App/MarkdownBlockParser.swift App/MarkdownBlockWriter.swift App/IncrementalMarkdown.swift tools/checks/IncrementalMarkdownChecks.swift -o "$check_dir/markdown"
"$check_dir/markdown"
swiftc App/IntegrationCatalog.swift App/LibrarySection.swift tools/checks/CatalogPresentationChecks.swift -o "$check_dir/catalog"
"$check_dir/catalog"
swiftc App/AIAnswerFailure.swift App/AgentSessionBudget.swift tools/checks/AgentBudgetChecks.swift -o "$check_dir/budget"
"$check_dir/budget"
swiftc App/AIAnswerFailure.swift App/AgentSessionBudget.swift App/LLMModelOption.swift App/LLMProvider.swift App/AgentGenerationPolicy.swift App/AgentOutputBudget.swift App/CloudTokenUsage.swift App/AIAnswerResult.swift App/AgentToolCall.swift App/AgentToolOutcome.swift App/AgentTurn.swift App/AgentRunEvent.swift App/AgentConversationLoop.swift tools/checks/AgentGenerationChecks.swift -o "$check_dir/generation"
"$check_dir/generation"
swiftc App/AIAnswerFailure.swift App/AIAnswerResult.swift App/AgentSessionBudget.swift App/AgentOutputBudget.swift App/AgentRunBudget.swift App/AgentToolCall.swift App/AgentToolOutcome.swift App/AgentTurn.swift App/AgentRunEvent.swift App/AgentConversationLoop.swift tools/checks/AgentRunBudgetChecks.swift -o "$check_dir/run-budget"
"$check_dir/run-budget"
swiftc -swift-version 6 App/AgentInteractionWaiter.swift tools/checks/AgentInteractionChecks.swift -o "$check_dir/interaction"
"$check_dir/interaction"
swiftc -swift-version 6 App/ProjectCitation.swift App/ProjectChatTurn.swift App/ProjectChatThread.swift App/MemoraModel+ProjectChatExecution.swift tools/checks/ProjectChatExecutionChecks.swift -o "$check_dir/project-execution"
"$check_dir/project-execution"
swiftc -swift-version 6 App/ProjectCitation.swift App/ProjectMentionSelection.swift App/ProjectChatTurn.swift App/ProjectChatThread.swift App/ProjectChatHistory.swift App/AIAnswerResult.swift App/AIAnswerFailure.swift App/ScopedAgentAnswer.swift App/MemoraModel+ProjectChatExecution.swift App/MemoraModel+ProjectChat.swift tools/checks/ProjectChatDispatchChecks.swift -o "$check_dir/project-dispatch"
"$check_dir/project-dispatch"
