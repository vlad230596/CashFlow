import { defineConfig } from 'wxt';

export default defineConfig({
  modules: ['@wxt-dev/module-react'],
  manifest: {
    name: 'CashFlow Cashback Importer',
    description: 'Imports cashback categories from supported online banks.',
    permissions: ['storage', 'scripting', 'sidePanel', 'downloads'],
    // Category images can live on changing bank CDN hosts and must be fetched
    // as bytes before they can be packed into a single ZIP archive.
    host_permissions: ['https://*/*'],
    action: {
      default_title: 'CashFlow Cashback Importer',
    },
    side_panel: {
      default_path: 'sidepanel.html',
    },
  },
});
