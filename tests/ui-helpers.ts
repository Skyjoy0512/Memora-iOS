import { expect } from 'e2e';

// Native actions wait for the destination to finish moving before touching it.
export async function tapControl(screenOrLocator: any, locator: any = screenOrLocator) {
  await expect(locator).toBeVisible();
  await stableBounds(locator);
  await locator.tap();
}

// agent-device's fill clears by tapping the middle-right of a multiline field
// and sending at most 120 backspaces. That is not Select All and leaves text
// after the caret. Exercise UIKit's actual selection/paste actions instead.
export async function replaceEditorWithPaste(screen: any, device: any, editor: any, value: string) {
  await device.setClipboard(value);
  await selectAllEditorText(screen, editor);
  await tapControl(await nativeEditMenuItem(screen, /^(ペースト|Paste)$/));
  await expect(editor).toHaveValue(value);
}

export async function selectAllEditorText(screen: any, editor: any) {
  await expect(editor).toBeFocused();
  await stableBounds(editor);
  // A multiline field's centre may be empty space after a short last line.
  // Tap actual text, then tap the caret to open UIKit's editing menu.
  await editor.tap({ position: { x: 12, y: 10 } });
  await stableBounds(editor);
  const name = /^(すべてを選択|全選択|Select All)$/;
  const visible = async () => await screen.getByRole('menuitem', { name }).isVisible()
    || await screen.getByRole('listitem', { name }).isVisible();
  if (!(await visible())) await editor.tap({ position: { x: 12, y: 10 } });
  await tapControl(await nativeEditMenuItem(screen, name));
}

async function nativeEditMenuItem(screen: any, name: RegExp) {
  // UIKit exposes both edit-menu presentations: the table cell is a menuitem,
  // while the transcript's system callout contains listitems on the same OS.
  const menu = screen.getByRole('menuitem', { name });
  const callout = screen.getByRole('listitem', { name });
  await expect.poll(async () => await menu.isVisible() || await callout.isVisible()).toBe(true);
  return await menu.isVisible() ? menu : callout;
}

export async function openSummaryImageMenu(screen: any) {
  const image = screen.getByTestId('summary.poster.inline');
  for (let attempt = 0; attempt < 12; attempt++) {
    const box = await image.boundingBox();
    if (box && box.y + box.height / 2 >= 150 && box.y + box.height / 2 <= 650) break;
    const downward = !box || box.y + box.height / 2 > 650;
    await screen.swipe({ from: { x: 215, y: downward ? 650 : 300 }, to: { x: 215, y: downward ? 400 : 550 }, duration: 500 });
  }
  await stableBounds(image);
  await image.longPress({ duration: 800 });
  await expect(screen.getByRole('button', { name: '拡大・共有', exact: true })).toBeVisible();
}

export async function openSummaryPoster(screen: any) {
  await openSummaryImageMenu(screen);
  await tapControl(screen.getByRole('button', { name: '拡大・共有', exact: true }));
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
  const destination = name === 'ホーム' ? 'ジャーナル' : name;
  const ids: Record<string, string> = { 'ライブラリ': 'files', 'ジャーナル': 'home', 'Ask AI': 'askAI' };
  const id = ids[destination];
  if (id) {
    const tab = screen.getByTestId(`root.tab.${id}`);
    const closeMarketplace = screen.getByTestId('marketplace.close');
    if (await closeMarketplace.isVisible()) await tapControl(closeMarketplace);
    const back = screen.getByTestId('BackButton').first();
    for (let depth = 0; depth < 4 && !await tab.isVisible() && await back.isVisible(); depth++) {
      await tapControl(back);
    }
    const selected = screen.getByRole('button', { name: destination, exact: true, selected: true });
    if (!await selected.isVisible()) await tapControl(tab);
    await expect(tab).toBeSelected();
    return;
  }
  await tapControl(screen, screen.getByLabel('メニュー').first());
  const auxiliary = destination === 'ツール' ? 'マーケットプレイス' : destination;
  await tapControl(screen, screen.getByRole('button', { name: auxiliary, exact: true }));
}

// At accessibility text sizes the Library's segmented control collapses into
// a "表示と並べ替え" menu. Hiding that condition in the tests keeps the same
// destination without changing the app.
export async function selectLibrarySection(screen: any, name: string) {
  const direct = screen.getByRole('button', { name, exact: true });
  const menu = screen.getByRole('button', { name: /ライブラリの表示/ }).first();
  await expect.poll(async () => await direct.isVisible() || await menu.isVisible()).toBe(true);
  if (await direct.isVisible()) { await tapControl(screen, direct); return; }
  await tapControl(screen, menu);
  await tapControl(screen, screen.getByRole('button', { name, exact: true }).last());
}

export async function openSidebarSearch(screen: any) {
  await tapControl(screen, screen.getByLabel('メニュー').first());
  await tapControl(screen, screen.getByTestId('sidebar.search'));
  const input = screen.getByRole('textbox', { visible: true }).first();
  await expect(input).toBeVisible();
  await stableBounds(input);
  await input.tap();
  await expect(input).toBeFocused();
}

