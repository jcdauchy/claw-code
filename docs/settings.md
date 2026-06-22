# Claw Settings Reference

This document describes all configuration options available in Claw, where settings files live, and how settings are loaded and merged.

---

## Settings File Locations

Claw loads settings from up to five files, in the order listed below. Later files override earlier ones (objects are deep-merged; arrays are concatenated).

| Scope | Path | Notes |
|---|---|---|
| User (legacy) | `~/.claw.json` | Deprecated — still loaded, prefer the new path |
| User | `~/.claw/settings.json` | Main user-level config |
| Project (legacy) | `.claw.json` (repo root) | Deprecated — still loaded |
| Project | `.claw/settings.json` | Committed, shared with your team |
| Local | `.claw/settings.local.json` | Machine-specific overrides, not committed |

`~` resolves to `$CLAW_CONFIG_HOME` if that env var is set, otherwise `$HOME/.claw`.

**Rule of thumb:** put shared team settings in `.claw/settings.json` and personal or machine-specific overrides in `.claw/settings.local.json`.

---

## Top-Level Fields

```jsonc
{
  "$schema": "SettingsSchema",   // optional, for IDE auto-complete
  "model": "claude-sonnet-4-6",  // default model to use
  "subagentModel": "...",        // model used for sub-agents
  "autoMemoryEnabled": true,     // enable/disable persistent memory (default: true)
  "rulesImport": "auto",         // external framework rules import (see below)
  "trustedRoots": [],            // filesystem paths Claw may access
  "aliases": {},                 // model name shortcuts (see below)
  "provider": {},                // AI provider config (see below)
  "providerFallbacks": {},       // fallback model chain (see below)
  "permissions": {},             // permission mode and allow/deny rules (see below)
  "hooks": {},                   // lifecycle hooks (see below)
  "mcpServers": {},              // MCP server definitions (see below)
  "plugins": {},                 // plugin configuration (see below)
  "sandbox": {},                 // sandbox/isolation settings (see below)
  "oauth": {},                   // OAuth config for Claude.ai auth (see below)
  "env": {},                     // extra environment variables to inject
  "apiTimeout": {}               // network timeout and retry settings (see below)
}
```

### `model`

The default model ID passed to the provider.

```json
{ "model": "claude-sonnet-4-6" }
```

Resolution order (first non-empty wins): `--model` CLI flag → `CLAW_MODEL` env var → `ANTHROPIC_MODEL` env var → `ANTHROPIC_DEFAULT_MODEL` env var → `model` in settings → provider default.

### `subagentModel`

Model used when spawning sub-agents. Falls back to `model` if not set.

### `autoMemoryEnabled`

Boolean (default `true`). When enabled, Claw automatically loads and saves persistent memory from `~/.claw/projects/<workspace-id>/memory/`. Set to `false` to disable.

```json
{ "autoMemoryEnabled": false }
```

### `rulesImport`

Controls whether Claw imports rules from external AI coding frameworks detected in the repo (Cursor, GitHub Copilot, etc.).

| Value | Behavior |
|---|---|
| `"auto"` (default) | Import from all detected frameworks |
| `"none"` | Do not import any external rules |
| `["cursor", "copilot"]` | Import only the named frameworks (case-insensitive) |

### `trustedRoots`

Array of filesystem paths that Claw may access. Merged (deduplicated) across all config files.

```json
{ "trustedRoots": ["/data/shared", "/home/me/projects"] }
```

### `aliases`

Map of short names to full model IDs.

```json
{
  "aliases": {
    "fast": "claude-haiku-4-5-20251001",
    "smart": "claude-opus-4-8"
  }
}
```

### `env`

Extra environment variables injected into the Claw process.

```json
{ "env": { "MY_VAR": "value" } }
```

---

## `provider`

Configure the AI provider. The API key can also be set via environment variable (takes precedence over the stored value).

```jsonc
{
  "provider": {
    "kind": "anthropic",   // "anthropic" | "openai" | "xai" — omit to auto-detect
    "apiKey": "sk-...",    // also: ANTHROPIC_API_KEY / OPENAI_API_KEY / XAI_API_KEY
    "baseUrl": "https://api.anthropic.com",  // override endpoint
    "model": "claude-sonnet-4-6"             // provider-level model default
  }
}
```

**Environment variables per provider:**

