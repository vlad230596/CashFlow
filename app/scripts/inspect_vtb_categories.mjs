const [, , portArg = '9223', targetId] = process.argv;
const targets = await (await fetch(`http://127.0.0.1:${Number(portArg)}/json`)).json();
const target = targets.find(
  (candidate) =>
    candidate.type === 'page' &&
    candidate.url.startsWith('https://online.sbpvtb.ru/bonus/categories') &&
    (!targetId || candidate.id === targetId),
);
if (!target) throw new Error('VTB category page target not found');

const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.onopen = resolve;
  socket.onerror = reject;
});

const response = await new Promise((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error('CDP evaluation timed out')), 8000);
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
          const normalize = (value) => value?.replace(/\\s+/g, ' ').trim() || '';
          const visible = (element) => {
            const rect = element.getBoundingClientRect();
            const style = getComputedStyle(element);
            return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden';
          };
          const controls = Array.from(document.querySelectorAll('button, input, [role="button"], [role="checkbox"], [role="radio"]'))
            .filter(visible)
            .map((element) => ({
              tag: element.tagName,
              type: element.getAttribute('type'),
              text: normalize(element.innerText || element.getAttribute('aria-label')),
              ariaLabel: element.getAttribute('aria-label'),
              role: element.getAttribute('role'),
              checked: element.checked ?? element.getAttribute('aria-checked'),
              disabled: element.disabled ?? element.getAttribute('aria-disabled'),
              testId: element.getAttribute('data-test-id') || element.getAttribute('data-testid'),
              parentText: normalize(element.parentElement?.innerText).slice(0, 500),
            }))
            .filter((item) => /%|кешбэк|категор|выбрат|подтверд|готово|продолж/i.test(item.text + ' ' + item.parentText));

          const percentNodes = Array.from(document.querySelectorAll('main *, section *'))
            .filter((element) => visible(element) && /\\d+(?:[.,]\\d+)?(?:\\s*[-–]\\s*\\d+(?:[.,]\\d+)?)?\\s*%/.test(normalize(element.textContent)))
            .map((element) => ({
              tag: element.tagName,
              className: typeof element.className === 'string' ? element.className : null,
              testId: element.getAttribute('data-test-id') || element.getAttribute('data-testid'),
              text: normalize(element.textContent).slice(0, 800),
              html: element.outerHTML.slice(0, 4000),
            }))
            .sort((left, right) => left.text.length - right.text.length)
            .slice(0, 80);

          const images = Array.from(document.images)
            .filter((image) => {
              const nearby = normalize(image.parentElement?.innerText);
              return visible(image) && (/%/.test(nearby) || /категор|кешбэк/i.test(image.alt + ' ' + nearby));
            })
            .map((image) => ({
              alt: image.alt || null,
              src: image.currentSrc || image.src,
              parentText: normalize(image.parentElement?.innerText).slice(0, 500),
            }));

          return {
            url: location.href,
            firstInputAncestors: (() => {
              const input = document.querySelector('input[type="checkbox"][data-test-id^="checked_"]');
              const result = [];
              let element = input?.parentElement;
              while (element && result.length < 12) {
                result.push({
                  tag: element.tagName,
                  inputCount: element.querySelectorAll('input[type="checkbox"]').length,
                  buttonTexts: Array.from(element.querySelectorAll('button'), (button) => normalize(button.innerText)).filter(Boolean),
                  text: normalize(element.innerText).slice(0, 500),
                });
                element = element.parentElement;
              }
              return result;
            })(),
            firstInputLabel: (() => {
              const input = document.querySelector('input[type="checkbox"][data-test-id^="checked_"]');
              return input ? {
                id: input.id,
                escapedId: CSS.escape(input.id),
                labelText: document.querySelector('label[for="' + CSS.escape(input.id) + '"]')?.textContent || null,
              } : null;
            })(),
            controls,
            percentNodes,
            images,
            resources: performance.getEntriesByType('resource').map((entry) => entry.name)
              .filter((url) => /cash|bonus|loyal|categor/i.test(url)).slice(-100),
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
