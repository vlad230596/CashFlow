/** Project-independent fault injection. Only the named local API is intercepted.
 * Static application files remain reachable: this models API loss, not a PWA.
 */
export class NetworkController {
  mode = 'online';
  calls = [];
  pending = new Set();
  externalRequests = [];
  unexpectedApiRequests = [];
  pageErrors = [];

  constructor(context, apiOrigin, respond) {
    this.context = context;
    this.apiOrigin = apiOrigin;
    this.respond = respond;
  }

  async install() {
    for (const page of this.context.pages()) this.observePage(page);
    this.context.on('page', (page) => this.observePage(page));
    await this.context.route(`${this.apiOrigin}/api/**`, async (route) => {
      const request = route.request();
      const call = { path: new URL(request.url()).pathname, method: request.method(), mode: this.mode, completed: false };
      this.calls.push(call);
      if (this.mode === 'offline') {
        await route.abort('internetdisconnected');
        call.completed = true;
        return;
      }
      if (this.mode === 'hanging') {
        await new Promise((resolve) => this.pending.add(resolve));
        if (this.mode === 'disposed') return;
      }
      const result = await this.respond(request);
      await route.fulfill({ json: result.body, status: result.status ?? 200 });
      call.completed = true;
    });
    // Fail closed: a wrongly configured build must never call production.
    await this.context.route('**/*', async (route) => {
      const url = new URL(route.request().url());
      if (url.origin !== this.apiOrigin) {
        this.externalRequests.push(url.origin);
        if (url.pathname.startsWith('/api/')) this.unexpectedApiRequests.push(url.origin + url.pathname);
        return route.abort('blockedbyclient');
      }
      return route.fallback();
    });
  }

  observePage(page) {
    page.on('pageerror', (error) => this.pageErrors.push(error.message));
  }

  setMode(mode) {
    if (!['online', 'offline', 'hanging'].includes(mode)) throw new Error(`Invalid network mode: ${mode}`);
    this.mode = mode;
    this.calls = [];
  }

  restore() {
    this.mode = 'online';
    for (const resolve of this.pending) resolve();
    this.pending.clear();
  }

  async dispose() {
    this.mode = 'disposed';
    for (const resolve of this.pending) resolve();
    this.pending.clear();
    await this.context.unrouteAll({ behavior: 'wait' });
  }
}
