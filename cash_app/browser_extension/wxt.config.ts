import { defineConfig } from 'wxt';

export default defineConfig({
  modules: ['@wxt-dev/module-react'],
  manifest: {
    name: 'CashFlow Cashback Importer',
    description: 'Imports cashback categories from supported online banks.',
    permissions: ['storage', 'scripting', 'sidePanel', 'downloads'],
    host_permissions: [
      'https://www.tbank.ru/*',
      'https://id.tbank.ru/*',
      'https://bank.yandex.ru/*',
      'https://sp.yandex.ru/*',
      'https://web.alfabank.ru/*',
      'https://private.auth.alfabank.ru/*',
      'https://online.sberbank.ru/*',
      'https://finance.ozon.ru/*',
      'https://online.sbpvtb.ru/*',
    ],
    action: {
      default_title: 'CashFlow Cashback Importer',
    },
    side_panel: {
      default_path: 'sidepanel.html',
    },
  },
});
