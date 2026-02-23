#!/usr/bin/env python3
"""
Creates an n8n workflow via the n8n REST API.

Workflow: Email → AI Agent (extract action items) → Asana Task Creation
Target Asana project: Interior Design Projects

Usage:
    export N8N_API_URL="https://your-n8n.example.com"
    export N8N_API_KEY="your-api-key"
    python3 create_workflow.py

After creating the workflow, open it in n8n to configure:
  1. IMAP email credentials
  2. OpenAI API credentials (for the AI agent)
  3. Asana API credentials, Workspace ID, and Project ID
"""

import json
import os
import sys
import urllib.request
import urllib.error


def get_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        print(f"ERROR: Environment variable {name} is not set.")
        print(f"  export {name}='your-value'")
        sys.exit(1)
    return value


WORKFLOW_DEFINITION = {
    "name": "Email to Asana – Interior Design Action Items",
    "nodes": [
        {
            "parameters": {
                "mailbox": "INBOX",
                "options": {"allowUnauthorizedCerts": False},
            },
            "id": "email-trigger",
            "name": "New Email Trigger",
            "type": "n8n-nodes-base.emailReadImap",
            "typeVersion": 2,
            "position": [240, 300],
        },
        {
            "parameters": {"options": {}},
            "id": "ai-agent",
            "name": "AI Agent – Extract Action Items",
            "type": "@n8n/n8n-nodes-langchain.agent",
            "typeVersion": 1.7,
            "position": [500, 300],
        },
        {
            "parameters": {"model": "gpt-4o-mini", "options": {}},
            "id": "openai-model",
            "name": "OpenAI Chat Model",
            "type": "@n8n/n8n-nodes-langchain.lmChatOpenAi",
            "typeVersion": 1,
            "position": [500, 520],
        },
        {
            "parameters": {
                "promptType": "define",
                "text": (
                    "Analyze the following email and extract any action items, "
                    "tasks, or to-dos.\n\n"
                    "From: {{ $json.from }}\n"
                    "Subject: {{ $json.subject }}\n"
                    "Date: {{ $json.date }}\n\n"
                    "Body:\n{{ $json.textPlain || $json.text || $json.html }}\n\n"
                    "---\n\n"
                    "Instructions:\n"
                    "1. Carefully read the email above.\n"
                    "2. Identify every action item, task, request, or to-do mentioned.\n"
                    "3. If there are NO action items, respond with EXACTLY: NO_ACTION_ITEMS\n"
                    "4. If there ARE action items, respond with a JSON array where each "
                    "object has:\n"
                    '   - "title": a short, clear task title (max 100 chars)\n'
                    '   - "description": detailed description with context from the email\n'
                    '   - "priority": 1 (urgent), 2 (high), 3 (normal), or 4 (low)\n\n'
                    "Example output when action items exist:\n"
                    '[{"title": "Send fabric samples to client", '
                    '"description": "Client requested fabric samples for the living room '
                    'redesign. Email from john@example.com on 2024-01-15.", "priority": 3}]\n\n'
                    "Respond ONLY with the JSON array or NO_ACTION_ITEMS. No other text."
                ),
            },
            "id": "ai-prompt",
            "name": "Action Item Extraction Prompt",
            "type": "@n8n/n8n-nodes-langchain.outputParserStructured",
            "typeVersion": 1.2,
            "position": [700, 520],
        },
        {
            "parameters": {
                "jsCode": (
                    "// Parse the AI agent output\n"
                    "const agentOutput = $input.first().json.output || "
                    "$input.first().json.text || '';\n\n"
                    "// Check if no action items were found\n"
                    "if (agentOutput.trim() === 'NO_ACTION_ITEMS' || "
                    "agentOutput.trim() === '') {\n"
                    "  return [{ json: { hasActions: false, actions: [] } }];\n"
                    "}\n\n"
                    "// Try to parse the JSON array of action items\n"
                    "try {\n"
                    "  let jsonStr = agentOutput.trim();\n"
                    "  const jsonMatch = jsonStr.match(/\\[[\\\\s\\\\S]*\\]/);\n"
                    "  if (jsonMatch) { jsonStr = jsonMatch[0]; }\n"
                    "  const actions = JSON.parse(jsonStr);\n"
                    "  if (!Array.isArray(actions) || actions.length === 0) {\n"
                    "    return [{ json: { hasActions: false, actions: [] } }];\n"
                    "  }\n"
                    "  return [{ json: { hasActions: true, actions: actions } }];\n"
                    "} catch (e) {\n"
                    "  return [{ json: { hasActions: true, actions: [{ "
                    "title: 'Review email action item', "
                    "description: agentOutput, priority: 3 }] } }];\n"
                    "}\n"
                )
            },
            "id": "parse-actions",
            "name": "Parse Action Items",
            "type": "n8n-nodes-base.code",
            "typeVersion": 2,
            "position": [760, 300],
        },
        {
            "parameters": {
                "conditions": {
                    "options": {
                        "caseSensitive": True,
                        "leftValue": "",
                        "typeValidation": "strict",
                    },
                    "conditions": [
                        {
                            "id": "condition-has-actions",
                            "leftValue": "={{ $json.hasActions }}",
                            "rightValue": True,
                            "operator": {
                                "type": "boolean",
                                "operation": "equals",
                            },
                        }
                    ],
                    "combinator": "and",
                },
                "options": {},
            },
            "id": "if-has-actions",
            "name": "Has Action Items?",
            "type": "n8n-nodes-base.if",
            "typeVersion": 2.2,
            "position": [1000, 300],
        },
        {
            "parameters": {"fieldToSplitOut": "actions", "options": {}},
            "id": "split-actions",
            "name": "Split Into Individual Tasks",
            "type": "n8n-nodes-base.splitOut",
            "typeVersion": 1,
            "position": [1240, 200],
        },
        {
            "parameters": {
                "resource": "task",
                "operation": "create",
                "workspace": "={{ $json.asana_workspace_id || '' }}",
                "project": "={{ $json.asana_project_id || '' }}",
                "name": "={{ $json.title }}",
                "otherProperties": {
                    "notes": (
                        "={{ $json.description }}\n\n---\n"
                        "Auto-created from email by n8n AI Agent"
                    ),
                },
            },
            "id": "asana-create-task",
            "name": "Create Asana Task",
            "type": "n8n-nodes-base.asana",
            "typeVersion": 1,
            "position": [1480, 200],
        },
        {
            "parameters": {},
            "id": "no-action",
            "name": "No Action Needed",
            "type": "n8n-nodes-base.noOp",
            "typeVersion": 1,
            "position": [1240, 420],
        },
    ],
    "connections": {
        "New Email Trigger": {
            "main": [
                [
                    {
                        "node": "AI Agent – Extract Action Items",
                        "type": "main",
                        "index": 0,
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
                        "index": 0,
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
                        "index": 0,
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
                        "index": 0,
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
                        "index": 0,
                    }
                ],
                [
                    {
                        "node": "No Action Needed",
                        "type": "main",
                        "index": 0,
                    }
                ],
            ]
        },
        "Split Into Individual Tasks": {
            "main": [
                [
                    {
                        "node": "Create Asana Task",
                        "type": "main",
                        "index": 0,
                    }
                ]
            ]
        },
    },
    "settings": {"executionOrder": "v1"},
    "staticData": None,
    "tags": [],
}


