# CashFlow Agent Notes

## Project Overview

CashFlow is a Flutter family cashback assistant. It manages cards, cashback categories, monthly plans, bank confirmation, partner offers, MCC rules, and personal subscription renewals. The app keeps account-scoped local caches and synchronizes with a backend API over HTTP.

Main user flows:

- View active cashback categories, sorted by cashback percent.
- Build a manual monthly selection plan and confirm selections imported from banks.
- Review and classify personal partner offers.
- Track subscription renewals and confirmed payments; schedule local reminders on Android.
- Manage banks, users, and cards from settings screens.
- Import and publish MCC rule revisions from administrative screens.

## Tech Stack

- Flutter / Dart.
- Dart SDK constraint: `^3.6.2`.
- State management: `provider` with a single `DataProvider` registered in `main.dart`.
- HTTP client: `http`.
- Local persistence: `shared_preferences` for small collections; IndexedDB (web)
  and atomic application-support files (native) for MCC snapshots.
- UI: Material widgets, mostly direct `Scaffold`, `AppBar`, `ListView`, `GridView`, forms, dialogs.
- Lints: `flutter_lints` via `analysis_options.yaml`.
- Platforms present: Android, iOS, web, Windows, Linux, macOS.

## Important Files

- `lib/main.dart` initializes Flutter, restores authentication, and registers `DataProvider`.
- `lib/providers/data_provider.dart` owns application state, backend calls, local cache, and mutations.
- `DataProvider` remains a compatible facade; `lib/services/reference_data_store.dart`,
  `api_client.dart`, `mcc_cache_store.dart`, and `import_coordinator.dart` own the extracted
  reference collections, authenticated transport, bounded MCC cache, and import stages.
- `lib/services/monthly_plan_projection.dart` and `card_context.dart` contain pure plan
  calculations and card/bank/owner presentation. `lib/utils/cashback_period.dart` and
  `lib/services/business_clock.dart` define calendar periods and Moscow business dates.
- `../docs/refactoring-handoff.md` records which original refactoring items are
  complete or partial and where to continue. Do not infer completion from extracted
  files alone; DataProvider and backend separation remain partial.
- `lib/models/` contains plain model classes with `fromJson` factories and static `toJson` methods.
- `lib/screens/home_screen.dart` defines the five-destination adaptive shell: Benefit, Plan, Offers, Subscriptions, and More.
- `lib/screens/cashback_screen.dart` shows searchable active cashback categories and benefit states.
- `lib/screens/monthly_cashback_screen.dart` handles monthly category selection and bulk category entry.
- `lib/screens/partner_offers_screen.dart` shows the account-scoped partner offer catalogue;
  filtering, sorting and the category breakdown live in `lib/services/partner_offer_catalog.dart`.
- `lib/screens/cards_screen.dart` («Карты и категории», opened from More) and
  `card_cashback_screen.dart` show what is selected per card (`services/card_cashback_overview.dart`).
- `lib/screens/subscriptions_screen.dart` manages renewals, payments, and archive state.
- `lib/screens/more_screen.dart` contains refresh, import, date, administration, session, and logout actions.
- `lib/screens/settings/` contains CRUD screens for banks, users, and cards.
- `lib/utils/category_info.dart` maps category names to Material icons and colors.
- `test/widget_test.dart` contains a current smoke test that starts `MyApp` with `DataProvider`.

## Data Flow

`DataProvider` is the central source of truth.

- On startup, `main.dart` creates `DataProvider`, calls `initialize()`, then registers it before `runApp`.
- `DataProvider.initialize()` restores the saved bearer and verified identity, then loads
  account-scoped caches without waiting for network validation. It validates `auth/me`
  and refreshes data in the background. Transport failure preserves the local session;
  a server 401 clears it. A bearer without a saved identity still needs online validation.
- Everything before `runApp` delays the first frame (the native splash stays up), so
  keep network and large reads out of `initialize()`. The MCC cache is read after the
  first rasterized frame (`afterFirstFrame`); see
  `../docs/incident-2026-10-15-slow-android-start.md`.
- All HTTP goes through `TimeoutClient` (15 s to response headers, 30 s for the body);
  a timeout is a transport failure and keeps a verified session.
