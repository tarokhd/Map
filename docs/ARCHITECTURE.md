# Iran Navigator Architecture

## Monorepo

The repository contains independent Android and Web clients plus a shared backend scaffold and API contract.

- `android/`: Kotlin + MapLibre Native Android app.
- `web/`: static MapLibre GL JS preview, deployed independently to GitHub Pages.
- `backend/`: FastAPI service and PostgreSQL/PostGIS local development stack.
- `shared/api-contracts/`: OpenAPI source of truth for cross-platform API behavior.
- `shared/models/`: cross-platform data conventions.

## Shared data flow

Android and Web must communicate with the Backend over HTTPS REST APIs. The Backend authenticates the caller, enforces per-user authorization, validates inputs, and reads/writes PostgreSQL/PostGIS. Client apps must never contain database credentials or connect directly to PostgreSQL.

The current backend only implements `/healthz` and `/readyz`. Saved-place and route-history endpoints are planned in the OpenAPI contract and database schema but are not implemented yet. Therefore cross-device synchronization is not active in this commit.

## Independent CI/CD

- Android workflow watches `android/**` and shared contracts.
- Web workflow watches `web/**` and shared contracts, then publishes only `web/` to GitHub Pages.
- Backend workflow validates Python source and the OpenAPI contract when `backend/**` or `shared/**` changes.

## Production work still required

1. Implement JWT/OIDC authentication and authorization.
2. Implement the saved-place and route-history CRUD endpoints.
3. Add Alembic migrations instead of relying only on first-run SQL initialization.
4. Deploy Backend and PostGIS to a secured server; terminate TLS at a reverse proxy.
5. Add rate limiting, backups, monitoring, privacy/retention policies, and secrets management.
6. Configure Android and Web API base URLs to the deployed backend.
7. Select reliable map tile, geocoding, and routing services with appropriate Iran coverage and terms.
