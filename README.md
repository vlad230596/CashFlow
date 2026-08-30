# CashFlow

CashFlow is an open-source Flutter application designed for personal finance management. It includes features like expense tracking, cashback optimization, MCC code matching, and payment reminders.

Production releases publish a signed Android APK to GitHub Releases and deploy the Flask API
and Flutter web application to `https://cash-flow-app.duckdns.org:8443`.
Every successful `main` build is deployed without a Git tag to the isolated development stack at
`https://cash-flow-app.duckdns.org:8444`. Production tags are created only by the manually
approved release workflow.

## Repository layout

- `app/` — Flutter client and browser extension.
- `backend/` — HTTP API and persistent data.
