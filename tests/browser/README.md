# Offline browser contract

Перенос в другой проект: [общее руководство Web + Android](../../docs/offline-testing-setup-guide.md).

Permanent regression tests against a **release Flutter web build and a synthetic
API**, running locally or in CI. No production accounts, databases or credentials
are used. Only `http://127.0.0.1:18741` is reachable from the test pages; remote
requests are aborted, including accidental production API calls. The server
binds to loopback and the runner refuses to reuse an existing server.

## Run

On Windows, from the repository root:

```powershell
.\scripts\test-offline-browser.ps1
```

The helper resolves Flutter using the existing VS Code SDK configuration, builds
the app, installs the pinned npm dependencies and Chromium, then executes every
scenario twice without retries. Use `-SkipBuild` only with a matching local API
build. Node.js 20 or later is required.

Equivalent commands on a machine with Flutter and Node configured:

```sh
cd app
flutter build web --release --no-web-resources-cdn --dart-define=CASHFLOW_API_URL=http://127.0.0.1:18741
cd ../tests/browser
npm ci
npx playwright install chromium
npm run test:repeat
```

CI installs Linux browser dependencies with `playwright install --with-deps`.
`offline-browser-ci.yml` is part of the required CI aggregate and uploads evidence
even when the tests fail. A single run is `npm test`; view the HTML report with
`npm run report`.

## Acceptance contract

| Start state and action | Hard evidence |
| --- | --- |
| Clean browser, normal login, initial fetch | Real login form, authenticated synthetic API calls, visible 5% offer and completion of the primary cache-writing refresh |
| Close page and open a new document with API disconnected | Within 2 seconds of navigation, search is enabled and the query returns the cached offer, card 4242, correct bank and owner, 5% |
| Keep API responses pending for 30 seconds after reopening | Same 2-second deadline; pending request really exists, no API response completed; cached result and query remain after 30 seconds |
| Restore the disconnected API and press the existing Retry button | Offer changes from 5% to 9%, old rate disappears, query remains, stale warning disappears and login is not shown |
| Release delayed responses after the 30-second window | Same 9% update occurs without another navigation or login |
| Exit Chromium completely, reopen its real profile, API disconnected | The same cached identity, search result, bank, owner and card survive the process exit, within the 2-second navigation budget |

Each case gets its own clean storage. Cache and authentication are populated by
the application, never injected into localStorage or IndexedDB. The full-process
case reuses an actual disk profile and deletes only that task-owned profile after
the test. API checks reject unknown endpoints and verify bearer authentication.
Unhandled page errors fail the tests. Known static font fallback requests may be
attempted by Flutter; they are blocked and their origins are reported, not treated
as application API failures.

The 2-second limit covers navigation, loading application resources, restoring
storage, rendering accessible UI, entering the query and observing the matching
result. It includes automation overhead; it is an upper bound, not a precise
first-paint measurement. `usefulScreenMs` measures the enabled search field;
`searchResultMs` additionally proves useful cached content. Chromium process
launch and the initial online warm-up are outside this timing window. Browser
numbers are not Android startup measurements.

For an explicitly different reference machine, set `OFFLINE_STARTUP_BUDGET_MS`.
The selected budget is recorded in the report. Tests run serially with no retries;
CI repeats each scenario twice. A failure must not be hidden by increasing the
budget or replacing the cached-content assertions with a generic shell check.

## Evidence and scope

`test-results/` contains measurement JSON, final screenshots and failure traces.
`playwright-report/` contains the HTML report. Measurements include timings and
request paths/modes, without credential bodies or authorization headers.

These tests model **unavailable or unresponsive API while the local application
files remain available**. They do not prove a website/PWA can load its HTML,
JavaScript and fonts after total network loss. CashFlow currently removes legacy
service workers and caches; full offline web boot needs a separate product
contract. Android storage, OS process startup, radio state and native plugins also
require a later device-level suite. Reconnection after failed requests currently
uses the UI's Retry button; automatic reconnect refresh is not asserted.

The synthetic API suite verifies frontend persistence and failure behavior, not
backend compatibility. The existing integration CI continues to cover the real
frontend/backend stack. Dates on offers cover the test lifetime rather than
depending on a current month's production data.

## Reuse in another project

- `support/network-controller.mjs`: API outage, held responses, release, request
  evidence and blocking requests outside the selected origin.
- `support/persistent-browser.mjs`: process restart with a real isolated profile.
- `support/evidence.mjs`: JSON measurements and report attachments.
- `support/cashflow-adapter.mjs`: replace for another app: login, fixtures,
  selectors, search and refresh actions. The semantics activation is Flutter-only.
- `specs/`: retain the acceptance sequence and change the project assertions.
- `support/static-server.mjs`, build command and CI: adapt to the new project's
  build directory, API configuration and artifact requirements.

Supporting Dart tests in `app/test/offline_startup_test.dart` exercise a pending
session validation without a real clock delay, preservation on 503 and revocation
on a delayed 401. Browser tests also protect the first web login's encrypted
storage writes: parallel first writes previously produced unreadable sessions.
