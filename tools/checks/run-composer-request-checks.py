#!/usr/bin/env python3
"""Suspend production composer preparation and change its live request context."""
from pathlib import Path
import os
import subprocess
import tempfile

os.chdir(Path(__file__).resolve().parents[2])
source = Path('App/QuickAIComposer.swift').read_text()
methods = source[source.index('  private func cancelStaleAttachmentPreparation()'):].rsplit('\n}', 1)[0]
with tempfile.TemporaryDirectory(prefix='memora-composer-request-', dir=os.environ.get('MEMORA_CHECK_ROOT')) as temporary:
    root = Path(temporary)
    fixture = Path('tools/checks/ComposerRequestChecks.swift').read_text()
    production = root / 'ComposerRequestChecks.swift'
    production.write_text(fixture.replace('// PRODUCTION_METHODS', methods))
    links = root / 'ProductionProjectLinks.swift'
    link_source = Path('App/MemoraModel+ProjectSources.swift').read_text()
    link_method = link_source.split('  @discardableResult', 1)[1].split('  func performProjectSourcePreparation', 1)[0]
    links.write_text('import Foundation\nextension MemoraModel {\n  @discardableResult' + link_method + '}\n')
    binary = root / 'checks'
    subprocess.run(['swiftc', 'App/AIAttachment.swift', 'App/ComposerMention.swift',
                    'App/AIQueryScope.swift', 'App/AIQuestionRequest.swift', 'App/LocalImportContext.swift',
                    'App/AIComposerRequestContext.swift', 'App/InlineURLDetector.swift', 'App/ProjectSourceURL.swift',
                    'App/MemoraModel+ProjectQuestionSources.swift', 'App/ProjectQuestionSourceFailure.swift',
                    str(links), str(production), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