- `AppLog` records startup stages and every request (method, path without query,
  status, duration) with wall time and ms since process start. Never log tokens,
  bodies or personal data. On Android the file is readable from release builds:
  `adb pull /sdcard/Android/data/com.example.cash_app/files/logs/cashflow.log`.
  Logcat on the user's phone keeps only ~20 minutes.
- Secure session fields are written sequentially: concurrent first writes can race the
  web storage encryption-key creation and make the next startup unable to decrypt them.
- `fetchAllData()` loads banks, users, cards, active cashback, cashback categories, partner offers, and subscriptions from the backend.
- Fetched data is cached to `SharedPreferences`.
- UI screens read state through `Provider.of<DataProvider>(context)` or `Consumer<DataProvider>`.
- Mutating methods call the backend first, update in-memory lists, then call `notifyListeners()`.

Current cached keys:

- `banks`
- `users`
- `cards`
- `activeCashbackCategories`
- Main collections, partner offers, and subscriptions use API URL/account-scoped keys.
- `MccRepository` returns cached MCC results immediately and revalidates in the background.
  Complete snapshots and dated individual-answer overlays are separate, scoped by API URL,
  account and date. A successful single-code request must never replace the complete base.
- `MccCacheStore` migrates legacy SharedPreferences data only after a successful dedicated
  storage write. It keeps a latest-snapshot pointer, up to three dates per scope, and a
  32 MiB logical-record budget; native recovery generations add physical disk overhead.
- Schema 3 stores normalized revisions, a server-computed sparse MCC index/defaults,
  and separate offer bindings. The reader retains compatibility with schemas 1 and 2.

## Backend Contract

The app uses a REST API base URL supplied at build time:

```text
--dart-define=CASHFLOW_API_URL=https://host:port
```

Without a build-time override, the app uses the production API:

```dart
https://cash-flow-app.duckdns.org:8443
```

All `/api` requests except login carry a bearer token. The token is stored with
`flutter_secure_storage`, never in `SharedPreferences`.

Known endpoints:

- `GET /api/banks`
- `POST /api/banks`
- `PUT /api/banks/{id}`
- `DELETE /api/banks/{id}`
- `GET /api/users`
- `POST /api/users`
- `PUT /api/users/{id}`
- `DELETE /api/users/{id}`
- `GET /api/cards`
- `POST /api/cards`
- `PUT /api/cards/{id}`
- `DELETE /api/cards/{id}`
- `GET /api/cashback`
- `POST /api/cashback`
- `PUT /api/cashback/{id}` for category selection updates
- `GET /api/active_cashback`
- `POST /api/cashback/import`
- `GET /api/partner-offers`
- `GET /api/partner-offers/{id}`
- `PUT /api/partner-offers/{id}/preference`
- `POST /api/partner-offers/import`
- `GET /api/subscriptions`
- `POST /api/subscriptions`
- `PUT /api/subscriptions/{id}`
- `POST /api/subscriptions/{id}/archive`
- `POST /api/subscriptions/{id}/restore`
- `POST /api/subscriptions/{id}/payments`
- `GET /api/mcc` (code and title of every reference MCC; loaded once into
  `DataProvider.mccCatalog` for search)
- `GET /api/mcc/offline-snapshot?schema=3&as_of=` (authenticated catalogue, normalized
  revisions, server-computed index, offer bindings and separate content versions;
  supports private ETag/304; downloaded in the background for offline search)
- `GET /api/mcc/offline-manifest?as_of=` (rule/binding/content versions)
- `GET /api/mcc/{code}`
- `GET /api/mcc/{code}/bank-rules?as_of=` (per bank: category, exclusion kind, status and
  `offer_ids` of offers in that period whose bank category earns the code; the Benefit
  screen intersects them with active offers)
- `GET /api/cashback/{id}/mcc-rules` (published bank category behind an offer, matched
  by normalized name, with titled included/excluded codes and program exclusions; 404
  when the bank has no rules for it)
- `GET /api/canonical-categories` (cached as `canonicalCategories`; cashback offers carry
  `canonical_keys`, and the plan groups offers by these unified categories)
- `PUT /api/canonical-categories/{key}` (editor+; replaces only `aliases`, the search
  synonyms edited in More → «Категории и синонимы»; the database copy is authoritative,
  `backend/data/canonical_categories.json` only seeds it)
