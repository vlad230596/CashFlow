const [, , portArg = '9223', targetId] = process.argv;
const port = Number(portArg);

const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
const target = targets.find(
  (candidate) =>
    candidate.type === 'page' &&
    /^https:\/\/finance\.ozon\.ru\/lk\/(?:bonus|cashback|favorite-categories)/.test(candidate.url) &&
    (!targetId || candidate.id === targetId),
);

if (!target) throw new Error('Ozon cashback page target not found');

const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.onopen = resolve;
  socket.onerror = reject;
});

const response = await new Promise((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error('CDP evaluation timed out')), 5000);
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.id !== 1) return;
    clearTimeout(timeout);
    resolve(message);
  };

  socket.send(
    JSON.stringify({
      id: 1,
      method: 'Runtime.evaluate',
      params: {
        expression: `(() => {
          const visible = (element) => {
            const rect = element.getBoundingClientRect();
            const style = getComputedStyle(element);
            return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden';
          };
          const roots = Array.from(
            document.querySelectorAll('[role="dialog"], dialog, [aria-modal="true"], [class*="modal"], [class*="drawer"], [class*="sheet"]'),
          ).filter(visible);
          const root = roots.sort((a, b) => b.innerText.length - a.innerText.length)[0];
          if (!root) return { found: false };

          const elements = Array.from(root.querySelectorAll('*')).filter(visible);
          return {
            found: true,
            rootCandidates: roots.map((element) => ({
              tag: element.tagName,
              role: element.getAttribute('role'),
              ariaModal: element.getAttribute('aria-modal'),
              className: typeof element.className === 'string' ? element.className : null,
              text: element.innerText.trim().slice(0, 2500),
            })),
            root: {
              tag: root.tagName,
              role: root.getAttribute('role'),
              ariaModal: root.getAttribute('aria-modal'),
              className: typeof root.className === 'string' ? root.className : null,
              text: root.innerText.trim().slice(0, 6000),
              html: root.outerHTML.slice(0, 30000),
            },
            controls: elements
              .filter((element) => element.matches('button, a, [role="button"]'))
              .map((element) => ({
                tag: element.tagName,
                text: element.innerText?.trim().slice(0, 300) || null,
                ariaLabel: element.getAttribute('aria-label'),
                className: typeof element.className === 'string' ? element.className : null,
              })),
            images: elements
              .filter((element) => element.matches('img, svg'))
              .map((element) => ({
                tag: element.tagName,
                alt: element.getAttribute('alt'),
                src: element.currentSrc || element.getAttribute('src'),
                className: typeof element.className === 'string' ? element.className : null,
                parentText: element.parentElement?.innerText?.trim().slice(0, 300) || null,
              })),
          };
        })()`,
        returnByValue: true,
      },
    }),
  );
});

socket.close();
if (response.result?.exceptionDetails) throw new Error(response.result.exceptionDetails.text);
console.log(JSON.stringify(response.result.result.value, null, 2));
