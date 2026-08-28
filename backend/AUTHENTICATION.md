# Authentication

CashFlow uses server-side bearer sessions. The client receives a random token after login,
while PostgreSQL stores only its SHA-256 digest. Sessions expire after 12 hours by default;
the allowed range is 1–24 hours.

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
