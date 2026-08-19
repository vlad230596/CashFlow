const [, , portArg = '9223'] = process.argv;
const targets = await (await fetch(`http://127.0.0.1:${Number(portArg)}/json`)).json();
const target = targets.find(
  (candidate) => candidate.type === 'page' && candidate.url.startsWith('https://web.alfabank.ru/marketplace/'),
);
if (!target) throw new Error('Alfa marketplace tab not found');

const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.onopen = resolve;
  socket.onerror = reject;
});

const expression = `JSON.stringify((() => {
  const normalize = (value) => (value || '').trim().replace(/\\s+/g, ' ');
  const visible = (element) => {
    const style = getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
  };
  const dialogs = Array.from(document.querySelectorAll('[role="dialog"], dialog, [aria-modal="true"]'))
    .filter(visible)
    .map((element) => ({
      tag: element.tagName,
      testId: element.getAttribute('data-test-id') || element.getAttribute('data-testid'),
      text: normalize(element.innerText).slice(0, 8000),
      html: element.outerHTML.slice(0, 20000),
    }));
  const tooltips = Array.from(document.querySelectorAll('[role="tooltip"], [data-test-id*="tooltip"]'))
    .filter(visible)
    .map((element) => ({
      tag: element.tagName,
      testId: element.getAttribute('data-test-id') || element.getAttribute('data-testid'),
      text: normalize(element.innerText || element.textContent).slice(0, 3000),
    }))
    .filter((item) => item.text);
  const controls = Array.from(document.querySelectorAll('button, [role="button"], input, [role="checkbox"], [role="radio"]'))
    .filter(visible)
    .map((element) => ({
      tag: element.tagName,
      text: normalize(element.innerText || element.value || element.getAttribute('aria-label')).slice(0, 500),
      testId: element.getAttribute('data-test-id') || element.getAttribute('data-testid'),
      ariaLabel: element.getAttribute('aria-label'),
      ariaChecked: element.getAttribute('aria-checked'),
      checked: Boolean(element.checked),
      disabled: Boolean(element.disabled),
    }))
    .filter((item) => /%|категор|выбра|готов|подтверд|подроб|назад|закры|август|рубеж|такси|аптек|АЗС|супер|марк|ресторан|кафе|продукт|одеж|красот|развлеч|всё|все/i.test(JSON.stringify(item)))
    .slice(0, 250);
  const shortTexts = Array.from(document.querySelectorAll('body *'))
    .filter((element) => visible(element) && element.children.length === 0)
    .map((element) => ({
      tag: element.tagName,
      text: normalize(element.innerText || element.textContent).slice(0, 500),
      testId: element.getAttribute('data-test-id') || element.getAttribute('data-testid'),
      className: typeof element.className === 'string' ? element.className.slice(0, 300) : null,
    }))
    .filter((item) => item.text && /%|категор|выбра|готов|подтверд|подроб|август|рубеж|такси|аптек|АЗС|супер|марк|ресторан|кафе|продукт|одеж|красот|развлеч|покупк/i.test(item.text))
    .slice(0, 500);
  return {
    url: location.href,
    cashbackCards: Array.from(document.querySelectorAll('[data-test-id="cashback-program-card-subtitle"]'))
      .map((element) => ({
        text: normalize(element.textContent),
        ancestors: Array.from({ length: 7 }, (_, index) => {
          let ancestor = element;
          for (let level = 0; level <= index; level += 1) ancestor = ancestor?.parentElement;
          return ancestor ? {
            tag: ancestor.tagName,
            testId: ancestor.getAttribute('data-test-id'),
            text: normalize(ancestor.innerText).slice(0, 1000),
            titles: Array.from(
              ancestor.querySelectorAll('[data-test-id="cashback-programs-item-title"]'),
              (title) => normalize(title.textContent),
            ),
          } : null;
        }).filter(Boolean),
      })),
    dialogs,
    tooltips,
    frames: Array.from(document.querySelectorAll('iframe'), (frame) => frame.src),
    controls,
    shortTexts,
  };
})())`;

const response = await new Promise((resolve, reject) => {
  const id = 1;
  const timeout = setTimeout(() => reject(new Error('CDP evaluation timed out')), 10000);
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.id !== id) return;
    clearTimeout(timeout);
    resolve(message);
  };
  socket.send(JSON.stringify({ id, method: 'Runtime.evaluate', params: { expression, returnByValue: true } }));
});

socket.close();
if (response.result?.exceptionDetails) throw new Error(response.result.exceptionDetails.text);
console.log(response.result.result.value);
