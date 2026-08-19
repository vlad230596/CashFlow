# CashFlow Browser Extension

Manifest V3 extension for importing cashback categories from supported online
banks. The extension runs only in dedicated Chrome profiles stored under
`.local/chrome-profiles/` and does not read or export browser cookies.

Implementation notes, T-Bank and Yandex Pay findings, and the checklist for
adding another bank are documented in
[docs/bank-cashback-parsing.md](docs/bank-cashback-parsing.md).
The multi-bank user flow, JSON contract, current integration status, and known
limitations are captured in
[docs/multi-bank-import-mvp.md](docs/multi-bank-import-mvp.md).

## Prerequisites

- Node.js 24 LTS installed at `C:\Program Files\nodejs`.
- Chrome for Testing installed under `.local/browsers/`. Branded Google Chrome
  137+ no longer supports loading unpacked extensions from the command line.

## Install and verify

From this directory:

```powershell
..\scripts\setup_node_env.ps1 -Run "npm ci"
..\scripts\setup_node_env.ps1 -Run "npm run check"
```

## Development

Run the complete multi-bank flow (the same command used by the Flutter button):

```powershell
.\scripts\start_cashback_import.ps1 -Profile user-1 -DebugPort 9223
```

It reuses a running dedicated browser when possible, passes the requested bank
list through extension storage, opens missing bank tabs, and opens the side panel.

Start the WXT watcher in one terminal:

```powershell
..\scripts\setup_node_env.ps1 -Run "npm run dev"
```

Start the dedicated browser from the repository root in another terminal:

```powershell
.\scripts\start_cashflow_extension_chrome.ps1 -Profile user-1 -DebugPort 9223
```

The launcher prefers the newest locally installed Chrome for Testing build and
falls back to system Chrome when no testing build is available. The dedicated
profile uses Russian UI and Accept-Language values by default; pass
`-Language en-US` only when a bank must be tested in English.

After rebuilding an extension that is already loaded, restart only its
dedicated profile so Chrome replaces the active content scripts while keeping
the authenticated session:

```powershell
.\scripts\restart_cashflow_extension_chrome.ps1 -Profile user-1 -DebugPort 9223
```

Calling `load_cashflow_extension.ps1` again is useful for an initial DevTools
load, but Chrome can keep an older content script alive when the same unpacked
extension ID is already installed.

The launcher preserves the selected Chrome profile, exposes DevTools only on
loopback, and loads the unpacked extension through the DevTools protocol.

Inspect visible bank tabs without reading page content:

```powershell
.\scripts\inspect_cashflow_chrome.ps1 -DebugPort 9223
```

Open the extension as Chrome's right-side panel without replacing the current
bank tab:

```powershell
.\scripts\start_cashback_import.ps1 -Profile user-1 -DebugPort 9223
```

The launcher obtains the unpacked extension ID from Chrome; no machine-specific
ID is stored in the repository. The same panel opens normally when the extension
toolbar icon is clicked.
Diagnostic scripts reuse an existing side-panel target and must not open
`sidepanel.html` as a regular browser tab.

Diagnostic output can contain page text from an authenticated bank session.
Save captures only under `.local/`, which is excluded from Git, and review any
copied excerpts before publishing them.

Use a different profile and port for a second user:

```powershell
.\scripts\start_cashflow_extension_chrome.ps1 -Profile user-2 -DebugPort 9224
```

Alfa Bank uses the Russian trusted CA chain. Its verified root certificate is
installed only in Chrome's profile-local certificate store for
`.local/chrome-profiles/user-1`; Windows certificate stores are not changed.
The Yandex Browser launcher remains an unused fallback and is not part of the
current development workflow. See `docs/bank-cashback-parsing.md` for the
certificate fingerprint and verification notes.

## Production build

```powershell
..\scripts\setup_node_env.ps1 -Run "npm run build"
..\scripts\setup_node_env.ps1 -Run "npm run zip"
```

Build artifacts are written to `.output/` and are excluded from Git.
