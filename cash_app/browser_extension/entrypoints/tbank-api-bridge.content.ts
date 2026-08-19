const requestType = 'cashflow:tbank-bonuses-request';
const responseType = 'cashflow:tbank-bonuses-response';

export default defineContentScript({
  matches: ['https://www.tbank.ru/*'],
  runAt: 'document_start',
  world: 'MAIN',
  main() {
    let latestData: unknown = null;
    const isBonusesUrl = (url: string) => /\/loyalty_api\/api\/bonuses\?/.test(url);

    const originalFetch = window.fetch.bind(window);
    window.fetch = async (...args) => {
      const response = await originalFetch(...args);
      if (isBonusesUrl(response.url)) {
        void response.clone().json().then((data) => { latestData = data; }).catch(() => undefined);
      }
      return response;
    };

    const originalSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function (...args) {
      this.addEventListener('loadend', () => {
        if (!isBonusesUrl(this.responseURL) || this.status < 200 || this.status >= 300) return;
        try {
          latestData = typeof this.response === 'string' ? JSON.parse(this.response) : this.response;
        } catch {
          // A later automatic collection attempt can retry through the API.
        }
      }, { once: true });
      return originalSend.apply(this, args);
    };

    window.addEventListener('message', async (event) => {
      if (event.data?.type !== requestType) return;
      const apiUrl = performance.getEntriesByType('resource')
        .map((entry) => entry.name)
        .find((url) => /\/loyalty_api\/api\/bonuses\?/.test(url));
      let data: unknown = latestData;
      if (!data && apiUrl) {
        try {
          const response = await originalFetch(apiUrl, {
            method: 'POST',
            credentials: 'include',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify({
              loyaltyIds: ['33', '104', '105', '97', '84', '83', '60'],
              bundle: 'pro',
              origin: 'web,ib5,platform',
            }),
          });
          if (response.ok) data = await response.json();
        } catch {
          data = null;
        }
      }
      window.postMessage({ type: responseType, nonce: event.data.nonce, data }, '*');
    });
  },
});
