# Porting offline startup tests to another project

A practical guide based on the Web and Android test setup implemented in CashFlow.
Prepared on October 16, 2026. Copy this document into another repository as a
specification for setting up equivalent checks.

Goal: a previously authenticated user opens the app with persisted data, sees
useful content immediately, and can search. An unavailable or unresponsive server
does not delay local content. Once connectivity returns, the screen receives
updated data while preserving the current search query.

## 1. Define the acceptance criteria first

Start with clean test storage. Sign in and load the initial data through the app
while the test API is available. Only then disconnect the network or hold responses.
Do not replace this preparation with direct token and cache injection: that would
leave session persistence and actual cache population untested.

| Scenario | Required evidence |
| --- | --- |
| Initial online load | Sign-in succeeds, reference data is visible, and its persistent storage write has completed |
| Reopen without API access | The session is restored and the required local data appears within the agreed time budget |
| Search without API access | The entered query is actually present in the field; results contain the expected entities and values |
| API hangs for 30 seconds | Local results appear before any response; a real request remains pending; data is still available after 30 seconds |
| Connectivity restored | The new value replaces the old one, the query is preserved, and no new sign-in is required |
| Full restart | Data is read from persistent storage after terminating the process or execution context |
| Completion or failure | Device settings are restored, test-owned processes are stopped, and reports are saved |

In CashFlow, the reference value changes from 5% to 9% to 13%, with card 4242 and a
known bank and owner. Another project might use an account balance, inventory
quantity, or order status. Assert specific values and their association with the
user, rather than merely checking that the home screen exists.

The reference time budget is **2000 ms**, and the API hold lasts **30 seconds**.
Choose the threshold for the target machine or emulator before running tests.
Moving to different hardware requires an explicit threshold decision; increasing
the limit after a failure does not fix a defect.

## 2. Architecture

```text
Runner → normal application UI → persistent storage
                    ↓
              test HTTP API
                    ↓
        online / offline / hanging / restore

Independent evidence: correct data + time to visibility + network state.
```

Separate the implementation into three parts:

1. **Shared mechanism:** network control, restarts, metrics, reports, and cleanup.
2. **Project adapter:** sign-in, API contract, fixtures, selectors, and refresh behavior.
3. **Application integration:** a build-time test API URL; on Android, a separate
   package and a signal that the first useful frame has rendered.

Start by porting one complete scenario and achieving two consecutive successful
runs. Expand coverage after that; a universal framework is not a prerequisite.

## 3. Files to reuse from CashFlow

The paths below refer to the CashFlow repository and identify the source files to
copy. Update imports and relative paths after moving them.

| Source | Purpose | Adaptation required |
| --- | --- | --- |
| `tests/browser/support/network-controller.mjs` | API disconnection, response holding and release, request log, external address blocking | Allowed origin and API boundaries |
| `tests/browser/support/persistent-browser.mjs` | Full Chromium restart using a real temporary profile | Viewport, locale, timezone |
| `tests/browser/support/evidence.mjs` | JSON metrics and report attachments | Usually reusable unchanged |
| `tests/browser/support/cashflow-adapter.mjs` | Fixture responses, UI sign-in and search | Replace data models, endpoints, account, and selectors |
| `tests/browser/support/static-server.mjs` | Local serving of the built web app | Build directory, port, MIME types, and application routes |
| `tests/browser/specs/` | Reopen and full restart tests | Expected content and project-specific interactions |
| `tests/browser/package.json`, `package-lock.json`, `playwright.config.mjs` | Pinned runner and configuration | Preserve the lockfile; update paths and addresses |
| `tests/android/fixture-server.mjs` | Real HTTP server with controlled responses | API contract and reference data |
| `tests/android/scripts/` | Preparation, radio control, network readiness, metrics, and cleanup | Package, addresses, device, and initial load completion condition |
| `.argent/flows/qa-android-offline-cache.yaml` | Recorded Android UI scenario | Re-record sign-in and assertions for the new app |
| `scripts/test-offline-browser.ps1`, `scripts/test-offline-android.ps1` | Complete local test runners | Build commands, SDK selection, paths, and packages |
| `.github/workflows/offline-browser-ci.yml` and its invocation from `ci.yml` | Browser CI and report retention | Environment, build, and required-check configuration |

**Reference implementation dependency:** the Android server imports
`CashflowFixture` from the browser adapter, which imports `@playwright/test`.
Therefore, the current Android helper also runs `npm ci` in `tests/browser`.
For an Android-only port, copy this dependency too, or extract the API fixtures
into a shared module without browser imports. Copying the YAML alone is insufficient.

