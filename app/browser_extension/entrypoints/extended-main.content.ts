type PageRequest = { type: 'cashflow:extended-main-request'; nonce: string; kind: 'tbank-cards' | 'alfa-cards' | 'alfa-rules' | 'vtb-catalogue' };

export default defineContentScript({
  matches: ['https://www.tbank.ru/*', 'https://web.alfabank.ru/*', 'https://online.sbpvtb.ru/*'],
  runAt: 'document_start',
  world: 'MAIN',
  main() {
    let latestVtbCatalogue: unknown = null;
    if (location.hostname === 'online.sbpvtb.ru') {
      const targetPath = '/msa/api-gw/private/dsls/dsls-content-category/v1/categories';
      const originalFetch = window.fetch.bind(window);
      window.fetch = async (...args) => {
        const response = await originalFetch(...args);
        if (response.url.includes(targetPath) && response.ok) {
          void response.clone().json().then((data) => { latestVtbCatalogue = data; }).catch(() => undefined);
        }
        return response;
      };
      const originalSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function (...args) {
        this.addEventListener('loadend', () => {
          if (!this.responseURL.includes(targetPath) || this.status !== 200) return;
          try { latestVtbCatalogue = typeof this.response === 'string' ? JSON.parse(this.response) : this.response; }
          catch { /* A later request can refresh the cache. */ }
        }, { once: true });
        return originalSend.apply(this, args);
      };
    }
    const propsOf = (node: Element) => {
      const key = Object.keys(node).find((name) => name.startsWith('__reactFiber$'));
      let fiber = key ? (node as unknown as Record<string, any>)[key] : null;
      const props: Record<string, any>[] = [];
      for (let index = 0; fiber && index < 16; index++, fiber = fiber.return) {
        if (fiber.memoizedProps) props.push(fiber.memoizedProps);
      }
      return props;
    };
    window.addEventListener('message', (event: MessageEvent<PageRequest>) => {
      if (event.source !== window || event.data?.type !== 'cashflow:extended-main-request') return;
      let data: unknown = null;
      if (event.data.kind === 'vtb-catalogue') {
        data = latestVtbCatalogue;
      } else if (event.data.kind === 'tbank-cards') {
        data = [...document.querySelectorAll<HTMLElement>('[data-qa-type^="desktop-bonuses-category-list-offer-"]')]
          .filter((card) => /^desktop-bonuses-category-list-offer-\d+$/.test(card.getAttribute('data-qa-type') || ''))
          .map((card) => {
            const offer = propsOf(card).find((props) => props.offer?.offerId)?.offer;
            return offer ? {
              text: card.innerText.replace(/\s+/g, ' ').trim(),
              id: String(offer.offerId), name: offer.merchantName || null,
              title: offer.title || null, subtitle: offer.subtitle || null,
              startDate: offer.startDate == null ? null : String(offer.startDate),
              endDate: offer.endDate == null ? null : String(offer.endDate),
              expirationLabel: offer.expirationText || null,
              detailUrl: offer.link ? new URL(offer.link, location.origin).href : null,
              iconUrl: offer.logo || null, artworkUrl: offer.image || null,
            } : null;
          }).filter(Boolean);
      } else if (event.data.kind === 'alfa-cards') {
        data = [...document.querySelectorAll<HTMLElement>('[role="dialog"] [data-test-id="offers-selection-body"] button[data-test-id="offer"]')]
          .map((card) => {
            const props = propsOf(card).find((item) => item.offerId);
            return props ? {
              text: card.innerText.replace(/\s+/g, ' ').trim(),
              id: String(props.offerId), name: props.title || null,
              rateLabel: props.condition || null,
              previewConditions: props.cashbackCondition || null,
              startDate: props.startDate == null ? null : String(props.startDate),
              endDate: props.endDate == null ? null : String(props.endDate),
              warningText: props.warningText || null,
              iconUrl: props.iconUrl || null,
            } : null;
          }).filter(Boolean);
      } else if (event.data.kind === 'alfa-rules') {
        const button = document.querySelector('[role="dialog"] [data-test-id="offer-details-body"] [data-test-id="promotion-rules-button"]');
        data = button ? propsOf(button).map((props) => props.urlToPdf || props.rulesUrl || props.urlToRules)
          .find((url) => typeof url === 'string' && /^https?:\/\//.test(url)) || null : null;
      }
      window.postMessage({ type: 'cashflow:extended-main-response', nonce: event.data.nonce, data }, '*');
    });
  },
});
