# Claw + llama.cpp + Qwen3-Coder on Windows — Cursor-like coding workflow

A step-by-step guide for using claw as a local AI coding assistant (think Cursor, but fully offline) backed by `llama-server` running `Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf`.

---

## Prerequisites

### 1. claw.exe on Windows PATH

Build from WSL and install (see [llama-cpp-qwen3-windows.md](../docs/llama-cpp-qwen3-windows.md)):

```bash
# In WSL
bash scripts/build-windows.sh
cp dist/claw.exe /mnt/c/Users/$USER/bin/claw.exe
```

Confirm:

```powershell
claw --version
```

### 2. llama.cpp Windows binary

Download from the llama.cpp GitHub releases page.  Pick the variant for your GPU:

| GPU | Package |
|---|---|
| NVIDIA CUDA 12.x | `llama-<ver>-bin-win-cuda-cu12.x.x-x64.zip` |
| AMD Vulkan / ROCm | `llama-<ver>-bin-win-vulkan-x64.zip` |
| CPU only | `llama-<ver>-bin-win-avx2-x64.zip` |

Extract to e.g. `C:\llama\`.  The key binary is `C:\llama\llama-server.exe`.

### 3. Model file

`Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf` (~18 GB).  Download from Hugging Face:

```powershell
# pip install huggingface_hub  (if not already installed)
huggingface-cli download `
    bartowski/Qwen3-Coder-30B-A3B-Instruct-GGUF `
    Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf `
    --local-dir C:\models
```

### 4. Memory / VRAM requirements

| VRAM | Strategy |
|---|---|
| 24 GB (RTX 4090, A100 24GB) | `--n-gpu-layers 99` — fully on GPU |
| 16 GB (RTX 4080) | `--n-gpu-layers 52` — most layers on GPU |
| 12 GB (RTX 3080 / 4070) | `--n-gpu-layers 36` — split GPU/CPU |
| 8 GB or less | CPU only; use `--ctx-size 4096` |

---

## Step 1 — Start the llama.cpp server

Open **PowerShell** (not WSL) and run:

```powershell
C:\llama\llama-server.exe `
    -m C:\models\Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf `
    --host 127.0.0.1 `
    --port 8080 `
    --alias qwen3-coder `
    --ctx-size 32768 `
    --n-gpu-layers 99 `
    --threads 8 `
    --flash-attn `
    --parallel 1
```

Wait for:
```
llama server listening at http://127.0.0.1:8080
```

> **Tip:** wrap this in a `.ps1` script and pin it to your taskbar so one click starts the server.

### Quick server health check

```powershell
Invoke-RestMethod `
    -Uri "http://127.0.0.1:8080/v1/chat/completions" `
    -Method POST `
    -Headers @{ "Content-Type"="application/json"; "Authorization"="Bearer local" } `
    -Body '{"model":"qwen3-coder","messages":[{"role":"user","content":"Say OK"}],"stream":false}'
```

You should see `"content": "OK"` (or similar) in the response.

---

## Step 2 — Configure claw to use the server

Open a **second** PowerShell window (keep the server running in the first).

### Set env vars permanently (recommended)

Run once — takes effect in every new terminal from then on:

```powershell
setx OPENAI_BASE_URL "http://127.0.0.1:8081/v1"
setx OPENAI_API_KEY  "local"
```

Open a new terminal after running `setx`. The values persist across reboots.

> **Note:** claw does **not** auto-load `.env` files. Env vars must be set in the actual environment via `setx` (permanent) or `$env:VAR = "value"` (current session only).

### Set env vars for the current session only

```powershell
$env:OPENAI_BASE_URL = "http://127.0.0.1:8081/v1"
$env:OPENAI_API_KEY  = "local"
```

### Lock the model in `~/.claw/settings.json` (global default)

Create `C:\Users\<you>\.claw\settings.json`:

```json
{
  "model": "openai/qwen3-coder"
}
```

The `openai/` prefix is required — it tells claw to route via the OpenAI-compatible provider rather than the Anthropic provider. The model name after the slash must match the `--alias` you passed to llama-server (or the id shown by `GET /v1/models` if no alias is set).

You can also create `.claw.json` at a project root for a per-project override:

```json
{
  "model": "openai/qwen3-coder"
}
```

Run `claw doctor` to confirm the resolved model and base URL are correct.

---

## Step 3 — Launch the interactive REPL

```powershell
cd C:\code\my-project
claw
```

You'll see the claw prompt.  Type a request and press Enter; claw uses tools
(`read_file`, `write_file`, `grep_search`, `glob_search`, `bash_execute`) to
explore and edit your project autonomously.

Press `Ctrl+C` to interrupt a running response.  Type `/exit` or `Ctrl+D` to quit.

---

## Common coding commands

### Add a file to context

Claw can read any file it needs automatically via the `Read` tool, but you can
also push content into the prompt directly:

```powershell
# Pipe a single file into a one-shot question
Get-Content src\auth.rs | claw -p "Explain what this module does"