Keep `node_modules`, APKs, temporary browser profiles, result directories, and
`.argent/secrets.env` out of Git. Preserve source files, flows, configuration,
the lockfile, and documentation.

## 4. Prepare the target project

Fill in these parameters before running the tests:

| Parameter | CashFlow example |
| --- | --- |
| Build-time API URL setting | `CASHFLOW_API_URL` |
| Web origin and API | `http://127.0.0.1:18741` |
| Android API as seen by the emulator | `http://10.0.2.2:18742` |
| Android API on the host | `http://127.0.0.1:18742` |
| Regular / test Android package | `com.example.cash_app` / `com.example.cash_app.offlineqa` |
| Test build flag | `CASHFLOW_OFFLINE_QA_METRICS=true` |
| Reference records | Active card, offer, bank, owner |
| Stable UI identifiers | `login-username`, `login-password`, `benefit-search` |
| Timezone / screen dimensions | `Europe/Moscow`; Web 1280×900, Android 1080×2400 |

The reference workstation uses Windows/PowerShell and a Flutter project.
Browser tests need Node.js 20+ and Playwright Chromium. Android additionally needs
a JDK, Android SDK Platform Tools (`adb`), Build Tools (`aapt`), Emulator, an AVD,
and Argent. Reference versions are Flutter 3.41.8, Playwright 1.64.1, and Argent
0.25.2; Android runs used API 36. These describe the verified configuration, rather
than requiring the newest versions or exactly these versions in another project.

`app/scripts/setup_vscode_flutter_env.ps1` reads the Flutter path from VS Code
settings. In another project, use its SDK selection mechanism or copy the helper
and configure `dart.flutterSdkPath`. The Android PowerShell helper also searches
for `aapt.exe` in the Android SDK associated with the discovered `adb`. Adapt this
part for Linux/macOS instead of running the Windows script unchanged.

The app needs a persisted session and a cache scoped by user and environment.
Showing local content must not wait for a network session check or data refresh.
An unavailable server and a received `401` are different events: a network delay
must not sign the user out, while a confirmed server rejection should follow the
app's authentication policy. Separate tests with a controlled pending request
help cover these branches; see `app/test/offline_startup_test.dart`.

## 5. Configure the test API

Prepare a small, consistent dataset matching the app's actual models: a user
identity, related records, searchable data, and a mutable reference field.
Use broad validity periods or an agreed test clock so records do not disappear
from the UI when the month changes. Match the actual response structure:
for example, an array and an `{items, total}` object are not interchangeable.

The API should:

- accept the synthetic account's sign-in and validate bearer tokens on subsequent requests;
- return deterministic responses and reject unknown endpoints;
- provide an `online` mode with normal responses;
- provide an `offline` mode with network errors or dropped connections;
- provide a `hanging` mode that keeps real requests pending;
- release held responses after the reference value changes;
- expose pending request counts and completed response evidence for assertions.

For Web, the reference setup intercepts API requests through Playwright while
keeping local app files accessible. Android uses a real HTTP server. Its
`/__qa/control` and `/__qa/status` routes belong exclusively to the test setup;
they do not need to be added to the product backend.

Bind the server to loopback. Allow only the selected browser origin, reject
accidental production requests, and use synthetic accounts. Request logs only
need paths, methods, modes, and completion state; omit passwords, tokens, and
authorization headers.

An immediate network error cannot replace `hanging`: it will not expose an app
that waits for a long timeout before displaying cached content.

## 6. Set up Web tests

1. Build an optimized web app with the test API URL.
2. Configure the local server and Playwright `webServer`; do not silently reuse
   an unrelated server already listening on the same port.
3. Create an isolated context, sign in, and wait until the required cache write
   completes, rather than stopping at the first successful HTTP response.
4. Close the page, switch the API mode, and open a new document.
5. Within one overall deadline, verify search availability, enter the query,
   and assert the specific local result.
6. In `hanging` mode, prove that a request is pending and no responses have
   completed. Hold the API for the full 30-second window and assert the data again.
7. Restore the API and verify the new value, disappearance of the old value,
   and preservation of the query. If the product requires Retry, click it explicitly.
8. In a separate test, terminate Chromium completely and reopen the same temporary
   disk profile. A new empty context does not prove persistence.

For Flutter, the reference setup activates the accessibility DOM through the
standard `flt-semantics-placeholder`. Search input uses keyboard events via
`pressSequentially`: in the verified configuration, `fill()` could change the
field's DOM mirror without updating its Dart controller. Always assert the entered
query itself; results might already have been visible before typing.