| Provider | API key env var | Base URL env var |
|---|---|---|
| Anthropic | `ANTHROPIC_API_KEY` | `ANTHROPIC_BASE_URL` |
| OpenAI-compatible | `OPENAI_API_KEY` | `OPENAI_BASE_URL` |
| xAI (Grok) | `XAI_API_KEY` | `XAI_BASE_URL` |
| Alibaba DashScope | `DASHSCOPE_API_KEY` | `DASHSCOPE_BASE_URL` |

Provider settings are saved to `~/.claw/settings.json` (file permissions `0600`) when configured interactively.

---

## `providerFallbacks`

Define an ordered fallback chain when the primary model is unavailable.

```json
{
  "providerFallbacks": {
    "primary": "claude-opus-4-8",
    "fallbacks": ["claude-sonnet-4-6", "claude-haiku-4-5-20251001"]
  }
}
```

---

## `permissions`

Control what Claw is allowed to do.

```jsonc
{
  "permissions": {
    "defaultMode": "auto",       // permission mode (see below)
    "allow": ["Bash(git *)", "Read"],   // always-allow patterns
    "deny":  ["Bash(rm -rf *)"],        // always-deny patterns
    "ask":   ["Write"],                 // always-ask patterns
    "deniedTools": ["dangerous-tool"]   // deny by tool name
  }
}
```

### `defaultMode`

| Value (aliases) | Behavior |
|---|---|
| `"default"` / `"plan"` / `"read-only"` | Most restrictive; requires approval for most operations |
| `"auto"` / `"acceptEdits"` / `"workspace-write"` | Allows workspace modifications without per-operation prompts |
| `"dontAsk"` / `"danger-full-access"` | No permission checks at all |

Can also be set via the `--permission-mode` CLI flag.

> **Deprecated:** The top-level `permissionMode` field still works but `permissions.defaultMode` is preferred.

---

## `hooks`

Run shell commands before or after tool use.

```jsonc
{
  "hooks": {
    "PreToolUse": [
      "echo 'about to use a tool'"
    ],
    "PostToolUse": [
      { "matcher": "Bash,Write", "hooks": [{ "type": "command", "command": "log-tool-use" }] }
    ],
    "PostToolUseFailure": [
      "notify-on-failure"
    ]
  }
}
```

**Hook events:**

| Event | Fires |
|---|---|
| `PreToolUse` | Before a tool executes |
| `PostToolUse` | After a tool succeeds |
| `PostToolUseFailure` | After a tool fails |

**Matcher syntax:** comma- or pipe-separated tool name patterns. Supports wildcards (`Bash*`, `*File`). Case-insensitive. Use `*` to match all tools.

**Hook formats:**
- Simple string: `"my-command"`
- Object: `{ "type": "command", "command": "my-command" }`
- With matcher: `{ "matcher": "Bash", "hooks": [...] }`

---

## `mcpServers`

Define MCP (Model Context Protocol) servers. Each key is a server name.

```jsonc
{
  "mcpServers": {
    "my-local-tool": {
      "type": "stdio",             // inferred if omitted: stdio when "command" present, http when "url" present
      "command": "my-tool",
      "args": ["--flag"],
      "env": { "TOKEN": "abc" },
      "toolCallTimeoutMs": 30000
    },
    "my-remote-api": {
      "type": "http",              // or "sse"
      "url": "https://mcp.example.com",
      "headers": { "Authorization": "Bearer ${TOKEN}" },
      "headersHelper": "optional-helper-command",
      "oauth": {
        "clientId": "...",
        "callbackPort": 9090,
        "authServerMetadataUrl": "https://...",
        "xaa": false
      }
    },
    "my-ws-server": {
      "type": "ws",
      "url": "wss://mcp.example.com",
      "headers": {}
    },
    "my-sdk-server": {
      "type": "sdk",
      "name": "server-name"
    }
  }
}
```

**Field expansion:** `${VAR}` and `$VAR` are expanded from environment variables in `command`, `args`, and `url` fields. `~/` expands to `$HOME`.

**`required`:** Add `"required": true` to a server definition to make Claw fail if the server cannot connect.

---

## `plugins`

```jsonc
{
  "plugins": {
    "enabled": {
      "my-plugin": true,
      "other-plugin": false
    },
    "externalDirectories": ["/path/to/plugins"],
    "installRoot": "/custom/install/root",
    "registryPath": "/path/to/registry",
    "bundledRoot": "/path/to/bundled",
    "maxOutputTokens": 4096
  }
}
```

