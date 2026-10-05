# Project Environment

- App: Flutter/Dart in `app/`; Android application id `com.example.cash_app`.
- Flutter commands must run from `app/` through `scripts/setup_vscode_flutter_env.ps1`.
- Android: build with `flutter build apk --debug`; install artifact at `build/app/outputs/flutter-apk/app-debug.apk`.
- Tests: `flutter analyze` and `flutter test`; UI coverage includes compact/expanded layouts, large text, dark mode, roles, and screen states.
- Canonical design reference: `docs/design/review-index.md`, with approved PNGs in `docs/design/concepts/` and matching HTML prototypes in `docs/design/prototypes/`.
- Primary mobile shell: `Выгода · План · Акции · Ещё`; compact navigation is bottom-aligned, expanded navigation is a side rail.
- Authenticated shell state lives in an `IndexedStack` in `app/lib/screens/home_screen.dart`; nested screens use `Navigator.push(MaterialPageRoute)`.
- Compact benefit details currently live in local `_selectedId` state inside `BenefitStatesView`, so Android Back must explicitly clear that state before the route can pop.
- Bank/user/card state is owned by `DataProvider`; persistent bank/user icon changes must update the SQLAlchemy model + migration, API JSON, Dart model/provider/cache, and settings UI together.
- Repository components: Flutter/Dart client in `app/`, Flask/Python/PostgreSQL/Alembic backend in `backend/`, and a WXT/React/TypeScript Manifest V3 browser extension in `app/browser_extension/`. This is not a React Native project; Metro is not applicable.
- Generated Flutter targets include Android, iOS, web, Windows, Linux, and macOS. Documented release targets are Flutter Web and a signed Android APK; the backend runs as a Linux/Gunicorn container behind Caddy.
- Backend parity uses Python 3.13 via `uv` (`uv sync --frozen`, `uv run ruff check .`, `uv run pytest -q`, `uv lock --check`, `uv run alembic upgrade head --sql`). The locally installed system Python may be outside the declared `<3.14` constraint.
- Browser-extension quality runs from `app/browser_extension/` with `npm run check` (TypeScript, Vitest, production build).
- Full-stack integration uses `docker compose -p cashflow-ci -f deploy/compose.ci.yaml up -d --build --wait --wait-timeout 180`; Docker availability varies by workstation.
- CI is orchestrated by `.github/workflows/ci.yml` for pushes/PRs to `dev` and `main`, with backend, frontend, browser-extension, and integration jobs. A successful `main` CI deploys the isolated development stack; production uses the manual protected `Release CashFlow` workflow with a SemVer input, signed APK, images, GitHub Release, and deployment.
- Public endpoints documented for delivery: production `https://cash-flow-app.duckdns.org:8443`, development `https://cash-flow-app.duckdns.org:8444`.