- `GET /api/canonical-categories/{key}/bank-categories?as_of=`
- `GET /api/admin/mcc-rule-revisions`
- `POST /api/admin/mcc-rule-snapshots`
- `POST /api/admin/mcc-rule-snapshots/preview` (read-only normalized document and full
  diff; preview hashes can accompany draft creation to reject an outdated comparison)
- `POST /api/admin/mcc-rule-revisions/{id}/publish`
- `POST /api/auth/login`
- `GET /api/auth/me`
- `POST /api/auth/logout`

Expected status codes:

- Create: `201`.
- Update: `200`.
- Delete: `204`.

JSON uses snake_case field names such as `payment_system`, `last_four_digits`, `cashback_percent`, `start_date`, `end_date`, and `is_selected`.

## Models And Assumptions

- `BankModel.id`, `BankModel.name`, and `BankModel.description` are nullable in Dart, but most UI code assumes `id` and `name` are present.
- `BankModel.bankKey` is the stable integration identity; `iconKey` and display name
  are independent. Prefer bankKey for import/export; alias matching supports older APIs.
- `CardModel` fields are nullable; list screens should render fallbacks rather than force unwrap card metadata.
- `UserModel.id` and `UserModel.name` are required.
- `CashbackCategoryModel` fields are required.
- Dates are serialized with `DateTime.toIso8601String()` and parsed with `DateTime.parse`.
- `DataProvider.getCardById()` returns a fallback `CardModel` when a referenced card is missing.
- `DataProvider.getCardName()` returns `Unknown card` when matching bank/user data is unavailable.

When changing backend contracts or model nullability, update the model, provider, and dependent UI together.

## UI Conventions

- The app uses a shared `CashFlowTheme` plus Material widgets.
- The authenticated shell uses an `IndexedStack`; nested routes use `Navigator.push` with `MaterialPageRoute`.
- Forms are implemented as stateful screens with `TextEditingController`s.
- Settings lists use `RefreshIndicator` and fetch all data on pull-to-refresh.
- Current product UI is primarily Russian; older settings and technical strings may still be English.
- Layouts use compact `<600`, medium `600–839`, and expanded `>=840` width policies.
- Some older Russian strings/comments may appear corrupted as mojibake in untouched source files.
- Keep UI changes modest and consistent unless explicitly asked for a redesign.

## Known Issues And Sharp Edges

- Treat corrupted Russian strings/comments as an explicit encoding/data-cleanup task, not as incidental formatting. Do not rewrite large files just to fix unrelated mojibake unless asked.
- Some settings/edit screens still force unwrap nullable IDs or names from `BankModel`, `CardModel`, and `UserModel`.
- `maxCashbackCategories` is shown and edited locally in `MonthlyCashbackScreen`, but changes are intentionally not persisted to the backend yet.
- Automatic MCC import returns `501 automatic_source_not_configured`. Import review
  shows an immediate local preview and uses authoritative server normalization/diff
  before draft creation; older APIs without preview retain the local fallback.
- Offline MCC results show snapshot collection time and rule date. A prior day's
  snapshot can explain bank rules but must not supply current offer IDs. The full
  offline experience requires one successful snapshot download from the updated API.
  Binding mutations invalidate stored offer links across restart until refreshed.
  Web data survives reload in IndexedDB, but a cold website launch without network
  requires a separately cached application shell; current `web/cache_reset.js` removes
  service workers and CacheStorage. Search works offline in an already loaded web app.
- Subscription notifications are intentionally Android-only; web, iOS, and desktop still store subscription data but do not schedule local notifications.
- The purchase-search UI is ahead of the backend domain model: operations, normalized merchants, MCC observations, and a universal recommendation endpoint do not exist yet.
- `flutter analyze` and `flutter test` require Flutter/Dart to be available in PATH; the current sandbox shell may not have them configured.
- Git may report dubious ownership in the sandbox for `D:/Projects/CashFlow`; avoid changing git config unless the user approves.

## Flutter Commands

Run Flutter and Dart commands through the repository helper so the agent uses the same SDK path as VS Code. The helper reads `dart.flutterSdkPath` from VS Code settings JSON and adds that SDK's `bin` directories to the current process environment. It intentionally does not guess SDK locations from `PATH`, `FLUTTER_ROOT`, or common install folders; if VS Code is not configured, Flutter commands should fail until the SDK path is configured.

