# Authentication

CashFlow uses server-side bearer sessions. The client receives a random token after login,
while PostgreSQL stores only its SHA-256 digest. Sessions last 30 days by default
(`CASHFLOW_SESSION_TTL_HOURS=720`); the allowed range is 1–8760 hours.

Expiration is sliding: when less than half of the configured lifetime remains, an
authenticated request extends the session by the full lifetime. The server exposes the
current value in `X-CashFlow-Session-Expires-At` so clients can persist the correct offline
expiration.

The Flutter client stores the token, verified identity, and expiration in platform secure
storage (Keychain, Keystore, or the platform equivalent). A locally unexpired, previously
verified session can open from cached data while the server is temporarily unreachable.
An explicit server `401` clears all saved authentication data immediately.

Accounts are separate from card owners. Registration is closed. Roles are hierarchical:

- `viewer` can read business data;
- `editor` can also change cashback categories and run imports;
- `admin` can also manage banks, card owners, cards, and authentication accounts.

Public routes are limited to `/health`, `/ready`, `/version`, and `/api/auth/login`.
Login throttling is stored in PostgreSQL and blocks a username/address pair for 15 minutes
after five failed attempts.

Create or reset the first administrator interactively after migrations:

```powershell
uv run flask --app main set-auth-user <username> --role admin
```

List configured accounts:

```powershell
uv run flask --app main list-auth-users
```

Passwords must contain at least 12 characters. They are hashed with scrypt using an individual
random salt. Passwords, bearer tokens, production environment files, and database dumps must
never be added to Git.
