const [, , portArg = '9223'] = process.argv;
const targets = await (await fetch(`http://127.0.0.1:${Number(portArg)}/json`)).json();
const target = targets.find(
  (candidate) =>
    candidate.type === 'page' &&
    candidate.url.startsWith('https://online.sberbank.ru/app/loyalty/main/categories'),
);
if (!target) throw new Error('Sber categories tab not found');

const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.onopen = resolve;
  socket.onerror = reject;
});

const expression = `JSON.stringify((() => {
  const normalize = (value) => (value || '').trim().replace(/\\s+/g, ' ');
  const inputs = Array.from(document.querySelectorAll('input')).map((input) => {
    let item = input.parentElement;
    while (item?.parentElement && normalize(item.innerText).length < 30) item = item.parentElement;
    return {
      type: input.type,
      checked: input.checked,
      disabled: input.disabled,
      name: input.name,
      value: input.value,
      ariaLabel: input.getAttribute('aria-label'),
      itemText: normalize(item?.innerText).slice(0, 1000),
      itemHtml: item?.outerHTML.slice(0, 8000),
    };
  });
  const percentLeaves = Array.from(document.querySelectorAll('body *'))
    .filter((element) => element.children.length === 0 && /^\\d+(?:[.,]\\d+)?%/.test(normalize(element.textContent)))
    .map((element) => {
      let item = element.parentElement;
      while (item?.parentElement) {
        const text = normalize(item.innerText);
        if (text.length >= 25 && (item.querySelector('img, svg') || item.querySelector('input'))) break;
        item = item.parentElement;
      }
      const image = item?.querySelector('img');
      return {
        leafText: normalize(element.textContent),
        itemText: normalize(item?.innerText).slice(0, 1000),
        itemTag: item?.tagName,
        itemClass: typeof item?.className === 'string' ? item.className : null,
        imageUrl: image?.currentSrc || image?.src || null,
        imageAlt: image?.alt || null,
        html: item?.outerHTML.slice(0, 12000),
      };
    });
  const sameOriginRequests = performance.getEntriesByType('resource')
    .filter((entry) => entry.initiatorType === 'fetch' || entry.initiatorType === 'xmlhttprequest')
    .map((entry) => entry.name)
    .filter((url) => url.startsWith('https://web-node') || url.startsWith('https://online.sberbank.ru'))
    .slice(-100);
  return { url: location.href, inputs, percentLeaves, sameOriginRequests };
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
