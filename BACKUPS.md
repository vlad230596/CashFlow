# CashFlow production backups

Backups use the same pull model as OfficeCooking but remain fully separate.

- VDS user: `cashflow-backup`;
- forced command: `/usr/local/bin/cashflow-backup-export`;
- root exporter: `/usr/local/sbin/cashflow-backup-export-root`;
- local staging: `D:\Backups\CashFlow\staging`;
- local restic repository: `D:\Backups\CashFlow\repository`;
- dedicated SSH key: `%USERPROFILE%\.ssh\cashflow-backup-pc1`;
- Backrest repository `cashflow-local` and plan `cashflow-daily`;
- daily schedule: `03:30` local time with missed runs queued after the next Backrest start.

The backup account has no Docker group membership or interactive command access. `pg_dump`
streams over SSH stdout and is not stored permanently on the VDS. An SSH or incomplete-dump
failure makes the backup fail instead of producing an empty snapshot.

Recommended retention, confirmed for this project:

- 14 daily;
- 8 weekly;
- 12 monthly;
- 3 yearly;
- always keep at least the latest 2 snapshots;
- full restic check and prune every 30 days.

The existing local-only Backrest process hosts the CashFlow plan, while its repository, key,
staging path, tag, and plan remain separate from OfficeCooking. The pre-snapshot command is
`scripts/pull-production-backup.ps1`. Backrest runs as `SYSTEM`, so the restricted key copy is
installed and verified with `scripts/configure-cashflow-backup-system-key.ps1`; its last
verification result is stored in
`%LOCALAPPDATA%\CashFlowBackup\system-backup-verification.json`.

At least once after setup and periodically thereafter, restore a copy of a plain SQL dump into
an isolated PostgreSQL 17.6 container with `scripts/verify-backup-restore.sh`. The script expects
eight public tables and Alembic revision `0002_authentication`; it deletes the supplied temporary
dump after verification, so never pass the only retained backup copy.
