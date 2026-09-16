import { writeFile } from 'node:fs/promises';

const port = Number(process.argv[2] ?? 9223);
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const panel = targets.find((t) => t.url.includes('/sidepanel.html') && t.title === 'CashFlow Importer');
if (!panel) throw new Error('Open the CashFlow extension panel first.');
const socket = new WebSocket(panel.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
try {
  const result = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Inspection timed out')), 20000);
    socket.onmessage = ({ data }) => {
      const message = JSON.parse(data);
      if (message.id !== 1) return;
      clearTimeout(timer);
      if (message.error || message.result?.exceptionDetails) reject(new Error(JSON.stringify(message.error ?? message.result.exceptionDetails)));
      else resolve(message.result.result.value);
    };
    socket.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: {
      expression: `(async () => {
        const tabs = await chrome.tabs.query({});
        return await Promise.all(tabs.filter(t => t.url?.startsWith('https://')).map(async t => {
          try {
            const p = await chrome.tabs.sendMessage(t.id, {type:'cashflow:probe-page'});
            return {tabId:t.id,bankId:p.bankId,path:new URL(p.url).pathname,authenticationStatus:p.authenticationStatus,selection:p.selection,categories:p.categories.map(c=>({name:c.name,percent:c.percent,type:c.type,selected:c.selected,confirmed:c.confirmed,group:c.group}))};
          } catch { return {tabId:t.id,host:new URL(t.url).hostname,error:'No probe response'}; }
        }));
      })()`, awaitPromise: true, returnByValue: true,
    }}));
  });
  if (process.argv[3]) await writeFile(process.argv[3], JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result, null, 2));
} finally { socket.close(); }
