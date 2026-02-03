# n8n on Fly 🚀

This repository contains a minimal Docker setup and a GitHub Actions workflow to deploy n8n to Fly.

## Files added
- `Dockerfile` — builds the official n8n image
- `.dockerignore` — ignores local files not needed in the image
- `fly.toml` — Fly config (replace `app` with your Fly app name or use repo secret `FLY_APP_NAME`)
- `.github/workflows/deploy.yml` — Action to deploy on push to `main`

---

## Quick local deploy steps (recommended)
1. Install and login: `flyctl auth login`
2. Create the app: `flyctl apps create <app-name> --region <region>`
3. Create a Postgres DB (recommended):
   - `flyctl postgres create --name <db-name> --region <region>`
   - Follow the instructions to get the database connection URL
4. Create a persistent volume for n8n file storage:
   - `flyctl volumes create n8n-data --region <region> --size 3`
5. Set secrets (example):
   - `flyctl secrets set POSTGRES_DATABASE_URL='<your-db-url>' N8N_BASIC_AUTH_PASSWORD='<secret>' N8N_BASIC_AUTH_USER='admin' --app <app-name>`
   - Recommended envs: `POSTGRES_DATABASE_URL`, `N8N_BASIC_AUTH_USER`, `N8N_BASIC_AUTH_PASSWORD`, `N8N_PUBLIC_API_BASE_URL`, `N8N_EDITOR_BASE_URL`
6. Deploy: `flyctl deploy --app <app-name> --config fly.toml`

---

## GitHub Actions CI/CD
1. Create a Fly API token: `flyctl auth token create --name "github-action"`
2. Add these repository secrets in `Settings -> Secrets`:
   - `FLY_API_TOKEN` (required)
   - `FLY_APP_NAME` (required)
   - `POSTGRES_DATABASE_URL` (optional)
   - `N8N_BASIC_AUTH_USER` (optional)
   - `N8N_BASIC_AUTH_PASSWORD` (optional)
3. On push to `main` the `deploy` workflow will authenticate to Fly and run `flyctl deploy`.

---

## Notes & suggestions
- Use Fly's managed Postgres for ease and set `POSTGRES_DATABASE_URL` as the DB connection string (n8n expects `DATABASE_URL` style for many setups; using `POSTGRES_DATABASE_URL` here is consistent with the workflow; adjust as needed).
- Protect your instance with basic auth (`N8N_BASIC_AUTH_ACTIVE=true`, `N8N_BASIC_AUTH_USER`, `N8N_BASIC_AUTH_PASSWORD`).
- Set `N8N_PUBLIC_API_BASE_URL` and `N8N_EDITOR_BASE_URL` to your Fly app domain (or custom domain) for correct links and webhook URL generation.

### Persistence & verification ✅
- The `fly.toml` mounts a Fly volume named `n8n-data` at `/home/node/.n8n`. This stores workflows, credentials, uploaded files, and other runtime state and **persists across restarts and deployments** until you manually delete the volume.
- To list volumes and verify the volume exists: `flyctl volumes list --region <region>`
- To verify persistence: create workflows and credentials in n8n, then run `flyctl apps restart <app-name>` and confirm the workflows and credentials are still present in the UI.
- To delete the volume (irreversible): `flyctl volumes destroy n8n-data --region <region>`
- Back up your Postgres DB regularly (e.g., via `pg_dump`) — managed Postgres also supports automated backups depending on your plan.

If you want, I can also: 1) open a PR with these files, 2) help you create the Fly Postgres DB and volumes using `flyctl` (you'll need to run `flyctl auth login` locally), or 3) update settings for a custom domain (DNS steps).
