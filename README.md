# CashFlow

CashFlow is an open-source family cashback assistant. It combines cashback
categories and partner offers across cards and banks so family members with
shared card access can choose the most rewarding card, coordinate monthly
category selections, and maintain MCC rules.

CashFlow does not track spending or manage payment reminders. Those concerns
belong to a separate companion application and may later integrate with
CashFlow through an explicit API contract.

Production releases publish a signed Android APK to GitHub Releases and deploy the Flask API
and Flutter web application to `https://cash-flow-app.duckdns.org:8443`.
Every successful `main` build is deployed without a Git tag to the isolated development stack at
`https://cash-flow-app.duckdns.org:8444`. Production tags are created only by the manually
approved release workflow.

## Repository layout

- `app/` — Flutter client and browser extension.
- `backend/` — HTTP API and persistent data.
- `docs/product-design-brief.md` — product scope and redesign foundation.
- `docs/product-design-status.md` — approved UX decisions, remaining work, and open questions.
