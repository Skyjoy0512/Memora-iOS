#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/memora-marketplace.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
swiftc Shared/MemoraIcon.swift App/CommunityError.swift App/MarketplaceDefinition.swift \
  App/MemoraSkill.swift App/MemoraSkill+Business.swift App/MemoraSkillMarkdown.swift \
  App/SummaryMarketTemplate.swift App/SummaryTemplateCategory.swift App/SummarySensitivity.swift \
  App/SummaryLength.swift App/SummaryTemplate.swift App/SummaryTemplateChoice.swift \
  App/SummaryUseCase.swift App/VideoSummaryTemplate.swift App/SummaryTemplateCatalog.swift \
  App/OccupationSummaryTemplates.swift tools/checks/MarketplaceDefinitionChecks.swift -o "$check_dir/definition"
MEMORA_MARKETPLACE_FIXTURE_PATH="$check_dir/catalog.json" "$check_dir/definition"
MEMORA_MARKETPLACE_FIXTURE_PATH="$check_dir/catalog.json" node --input-type=module - <<'NODE'
import {readFileSync} from 'node:fs';
import {definition} from './backend/marketplace/functions/definition.js';
const all = JSON.parse(readFileSync(process.env.MEMORA_MARKETPLACE_FIXTURE_PATH));
for (const item of all) definition(item);
console.log(`Server accepted all ${all.length} real Swift catalog definitions`);
NODE
npm test --prefix backend/marketplace/functions