export async function focusComposer(screen: any) {
  const input = screen.getByTestId('ai.composer.input');
  await expect(input).toBeVisible();
  // Deep links already autofocus. A second tap on a moving field can hit the
  // background and dismiss focus instead of focusing the composer. A hardware
  // keyboard attached to the simulator has no soft-keyboard node, so focus is
  // the reliable signal.
  let focused = false;
  try {
    await expect(input).toBeFocused({ timeout: 1_000 });
    focused = true;
  } catch {}
  if (!focused) {
    const box = await stableBounds(input);
    await screen.tapAt({ x: box.x + box.width / 2, y: box.y + box.height / 2 });
  }
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
  const open = screen.getByRole('button', { name: '開く', exact: true });
  // Onboarding can raise the microphone prompt before the first screen is
  // readable. Decline it so the flow continues; scenarios that need the
  // microphone set their own permission.
  const denyMicrophone = screen.getByRole('button', { name: '許可しない', exact: true });
  const ready = async () => {
    try {
      return await skip.isVisible() || await menu.isVisible() || await open.isVisible()
        || await denyMicrophone.isVisible();
    } catch {
      return false;
    }
  };
  await expect.poll(ready).toBe(true);
  if (await denyMicrophone.isVisible()) await denyMicrophone.tap();
  await expect.poll(async () => (await skip.isVisible()) || (await menu.isVisible()) || (await open.isVisible())).toBe(true);
  if (!await skip.isVisible() && !await menu.isVisible() && await open.isVisible()) {
    // A previous interrupted deep-link test can leave the system consent
    // alert above a freshly installed app. Dismiss it before onboarding.
    await tapControl(screen.getByRole('button', { name: 'キャンセル', exact: true }));
    await app.restart();
  }
  await expect.poll(async () => (await skip.isVisible()) || (await menu.isVisible())).toBe(true);
  if (await skip.isVisible()) {
    // Skip stays still while the onboarding waveform animates.
    const box = await skip.boundingBox();
    if (!box) throw new Error('onboarding skip has no frame');
    await screen.tapAt({ x: box.x + box.width / 2, y: box.y + box.height / 2 });
  }
  await requireRootMenu(app, screen);
}

export async function requireRootMenu(app: any, screen: any) {
  const menu = screen.getByLabel('メニュー').first();
  try {
    await expect(menu).toBeVisible({ timeout: 4_000 });
  } catch {
    // After a fresh install the simulator sometimes exposes only the app
    // container even with Library visible. Relaunch once to reattach the driver.
    await app.restart();
    await expect(menu).toBeVisible();
  }
}

export async function scrollToControl(screen: any, control: any, frame?: { minimumY: number; maximumY: number }, header?: any) {
  // A section header pins under the navigation bar once the page scrolls, and
  // content keeps moving beneath it: a control that reads as on screen there is
  // still covered and takes no tap. Measure from the pinned edge when it is.
  const visibleTop = async () => {
    if (!frame) return 300;
    const pinned = header ? await header.boundingBox() : null;
    return pinned && pinned.y < 400
      ? Math.max(frame.minimumY, pinned.y + pinned.height)
      : frame.minimumY;
  };
  const settles = async () => {
    try {
      if (!await control.isVisible()) return false;
      if (!frame) return true;
      const box = await control.boundingBox();
      return !!box && box.y >= await visibleTop() && box.y + box.height <= frame.maximumY;
    } catch {
      return false;
    }
  };
  if (await settles()) return;
  // Swipe inside the band between the page header and the fixed bottom
  // controls. A gesture that starts over a floating action never reaches the
  // scroll view, and a downward drag at the page's top reverses the zoom
  // navigation transition and leaves the screen entirely.
  const band = async () => {
    const top = frame ? (await visibleTop()) + 24 : 300;
    let bottom = frame ? frame.maximumY - 24 : 700;
    if (!frame) {
      // A keyboard owns the bottom of the screen; a gesture that runs into it
      // is refused rather than scrolling the page behind it.
      try {
        const keyboard = screen.getByRole('keyboard');
        const box = await keyboard.isVisible() ? await keyboard.boundingBox() : null;
        if (box) bottom = Math.min(bottom, box.y - 24);
      } catch {}
    }
    const travel = Math.max(120, Math.min(bottom - top - 40,
      frame ? Math.min(420, frame.maximumY - top - 80) : 400));
    return { top, bottom, travel };
  };
  for (let attempt = 0; attempt < 12; attempt++) {
    if (await settles()) return;
    const { bottom, travel } = await band();
    await screen.swipe({ from: { x: 215, y: bottom }, to: { x: 215, y: bottom - travel }, duration: 500 });
  }
  // Coming back only in short steps, so the page is never dragged past its top.
  for (let attempt = 0; attempt < 12; attempt++) {
    if (await settles()) return;
    const { top, travel } = await band();
    await screen.swipe({ from: { x: 215, y: top }, to: { x: 215, y: top + Math.max(60, travel / 3) }, duration: 500 });
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

// A restart can leave the driver attached to the closing scene for a moment.
// Wait for the root again, relaunching once, before driving the tab bar.
export async function restartToLibrary(app: any, screen: any) {
  await app.restart();
  await requireRootMenu(app, screen);
  await tapTab(screen, 'ライブラリ');
}
