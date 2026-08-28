#!/bin/sh
set -eu

if [ -n "${SSH_ORIGINAL_COMMAND:-}" ]; then
  echo 'This key may only export the CashFlow PostgreSQL backup.' >&2
  exit 64
fi

exec /usr/bin/sudo -n /usr/local/sbin/cashflow-backup-export-root
