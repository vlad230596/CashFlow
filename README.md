# CashFlow

CashFlow is an open-source family cashback assistant. It combines cashback
categories and partner offers across cards and banks so family members with
shared card access can compare available benefits, coordinate monthly category
selections, maintain MCC rules, and track upcoming subscription renewals.

CashFlow does not provide general spending accounting. Subscription reminders
are a deliberately narrow recurring-payment feature; a broader financial-control
application may later integrate with CashFlow through an explicit API contract.

Production releases publish a signed Android APK to GitHub Releases and deploy the Flask API
and Flutter web application to `https://cash-flow-app.duckdns.org:8443`.
Every successful `main` build is deployed without a Git tag to the isolated development stack at
`https://cash-flow-app.duckdns.org:8444`. Production tags are created only by the manually
approved release workflow.

Current user and business data lives in the production PostgreSQL database on
the VDS; local `backend/instance/*.db` files are legacy or development artifacts
and are not production replicas. Agents and maintainers should start with
[`AGENTS.md`](AGENTS.md) for environment selection and read-only data access.

## Repository layout

- `app/` — Flutter client and browser extension.
- `backend/` — HTTP API and persistent data.
- `AGENTS.md` — environment selection, production data access, and stale-data guardrails.
- `docs/project-status.md` — current release, implemented features, gaps, and backlog.
- `docs/product-design-brief.md` — product scope and redesign foundation.
- `docs/product-design-status.md` — approved UX decisions, remaining work, and open questions.
