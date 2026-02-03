#!/usr/bin/env bash
set -euo pipefail

if [ -z "${FLY_APP_NAME:-}" ]; then
  echo "Set FLY_APP_NAME environment variable before running this script. Example: export FLY_APP_NAME=my-n8n-app"
  exit 1
fi

REGION="${REGION:-ord}"

echo "Creating Fly app '$FLY_APP_NAME' in region '$REGION' (if it already exists the command will fail harmlessly)"
flyctl apps create "$FLY_APP_NAME" --region "$REGION" || true

echo "Creating managed Postgres for $FLY_APP_NAME (follow interactive prompts)"
flyctl postgres create --name "${FLY_APP_NAME}-db" --region "$REGION" || true

echo "Creating writable volume for n8n files"
flyctl volumes create n8n-data --region "$REGION" --size 3 || true

echo "\nNext steps (manually):"
echo " 1) Get the DB connection string from Fly dashboard or run: flyctl postgres list"
echo " 2) Set secrets:"
echo "    flyctl secrets set POSTGRES_DATABASE_URL='<your-db-url>' --app $FLY_APP_NAME"
echo "    flyctl secrets set N8N_BASIC_AUTH_USER='admin' N8N_BASIC_AUTH_PASSWORD='<secret>' --app $FLY_APP_NAME"
echo "    (Optional) flyctl secrets set N8N_PUBLIC_API_BASE_URL='https://<your-domain>' N8N_EDITOR_BASE_URL='https://<your-domain>' --app $FLY_APP_NAME"
echo " 3) Deploy: flyctl deploy --app $FLY_APP_NAME --config fly.toml"

echo "Done. Review the README.md for details."
