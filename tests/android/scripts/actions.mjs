import { execFileSync } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';

const results = fileURLToPath(new URL('../results/', import.meta.url));
const statePath = fileURLToPath(new URL('../results/device-state.json', import.meta.url));
const device = process.env.CASHFLOW_ANDROID_DEVICE ?? 'emulator-5554';
const pkg = 'com.example.cash_app.offlineqa';
const origin = 'http://127.0.0.1:18742';
const adb = (...args) => execFileSync(process.env.ADB_PATH ?? 'adb', ['-s', device, ...args], { encoding: 'utf8', timeout: 20000 }).trim();
const status = async () => (await fetch(`${origin}/__qa/status`)).json();
const control = async (body) => {
  const response = await fetch(`${origin}/__qa/control`, { method: 'POST', body: JSON.stringify(body) });
  if (!response.ok) throw new Error('Cannot control synthetic API');
  await response.json();
};
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const networkReady = async () => {
  const deadline = Date.now() + 15000;
  while (true) {
    try { adb('shell', 'ping', '-c', '1', '-W', '1', '10.0.2.2'); return; }
    catch {
      if (Date.now() >= deadline) throw new Error('Emulator host route did not reconnect');
      await pause(100);
    }
  }
};

export async function action(name) {
  if (!/^emulator-\d+$/.test(device)) throw new Error('Only a dedicated Android emulator is supported');
  await mkdir(results, { recursive: true });
  let state = await readFile(statePath, 'utf8').then(JSON.parse).catch(() => ({ device, runs: [] }));
  if (state.device !== device) throw new Error('Device state belongs to another emulator');
  if (name === 'prepare') {
    state.originalWifi ??= adb('shell', 'settings', 'get', 'global', 'wifi_on');
    state.originalData ??= adb('shell', 'settings', 'get', 'global', 'mobile_data');
    state.originalHandwriting ??= adb('shell', 'settings', 'get', 'secure', 'stylus_handwriting_enabled');
    await writeFile(statePath, JSON.stringify(state, null, 2));
    adb('shell', 'svc', 'wifi', 'enable');
    adb('shell', 'svc', 'data', 'enable');
    // API 36's Gboard stylus tutorial can steal focus from injected touch input.
    // It is device setup, not application behavior; restore it during cleanup.
    adb('shell', 'settings', 'put', 'secure', 'stylus_handwriting_enabled', '0');
    await control({ mode: 'online', percent: 5, reset: true });
    if (adb('shell', 'pm', 'clear', pkg) !== 'Success') throw new Error('Cannot reset the isolated QA package');
    await networkReady();
  } else if (name === 'wait-warm') {
    const deadline = Date.now() + 10000;
    while (!(await status()).calls.some((call) => call.path === '/api/partner-offers' && call.completed)) {
      if (Date.now() > deadline) throw new Error('Initial authenticated refresh did not complete');
      await pause(100);
    }
  } else if (name === 'offline' || name === 'hanging') {
    await control({ mode: name, reset: true });
    adb('shell', 'svc', 'wifi', name === 'offline' ? 'disable' : 'enable');
    adb('shell', 'svc', 'data', name === 'offline' ? 'disable' : 'enable');
    if (name === 'offline' && (adb('shell', 'settings', 'get', 'global', 'wifi_on') !== '0' || adb('shell', 'settings', 'get', 'global', 'mobile_data') !== '0')) throw new Error('Radios were not disabled');
    if (name === 'hanging') await networkReady();
    state.marker = randomUUID();
    state.mode = name;
    state.started = Date.now();
    adb('shell', 'log', '-p', 'i', '-t', 'CashflowOfflineQa', state.marker);
  } else if (name === 'assert-startup') {
    const raw = adb('logcat', '-d', '-v', 'brief', '-s', 'CashflowOfflineQa:I', 'ActivityTaskManager:I');
    const sinceMarker = raw.slice(raw.lastIndexOf(state.marker));
    const line = sinceMarker.split('\n').find((value) => value.includes(`Fully drawn ${pkg}/`));
    if (!line) throw new Error('No Android fully-drawn timing for the cached UI');
    const duration = line.match(/:\s*\+([\w.]+)/)?.[1];
    const units = { ms: 1, s: 1000, m: 60000, h: 3600000 };
    const usefulFrameMs = [...(duration ?? '').matchAll(/(\d+)(ms|s|m|h)/g)].reduce((sum, part) => sum + Number(part[1]) * units[part[2]], 0);
    if (!usefulFrameMs) throw new Error('Invalid Android fully-drawn timing');
    const budgetMs = Number(process.env.OFFLINE_STARTUP_BUDGET_MS ?? 2000);
    state.runs.push({ mode: state.mode, usefulFrameMs, budgetMs, at: new Date().toISOString(), device });
    await writeFile(statePath, JSON.stringify(state, null, 2));
    if (usefulFrameMs > budgetMs) throw new Error(`Cached useful frame took ${usefulFrameMs} ms; budget is ${budgetMs} ms`);
    const server = await status();
    if (server.calls.some((call) => call.completed)) throw new Error('API answered during the offline startup');
    if (state.mode === 'hanging' && !server.pending) throw new Error('No API request is actually pending');
    console.log(`PASS ${state.mode}: Android cached useful frame ${usefulFrameMs} ms`);
  } else if (name === 'hold-30s') {
    await pause(Math.max(0, 30000 - (Date.now() - state.started)));
    const server = await status();
    if (server.mode !== 'hanging' || !server.pending || server.calls.some((call) => call.completed)) throw new Error('API did not stay blocked for the full window');
  } else if (name === 'restore-nine' || name === 'restore-thirteen') {
    adb('shell', 'svc', 'wifi', 'enable');
    adb('shell', 'svc', 'data', 'enable');
    await networkReady();
    await control({ mode: 'online', percent: name === 'restore-nine' ? 9 : 13 });
  } else if (name === 'cleanup') {
    if (state.originalHandwriting === 'null') adb('shell', 'settings', 'delete', 'secure', 'stylus_handwriting_enabled');
    else if (state.originalHandwriting != null) adb('shell', 'settings', 'put', 'secure', 'stylus_handwriting_enabled', state.originalHandwriting);
    adb('shell', 'svc', 'wifi', state.originalWifi === '0' ? 'disable' : 'enable');
    adb('shell', 'svc', 'data', state.originalData === '0' ? 'disable' : 'enable');
    await control({ mode: 'online' });
    const server = await status();
    if (server.unexpected.length) throw new Error(`Unexpected test API calls: ${server.unexpected.join(', ')}`);
  } else throw new Error(`Unknown Android test action: ${name}`);
  await writeFile(statePath, JSON.stringify(state, null, 2));
}
