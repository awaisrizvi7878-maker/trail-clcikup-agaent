#!/usr/bin/env bash
#
# Creates an n8n workflow via the n8n REST API.
# The workflow:
#   1. Triggers on new emails (IMAP)
#   2. Uses an AI Agent to extract action items
#   3. Creates ClickUp tasks in the "Interior Design Projects" space
#
# Required environment variables (set them before running):
#   N8N_API_URL      – Base URL of your n8n instance  (e.g. https://your-n8n.example.com)
#   N8N_API_KEY      – n8n API key
#
# After importing the workflow you still need to configure credentials
# inside n8n for:
#   - IMAP (email)
#   - OpenAI (for the AI agent)
#   - ClickUp API
#
# Usage:
#   export N8N_API_URL="https://your-n8n.example.com"
#   export N8N_API_KEY="your-api-key"
#   bash create_workflow.sh
# ---------------------------------------------------------------------------

set -euo pipefail

: "${N8N_API_URL:?Set N8N_API_URL to your n8n instance URL}"
: "${N8N_API_KEY:?Set N8N_API_KEY to your n8n API key}"

# Strip trailing slash from URL
N8N_API_URL="${N8N_API_URL%/}"

WORKFLOW_PAYLOAD=$(cat <<'ENDJSON'
{
  "name": "Email to ClickUp – Interior Design Action Items",
  "nodes": [
    {
      "parameters": {
        "mailbox": "INBOX",
        "options": {
          "allowUnauthorizedCerts": false
        }
      },
      "id": "email-trigger",
      "name": "New Email Trigger",
      "type": "n8n-nodes-base.emailReadImap",
      "typeVersion": 2,
      "position": [240, 300]
    },
    {
      "parameters": {
        "options": {}
      },
      "id": "ai-agent",
      "name": "AI Agent – Extract Action Items",
      "type": "@n8n/n8n-nodes-langchain.agent",
      "typeVersion": 1.7,
      "position": [500, 300]
    },
    {
      "parameters": {
        "model": "gpt-4o-mini",
        "options": {}
      },
      "id": "openai-model",
      "name": "OpenAI Chat Model",
      "type": "@n8n/n8n-nodes-langchain.lmChatOpenAi",
      "typeVersion": 1,
      "position": [500, 520]
    },
    {
      "parameters": {
        "promptType": "define",
        "text": "=Analyze the following email and extract any action items, tasks, or to-dos.\n\nFrom: {{ $json.from }}\nSubject: {{ $json.subject }}\nDate: {{ $json.date }}\n\nBody:\n{{ $json.textPlain || $json.text || $json.html }}\n\n---\n\nInstructions:\n1. Carefully read the email above.\n2. Identify every action item, task, request, or to-do mentioned.\n3. If there are NO action items, respond with EXACTLY: NO_ACTION_ITEMS\n4. If there ARE action items, respond with a JSON array where each object has:\n   - \"title\": a short, clear task title (max 100 chars)\n   - \"description\": a detailed description including relevant context from the email\n   - \"priority\": 1 (urgent), 2 (high), 3 (normal), or 4 (low)\n\nExample output when action items exist:\n[{\"title\": \"Send fabric samples to client\", \"description\": \"Client requested fabric samples for the living room redesign. Email from john@example.com on 2024-01-15.\", \"priority\": 3}]\n\nRespond ONLY with the JSON array or NO_ACTION_ITEMS. No other text."
      },
      "id": "ai-prompt",
      "name": "Action Item Extraction Prompt",
      "type": "@n8n/n8n-nodes-langchain.outputParserStructured",
      "typeVersion": 1.2,
      "position": [700, 520]
    },
    {
      "parameters": {
        "jsCode": "// Parse the AI agent output\nconst agentOutput = $input.first().json.output || $input.first().json.text || '';\n\n// Check if no action items were found\nif (agentOutput.trim() === 'NO_ACTION_ITEMS' || agentOutput.trim() === '') {\n  return [{ json: { hasActions: false, actions: [] } }];\n}\n\n// Try to parse the JSON array of action items\ntry {\n  // Extract JSON from the response (handle markdown code blocks)\n  let jsonStr = agentOutput.trim();\n  const jsonMatch = jsonStr.match(/\\[[\\s\\S]*\\]/);\n  if (jsonMatch) {\n    jsonStr = jsonMatch[0];\n  }\n  \n  const actions = JSON.parse(jsonStr);\n  \n  if (!Array.isArray(actions) || actions.length === 0) {\n    return [{ json: { hasActions: false, actions: [] } }];\n  }\n  \n  return [{ json: { hasActions: true, actions: actions } }];\n} catch (e) {\n  // If parsing fails, treat the whole output as a single action item\n  return [{ json: { hasActions: true, actions: [{ title: 'Review email action item', description: agentOutput, priority: 3 }] } }];\n}\n"
      },
      "id": "parse-actions",
      "name": "Parse Action Items",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [760, 300]
    },
    {
      "parameters": {
        "conditions": {
          "options": {
            "caseSensitive": true,
            "leftValue": "",
            "typeValidation": "strict"
          },
          "conditions": [
            {
              "id": "condition-has-actions",
              "leftValue": "={{ $json.hasActions }}",
              "rightValue": true,
              "operator": {
                "type": "boolean",
                "operation": "equals"
              }
            }
          ],
          "combinator": "and"
        },
        "options": {}
      },
      "id": "if-has-actions",
      "name": "Has Action Items?",
      "type": "n8n-nodes-base.if",
      "typeVersion": 2.2,
      "position": [1000, 300]
    },
    {
      "parameters": {
        "fieldToSplitOut": "actions",
        "options": {}
      },
      "id": "split-actions",
      "name": "Split Into Individual Tasks",
      "type": "n8n-nodes-base.splitOut",
      "typeVersion": 1,
      "position": [1240, 200]
    },
    {
      "parameters": {
        "list": "={{ $json.clickup_list_id || '' }}",
        "taskName": "={{ $json.title }}",
        "additionalFields": {
          "content": "={{ $json.description }}\n\n---\nAuto-created from email by n8n AI Agent",
          "priority": "={{ $json.priority }}"
        }
      },
      "id": "clickup-create-task",
      "name": "Create ClickUp Task",
      "type": "n8n-nodes-base.clickUp",
      "typeVersion": 1,
      "position": [1480, 200],
      "notes": "Configure the List ID for Interior Design Projects in ClickUp"
    },
    {
      "parameters": {},
      "id": "no-action",
      "name": "No Action Needed",
      "type": "n8n-nodes-base.noOp",
      "typeVersion": 1,
      "position": [1240, 420]
    }
  ],
  "connections": {
    "New Email Trigger": {
      "main": [
        [
          {
            "node": "AI Agent – Extract Action Items",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "AI Agent – Extract Action Items": {
      "main": [
        [
          {
            "node": "Parse Action Items",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "OpenAI Chat Model": {
      "ai_languageModel": [
        [
          {
            "node": "AI Agent – Extract Action Items",
            "type": "ai_languageModel",
            "index": 0
          }
        ]
      ]
    },
    "Parse Action Items": {
      "main": [
        [
          {
            "node": "Has Action Items?",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Has Action Items?": {
      "main": [
        [
          {
            "node": "Split Into Individual Tasks",
            "type": "main",
            "index": 0
          }
        ],
        [
          {
            "node": "No Action Needed",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Split Into Individual Tasks": {
      "main": [
        [
          {
            "node": "Create ClickUp Task",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  },
  "settings": {
    "executionOrder": "v1"
  },
  "staticData": null,
  "tags": []
}
ENDJSON
)

echo "=============================================="
echo " Creating n8n Workflow via API"
echo "=============================================="
echo ""
echo "Target: ${N8N_API_URL}"
echo ""

# Create the workflow
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST "${N8N_API_URL}/api/v1/workflows" \
  -H "Content-Type: application/json" \
  -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
  -d "${WORKFLOW_PAYLOAD}")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  WORKFLOW_ID=$(echo "$BODY" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

  if [[ -z "$WORKFLOW_ID" ]]; then
    WORKFLOW_ID=$(echo "$BODY" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
  fi

  echo "Workflow created successfully!"
  echo "Workflow ID: ${WORKFLOW_ID}"
  echo ""

  # Activate the workflow
  echo "Activating workflow..."
  ACTIVATE_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X PATCH "${N8N_API_URL}/api/v1/workflows/${WORKFLOW_ID}" \
    -H "Content-Type: application/json" \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    -d '{"active": true}')

  ACTIVATE_CODE=$(echo "$ACTIVATE_RESPONSE" | tail -1)

  if [[ "$ACTIVATE_CODE" -ge 200 && "$ACTIVATE_CODE" -lt 300 ]]; then
    echo "Workflow activated successfully!"
  else
    echo "Warning: Could not activate workflow (credentials may need configuration first)."
    echo "You can activate it manually in the n8n UI after configuring credentials."
  fi

  echo ""
  echo "=============================================="
  echo " NEXT STEPS"
  echo "=============================================="
  echo ""
  echo "Open the workflow in n8n and configure:"
  echo ""
  echo "1. IMAP Email credentials:"
  echo "   - Click 'New Email Trigger' node"
  echo "   - Add your IMAP credentials (host, port, user, password)"
  echo ""
  echo "2. OpenAI API credentials:"
  echo "   - Click 'OpenAI Chat Model' node"
  echo "   - Add your OpenAI API key"
  echo ""
  echo "3. ClickUp credentials & List ID:"
  echo "   - Click 'Create ClickUp Task' node"
  echo "   - Add your ClickUp API token"
  echo "   - Set the List ID for your 'Interior Design Projects' space"
  echo "   - To find your List ID: ClickUp > Space > Folder > List > ... > Copy Link"
  echo "     The number at the end of the URL is the List ID"
  echo ""
  echo "Workflow URL: ${N8N_API_URL}/workflow/${WORKFLOW_ID}"
else
  echo "ERROR: Failed to create workflow (HTTP ${HTTP_CODE})"
  echo ""
  echo "Response:"
  echo "$BODY"
  exit 1
fi