Use these from the `app/` directory:

```powershell
.\scripts\setup_vscode_flutter_env.ps1 -Run "flutter pub get"
.\scripts\setup_vscode_flutter_env.ps1 -Run "flutter analyze"
.\scripts\setup_vscode_flutter_env.ps1 -Run "flutter test"
.\scripts\setup_vscode_flutter_env.ps1 -Run "dart format lib test"
```

To run several commands in the same PowerShell session, dot-source the helper first:

```powershell
. .\scripts\setup_vscode_flutter_env.ps1
flutter pub get
flutter analyze
flutter test
dart format lib test
```

For web runs, use the same helper:

```powershell
.\scripts\setup_vscode_flutter_env.ps1 -Run "flutter run -d chrome"
```

For one-off troubleshooting only, an explicit SDK path may be passed:

```powershell
.\scripts\setup_vscode_flutter_env.ps1 -FlutterSdkPath C:\path\to\flutter -Run "flutter --version"
```

The backend must be reachable at the configured `CASHFLOW_API_URL` for refresh and mutation flows.

Offline browser regression tests use a synthetic local API and a release web build.
From the repository root run `scripts/test-offline-browser.ps1`; see
`tests/browser/README.md` for the 2-second cached-search contract, process restart,
30-second hanging responses, CI evidence and reuse in other projects. This suite
does not prove a PWA can boot without access to its application files or validate
native Android storage and startup timing.

The Android counterpart is `scripts/test-offline-android.ps1` from the repository
root; see `tests/android/README.md`. It uses the dedicated package
`com.example.cash_app.offlineqa`, enabled by the Flutter define
`CASHFLOW_OFFLINE_QA_METRICS=true`. The same define selects package isolation in
Gradle; always verify the actual APK package before installing. Its first cached
rasterized frame reports Android fully-drawn timing through a QA-only channel.
The ordinary package is never cleared by the runner. The saved Argent flow uses
stable semantics identifiers for login and Benefit search and resets only QA data.

Android Back regression coverage is documented in `../tests/android/BACK.md`.
From the repository root, `scripts/test-android-back.ps1 -Passes 2` builds the
isolated QA APK and runs 23 real-IME checks twice. These emulator checks are
manual and are not connected to GitHub Actions. Widget regressions in
`test/keyboard_first_back_test.dart` and `test/mcc_search_test.dart` run with
the normal `flutter test` in Frontend CI and the release quality checks.
For editable routes, `screens/widgets/keyboard_first_back.dart` provides the
shared keyboard-first arrow; internal PopScope handlers must also dismiss a
visible IME before changing navigation state. Keep `maybePop` so route guards
remain effective after the keyboard closes.

## Working Guidelines For Agents

- Prefer `rg` / `rg --files` for searches.
- Keep changes scoped to the requested feature or bug.
- Follow the existing `provider` pattern unless a larger architecture change is explicitly requested.
- Preserve `DataProvider` as the public facade. Put domain implementation in the
  appropriate service/store; continue extracting one domain at a time according to
  `../docs/refactoring-handoff.md`, retaining session, cache and mutation guards.
- Keep model JSON keys aligned with the backend snake_case API.
- Avoid broad formatting-only edits, especially in files with existing encoding issues.
- Preserve user edits in a dirty worktree.
- Add or update tests when changing behavior; `test/widget_test.dart` is a smoke test for the current app shell.
- If backend behavior is unclear, ask before inventing an endpoint or changing payload shape.

## Open Questions

- What source supplies operations and actual MCC observations for merchant recommendations?
- How should merchant aliases and multiple observed MCC codes be normalized?
- Which category states participate in the best-payment calculation?
- How should family-space membership and per-card access relate to application accounts?
- Should subscription notifications be extended beyond Android?
- Should remaining corrupted Russian strings/comments be repaired as a separate cleanup task?
- Should changes to the local maximum in the monthly plan be persisted? The card's
  `max_cashback_categories` field and update endpoint already exist; the plan UI
  does not currently persist this local override. Define its ownership before wiring it.
- Should Web support cold startup offline, and how should PWA updates recover from
  an outdated shell? IndexedDB persistence alone does not cache the application shell.
- Release targets are Web and Android APK; decide whether iOS and desktop become supported acceptance targets rather than generated project scaffolding only.
