#!/usr/bin/env bash
# One-command deploy: creates the workflow in your n8n instance
# Run this from a machine that can reach your n8n server.

set -euo pipefail

N8N_URL="http://168.231.110.40:32768"
N8N_API_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJlNWQ0NmZhMi1lNzlhLTQ2YmItYjZmMC04Yjc4MTczNzFiYjIiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwianRpIjoiNjM1ODhhNzctNTg5YS00YjkwLWFkZDQtZDM5NWZiZDY5M2U3IiwiaWF0IjoxNzcxODE2MTE1LCJleHAiOjE3NzQzMjQ4MDB9.pCZr66Xgci4eaRmk3WmqjupHgONMY_lGjdtxFYzrsj8"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKFLOW_FILE="${SCRIPT_DIR}/workflow_import.json"

echo "Deploying workflow to n8n at ${N8N_URL}..."

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "${N8N_URL}/api/v1/workflows" \
  -H "Content-Type: application/json" \
  -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
  -d @"${WORKFLOW_FILE}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  WORKFLOW_ID=$(echo "$BODY" | grep -oP '"id"\s*:\s*"?\K[^",]+' | head -1)
  echo "Workflow created! ID: ${WORKFLOW_ID}"
  echo "Open it: ${N8N_URL}/workflow/${WORKFLOW_ID}"
  echo ""
  echo "Next steps — configure credentials in each node:"
  echo "  1. New Email Trigger  → IMAP credentials"
  echo "  2. OpenAI Chat Model  → OpenAI API key"
  echo "  3. Create ClickUp Task → ClickUp API token + List ID"
else
  echo "ERROR (HTTP ${HTTP_CODE}): ${BODY}"
  exit 1
fi