Example commands **for CashFlow**; replace the directory and API setting when porting:

```powershell
cd app
.\scripts\setup_vscode_flutter_env.ps1 -Run 'flutter build web --release --no-web-resources-cdn --dart-define=CASHFLOW_API_URL=http://127.0.0.1:18741'
cd ../tests/browser
npm ci
npx playwright install chromium
npm run test:repeat
```

Complete runner from the CashFlow root: `scripts/test-offline-browser.ps1`.

## 7. Set up Android tests

### Isolate the build before installation

Create a separate application ID, such as `<main-package>.offlineqa`.
The test API, metrics flag, and package selection should be controlled consistently
by one build variant. In CashFlow, Gradle reads the same encoded `dart-defines`
that enables `CASHFLOW_OFFLINE_QA_METRICS=true` in Dart. Replace CashFlow-specific
names if the target project uses different flags.

Verify the identifier **inside the built APK**, rather than relying solely on
Gradle sources or `output-metadata.json`. During the initial CashFlow setup, a
separate build variable did not take effect and the APK updated the emulator's
regular package. Its data was not cleared, and the regular build was subsequently
restored. The final helper therefore checks `aapt dump badging` before installing.

Allow `pm clear` only for the verified test package on a dedicated emulator.
Keep regular app and user data cleanup out of this setup. Reject physical devices
if the runner is designed for an AVD. Test signing must not weaken the signing
checks for regular releases.

### Connect the emulator to the server

Check the tools and select a device:

```powershell
adb version
emulator -list-avds
adb devices
```

In the standard Android Emulator, `10.0.2.2` accesses the host loopback interface:
configure the app with `http://10.0.2.2:18742` and bind the server to
`127.0.0.1:18742`. Other emulator or device types may need a different address.
If using HTTP, permit it for the test variant through the project's network
configuration; the production policy does not need to change for the test.

Do not treat `adb reverse` as evidence of the normal network path: a USB/adb tunnel
may keep API access available after disabling radios. The reference setup uses
no such tunnel. It disables Wi-Fi and mobile data, verifies their settings, and
also drops API connections. In `hanging` mode, radios remain enabled while the
server holds responses. After restoring connectivity, wait for a real route to
the host; the reference uses `ping`, rather than a fixed delay before Retry.

### Measure the first useful frame

`am start -W`, splash disappearance, and Argent call duration do not measure the
time until useful data appears. The reference implementation works as follows:

1. The test Flutter build restores the session and local snapshot.
2. After `runApp`, it awaits `waitUntilFirstFrameRasterized`.
3. Only when an authenticated user and a usable snapshot exist does it signal
   frame readiness through a QA-only MethodChannel.
4. The test package's `MainActivity` calls Android `reportFullyDrawn()`.
5. The runner reads the current launch's `Fully drawn` logcat entry and compares
   its time against the budget. A run marker separates it from older entries.
6. Independent UI assertions confirm that the screen contains the correct data.

Implementation points: `app/lib/main.dart`, Android `MainActivity.kt`, and
`tests/android/scripts/actions.mjs`. Another stack needs an equivalent signal
after useful content renders; the principle does not depend on Flutter.
The marker must not fire on an empty screen or before reading the cache.

### Record and replay the UI flow

Add stable accessibility or test identifiers for sign-in fields, search, and
relevant screens. Record the initial path through Argent, then turn it into a
saved flow. After navigation, assert the destination's identity and readiness;
after typing, assert the full value. Assert that old data is absent only after
that same data has previously been confirmed visible.

Parameterize credentials through `{{secret:...}}`, use synthetic values only,
and keep `.argent/secrets.env` out of Git. Final actions should target stable
identifiers or names, without coordinates or a hard-coded emulator serial.
The CashFlow recording is an example; record the target app's sign-in again.

Before the first acceptance run, restart Argent services for the selected device
only. Then run the same flow twice consecutively, without manual intervention or
retries that hide failures. Inspect warnings as well as the final `ok` status.
In CashFlow, cursor movement on an autofocus form is acceptable; a missing element
tree or an unverified coordinate hit is not an acceptable warning.

Complete runner from the **CashFlow** root, with the dedicated AVD already running:

```powershell
.\scripts\test-offline-android.ps1 -Device emulator-5554
```

Running the flow on its own requires an installed QA APK, a running fixture server,
and configured synthetic credentials:

```powershell
argent flow run qa-android-offline-cache --device emulator-5554 --platform android --json
```

On Android API 36 in the verified configuration, Gboard displayed a stylus input
tutorial that stole focus. Setup disables `stylus_handwriting_enabled`, saves its
previous value, and restores it on completion. This emulator setting makes runs
reproducible; it does not bypass an application defect.