def api_request(url: str, method: str, data: dict | None = None,
                api_key: str = "") -> tuple[int, dict]:
    """Make an HTTP request to the n8n API."""
    headers = {
        "Content-Type": "application/json",
        "X-N8N-API-KEY": api_key,
    }
    body = json.dumps(data).encode("utf-8") if data else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)

    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body_text = e.read().decode("utf-8", errors="replace")
        try:
            return e.code, json.loads(body_text)
        except json.JSONDecodeError:
            return e.code, {"error": body_text}
    except urllib.error.URLError as e:
        print(f"ERROR: Cannot connect to n8n at {url}")
        print(f"  Reason: {e.reason}")
        sys.exit(1)


def main() -> None:
    n8n_url = get_env("N8N_API_URL").rstrip("/")
    api_key = get_env("N8N_API_KEY")

    print("=" * 50)
    print(" Creating n8n Workflow via API")
    print("=" * 50)
    print(f"\nTarget: {n8n_url}\n")

    # --- Create the workflow ---
    status, body = api_request(
        f"{n8n_url}/api/v1/workflows", "POST", WORKFLOW_DEFINITION, api_key
    )

    if status < 200 or status >= 300:
        print(f"ERROR: Failed to create workflow (HTTP {status})")
        print(json.dumps(body, indent=2))
        sys.exit(1)

    workflow_id = body.get("id", "unknown")
    print(f"Workflow created successfully!")
    print(f"Workflow ID: {workflow_id}\n")

    # --- Activate the workflow ---
    print("Activating workflow...")
    act_status, _ = api_request(
        f"{n8n_url}/api/v1/workflows/{workflow_id}",
        "PATCH",
        {"active": True},
        api_key,
    )

    if 200 <= act_status < 300:
        print("Workflow activated successfully!\n")
    else:
        print("Warning: Could not activate (configure credentials first).\n")

    # --- Print next steps ---
    print("=" * 50)
    print(" NEXT STEPS")
    print("=" * 50)
    print("""
Open the workflow in n8n and configure:

1. IMAP Email credentials:
   - Click 'New Email Trigger' node
   - Add your IMAP credentials (host, port, user, password)

2. OpenAI API credentials:
   - Click 'OpenAI Chat Model' node
   - Add your OpenAI API key

3. Asana credentials & Project:
   - Click 'Create Asana Task' node
   - Add your Asana Personal Access Token
   - Set the Workspace and Project for 'Interior Design Projects'
   - To find IDs: Asana > Project > copy the project URL
     The number in the URL is the Project ID
""")
    print(f"Workflow URL: {n8n_url}/workflow/{workflow_id}")


if __name__ == "__main__":
    main()
