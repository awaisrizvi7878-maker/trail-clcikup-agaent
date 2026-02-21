# Email to ClickUp – AI Action Item Agent

An n8n workflow that reads incoming emails, uses an AI agent to extract action items, and automatically creates tasks in ClickUp under the **Interior Design Projects** space.

## Workflow Overview

```
New Email (IMAP) → AI Agent (extract action items) → Parse → ClickUp Task
```

### Nodes

| Node | Purpose |
|------|---------|
| **New Email Trigger** | Polls IMAP inbox for new emails |
| **AI Agent** | Uses OpenAI (GPT-4o-mini) to analyze email content and extract action items |
| **Parse Action Items** | Parses the AI response into structured task data |
| **Has Action Items?** | Routes based on whether actions were found |
| **Split Into Individual Tasks** | Splits multiple action items into individual items |
| **Create ClickUp Task** | Creates a task in ClickUp with title, description, and priority |

## Setup

### Prerequisites

- A running n8n instance with API access enabled
- n8n API key (Settings → API → Create API Key)
- IMAP email account credentials
- OpenAI API key
- ClickUp API token

### 1. Set Environment Variables

```bash
export N8N_API_URL="https://your-n8n-instance.example.com"
export N8N_API_KEY="your-n8n-api-key"
```

### 2. Create the Workflow

**Using the shell script:**
```bash
bash create_workflow.sh
```

**Using Python (no dependencies required):**
```bash
python3 create_workflow.py
```

### 3. Configure Credentials in n8n

After the workflow is created, open it in the n8n UI and configure:

1. **IMAP Email** – click the "New Email Trigger" node and add your email credentials
2. **OpenAI** – click the "OpenAI Chat Model" node and add your API key
3. **ClickUp** – click the "Create ClickUp Task" node, add your API token, and set the List ID for your Interior Design Projects space

#### Finding your ClickUp List ID

1. Open ClickUp → navigate to your **Interior Design Projects** space
2. Open the List where tasks should be created
3. Click `...` → **Copy Link**
4. The number at the end of the URL is the List ID

### 4. Activate

Once credentials are configured, activate the workflow in n8n. It will begin monitoring your inbox for new emails and creating ClickUp tasks for any action items found.
