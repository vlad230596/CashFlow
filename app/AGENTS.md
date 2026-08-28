# CashFlow Agent Notes

## Project Overview

CashFlow is a Flutter application for tracking bank cards and cashback categories. The app keeps a local cache of data and synchronizes with a backend API over HTTP.

Main user flows:

- View active cashback categories, sorted by cashback percent.
- View cards and their active cashback categories.
- Manage banks, users, and cards from settings screens.
- Manage monthly cashback category selection per card.

## Tech Stack

- Flutter / Dart.
- Dart SDK constraint: `^3.6.2`.
- State management: `provider` with a single `DataProvider` registered in `main.dart`.
- HTTP client: `http`.
- Local persistence: `shared_preferences`.
- UI: Material widgets, mostly direct `Scaffold`, `AppBar`, `ListView`, `GridView`, forms, dialogs.
- Lints: `flutter_lints` via `analysis_options.yaml`.
- Platforms present: Android, iOS, web, Windows, Linux, macOS.

## Important Files

- `lib/main.dart` initializes Flutter, restores authentication, and registers `DataProvider`.
- `lib/providers/data_provider.dart` owns application state, backend calls, local cache, and mutations.
- `lib/models/` contains plain model classes with `fromJson` factories and static `toJson` methods.
- `lib/screens/home_screen.dart` defines the tabbed app shell and settings menu.
- `lib/screens/cashback_screen.dart` shows searchable active cashback categories.
- `lib/screens/cards_screen.dart` shows cards with related active categories.
- `lib/screens/monthly_cashback_screen.dart` handles monthly category selection and bulk category entry.
- `lib/screens/settings/` contains CRUD screens for banks, users, and cards.
- `lib/utils/category_info.dart` maps category names to Material icons and colors.
- `test/widget_test.dart` contains a current smoke test that starts `MyApp` with `DataProvider`.

## Data Flow

`DataProvider` is the central source of truth.

- On startup, `main.dart` creates `DataProvider`, calls `initialize()`, then registers it before `runApp`.
- `DataProvider.initialize()` loads local cached data, restores the bearer session from secure
  storage, and starts `fetchAllData()` only for an authenticated user.
- `fetchAllData()` loads banks, users, cards, active cashback, and all cashback categories from the backend.
- Fetched data is cached to `SharedPreferences`.
- UI screens read state through `Provider.of<DataProvider>(context)` or `Consumer<DataProvider>`.
- Mutating methods call the backend first, update in-memory lists, then call `notifyListeners()`.

Current cached keys:

- `banks`
- `users`
- `cards`
- `activeCashbackCategories`

## Backend Contract

The app uses a REST API base URL supplied at build time:

```text
--dart-define=CASHFLOW_API_URL=https://host:port
```

The local-development default remains:

```dart
http://192.168.31.142:5000
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
- `CardModel` fields are nullable; list screens should render fallbacks rather than force unwrap card metadata.
- `UserModel.id` and `UserModel.name` are required.
- `CashbackCategoryModel` fields are required.
- Dates are serialized with `DateTime.toIso8601String()` and parsed with `DateTime.parse`.
- `DataProvider.getCardById()` returns a fallback `CardModel` when a referenced card is missing.
- `DataProvider.getCardName()` returns `Unknown card` when matching bank/user data is unavailable.

When changing backend contracts or model nullability, update the model, provider, and dependent UI together.

## UI Conventions

- The app uses Material widgets without a custom design system.
- Navigation is currently direct `Navigator.push` with `MaterialPageRoute`.
- Forms are implemented as stateful screens with `TextEditingController`s.
- Settings lists use `RefreshIndicator` and fetch all data on pull-to-refresh.
- Most user-facing text is currently English, with some Russian UI in monthly cashback flows.
- Some older Russian strings/comments may appear corrupted as mojibake in untouched source files.
- Keep UI changes modest and consistent unless explicitly asked for a redesign.

## Known Issues And Sharp Edges

- Treat corrupted Russian strings/comments as an explicit encoding/data-cleanup task, not as incidental formatting. Do not rewrite large files just to fix unrelated mojibake unless asked.
- Some settings/edit screens still force unwrap nullable IDs or names from `BankModel`, `CardModel`, and `UserModel`.
- `maxCashbackCategories` is shown and edited locally in `MonthlyCashbackScreen`, but changes are intentionally not persisted to the backend yet.
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

The backend must be reachable at the configured `serverIp` for refresh and mutation flows.

## Working Guidelines For Agents

- Prefer `rg` / `rg --files` for searches.
- Keep changes scoped to the requested feature or bug.
- Follow the existing `provider` pattern unless a larger architecture change is explicitly requested.
- Put new shared state and backend methods in `DataProvider`.
- Keep model JSON keys aligned with the backend snake_case API.
- Avoid broad formatting-only edits, especially in files with existing encoding issues.
- Preserve user edits in a dirty worktree.
- Add or update tests when changing behavior; `test/widget_test.dart` is a smoke test for the current app shell.
- If backend behavior is unclear, ask before inventing an endpoint or changing payload shape.

## Open Questions

- Is the backend repository available locally, and should agents inspect it when changing API-related code?
- Should `serverIp` remain hardcoded, move to settings, or be configured through environment/build config?
- Should the full app language stay mixed during transition, or should English settings screens be localized to Russian?
- Should remaining corrupted Russian strings/comments be repaired as a separate cleanup task?
- Should monthly `maxCashbackCategories` be persisted, and if yes, which endpoint owns that value?
- Which platforms are actually supported targets: mobile only, desktop, web, or all generated Flutter platforms?
