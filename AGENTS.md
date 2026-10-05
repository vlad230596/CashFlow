# CashFlow Agent Guide

This file is the operational entry point for the whole repository. More specific
instructions may exist below a subdirectory (for example `app/AGENTS.md`), but
they do not override the environment and data-source rules in this file.

## Environments and sources of truth

| Environment | URL / location | Data store | Intended use |
| --- | --- | --- | --- |
| Production | `https://cash-flow-app.duckdns.org:8443` | PostgreSQL on the VDS in `/opt/cashflow` | Real current user and business data |
| Development | `https://cash-flow-app.duckdns.org:8444` | Isolated PostgreSQL in `/opt/cashflow-dev` | Synthetic integration data from `main` |
| Local backend | workspace process, when explicitly started | SQLite fallback or an explicitly configured database | Tests and local development only |

Production and development are deployed applications. The PostgreSQL services
do not publish a host port; Caddy exposes the HTTP API and web application.

For questions about what exists "now", "this month", "on any card", or in the
"selected/current database", use **production** unless the user explicitly
names local, test, development, a fixture, or a file. Do not infer the current
state from repository fixtures, Flutter caches, JSON captures, backup files, or
local SQLite databases.

Before answering a current-data question:

1. Resolve relative dates in the user's/project timezone (`Europe/Moscow`).
2. Use the authenticated production API when the required endpoint and session
   are available.
3. Otherwise use the read-only production snapshot route below.
4. State the environment and snapshot time in the answer when it matters.

Never mutate production, deploy, restore a database, or run administrative
commands unless the user explicitly requests that action. A data question
authorizes read-only inspection only.

## Read-only production database access

This workstation is configured for SSH access to the VDS. For ad-hoc database
inspection, prefer the restricted backup account: it can only execute the
server-side plain-format `pg_dump` command and cannot open an interactive shell.

- Host: `cash-flow-app.duckdns.org`
- Pinned SSH host-key alias: `5.45.117.224`
- User: `cashflow-backup`
- Key: `%USERPROFILE%\.ssh\cashflow-backup-pc1`
- Known hosts: `%USERPROFILE%\.ssh\known_hosts`
- Export helper: `scripts/pull-production-backup.ps1`

Export to a task-specific temporary path, not over a retained backup:

```powershell
.\scripts\pull-production-backup.ps1 `
  -Destination <temporary-path>\cashflow-production.sql
```

The helper connects through the public domain but validates the server against
the existing `5.45.117.224` entry in `known_hosts` via `HostKeyAlias`. If the VDS
or its SSH host key changes, verify the replacement out of band and update the
helper, this guide, and `known_hosts` together; never disable strict checking.

Restore or inspect that dump only in an isolated temporary PostgreSQL instance.
Do not point local application processes at it and do not copy it into
`backend/instance/cards.db`. `scripts/verify-backup-restore.sh` validates a dump
but deliberately deletes the supplied dump afterward, so pass a disposable
copy. Production data and dumps are sensitive: do not commit them or print
unrelated rows, authentication records, password hashes, session tokens, or
other secrets.

Other SSH keys have narrower roles and are not the default for data questions:

- `cashflow-production-github` belongs to the CI deployment path.
- `cashflow-vds-setup-ed25519` is for server bootstrap/maintenance.
- `cashflow-backup-pc1` is the least-privilege read-only export path.
- `cashflow-dev-agent-ed25519` (user `cashflow-agent`) runs only the whitelisted
  development operations of `deploy/cashflow-dev-agent`: `status`, `logs`,
  `alembic-current`, `import-bank-mcc-rules`. It cannot reach production or open a
  shell. Use it for development operations the user has asked for, for example:
  `ssh -i ~/.ssh/cashflow-dev-agent-ed25519 -o HostKeyAlias=5.45.117.224 cashflow-agent@cash-flow-app.duckdns.org status`.

## Legacy and generated local data

`backend/instance/cards.db` and `backend/*.db` are ignored local artifacts from
the original SQLite deployment, recovery work, tests, or migrations. They are
not replicas of production and may have old dates, old rows, and an old Alembic
revision. In particular, the workspace copy observed on 2026-09-30 was at
`0002_authentication`, while the repository migration head was
`0009_identity_icons` (since 2026-10-05 it is `0010_canonical_categories`).

The `sqlite:///cards.db` fallback in `backend/main.py` exists for explicitly
local development. Its presence never means that a nearby `cards.db` is the
selected database. Production sets `CASHFLOW_DATABASE_URL` to PostgreSQL in
`compose.prod.yaml`.

The counts and SQLite commands in the initial-transfer section of
`DEPLOYMENT.md` describe the one-time 2026-08-28 migration. They are historical
verification facts, not the current production inventory.

## Documentation map

- `README.md`: product summary and public environment URLs.
- `DEPLOYMENT.md`: production/development topology and release operations.
- `BACKUPS.md`: production backup and restore-verification procedures.
- `backend/MIGRATIONS.md`: schema migrations and the legacy SQLite importer.
- `docs/project-status.md`: currently released version, implemented scope, and backlog.
- `app/AGENTS.md`: Flutter-specific implementation guidance.

When environment topology, migration head, or access procedures change, update
this file and the relevant operational document in the same change.