> **Deprecated:** The top-level `enabledPlugins` field still works but `plugins.enabled` is preferred.

---

## `sandbox`

Control filesystem and network isolation.

```jsonc
{
  "sandbox": {
    "enabled": true,
    "namespaceRestrictions": true,   // enable OS namespace restrictions
    "networkIsolation": true,        // block network access
    "filesystemMode": "workspace-only",  // "off" | "workspace-only" | "allow-list"
    "allowedMounts": ["/data/shared"]    // used when filesystemMode = "allow-list"
  }
}
```

---

## `oauth`

OAuth configuration for authenticating with Claude.ai (not the provider API).

```jsonc
{
  "oauth": {
    "clientId": "my-client-id",           // required
    "authorizeUrl": "https://...",         // required
    "tokenUrl": "https://...",             // required
    "callbackPort": 8765,
    "manualRedirectUrl": "https://...",
    "scopes": ["read", "write"]
  }
}
```

---

## `apiTimeout`

Tune network timeouts and retry behaviour.

```jsonc
{
  "apiTimeout": {
    "connectTimeoutSecs": 30,   // TCP connect timeout (default: 30)
    "requestTimeoutSecs": 300,  // Full request timeout in seconds (default: 300)
    "maxRetries": 8             // Max retry attempts on transient errors (default: 8)
  }
}
```

---

## CLI Flags

These override the corresponding settings file values.

| Flag | Description |
|---|---|
| `--model <id>` | Override the model |
| `--permission-mode <mode>` | Override `permissions.defaultMode` |
| `--cwd <path>` / `-C <path>` | Set the working directory |
| `--output-format text\|json` | Output format |
| `--allowed-tools <csv>` | Comma-separated list of allowed tools |
| `--skip-permissions` | Skip permission prompts (alias for `workspace-write`) |
| `--dangerously-skip-permissions` | Disable all permission checks |
| `--resume <file>` | Resume a saved session |
| `--print` / `-p` | Non-interactive print mode |
| `--compact` | Compact output |
| `--base-commit <sha>` | Base commit for diff context |
| `--reasoning-effort` | Reasoning effort level (for supported models) |

---

## Environment Variables

| Variable | Description |
|---|---|
| `CLAW_CONFIG_HOME` | Override the config directory (default: `$HOME/.claw`) |
| `CLAW_MODEL` | Default model (highest precedence in model resolution) |
| `ANTHROPIC_MODEL` | Default model (Anthropic-specific) |
| `ANTHROPIC_DEFAULT_MODEL` | Default model fallback |
| `CLAW_OUTPUT_FORMAT` | Default output format (`text` or `json`) |
| `CLAW_LOG` | Claw log level |
| `RUST_LOG` | Rust log level |

---

## Persistent Memory

When `autoMemoryEnabled` is `true`, Claw reads and writes memory files at:

```
~/.claw/projects/<workspace-fingerprint>/memory/
```

- **`MEMORY.md`** — index file (max 200 lines); loaded automatically into every conversation
- **`*.md` files** — individual memory entries with YAML frontmatter

Memory entry format:

```markdown
---
name: short-kebab-slug
description: one-line summary used to determine relevance
type: user | feedback | project | reference
---

Memory content here.
```

---

## Complete Example

```jsonc
// .claw/settings.json
{
  "$schema": "SettingsSchema",
  "model": "claude-sonnet-4-6",
  "autoMemoryEnabled": true,
  "rulesImport": "auto",
  "provider": {
    "kind": "anthropic"
  },
  "permissions": {
    "defaultMode": "auto",
    "allow": ["Read", "Bash(git *)"],
    "deny": ["Bash(rm -rf *)"]
  },
  "hooks": {
    "PostToolUse": [
      { "matcher": "Write,Edit", "hooks": [{ "type": "command", "command": "prettier --write $FILE" }] }
    ]
  },
  "mcpServers": {
    "filesystem": {
      "command": "mcp-server-filesystem",
      "args": ["--root", "${HOME}/projects"]
    }
  },
  "apiTimeout": {
    "connectTimeoutSecs": 30,
    "requestTimeoutSecs": 300,
    "maxRetries": 8
  }
}
```

```jsonc
// .claw/settings.local.json  (machine-specific, not committed)
{
  "provider": {
    "apiKey": "sk-ant-..."
  }
}
```