# Pipe multiple files (PowerShell)
Get-Content src\auth.rs, src\user.rs | claw -p "How do these two modules interact?"
```

In the interactive REPL, just describe the file by path and claw will read it:

```
> Read src/auth.rs and explain the token validation logic
```

### Understand a function

One-shot:
```powershell
Get-Content src\parser.rs | claw -p "Explain the parse_expression function in detail"
```

Interactive:
```
> Explain the parse_expression function in src/parser.rs
```

### Rewrite / refactor a function

```
> Rewrite the calculate_checksum function in src/checksum.rs to use a streaming
  approach instead of loading the whole file into memory
```

Claw will read the file, write the replacement, and show you what changed.
If it looks good, the edit is already on disk — no paste step needed.

To target a specific function by name across the project:
```
> Grep for all callers of process_batch in the src/ directory, then refactor
  the function signature from (Vec<Item>) to (impl Iterator<Item=Item>) and
  update every call site
```

### Implement a new feature

Describe it in plain English; include which files to touch if you know:

```
> Add a --dry-run flag to the CLI (src/cli.rs) that prints what would be
  written but does not call write_file. Wire it through to the export command
  in src/export.rs
```

Or start broader and let claw explore:

```
> I need rate-limiting on the /api/v1/infer endpoint. The server is in
  src/server.rs. Use a token-bucket algorithm, limit to 60 req/min per IP,
  and return HTTP 429 when exceeded. Use only the standard library.
```

### Fix a bug

Paste the error or describe the symptom:

```
> I'm getting a panic: "index out of bounds: the len is 0 but the index is 0"
  in src/tokenizer.rs at line 142. Here is the stack trace: [paste trace]
  Find the root cause and fix it.
```

Or pipe the output directly:
```powershell
cargo test 2>&1 | claw -p "The test suite is failing. Read the failure output and fix the broken tests."
```

### Add tests for a function

```
> Add unit tests for the parse_config function in src/config.rs.
  Cover: valid input, missing required field, unknown field, empty string.
  Put the tests in a #[cfg(test)] module at the bottom of the file.
```

### Review code before committing

Interactive slash command:
```
/review
```

Or scope it to a specific file:
```
> Review src/auth.rs for security issues, error handling gaps, and anything
  that would fail a production code review
