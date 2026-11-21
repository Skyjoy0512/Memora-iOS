import type { E2EConfig } from 'e2e';
import { mobile } from '@e2e-dev/mobile';
import { deepSeek } from '@ai-sdk/deepseek';

const simulator = process.env.MEMORA_E2E_SIMULATOR;

// iOS simulator target for the Memora app. The bundle id and the built .app are
// the ones Bitrig produces for this project; agent steps use DeepSeek through
// DEEPSEEK_API_KEY, which is read from the environment and never stored here.
export default {
  agents: {
    default: {
      model: deepSeek('deepseek-chat'),
      system: 'You are a thorough QA agent. Verify every outcome.',
    },
  },
  targets: [
    {
      name: 'ios',
      engine: mobile({
        platform: 'ios',
        device: simulator ?? 'iPhone 18 Pro Max',
        session: simulator ? `memora-${simulator}` : undefined,
        settle: 300,
        transition: 700,
      }),
      app: {
        bundleId: 'app.bitrig.new.811eee03-bad9-4f5e-9d1d-d2820c1e93b4',
        appPath: process.env.MEMORA_E2E_APP_PATH ??
          '/Users/ken/Library/Bitrig/Users/23515/Builds/a8e58691-1b31-4bb3-8c2f-f9dec163a2ea/DerivedData/Build/Products/Debug-iphonesimulator/Memora.app',
      },
    },
  ],
  workers: 1,
  actionTimeout: 10_000,
  assertionTimeout: 10_000,
} satisfies E2EConfig;