## 8. Interpret timing correctly

| Reference metric | Included | Excluded |
| --- | --- | --- |
| Web `usefulScreenMs` | Navigation until the search field becomes available | Chromium process startup and initial online preparation |
| Web `searchResultMs` | Navigation, cache reading, query entry, and detection of the correct result, including automation overhead | Time before navigation starts |
| Android `usefulFrameMs` | Native launch until the signal after the first rasterized frame with local data | Initial online sign-in and subsequent search query entry |

Web and Android values cannot be compared directly because their measurement
boundaries differ. Android search is verified functionally, separately from the
native startup metric. If the target project needs a deadline for results after
query entry, add a separate measurement with explicit start and end points.

## 9. Reports, cleanup, and CI

For each run, retain the scenario, threshold, environment or device, actual timing,
expected and actual values, UI assertion results, and request state.
Capture screenshots or traces on failure, but do not treat an image as the only
evidence of correctness. The 5% → 9% → 13% sequence is an example of a verifiable
change, rather than universal fixture values to copy.

Reference output locations:

- Web: `tests/browser/test-results/`, `playwright-report/`, JSON metrics, and traces.
- Android: `tests/android/results/pass-1.json`, `pass-2.json`, and
  `device-state.json` containing native metrics.

Restore network and input settings both after success and in `finally` after
failure. Stop the test-owned server using its saved process handle; scope Argent
service shutdown to the selected device. Do not clear unrelated browser profiles,
an entire device, or a user's database. Do not transfer previous run state or the
serial number in `device-state.json` to another machine: it is a local artifact.

Web CI builds a release, runs `npm ci`, installs Chromium with system dependencies
(`npx playwright install --with-deps chromium`), runs `npm run test:repeat`, and
uploads reports with `if: always()`. In CashFlow, this is a required CI check.
Android currently runs locally; its CI setup separately requires an emulator,
hardware acceleration, SDK/JDK, and Argent. Copying the Web workflow alone does
not enable Android testing.

## 10. Coverage limits

These checks do not establish:

- Fully offline reopening of a website or PWA without access to HTML, JavaScript,
  fonts, and other files. The Web suite keeps local file serving available.
  That separate scenario requires testing the app shell cache or service worker.
- Correctness of the real backend. A synthetic API tests client behavior;
  a separate integration suite with a real test backend is still needed.
- Automatic refresh after reconnection when the scenario clicks Retry.
- Offline writes, queue synchronization, conflict resolution, or multiple devices.
  This setup tests reading previously loaded data.
- Physical phone performance based on emulator results.
- Availability of data that was never loaded or persisted.

## 11. Port completion checklist

- [ ] The test API URL is selected at build time; production is not used.
- [ ] Fixtures match the models and contain related reference records and a mutable value.
- [ ] The session and cache are created through actual UI sign-in and loading.
- [ ] Tests cover disconnection and a separate request held for at least 30 seconds.
- [ ] A full restart preserves data; a fresh empty session is not presented as a restart.
- [ ] Measurement boundaries are documented; the fixed threshold is recorded in reports.
- [ ] Correct results, query preservation, and replacement of old values are explicitly asserted.
- [ ] The Android APK is checked before installation; only the QA package is cleared.
- [ ] All interactions use stable UI targets; warnings have been reviewed.
- [ ] Two consecutive runs pass without retries that hide failures.
- [ ] Failure triggers cleanup; tokens and local artifacts are excluded from Git.
- [ ] CI status and uncovered scenarios are documented separately from local success.

## Short task prompt for an agent in another project

> Set up ongoing offline read regression tests using this guide. Read repository
> instructions and existing build procedures. Configure a test API with known
> data and a separate Android QA package. Through the actual UI, sign in, load
> data, terminate the app completely, launch without connectivity, search, launch
> with API responses held for 30 seconds, and restore connectivity with changed
> data. Record metrics and measurement boundaries; assert useful content before
> the server responds. Preserve the runner, project adapter, launch commands, and
> reports. Achieve two consecutive complete passes; report real defects without
> weakening assertions. Restore settings and stop only test-owned resources.
> Do not use production or clear the regular app. Document configured CI and
> remaining limitations separately.

## Reference project resources

- [Browser tests and commands](../tests/browser/README.md).
- [Android flow, contract, and results](../tests/android/README.md).
- [Web runner](../scripts/test-offline-browser.ps1).
- [Android runner](../scripts/test-offline-android.ps1).
- [Recorded Android flow](../.argent/flows/qa-android-offline-cache.yaml).
