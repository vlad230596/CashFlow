const [, , portArg = '9223', urlPrefix = 'https://bank.yandex.ru/', targetId] = process.argv;
const port = Number(portArg);

const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
const target = targets.find(
  (candidate) =>
    candidate.type === 'page' &&
    candidate.url.startsWith(urlPrefix) &&
    (!targetId || candidate.id === targetId),
);

if (!target) {
  throw new Error(`Page target not found for URL prefix: ${urlPrefix}`);
}

const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.onopen = resolve;
  socket.onerror = reject;
});

const response = await new Promise((resolve, reject) => {
  const id = 1;
  const timeout = setTimeout(() => reject(new Error('CDP evaluation timed out')), 5000);

  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.id !== id) return;
    clearTimeout(timeout);
    resolve(message);
  };

  socket.send(
    JSON.stringify({
      id,
      method: 'Runtime.evaluate',
      params: {
        expression: `JSON.stringify({
          url: location.href,
          title: document.title,
          htmlLang: document.documentElement.lang,
          navigatorLanguage: navigator.language,
          navigatorLanguages: navigator.languages,
          bodyText: document.body.innerText.slice(0, 2500),
          frames: Array.from(document.querySelectorAll('iframe'), (frame) => frame.src),
          controls: Array.from(
            document.querySelectorAll('button, a, [role="button"], input'),
            (element) => ({
              tag: element.tagName,
              text: element.innerText?.trim().slice(0, 300) || null,
              ariaLabel: element.getAttribute('aria-label'),
              href: element.href || null,
              className: typeof element.className === 'string' ? element.className : null,
            }),
          ).filter((item) => item.text || item.ariaLabel).slice(0, 150),
          dayTexts: Array.from(document.querySelectorAll('body *'))
            .map((element) => ({
              tag: element.tagName,
              className: typeof element.className === 'string' ? element.className : null,
              text: element.innerText?.trim() || '',
            }))
            .filter((item) => /\d+\s+(?:день|дня|дней)/i.test(item.text))
            .sort((left, right) => left.text.length - right.text.length)
            .slice(0, 30),
          lists: Array.from(document.querySelectorAll('ul'), (element) => ({
            className: typeof element.className === 'string' ? element.className : null,
            text: element.innerText?.trim().slice(0, 2000) || null,
            parentText: element.parentElement?.innerText?.trim().slice(0, 2500) || null,
            previousText:
              element.previousElementSibling?.innerText?.trim().slice(0, 500) || null,
          })).slice(0, 30),
          selectorCounts: {
            cashbackLists: document.querySelectorAll('ul[class*="List_block"]').length,
            directCashbackItems: document.querySelectorAll(
              'ul[class*="List_block"] > li[class*="SelectorListItem_block"]',
            ).length,
            allSelectorItems: document.querySelectorAll(
              'li[class*="SelectorListItem_block"]',
            ).length,
          },
          dataTestNodes: Array.from(
            document.querySelectorAll('[data-testid], [data-test-id]'),
            (element) => ({
              tag: element.tagName,
              testId: element.getAttribute('data-testid') || element.getAttribute('data-test-id'),
              text: element.innerText?.trim().slice(0, 300) || null,
            }),
          ).filter((item) => item.text).slice(0, 200),
          selectorItems: Array.from(
            document.querySelectorAll('li[class*="SelectorListItem_block"]'),
            (element) => ({
              text: element.innerText?.trim() || null,
              html: element.outerHTML.slice(0, 8000),
              parentTag: element.parentElement?.tagName || null,
              parentClass:
                typeof element.parentElement?.className === 'string'
                  ? element.parentElement.className
                  : null,
            }),
          ).slice(0, 30),
          images: Array.from(document.images, (element) => ({
            alt: element.alt || null,
            src: element.currentSrc || element.src,
            nearbyText: element.parentElement?.innerText?.trim().slice(0, 200) || null,
            ancestors: Array.from({ length: 6 }, (_, index) => {
              let ancestor = element;
              for (let level = 0; level <= index; level += 1) {
                ancestor = ancestor?.parentElement;
              }
              return ancestor
                ? {
                    tag: ancestor.tagName,
                    className:
                      typeof ancestor.className === 'string' ? ancestor.className : null,
                    text: ancestor.innerText?.trim().slice(0, 250) || null,
                  }
                : null;
            }).filter(Boolean),
          })).slice(0, 150),
        })`,
        returnByValue: true,
      },
    }),
  );
});

socket.close();

if (response.error) throw new Error(JSON.stringify(response.error));
if (response.result?.exceptionDetails) {
  throw new Error(response.result.exceptionDetails.text);
}

console.log(response.result.result.value);
