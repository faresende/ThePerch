{
  "meta": {
    "lastTouchedVersion": "2026.2.26",
    "lastTouchedAt": "2026-03-01T04:00:21.114Z"
  },
  "wizard": {
    "lastRunAt": "2026-02-28T10:17:25.888Z",
    "lastRunVersion": "2026.2.26",
    "lastRunCommand": "doctor",
    "lastRunMode": "local"
  },
  "auth": {
    "profiles": {
      "anthropic:default": {
        "provider": "anthropic",
        "mode": "api_key"
      },
      "anthropic:anthropic-claudinho": {
        "provider": "anthropic",
        "mode": "token"
      },
      "anthropic:biochecha": {
        "provider": "anthropic",
        "mode": "token"
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-opus-4-6",
        "fallbacks": [
          "anthropic/claude-sonnet-4-6",
          "google/gemini-1.5-pro",
          "openai/gpt-4o"
        ]
      },
      "workspace": "/Users/faresende/.openclaw/workspace",
      "compaction": {
        "mode": "safeguard"
      },
      "typingMode": "message",
      "heartbeat": {
        "prompt": "Read HEARTBEAT.md if it exists (workspace context). Follow it strictly. Do not infer or repeat old tasks from prior chats. If nothing needs attention, reply HEARTBEAT_OK:71734044a68e64db"
      },
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 8
      }
    },
    "list": [
      {
        "id": "main",
        "subagents": {
          "allowAgents": [
            "calendario",
            "biochecha",
            "entregas",
            "legal",
            "archie",
            "main",
            "picasso"
          ]
        }
      },
      {
        "id": "biochecha",
        "name": "biochecha",
        "workspace": "/Users/faresende/.openclaw/agents/biochecha",
        "agentDir": "/Users/faresende/.openclaw/agents/biochecha/agent",
        "model": "anthropic/claude-opus-4-6"
      },
      {
        "id": "calendario",
        "name": "calendario",
        "workspace": "/Users/faresende/.openclaw/agents/calendario",
        "agentDir": "/Users/faresende/.openclaw/agents/calendario/agent",
        "model": "anthropic/claude-sonnet-4-6"
      },
      {
        "id": "entregas",
        "name": "entregas",
        "workspace": "/Users/faresende/.openclaw/agents/entregas",
        "agentDir": "/Users/faresende/.openclaw/agents/entregas/agent",
        "model": "anthropic/claude-sonnet-4-6"
      },
      {
        "id": "legal",
        "name": "legal",
        "workspace": "/Users/faresende/.openclaw/agents/legal",
        "agentDir": "/Users/faresende/.openclaw/agents/legal/agent",
        "model": "anthropic/claude-sonnet-4-6"
      },
      {
        "id": "archie",
        "name": "archie",
        "workspace": "/Users/faresende/.openclaw/agents/archie",
        "agentDir": "/Users/faresende/.openclaw/agents/archie/agent",
        "model": "anthropic/claude-sonnet-4-6"
      },
      {
        "id": "picasso",
        "name": "picasso",
        "workspace": "/Users/faresende/.openclaw/agents/picasso",
        "agentDir": "/Users/faresende/.openclaw/agents/picasso",
        "model": "anthropic/claude-sonnet-4-6"
      },
      {
        "id": "bartleby",
        "workspace": "/Users/faresende/.openclaw/agents/bartleby",
        "agentDir": "/Users/faresende/.openclaw/agents/bartleby/agent",
        "model": "anthropic/claude-opus-4-6"
      }
    ]
  },
  "tools": {
    "sessions": {
      "visibility": "all"
    },
    "agentToAgent": {
      "enabled": true,
      "allow": [
        "main",
        "calendario",
        "biochecha",
        "archie"
      ]
    }
  },
  "bindings": [
    {
      "agentId": "main",
      "match": {
        "channel": "telegram",
        "accountId": "default"
      }
    },
    {
      "agentId": "biochecha",
      "match": {
        "channel": "telegram",
        "accountId": "biochecha"
      }
    },
    {
      "agentId": "archie",
      "match": {
        "channel": "telegram",
        "accountId": "archie"
      }
    },
    {
      "agentId": "bartleby",
      "match": {
        "channel": "telegram",
        "accountId": "bartleby"
      }
    }
  ],
  "messages": {
    "ackReactionScope": "group-mentions"
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "restart": true,
    "ownerDisplay": "raw"
  },
  "hooks": {
    "internal": {
      "enabled": true,
      "entries": {
        "command-logger": {
          "enabled": true
        },
        "session-memory": {
          "enabled": true
        }
      }
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "groupPolicy": "allowlist",
      "streaming": "off",
      "accounts": {
        "biochecha": {
          "enabled": true,
          "dmPolicy": "pairing",
          "botToken": "8567199361:AAEwuvnsyLa4425mP90wfZEdnFVWU-g_hf8",
          "allowFrom": [
            "7126059841"
          ],
          "groupPolicy": "allowlist",
          "streaming": "off"
        },
        "archie": {
          "enabled": true,
          "dmPolicy": "pairing",
          "botToken": "8761581586:AAEvQJvndamIj7Ha0lwhgaQev4jHAfTfVYU",
          "allowFrom": [
            "7126059841"
          ],
          "groupPolicy": "allowlist",
          "streaming": "off"
        },
        "default": {
          "dmPolicy": "pairing",
          "botToken": "8310439700:AAGXfcHaWLG0gDaYyj5YUjpcJQyzQNwJhV4",
          "allowFrom": [
            "7126059841"
          ],
          "groupPolicy": "allowlist",
          "streaming": "off"
        },
        "bartleby": {
          "enabled": true,
          "dmPolicy": "pairing",
          "botToken": "8642708941:AAHLioaQMHEjkOHGU242CwF4c7BwxZgNyh4",
          "allowFrom": [
            "8556192228"
          ],
          "groupPolicy": "disabled",
          "streaming": "off"
        }
      }
    }
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback",
    "auth": {
      "mode": "token",
      "token": "aa1dec79f47ef3c33da308906a5bcd61053e5660c8e6c896825581ed79cdd455"
    },
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    }
  },
  "skills": {
    "install": {
      "nodeManager": "npm"
    },
    "entries": {
      "goplaces": {
        "apiKey": "AIzaSyBhirpXLuT3AT_4fv9RAvhBzk596GWyGL0"
      },
      "nano-banana-pro": {
        "apiKey": "AIzaSyCduQQBhd-6RzHAfX1QAIhOwwW8fXEY4GU"
      },
      "openai-image-gen": {
        "apiKey": "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"
      },
      "openai-whisper-api": {
        "apiKey": "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"
      },
      "sag": {
        "apiKey": "5d329395c4c38cfad4f9cc2101c48fb6a12f091eb02bfb4301acee93955bcb49"
      }
    }
  },
  "plugins": {
    "entries": {
      "telegram": {
        "enabled": true
      }
    }
  }
}