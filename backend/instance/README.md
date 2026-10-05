# Local instance data is not production

Files in this directory are generated or legacy local artifacts and are ignored
by Git. In particular, `cards.db` was the source for the one-time SQLite to
PostgreSQL migration; it is not synchronized from the deployed application.

Do not use these files to answer questions about current users, cards, cashback
categories, confirmations, offers, subscriptions, or the current month. The
production source of truth is the PostgreSQL database behind
`https://cash-flow-app.duckdns.org:8443`. Follow the read-only access procedure
in the repository-root `AGENTS.md`.

