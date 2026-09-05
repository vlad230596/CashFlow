const cashFlowCacheReset = (async () => {
  if ('serviceWorker' in navigator) {
    const registrations = await navigator.serviceWorker.getRegistrations();
    await Promise.all(registrations.map((registration) => registration.unregister()));
  }

  if ('caches' in window) {
    const cacheNames = await caches.keys();
    await Promise.all(cacheNames.map((cacheName) => caches.delete(cacheName)));
  }

})().catch((error) => {
  console.warn('Could not clear the legacy application cache:', error);
});

window.cashFlowCacheReset = cashFlowCacheReset;

if (window.location.pathname === '/refresh') {
  cashFlowCacheReset.finally(() => {
    window.location.replace(`/?cache-reset=${Date.now()}`);
  });
}
