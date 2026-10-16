// Real Android IME + KEYCODE_BACK. Widget handlePopRoute cannot test IME order.
import { mkdir, writeFile } from 'node:fs/promises';
import { Device, find, findAll, summarize } from './lib/device.mjs';

const pkg = 'com.example.cash_app.offlineqa';
const device = new Device(process.env.CASHFLOW_ANDROID_DEVICE);
const only = process.argv.includes('--only') ? process.argv[process.argv.indexOf('--only') + 1] : '';
const pass = process.env.BACK_PASS ?? '1';
const results = new URL('./results/', import.meta.url);
await mkdir(results, { recursive: true });
const report = { startedAt: new Date().toISOString(), device: device.serial, pkg,
  apiLevel: device.shell('getprop', 'ro.build.version.sdk'), ime: device.setting('secure', 'default_input_method'),
  contract: 'Back with IME visible hides only IME; same screen, same field value. Second hardware Back navigates where specified.', rows: [] };
const tap = async (selector) => device.tap(await device.waitFor(n => find(n, selector), { what: JSON.stringify(selector) }));
const screen = async selector => device.waitFor(n => find(n, selector), { what: JSON.stringify(selector) });
const tab = name => tap({ text: name });
const more = async () => { await tab('Ещё'); await screen({ text: 'Карты и категории' }); };
const cards = async () => { await more(); await tap({ text: 'Карты и категории' }); };
const settings = async name => { await more(); await tap({ text: name }); };
const user = async () => { await settings('Владельцы карт'); await tap({ id: 'edit-user-21' }); };
const bank = async () => { await settings('Банки'); await tap({ id: 'edit-bank-11' }); };
const card = async () => { await settings('Карты'); await tap({ id: 'edit-card-31' }); };
const subscription = async () => { await tab('Подписки'); await tap({ text: 'Добавить' }); };

const scenarios = [
  { name: 'benefit / search / root', open: async () => {}, screen: { id: 'benefit-search' }, field: { editable: true }, text: 'qa' },
  { name: 'benefit / MCC internal detail', open: async () => {}, screen: { id: 'benefit-search' }, typedScreen: { text: 'QA groceries' }, field: { editable: true }, text: '5411' },
  { name: 'benefit / category detail search', open: async () => { await tap({ text: 'Продукты и супермаркеты' }); }, screen: { text: 'К результатам' }, field: { editable: true }, text: 'Offline' },
  { name: 'offers / search', open: () => tab('Акции'), screen: { exact: 'Акции' }, field: { editable: true }, text: 'qa', parent: { id: 'benefit-search' } },
  { name: 'plan / add categories dialog', open: async () => { await tab('План'); await tap({ text: 'Добавить потребность' }); }, screen: { text: 'Добавить категории' }, field: { editable: true }, text: 'qa', parent: { text: 'Добавить потребность' } },
  { name: 'cards / search', open: cards, screen: { exact: 'Карты и категории' }, field: { editable: true }, text: 'qa', parent: { text: 'Расчётная дата кешбэка' }, arrow: true },
  { name: 'user / name', open: user, screen: { text: 'Пользователь' }, field: { text: 'Имя', editable: true }, text: 'qa', parent: { text: 'Manage Users' }, arrow: true },
  { name: 'emoji / search', open: async () => { await user(); await tap({ text: 'Эмодзи пользователя' }); }, screen: { text: 'Эмодзи пользователя' }, typedScreen: { text: 'Поиск эмодзи', editable: true }, field: { text: 'Поиск эмодзи', editable: true }, text: 'cat', parent: { text: 'Имя' }, arrow: true },
  { name: 'bank / name', open: bank, screen: { text: 'Edit Bank' }, field: { text: 'Bank Name', editable: true }, text: 'qa', parent: { text: 'Banks' }, arrow: true },
  { name: 'bank / description', open: bank, screen: { text: 'Edit Bank' }, field: { text: 'Description', editable: true }, text: 'qa', parent: { text: 'Banks' }, arrow: true },
  { name: 'card / payment system', open: card, screen: { text: 'Edit Card' }, field: { text: 'Payment System', editable: true }, text: 'qa', parent: { text: 'Cards' }, arrow: true },
  { name: 'card / type', open: card, screen: { text: 'Edit Card' }, field: { text: 'Card Type', editable: true }, text: 'qa', parent: { text: 'Cards' }, arrow: true },
  { name: 'subscription / name', open: subscription, screen: { text: 'Новая подписка' }, field: { text: 'Название', editable: true }, text: 'qa', parent: { exact: 'Подписки' }, arrow: true },
  { name: 'subscription / amount', open: subscription, screen: { text: 'Новая подписка' }, field: { text: 'Сумма', editable: true }, text: '123', parent: { exact: 'Подписки' }, arrow: true },
];

