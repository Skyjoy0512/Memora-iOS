import type { E2EConfig } from 'e2e';
import { mobile } from '@e2e-dev/mobile';
import base from './e2e.config';

export default {
  ...base,
  targets: [{
    name: 'ios-narrow',
    engine: mobile({ platform: 'ios', device: 'iPhone 18 Pro', settle: 300, transition: 700 }),
    app: base.targets[0].app,
  }],
} satisfies E2EConfig;
