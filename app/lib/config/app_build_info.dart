const _configuredAppVersion = String.fromEnvironment(
  'CASHFLOW_APP_VERSION',
);

const appVersionLabel =
    _configuredAppVersion == '' ? 'local' : _configuredAppVersion;