```

### Generate a commit message and commit

After you are happy with the changes:
```
/commit
```

Claw reads `git diff --staged`, writes a conventional-commits message, and
runs `git commit` for you.

### Create a pull request

```
/pr
```

Claw reads the branch diff against main, writes a PR title + body with a
test plan, and runs `gh pr create`.

---

## Workflow tips for local models

### Context budget

Qwen3-Coder-30B at 32K context is generous but not unlimited.  For large
codebases:

- Start the server with `--ctx-size 32768` (default) and increase only if you
  genuinely need to fit more; larger context = slower generation.
- Use `/compact` in the REPL when the session grows long — it summarises the
  conversation and frees tokens.
- For cross-file refactors, focus claw on a small set of files per session
  rather than asking it to read the entire repo.

```
# In the REPL
/compact
```

### Thinking mode

Qwen3-Coder-30B supports a thinking mode that produces better reasoning for
complex tasks.  Enable it server-side with an extra body param or in the REPL:

```powershell
# Pass via extra body at the prompt level
claw --model qwen3-coder prompt "Think step by step: implement a Fenwick tree in Rust"
```

If the model produces `<think>...</think>` tokens, claw renders them in a
collapsed block so you can expand reasoning without it cluttering the output.

### Watching token/speed metrics

In the REPL:
```
/cost
```

Prints tokens used and estimated USD (will be $0.00 for local models but the
token count is useful for context budget awareness).

```
/status
```

Shows the model name, provider endpoint, loaded CLAUDE.md files, and git state.

### Switching between tasks

Claw keeps a session history.  When you switch tasks, clear the history to
avoid stale context:

```
/clear
```

Or export the current session for reference before clearing:
```
/export session-auth-refactor.md
/clear
```

---

## Project memory — CLAUDE.md

Create a `CLAUDE.md` at your project root.  Claw reads it at startup and
injects it as system context for every request.

Minimal example for a Rust project:

```markdown
# CLAUDE.md

## Stack
- Language: Rust 2021 edition
- Async runtime: tokio
- HTTP: axum 0.7
- DB: sqlx + PostgreSQL

## Conventions
- Use `anyhow::Result` for error propagation in binary crates.
- Prefer `tracing` over `println!` for logging.
- All public functions must have doc comments.
- Run `cargo clippy -- -D warnings` and `cargo test` before committing.

## File layout
- `src/api/` — HTTP handlers
- `src/db/`  — sqlx queries and migrations
- `src/domain/` — business logic (no I/O)
```

Claw also picks up `.cursorrules` and `.github/copilot-instructions.md`
automatically, so existing Cursor/Copilot context files work as-is.

---

## Quick-reference cheat sheet

| Goal | Command |
|---|---|
| Start interactive REPL | `claw` |
| One-shot prompt | `claw -p "question"` |
| One-shot with file | `Get-Content file.rs \| claw -p "question"` |
| Explain a function | `> Explain <function> in <file>` |
| Rewrite a function | `> Rewrite <function> in <file> to <goal>` |
| New feature | `> Implement <feature> in <file>` |
| Fix failing tests | `cargo test 2>&1 \| claw -p "fix failures"` |
| Add tests | `> Add unit tests for <function> in <file>` |
| Code review | `/review` |
| Commit | `/commit` |
| Pull request | `/pr` |
| Free context | `/compact` |
| New task | `/clear` |
| Switch model | `/model openai/qwen3-coder` |
| Check status | `/status` |
| Session cost/tokens | `/cost` |

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `missing Anthropic credentials` error | `OPENAI_BASE_URL` is not set; run `setx OPENAI_BASE_URL "http://127.0.0.1:8081/v1"` and open a new terminal. |
| `invalid model syntax` / `Expected provider/model` | Model in `.claw.json` or `settings.json` is missing the `openai/` prefix; change `"qwen3-coder"` to `"openai/qwen3-coder"`. |
| Requests go to openai.com instead of localhost | `OPENAI_BASE_URL` is not set in the current terminal; use `setx` to make it permanent, then open a new terminal. |
| `model not found` | Use the exact string from `--alias` in your server command. |
| Responses are very slow | Lower `--ctx-size` or reduce `--n-gpu-layers`; check GPU utilisation with Task Manager → GPU. |
| Server returns HTML instead of JSON | Wrong port or the server crashed; check the server terminal. |
| Claw reads wrong files | Run `/status` to see which CLAUDE.md files are loaded and what the working directory is. |
| `/commit` stages unwanted files | Run `git add -p` manually first; claw commits whatever is staged. |
| Context fills up mid-session | `/compact` or `/clear`; reduce `--ctx-size` if you want a hard cap. |
