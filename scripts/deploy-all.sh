#!/usr/bin/env bash
set -euo pipefail

# deploy-all.sh
# Automates: commit -> push -> create PR -> (optionally) set GitHub secrets -> (optionally) create Fly resources -> deploy
# Run this locally where you have 'git', 'gh' and 'flyctl' configured/logged-in.

PROGNAME=$(basename "$0")

echoerr() { printf "%s\n" "$*" >&2; }

usage() {
  cat <<EOF
Usage: $PROGNAME --app <fly-app-name> [--region <region>] [--create-fly-resources]

This script will:
  - Create a branch and commit local changes
  - Push branch and open a PR to main (using 'gh')
  - Optionally set GitHub repo secrets (using 'gh')
  - Optionally create Fly resources (app, volume, postgres) and deploy (using 'flyctl')

Requirements: git, gh (GitHub CLI), flyctl. You should be logged in to both GH and Fly locally.

Examples:
  FLY_REGION=ord $PROGNAME --app my-n8n-app --create-fly-resources

EOF
}

APP=""
REGION="ord"
CREATE_FLY_RESOURCES="false"

while [[ $# -gt 0 ]]; do
  case $1 in
    --app) APP="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --create-fly-resources) CREATE_FLY_RESOURCES="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echoerr "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

if [ -z "$APP" ]; then
  echoerr "Error: --app is required."; usage; exit 1
fi

# checks
for cmd in git gh flyctl; do
  if ! command -v $cmd >/dev/null 2>&1; then
    echoerr "Error: $cmd is required but not installed or not on PATH."; exit 1
  fi
done

# ensure clean working tree
if [ -n "$(git status --porcelain)" ]; then
  echo "Committing local changes..."
  git add -A
  git commit -m "chore: add Fly deployment files and optional resource creation step" || true
fi

BRANCH=feature/fly-n8-$(date +%s)
git checkout -b "$BRANCH"

git push -u origin "$BRANCH"

# open PR
PR_URL=""
if gh pr create --title "chore: add Fly deployment files for n8n" --body "Adds Dockerfile, fly.toml, GitHub Actions deploy with optional Fly resource creation, and helper scripts." --base main --head "$BRANCH" --web; then
  echo "Opened PR (browser) — please complete any required fields in the web UI if necessary.";
else
  echo "Attempting non-web PR creation..."
  PR_URL=$(gh pr create --title "chore: add Fly deployment files for n8n" --body "Adds Dockerfile, fly.toml, GitHub Actions deploy with optional Fly resource creation, and helper scripts." --base main --head "$BRANCH" --json url -q .url) || true
  [ -n "$PR_URL" ] && echo "PR created: $PR_URL"
fi

# Ask to set GitHub secrets
read -p "Do you want to set GitHub repo secrets (FLY_API_TOKEN, FLY_APP_NAME, etc.) now? [y/N]: " set_secrets
if [[ "$set_secrets" =~ ^[Yy]$ ]]; then
  echo "Setting secrets (press enter to skip a secret)..."

  read -s -p "FLY_API_TOKEN (will be saved as SECRET FLY_API_TOKEN): " FLY_API_TOKEN_VAL; echo
  if [ -n "$FLY_API_TOKEN_VAL" ]; then
    gh secret set FLY_API_TOKEN --body "$FLY_API_TOKEN_VAL"
  fi

  read -p "FLY_APP_NAME (repo secret FLY_APP_NAME) [${APP}]: " tmp
  if [ -n "$tmp" ]; then
    gh secret set FLY_APP_NAME --body "$tmp"
  else
    gh secret set FLY_APP_NAME --body "$APP"
  fi

  read -p "CREATE_FLY_RESOURCES (true/false) [${CREATE_FLY_RESOURCES}]: " tmp
  if [ -n "$tmp" ]; then
    gh secret set CREATE_FLY_RESOURCES --body "$tmp"
  else
    gh secret set CREATE_FLY_RESOURCES --body "$CREATE_FLY_RESOURCES"
  fi

  read -p "FLY_REGION [${REGION}]: " tmp
  if [ -n "$tmp" ]; then
    gh secret set FLY_REGION --body "$tmp"
  else
    gh secret set FLY_REGION --body "$REGION"
  fi

  read -p "POSTGRES_DATABASE_URL (optional): " tmp
  if [ -n "$tmp" ]; then gh secret set POSTGRES_DATABASE_URL --body "$tmp"; fi
  read -p "N8N_BASIC_AUTH_USER (optional): " tmp
  if [ -n "$tmp" ]; then gh secret set N8N_BASIC_AUTH_USER --body "$tmp"; fi
  read -s -p "N8N_BASIC_AUTH_PASSWORD (optional): " tmp; echo
  if [ -n "$tmp" ]; then gh secret set N8N_BASIC_AUTH_PASSWORD --body "$tmp"; fi
  read -p "N8N_PUBLIC_API_BASE_URL (optional): " tmp
  if [ -n "$tmp" ]; then gh secret set N8N_PUBLIC_API_BASE_URL --body "$tmp"; fi
  read -p "N8N_EDITOR_BASE_URL (optional): " tmp
  if [ -n "$tmp" ]; then gh secret set N8N_EDITOR_BASE_URL --body "$tmp"; fi
fi

# Optionally create Fly resources now
if [[ "$CREATE_FLY_RESOURCES" == "true" || "$CREATE_FLY_RESOURCES" == "True" ]]; then
  echo "Creating Fly resources for app: $APP in region: $REGION"
  # Ensure fly is logged in
  if ! flyctl status >/dev/null 2>&1; then
    echo "You're not logged in to Flyctl. Please run: flyctl auth login"; exit 1
  fi

  flyctl apps create "$APP" --region "$REGION" || echo "app may already exist"
  flyctl volumes create n8n-data --region "$REGION" --size 3 || echo "volume exists or creation failed"
  flyctl postgres create --name "${APP}-db" --region "$REGION" || echo "postgres creation failed or already exists"
  echo "Note: If Postgres was created, please set POSTGRES_DATABASE_URL secret to the returned connection string or from Fly dashboard."

  # Prompt to set DB secret
  read -p "Do you have a Postgres connection URL to set now as POSTGRES_DATABASE_URL? [y/N]: " set_db
  if [[ "$set_db" =~ ^[Yy]$ ]]; then
    read -p "POSTGRES_DATABASE_URL: " dburl
    if [ -n "$dburl" ]; then
      flyctl secrets set POSTGRES_DATABASE_URL="$dburl" --app "$APP"
    fi
  fi

  # Set n8n basic auth as fly secrets
  read -p "Set N8N_BASIC_AUTH_USER and PASSWORD now? [y/N]: " set_auth
  if [[ "$set_auth" =~ ^[Yy]$ ]]; then
    read -p "N8N_BASIC_AUTH_USER: " auth_user
    read -s -p "N8N_BASIC_AUTH_PASSWORD: " auth_pass; echo
    flyctl secrets set N8N_BASIC_AUTH_USER="$auth_user" N8N_BASIC_AUTH_PASSWORD="$auth_pass" --app "$APP"
    flyctl secrets set N8N_BASIC_AUTH_ACTIVE=true --app "$APP"
  fi

  # Deploy
  flyctl deploy --app "$APP" --config fly.toml
  echo "Deployed. Use 'flyctl status --app $APP' and 'flyctl volumes list --region $REGION' to verify resources."
else
  echo "Skipping Fly resource creation. You can create resources later or enable CREATE_FLY_RESOURCES secret."
fi

cat <<EOF

Done. Next recommended steps:
 - Review and merge the PR that was created.
 - If you didn't set secrets via the script, add them in repo Settings -> Secrets.
 - After secrets and resources are in place, trigger a deploy (push to main or run the action).

EOF
