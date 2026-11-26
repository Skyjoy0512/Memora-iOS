#!/usr/bin/env python3
"""Actual approval, outcome aggregation, retry rules and local write-tool branches."""
from pathlib import Path
import os
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
agent = Path('App/MemoraModel+Agent.swift').read_text()
ai = Path('App/MemoraModel+AI.swift').read_text()
tools = Path('App/MemoraModel+AgentTools.swift').read_text()
methods = agent[agent.index('  func runAgentTool('):agent.index('  /// Shows the agent\'s questions')]
methods += ai[ai.index('  func canRetryAIAnswer('):ai.index('  /// Asks the latest question again')]
methods += ai[ai.index('  func aiConversationContext()'):ai.index('  /// The records a question reaches:')]
for start, end in [('  private func saveMemoryTool(', '  // MARK: - Reading'),
                   ('  private func createProjectTool(', '  private func moveRecordsTool('),
                   ('  private func addJournalMemoTool(', '  private func createCalendarEventTool(')]:
    methods += tools[tools.index(start):tools.index(end)].replace('private func', 'func')
with tempfile.TemporaryDirectory(prefix='memora-agent-outcomes-', dir=os.environ.get('MEMORA_CHECK_ROOT')) as temporary:
    root = Path(temporary)
    production = root / 'ProductionOutcomes.swift'
    production.write_text('import Foundation\nextension MemoraModel {\n' + methods + '}\n')
    binary = root / 'checks'
    subprocess.run(['swiftc', 'App/AgentToolOutcome.swift', 'App/AgentToolCall.swift', 'App/AgentInteractionWaiter.swift', 'App/ProjectCitation.swift',
                    'App/MemoraModel+AgentApproval.swift', str(production),
                    'tools/checks/AgentOutcomeChecks.swift', '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, env=dict(os.environ, SWIFT_BACKTRACE='enable=no'))
