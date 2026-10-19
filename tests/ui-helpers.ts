import { expect } from 'e2e';

// Native actions wait for the destination to finish moving before touching it.
export async function tapControl(screen: any, locator: any) {
  await expect(locator).toBeVisible();
  await locator.tap();
}

export async function tapTab(screen: any, name: string) {
  // The native Glass selection morph never becomes a static segmented image.
  const control = screen.getByRole('tab', { name, exact: true });
  await expect(control).toBeVisible();
  const box = await control.boundingBox();
  if (!box) throw new Error('tab has no frame');
  await screen.tapAt({ x: box.x + box.width / 2, y: box.y + box.height / 2 });
  await expect(screen.getByRole('tab', { name, exact: true, selected: true })).toBeVisible();
}

export async function focusComposer(screen: any) {
  const input = screen.getByTestId('ai.composer.input');
  await expect(input).toBeVisible();
  // Deep-link autofocus changes this field's frame. Read it after the initial
  // observation, rather than asking XCTest to tap a cached collapsed frame.
  const box = await input.boundingBox();
  if (!box) throw new Error('composer has no frame');
  await screen.tapAt({ x: box.x + box.width / 2, y: box.y + box.height / 2 });
  await expect(screen.getByRole('keyboard')).toBeVisible();
  return input;
}

export async function launchMemora(app: any, device: any, screen: any) {
  // This dedicated test simulator is not Bitrig's preview. Each scenario owns
  // fresh app data; restart *inside* a scenario still tests durable SQLite data.
  await device.installApp(undefined, { reinstall: true });
  await app.restart();
  const skip = screen.getByRole('button', { name: 'スキップ', exact: true });
  const journal = screen.getByRole('tab', { name: 'ジャーナル', exact: true });
  await expect.poll(async () => (await skip.isVisible()) || (await journal.isVisible())).toBe(true);
  if (await skip.isVisible()) {
    // Skip stays still while the onboarding waveform animates.
    const box = await skip.boundingBox();
    if (!box) throw new Error('onboarding skip has no frame');
    await screen.tapAt({ x: box.x + box.width / 2, y: box.y + box.height / 2 });
  }
  await expect(journal).toBeVisible();
}