async function coldStart() {
  device.forceStop(pkg); device.launch(pkg);
  await screen({ id: 'benefit-search' });
}
function check(row, step, condition, detail) {
  row.steps.push({ step, ok: Boolean(condition), detail });
  if (!condition) { const e = new Error(step); e.assertion = true; throw e; }
}
async function run(s, mode) {
  const row = { name: s.name, mode, phase: 'setup', steps: [], status: 'running' };
  report.rows.push(row);
  try {
    await coldStart(); await s.open(); await screen(s.screen);
    check(row, 'screen identity', true, s.screen);
    await tap(s.field);
    check(row, 'keyboard shown before Back', await device.waitIme(true), undefined);
    const focused = find(device.dump(), { editable: true, focused: true });
    check(row, 'editable focused', focused, undefined);
    device.typeAscii(s.text);
    const typed = await device.waitFor(n => findAll(n, { editable: true }).find(f => f.text.toLowerCase().includes(s.text.toLowerCase())), { what: 'typed marker' });
    const value = typed.text;
    check(row, 'marker entered', true, value);
    await screen(s.typedScreen ?? s.screen);
    // An MCC query changes internal navigation state; establish identity after typing.
    const before = summarize(device.dump());
    row.phase = 'back';
    if (mode === 'hardware') device.back();
    else await tap({ exact: 'Back' });
    const imeHidden = await device.waitIme(false);
    const nodes = device.dump();
    row.observed = { imeHidden, sameScreen: Boolean(find(nodes, s.typedScreen ?? s.screen)), sameText: findAll(nodes, { editable: true }).some(f => f.text === value), before, after: summarize(nodes) };
    // Record every aspect before failing so reversed navigation is distinguishable.
    check(row, 'Back hides only keyboard, keeps screen and text', imeHidden && row.observed.sameScreen && row.observed.sameText, row.observed);
    if (s.parent) {
      if (mode === 'hardware') device.back();
      else await tap({ exact: 'Back' });
      const parent = await screen(s.parent).catch(() => null);
      check(row, 'second Back reaches parent', parent, s.parent);
      check(row, 'second Back navigates', true, s.parent);
    }
    if (s.name === 'benefit / MCC internal detail') {
      device.back();
      const parentNodes = device.dump();
      check(row, 'second Back closes MCC result', !find(parentNodes, s.typedScreen)
        && find(parentNodes, { id: 'benefit-search' })?.text === '', summarize(parentNodes));
    }
    check(row, 'no keyboard on parent', await device.waitIme(false), undefined);
    row.status = 'passed';
  } catch (e) {
    row.status = e.assertion && row.phase === 'back' ? 'failed' : 'error'; row.error = e.message;
    row.screen = e.screen ?? summarize(device.dump());
    if (row.status === 'failed' && row.observed && !row.observed.imeHidden && mode === 'hardware') {
      // Diagnose the reported reversed order without changing the first-Back verdict.
      device.back();
      row.afterSecondBack = { imeHidden: await device.waitIme(false), screen: summarize(device.dump()) };
    }
  }
  console.log(`${row.status.toUpperCase()} ${mode}: ${s.name}${row.error ? `: ${row.error}` : ''}`);
  await writeFile(new URL(`back-pass-${pass}.json`, results), JSON.stringify(report, null, 2));
}

const oldHandwriting = device.setting('secure', 'stylus_handwriting_enabled');
try {
  if (!scenarios.some(s => !only || s.name.includes(only))) throw new Error(`No scenarios match ${only}`);
  if (device.shell('getprop', 'ro.kernel.qemu') !== '1') throw new Error('Refusing non-emulator');
  if (!device.shell('pm', 'path', pkg).startsWith('package:')) throw new Error('Install verified isolated QA APK first');
  device.putSetting('secure', 'stylus_handwriting_enabled', '0');
  device.clearApp(pkg); device.launch(pkg);
  await tap({ id: 'login-username' }); device.typeAscii('offline-reader');
  await tap({ id: 'login-password' }); device.typeAscii('synthetic-test-password');
  device.back(); await tap({ exact: 'Войти' }); await screen({ id: 'benefit-search' });
  for (const s of scenarios) {
    if (only && !s.name.includes(only)) continue;
    await run(s, 'hardware');
    if (s.arrow) await run(s, 'app-bar');
  }
  const status = await (await fetch('http://127.0.0.1:18742/__qa/status')).json();
  report.unexpectedApi = status.unexpected;
  if (status.calls.some(c => c.method !== 'GET' && c.path !== '/api/auth/login')) throw new Error('Unexpected data mutation request');
} catch (error) {
  report.setupError = error.message;
  throw error;
} finally {
  device.putSetting('secure', 'stylus_handwriting_enabled', oldHandwriting);
  report.finishedAt = new Date().toISOString();
  report.summary = Object.fromEntries(['passed', 'failed', 'error'].map(status => [status, report.rows.filter(r => r.status === status).length]));
  await writeFile(new URL(`back-pass-${pass}.json`, results), JSON.stringify(report, null, 2));
}
process.exitCode = report.rows.some(r => r.status !== 'passed') || report.unexpectedApi?.length ? 1 : 0;
