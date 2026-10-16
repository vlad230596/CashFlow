# Android offline acceptance contract

Отдельная регрессия порядка «сначала клавиатура, затем навигация»:
[Android Back](BACK.md), запуск `scripts/test-android-back.ps1`.

Перенос в другой проект: [общее руководство Web + Android](../../docs/offline-testing-setup-guide.md).

Target: a dedicated Android phone emulator, isolated package
`com.example.cash_app.offlineqa`, optimized release APK, synthetic local API.
The regular CashFlow package and production data must not be changed.

| Action | Required executable evidence |
| --- | --- |
| Reset only the QA package, login normally, fetch known data | Login screen, then Benefit search and fixture card with 5%; authenticated primary refresh completes |
| Disable Wi-Fi and mobile data; force-stop and launch | Android fully-drawn timing <= 2000 ms after cached first frame rasterization; cached offer, correct bank/owner/card, no API response |
| Search offline | Query is present and returns the saved offer and 5% |
| Reconnect and Retry | Same query remains, 9% replaces 5%, stale warning disappears |
| Restart with requests held | Cached 9% appears within the startup budget; an API request is pending and no answer completes |
| Keep requests blocked for 30 seconds | Cached result remains usable; releasing replies updates it to 13% without login |
| Finish or fail | Restore emulator radio settings; retain timing and flow evidence |

UI checks use Argent; native startup timing uses Android `reportFullyDrawn` after
Flutter's first cached frame has rasterized. UI automation round trips are outside
that metric. Synthetic API fault injection is separate from the emulator's radios:
the offline server also resets connections, and the hanging server holds replies.
This prevents emulator host routing from accidentally making the API available.

## Run

On Windows, with a dedicated phone emulator already running and Node, Android SDK
and Argent installed:

```powershell
.\scripts\test-offline-android.ps1 -Device emulator-5554
```

The helper uses the repository's VS Code Flutter SDK setup, builds the release
APK, **checks the actual APK's package with aapt before installing**, starts the
loopback-only synthetic API and replays every check twice without retries. It
refuses physical devices. `-SkipBuild` reuses only the saved QA APK under
`tests/android/results/`, and checks its package again. Production signing remains
required for ordinary CI release builds; only the separate QA package can use
local debug signing in CI.

The saved flow is `.argent/flows/qa-android-offline-cache.yaml`. With the same
isolated APK and fixture server already running, the standalone runner is:

```powershell
argent flow run qa-android-offline-cache --device emulator-5554 --platform android --json
```

The wrapper recycles only this device's Argent services before pass 1. Each pass
clears **only the QA package**, logs in through the real form, downloads data,
restarts the process twice and restores radio/handwriting settings. The wrapper's
`finally` also restores settings and stops its own server on failure. Credentials
are fixed synthetic fixture values in the ignored `.argent/secrets.env` file;
flows contain placeholders. No real account is used.

`results/pass-1.json`, `results/pass-2.json` contain every structural verdict and
warning. `results/device-state.json` contains native startup timings and budgets.
The default budget is 2000 ms; an explicit `OFFLINE_STARTUP_BUDGET_MS` changes it
and is recorded. Process launch is part of Android's fully-drawn metric; initial
online login and subsequent human-style query entry are outside that metric.
The first cached frame must really have data, and separate UI checks verify
content and search. This is not a timing of the splash screen or an Argent call.

## Navigation and evidence

| Transition | Destination identity | Readiness / content |
| --- | --- | --- |
| Clean QA launch | `Войти в семью` | `idle`, stable `login-password` and `login-username` input targets |
| Submit login form | `benefit-search` | `idle`, fixture offer 5%, primary cache-writing refresh completed |
| Restart with radios disabled | `benefit-search` | `idle`, cached 5%, native <= 2000 ms, stale warning |
| Enter offline query | `benefit-search` contains `Offline` | Card 4242, 5%, bank and owner labels |
| Restore radios and press Retry | Saved card changes to 9% | Old 5% and stale banner disappear; query remains |
| Restart with API replies held | `benefit-search` | `idle`, cached 9%, native <= 2000 ms and a real pending request |
| Search and wait full response window | Query remains `Offline` | Cached card 4242 / 9% still visible after at least 30 seconds |
| Release API replies | Card changes to 13% | 9% disappears, bank/owner and query remain without login/navigation |

All final UI actions use stable identifiers or named controls. Exact fixture
values are intentional data assertions; no device id or screen coordinates are
stored in the flow. No screenshot baselines or visual mismatch tolerance are
used: this suite verifies structure and values, not pixel layout.

API 36's Gboard handwriting tutorial was observed stealing focus during the live
walkthrough. Setup disables that emulator feature and cleanup restores its prior
value. Radio reconnection waits for a real route to `10.0.2.2`, rather than a fixed
sleep before Retry. Login may report small pixel motion during `idle` because its
username field has an autofocus caret; this is an accepted caret warning, followed
by stable input targets and a hard successful-login check, not a loading verdict.

## Reuse and limits

`fixture-server.mjs` reuses the browser suite's synthetic API fixture. Port 18742
is reachable from the standard Android emulator through `10.0.2.2`; it does not
require an adb reverse tunnel that could bypass the network-loss scenario.
`scripts/actions.mjs` provides setup, radio changes, API faults, native timing and
cleanup; the small `.mjs` entry points are recorded flow script steps. To move this
mechanism to another app, replace package/launch metrics, fixture data and the
flow's login/search/content selectors.

These are local emulator tests. A physical phone, Android release signing and
production deployment are separate checks. The local helper is automation-ready;
the Android suite is not yet wired into the required GitHub CI aggregate.
The regular application package is never cleared by this pipeline.

## Verified locally, 15 October 2026

Final unchanged flow: two consecutive passes with the standalone Argent runner
0.25.2, 50 passing steps per run, no failed or errored steps. Pass 1 started after
recycling only `emulator-5554`'s Argent services. Target:
`CashFlow_Medium_API_36`, Android API 36, 1080x2400.

| Run | Radios off | API hanging |
| --- | --- | --- |
| 1 | 1129 ms | 946 ms |
| 2 | 1625 ms | 1166 ms |

Both runs proved correct saved data, query persistence, a full 30-second blocked
response window, and updates from 5% to 9% to 13%. The autofocus-caret idle warning
described above is accepted; there are no coordinate exceptions, missing-tree
warnings or snapshot baselines. Local results are not proof of deployment or of
the same timing on a physical device.

Metric references: [Android fully drawn startup time](https://developer.android.com/topic/performance/vitals/launch-time)
and [Flutter first-frame rasterization](https://api.flutter.dev/flutter/widgets/WidgetsBinding/waitUntilFirstFrameRasterized.html).
