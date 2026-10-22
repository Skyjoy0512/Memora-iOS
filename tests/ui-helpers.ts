import { expect } from 'e2e';

// Native actions wait for the destination to finish moving before touching it.
export async function tapControl(screenOrLocator: any, locator: any = screenOrLocator) {
  await expect(locator).toBeVisible();
  await stableBounds(locator);
  await locator.tap();
}

async function stableBounds(control: any) {
  let box: any;
  let previous = '';
  let stableReads = 0;
  await expect.poll(async () => {
    box = await control.boundingBox();
    if (!box) { stableReads = 0; return false; }
    const signature = [box.x, box.y, box.width, box.height].map(value => value.toFixed(2)).join(',');
    stableReads = signature === previous ? stableReads + 1 : 0;
    previous = signature;
    return stableReads >= 2;
  }).toBe(true);
  return box;
}

export async function tapTab(screen: any, name: string) {
  // Navigation lives in the side menu; the old bottom tab names still work so
  // older scenarios stay readable.
  const destinations: Record<string, string> = {
    'ジャーナル': 'ジャーナル',
    'ホーム': 'ジャーナル',
    'ライブラリ': 'ライブラリ',
  };
  const destination = destinations[name] ?? name;
  await tapControl(screen, screen.getByLabel('メニュー').first());
  await tapControl(screen, screen.getByRole('button', { name: destination, exact: true }));
  await expect(screen.getByLabel('メニュー').first()).toBeVisible();
}

export async function focusComposer(screen: any) {
  const input = screen.getByTestId('ai.composer.input');
  await expect(input).toBeVisible();
  const keyboard = screen.getByRole('keyboard');
  // Deep links already autofocus. A second tap on a moving field can hit the
  // background and dismiss the keyboard instead of focusing the composer.
  if (!(await keyboard.isVisible())) {
    const box = await stableBounds(input);
    if (!(await keyboard.isVisible())) {
      await screen.tapAt({ x: box.x + box.width / 2, y: box.y + box.height / 2 });
    }
  }
  await expect(screen.getByRole('keyboard')).toBeVisible();
  await expect(input).toBeFocused();
  return input;
}

export async function launchMemora(app: any, device: any, screen: any) {
  // This dedicated test simulator is not Bitrig's preview. Each scenario owns
  // fresh app data; restart *inside* a scenario still tests durable SQLite data.
  await device.installApp(undefined, { reinstall: true });
  await app.restart();
  const skip = screen.getByRole('button', { name: 'スキップ', exact: true });
  const menu = screen.getByLabel('メニュー').first();
  await expect.poll(async () => (await skip.isVisible()) || (await menu.isVisible())).toBe(true);
  if (await skip.isVisible()) {
    // Skip stays still while the onboarding waveform animates.
    const box = await skip.boundingBox();
    if (!box) throw new Error('onboarding skip has no frame');
    await screen.tapAt({ x: box.x + box.width / 2, y: box.y + box.height / 2 });
  }
  await expect(menu).toBeVisible();
}

export async function scrollToControl(screen: any, control: any) {
  for (let attempt = 0; attempt < 9; attempt++) {
    if (await control.isVisible()) return;
    await screen.swipe({ from: { x: 215, y: 700 }, to: { x: 215, y: 300 }, duration: 500 });
  }
  await expect(control).toBeVisible();
}

// The gallery lives under the diagnostics topic, not among ordinary preferences.
export async function openSettingsGallery(screen: any) {
  const diagnostics = screen.getByTestId('settings.category.diagnostics').first();
  await scrollToControl(screen, diagnostics);
  await tapControl(screen, diagnostics);
  await tapControl(screen, screen.getByRole('button', { name: '状態と復旧UIを確認', exact: true }));
}
