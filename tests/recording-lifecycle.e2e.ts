import { createHash, randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, rmdirSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launchMemora, tapControl, tapTab } from './ui-helpers';
import { isolatedDatabase, sql } from './sqlite-fixture-helpers';

// A short regression by default; an explicit duration runs real wall-clock
// recording, not the accelerated synthetic transcript benchmark.
const backgroundSeconds = Number(process.env.MEMORA_RECORDING_BACKGROUND_SECONDS ?? '10');
if (!Number.isInteger(backgroundSeconds) || backgroundSeconds < 5 || backgroundSeconds > 7_200) {
  throw new Error('MEMORA_RECORDING_BACKGROUND_SECONDS must be an integer from 5 to 7200');
}

async function startIsolatedRecording(app: any, device: any, screen: any) {
  await launchMemora(app, device, screen);
  const marker = 'recording-lifecycle-' + randomUUID();
  await device.openLink('memora://new-memo');
  await screen.getByRole('textbox', { name: 'メモのタイトル', exact: true }).fill(marker);
  await tapControl(screen.getByRole('button', { name: '追加', exact: true }));
  await expect(screen.getByText('ライフログを追加', { exact: true })).not.toBeVisible();
  const { bundleId } = await device.foregroundApp();
  const database = isolatedDatabase(marker, bundleId!);
  const simulator = database.match(/\/Devices\/([A-F0-9-]{36})\/data\//i)?.[1];
  if (!simulator) throw new Error('Cannot identify the isolated recording simulator');
  await device.setPermission('microphone', 'grant');
  await app.restart();
  await tapControl(screen.getByLabel('新規作成').first());
  await tapControl(screen.getByRole('button', { name: '録音を開始', exact: true }));
  await expect(screen.getByRole('button', { name: '終了して保存', exact: true })).toBeVisible();
  // The retained old build predates this control. Baseline mode is used only
  // for the separate SIGKILL durability comparison, never a low-power claim.
  if (process.env.MEMORA_RECORDING_BASELINE !== '1') {
    await tapControl(screen.getByRole('tab', { name: '省電力', exact: true }));
  }
  const document = (key: string) => {
    const value = sql(database, `SELECT CAST(data AS TEXT) FROM documents WHERE key='${key}';`);
    return value ? JSON.parse(value) : null;
  };
  await tapControl(screen.getByRole('button', { name: '重要マークを追加', exact: true }));
  await expect.poll(() => document('memoraRecordingDraft')?.markers?.length ?? 0).toBe(1);
  const draft = document('memoraRecordingDraft');
  expect(draft?.fileName).toMatch(/\.m4a$/);
  const root = dirname(dirname(dirname(dirname(database))));
  const audio = join(root, 'Documents', 'Recordings', draft.fileName.split('/').pop());
  expect(existsSync(audio)).toBe(true);
  const jobs = execFileSync('xcrun', ['simctl', 'spawn', simulator, 'launchctl', 'list'], { encoding: 'utf8' });
  const escapedBundle = bundleId!.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const pids = [...jobs.matchAll(new RegExp(`^(\\d+)\\s+\\S+\\s+UIKitApplication:${escapedBundle}\\[.*$`, 'gm'))];
  if (pids.length !== 1) throw new Error('Cannot uniquely identify the isolated recording process');
  const pid = Number(pids[0][1]);
  const sample = () => {
    const [cpuTime, rss] = execFileSync('/bin/ps', ['-p', String(pid), '-o', 'time=,rss='], { encoding: 'utf8' }).trim().split(/\s+/);
    const [minutes, seconds] = cpuTime.split(':').map(Number);
    return { elapsedSeconds: (performance.now() - started) / 1_000, audioBytes: statSync(audio).size,
      hostCpuSeconds: minutes * 60 + seconds, hostRssKiB: Number(rss) };
  };
  const started = performance.now();
  return { bundleId: bundleId!, database, draft, audio, document, pid, sample };
}

function validateAAC(audio: string) {
  const info = execFileSync('/usr/bin/afinfo', [audio], { encoding: 'utf8', timeout: 10_000 });
  expect(info).toMatch(/44100 Hz/);
  expect(info).toMatch(/1 ch,/);
  expect(info).toMatch(/aac/);
  expect(info).toMatch(/audio packets: [1-9]/);
  const duration = Number(info.match(/estimated duration: ([0-9.]+)/)![1]);
  const directory = mkdtempSync(join(process.env.MEMORA_CHECK_TMPDIR ?? tmpdir(), 'memora-lifecycle-aac-'));
  const decoded = join(directory, 'decoded.wav');
  try {
    execFileSync('/usr/bin/afconvert', ['-f', 'WAVE', '-d', 'LEI16', audio, decoded], { timeout: 30_000 });
    const pcm = execFileSync('/usr/bin/afinfo', [decoded], { encoding: 'utf8', timeout: 10_000 });
    const decodedDuration = Number(pcm.match(/estimated duration: ([0-9.]+)/)![1]);
    expect(Math.abs(decodedDuration - duration)).toBeLessThan(0.001);
    return { duration, decodedDuration, bytes: statSync(audio).size, info };
  } finally {
    if (existsSync(decoded)) rmSync(decoded);
    rmdirSync(directory);
  }
}

test('background low-power recording keeps the same draft and a complete decodable AAC',
  { timeout: backgroundSeconds * 1_000 + 240_000 }, async ({ app, device, screen }) => {
    const capture = await startIsolatedRecording(app, device, screen);
    const samples = [capture.sample()];
    const backgroundStarted = performance.now();
    await device.home();
    // Only read the process/files here. Reading the app's AX tree would bring
    // it back to the foreground and invalidate a background recording test.
    await expect.poll(() => {
      const sample = capture.sample();
      samples.push(sample);
      expect(capture.document('memoraRecordingDraft')?.fileName).toBe(capture.draft.fileName);
      return performance.now() - backgroundStarted >= backgroundSeconds * 1_000
        && sample.audioBytes > samples[0].audioBytes;
    }, { timeout: backgroundSeconds * 1_000 + 30_000, interval: 5_000 }).toBe(true);
    const actualBackgroundSeconds = (performance.now() - backgroundStarted) / 1_000;
    await device.openApp(capture.bundleId);
    await expect(screen.getByRole('button', { name: '一時停止', exact: true })).toBeVisible();
    await expect(screen.getByText('省電力動作中：ライブ認識と音量アニメーションを休止。録音品質は変わりません。', { exact: true })).toBeVisible();
    expect(capture.document('memoraRecordingDraft')?.fileName).toBe(capture.draft.fileName);
    await app.screenshot('recording-after-background');
    await tapControl(screen.getByRole('button', { name: '終了して保存', exact: true }));
    await expect.poll(() => capture.document('memoraRecordingDraft')).toBeNull();
    const record = capture.document('memoraMeetings').find((item: any) => item.id === capture.draft.id);
    expect(record).toBeDefined();
    expect(record.audioURL).toBe(capture.draft.fileName);
    const audio = validateAAC(capture.audio);
    expect(audio.duration).toBeGreaterThanOrEqual(actualBackgroundSeconds - 1);
    console.log('RECORDING_LIFECYCLE_EVIDENCE=' + JSON.stringify({ scenario: 'background-low-power',
      requestedBackgroundSeconds: backgroundSeconds, actualBackgroundSeconds,
      sampleCount: samples.length, samples: [samples[0], samples[samples.length - 1]],
      minimumSampledRssKiB: Math.min(...samples.map(sample => sample.hostRssKiB)),
      maximumSampledRssKiB: Math.max(...samples.map(sample => sample.hostRssKiB)), audio,
      caveat: 'Simulator input; host process CPU/RSS, not device battery, thermal state, or speech quality' }));
  });

test('SIGKILL recovers one recording without replacing the audio or restarting capture',
  { timeout: 240_000 }, async ({ app, device, screen }) => {
    const capture = await startIsolatedRecording(app, device, screen);
    const firstSize = statSync(capture.audio).size;
    await expect.poll(() => statSync(capture.audio).size, { timeout: 30_000, interval: 1_000 }).toBeGreaterThan(firstSize);
    // PID comes only from this UI-marked test container's selected simulator.
    process.kill(capture.pid, 'SIGKILL');
    await expect.poll(() => {
      try { process.kill(capture.pid, 0); return false; }
      catch { return true; }
    }).toBe(true);
    const original = createHash('sha256').update(readFileSync(capture.audio)).digest('hex');
    expect(capture.document('memoraRecordingDraft')?.id).toBe(capture.draft.id);
    // Durability and container readability are distinct. This probe records
    // the existing unfinalized-AAC limitation without claiming playable audio.
    let readable = true;
    try { execFileSync('/usr/bin/afinfo', [capture.audio], { stdio: 'pipe' }); }
    catch { readable = false; }
    await app.restart();
    await expect(screen.getByLabel('メニュー').first()).toBeVisible();
    await expect.poll(() => capture.document('memoraRecordingDraft')).toBeNull();
    const recovered = () => capture.document('memoraMeetings').filter((record: any) => record.id === capture.draft.id);
    expect(recovered()).toHaveLength(1);
    expect(recovered()[0].audioURL).toBe(capture.draft.fileName);
    const expectsReadFailure = !readable && process.env.MEMORA_RECORDING_BASELINE !== '1';
    if (expectsReadFailure) {
      expect(recovered()[0].status.failed?._0).toContain('音声の長さを確認できません');
      expect(recovered()[0].duration).toBe(0);
      expect(recovered()[0].recordingMarkers).toEqual(capture.draft.markers);
      await tapTab(screen, 'ライブラリ');
      await tapControl(screen.getByRole('button', { name: new RegExp('^' + recovered()[0].title) }).first());
      await expect(screen.getByText('処理を完了できませんでした', { exact: true })).toBeVisible();
      await expect(screen.getByText(/元のファイルは変更していません/)).toBeVisible();
      await expect(screen.getByText(/時間不明/).first()).toBeVisible();
      await expect(screen.getByRole('button', { name: '文字起こしを開始', exact: true })).not.toBeVisible();
      await device.setAppearance('dark');
      await app.screenshot('recording-read-failure-dark');
      await device.setAppearance('light');
    } else {
      expect(recovered()[0].status).toEqual({ waitingForTranscription: {} });
    }
    expect(recovered()[0].transcript).toEqual([]);
    expect(createHash('sha256').update(readFileSync(capture.audio)).digest('hex')).toBe(original);
    await expect(screen.getByRole('button', { name: /録音を続けています/ })).not.toBeVisible();
    const audio = readable ? validateAAC(capture.audio) : { readable: false, bytes: statSync(capture.audio).size };
    await app.screenshot('recording-recovered-after-sigkill');
    await app.restart();
    await expect(screen.getByLabel('メニュー').first()).toBeVisible();
    expect(recovered()).toHaveLength(1);
    if (expectsReadFailure) expect(recovered()[0].recordingMarkers).toEqual(capture.draft.markers);
    expect(capture.document('memoraLifeLogEntries').filter((entry: any) => entry.meetingID === capture.draft.id)).toHaveLength(1);
    expect(createHash('sha256').update(readFileSync(capture.audio)).digest('hex')).toBe(original);
    console.log('RECORDING_LIFECYCLE_EVIDENCE=' + JSON.stringify({ scenario: 'sigkill-recovery',
      baseline: process.env.MEMORA_RECORDING_BASELINE === '1', recoveryCount: recovered().length,
      audioUnchanged: true, audio, readable, markerCount: recovered()[0].recordingMarkers?.length,
      recoveryStatus: recovered()[0].status,
      caveat: 'Simulator SIGKILL only; not a real-device call, route loss, storage failure, or power loss test' }));
  });

test('a finalized AAC staged as a recovery draft still offers manual transcription',
  { timeout: 240_000 }, async ({ app, device, screen }) => {
    const capture = await startIsolatedRecording(app, device, screen);
    await tapControl(screen.getByRole('button', { name: '終了して保存', exact: true }));
    await expect.poll(() => capture.document('memoraRecordingDraft')).toBeNull();
    const audio = validateAAC(capture.audio);
    const original = createHash('sha256').update(readFileSync(capture.audio)).digest('hex');
    await device.closeApp();
    // Only this fresh, UI-marked test container is staged. This verifies the
    // readable branch; it does not claim SIGKILL produced finalized audio.
    const draft = { ...capture.draft, title: '確定済みAACの復旧確認', note: '復旧後も残す架空の録音メモ' };
    const meetings = capture.document('memoraMeetings').filter((record: any) => record.id !== draft.id);
    const entries = capture.document('memoraLifeLogEntries').filter((entry: any) => entry.id !== draft.id && entry.meetingID !== draft.id);
    const writes = [['memoraMeetings', meetings], ['memoraLifeLogEntries', entries], ['memoraRecordingDraft', draft]];
    sql(capture.database, 'BEGIN IMMEDIATE; ' + writes.map(([key, value]) => {
      const hex = Buffer.from(JSON.stringify(value)).toString('hex');
      return `INSERT OR REPLACE INTO documents(key,data,updated_at) VALUES ('${key}',X'${hex}',0);`;
    }).join(' ') + ' COMMIT;');
    await app.restart();
    await expect.poll(() => capture.document('memoraRecordingDraft')).toBeNull();
    const recovered = () => capture.document('memoraMeetings').filter((record: any) => record.id === draft.id);
    expect(recovered()).toHaveLength(1);
    expect(recovered()[0].status).toEqual({ waitingForTranscription: {} });
    expect(recovered()[0].notes).toBe(draft.note);
    expect(recovered()[0].recordingMarkers).toEqual(draft.markers);
    expect(recovered()[0].audioURL).toBe(draft.fileName);
    expect(Math.abs(recovered()[0].duration - audio.duration)).toBeLessThan(0.1);
    await tapTab(screen, 'ライブラリ');
    await tapControl(screen.getByRole('button', { name: new RegExp('^' + draft.title) }).first());
    await expect(screen.getByText('文字起こしはまだ始まっていません', { exact: true })).toBeVisible();
    await expect(screen.getByRole('button', { name: '文字起こしを開始', exact: true })).toBeEnabled();
    await app.screenshot('recording-readable-recovery');
    await app.restart();
    await expect(screen.getByLabel('メニュー').first()).toBeVisible();
    expect(recovered()).toHaveLength(1);
    expect(recovered()[0].recordingMarkers).toEqual(draft.markers);
    expect(createHash('sha256').update(readFileSync(capture.audio)).digest('hex')).toBe(original);
    console.log('RECORDING_LIFECYCLE_EVIDENCE=' + JSON.stringify({ scenario: 'finalized-aac-recovery-fixture',
      manualTranscriptionOnly: true, markerCount: draft.markers.length, audioUnchanged: true,
      duration: audio.duration, caveat: 'Real AAC recording, staged draft; not a playable SIGKILL recovery claim' }));
  });
