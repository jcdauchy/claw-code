# claw on Windows with llama.cpp + Qwen3.6-35B

This guide covers building a Windows-native `claw.exe` binary from WSL2 + Docker, then wiring it up to a local `llama-server` instance running Qwen3.6-35B-A3B-Q4_K_M.gguf (or any other GGUF model).

For general OpenAI-compatible routing and non-Windows llama.cpp setup, see [local-openai-compatible-providers.md](local-openai-compatible-providers.md).

---

## Part 1 — Build claw.exe from WSL2

### Prerequisites

| Requirement | How to check |
|---|---|
| WSL2 installed and a distro running | `wsl --list --verbose` in PowerShell |
| Docker Desktop running (WSL2 backend) | `docker info` in your WSL shell |
| Git in WSL | `git --version` |
| Repo cloned in WSL | `ls /path/to/claw-code/rust/Cargo.toml` |

Docker Desktop with the WSL2 backend exposes the Docker socket to every WSL2
distro automatically; no extra configuration is needed.

### Build

From your WSL2 shell, inside the repo root:

```bash
bash scripts/build-windows.sh
```

This runs a two-stage Docker build inside WSL:

1. **Builder stage** — `rust:1.91-bookworm` with `gcc-mingw-w64-x86-64` installed.
   Compiles `claw` for `x86_64-pc-windows-gnu`.  All TLS is handled by `rustls`
   (pure Rust), so no OpenSSL or MSVC toolchain is needed.
2. **Export stage** — scratch image containing only `claw.exe`.
   The script creates a temporary container, copies out the binary, and removes
   the container automatically.

Output: `dist/claw.exe` relative to the repo root (or pass a custom path as the
first argument: `bash scripts/build-windows.sh /tmp/out`).

### Install on Windows

Copy the binary to any folder on your Windows `PATH`:

```powershell
# From PowerShell — adjust the WSL distro path as needed
Copy-Item "\\wsl$\Ubuntu\home\<you>\claw-code\dist\claw.exe" `
    "$env:USERPROFILE\bin\claw.exe"
```

Or from your WSL shell (using the `/mnt/c/…` mount):

```bash
cp dist/claw.exe /mnt/c/Users/$USER/bin/claw.exe
```

Verify:

```powershell
claw --version
```

---

## Part 2 — Set up llama.cpp server on Windows

### Download llama.cpp

Download a pre-built Windows release from the llama.cpp GitHub releases page.
Choose the variant that matches your GPU:

| GPU | Binary package to download |
|---|---|
| NVIDIA (CUDA) | `llama-<version>-bin-win-cuda-cu12.x.x-x64.zip` |
| AMD (ROCm/HIP) | `llama-<version>-bin-win-hip-x64.zip` |
| Any GPU (Vulkan) | `llama-<version>-bin-win-vulkan-x64.zip` |
| CPU only | `llama-<version>-bin-win-noavx-x64.zip` (or avx2/avx512 if your CPU supports it) |

Extract the ZIP; the key executable is `llama-server.exe`.

### Download the model

Qwen3.6-35B-A3B-Q4_K_M.gguf is a 4-bit quantised Mixture-of-Experts model
(~22 GB on disk, ~24 GB RAM/VRAM to load fully).

Use `huggingface-cli` or `wget`/`curl` to download:

```powershell
# With huggingface-cli (pip install huggingface_hub)
huggingface-cli download \
    bartowski/Qwen3.6-35B-A3B-GGUF \
    Qwen3.6-35B-A3B-Q4_K_M.gguf \
    --local-dir C:\models
```

Or place the `.gguf` file wherever you prefer; adjust the `-m` flag below.

### Start the server

Qwen3.6-35B-A3B is a Mixture-of-Experts model with a 128K context window.
Recommended server flags:

```powershell
.\llama-server.exe `
    -m C:\models\Qwen3.6-35B-A3B-Q4_K_M.gguf `
    --host 127.0.0.1 `
    --port 8080 `
    --alias qwen3-35b `
    --ctx-size 32768 `
    --n-gpu-layers 99 `
    --threads 8 `
    --parallel 1 `
    --flash-attn
```

Flag notes:

| Flag | Why |
|---|---|
| `--alias qwen3-35b` | Sets the model name claw will send in requests; use this same string in `--model` below. |
| `--ctx-size 32768` | 32K context; increase to 65536 or 131072 if VRAM allows but inference slows. |
| `--n-gpu-layers 99` | Offload all layers to GPU.  Drop to e.g. 48 if you have less than 24 GB VRAM. |
| `--threads 8` | CPU threads for non-GPU layers; tune to your core count. |
| `--flash-attn` | Enables FlashAttention — significant speedup on CUDA/Vulkan, reduce memory. |
| `--parallel 1` | Number of parallel decode slots; keep at 1 for single-user local use. |

CPU-only (slow but works):

```powershell
.\llama-server.exe `
    -m C:\models\Qwen3.6-35B-A3B-Q4_K_M.gguf `
    --host 127.0.0.1 `
    --port 8080 `
    --alias qwen3-35b `
    --ctx-size 8192 `
    --threads 16
```

The server prints `llama server listening at http://127.0.0.1:8080` when ready.

### Smoke-test the server directly

Before involving claw, confirm the OpenAI-compatible endpoint works:

```powershell
Invoke-RestMethod `
    -Uri "http://127.0.0.1:8080/v1/chat/completions" `
    -Method POST `
    -Headers @{ "Content-Type" = "application/json"; "Authorization" = "Bearer local-dev-token" } `
    -Body '{"model":"qwen3-35b","messages":[{"role":"user","content":"Reply exactly HELLO_WORLD_123"}],"stream":false}'
```

Expected: a JSON response containing `HELLO_WORLD_123` in the assistant message.

---

## Part 3 — Connect claw to the server

Set these two environment variables before running claw.  You can put them in
your PowerShell profile (`$PROFILE`) or in a `.env` file at the repo root
(claw reads `.env` from the working directory automatically).

```powershell
$env:OPENAI_BASE_URL = "http://127.0.0.1:8080/v1"
$env:OPENAI_API_KEY  = "local-dev-token"   # any non-empty string; llama-server ignores it
```

Run claw with the alias you set in `--alias`:

```powershell
claw --model qwen3-35b prompt "Explain what a Mixture-of-Experts model is"
```

Or use the `local/` prefix to force OpenAI-compatible routing without an alias
(useful if you started the server without `--alias`):

```powershell
claw --model "local/qwen3-35b" prompt "Hello"
```

`.env` file equivalent (drop this in your project root and omit the `$env:` exports):

```
OPENAI_BASE_URL=http://127.0.0.1:8080/v1
OPENAI_API_KEY=local-dev-token
```

---

## GPU memory quick-reference

Qwen3.6-35B-A3B-Q4_K_M at 4-bit:

| VRAM | Strategy |
|---|---|
| ≥ 24 GB (e.g. RTX 4090, A100) | `--n-gpu-layers 99` — fully GPU-resident |
| 16 GB (e.g. RTX 4080) | `--n-gpu-layers 60` — split; some layers stay on CPU |
| 12 GB (e.g. RTX 3080/4070) | `--n-gpu-layers 40` — mostly CPU, slower |
| 8 GB or less | CPU only; reduce `--ctx-size` to 4096 |

Tune `--n-gpu-layers` by watching the server's startup output which prints
`n_gpu_layers = N` and confirms how many layers were offloaded.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `docker build` fails in WSL with "cannot connect to Docker daemon" | Open Docker Desktop, confirm WSL integration is enabled in Settings → Resources → WSL Integration. |
| `claw.exe` shows Anthropic credential error | Set `OPENAI_BASE_URL` and `OPENAI_API_KEY`; unset `ANTHROPIC_API_KEY` if present during testing. |
| `model not found` from llama-server | Use the exact string passed to `--alias` (or omit alias and let the server pick its own name from the GGUF metadata, then query `GET /v1/models` to find it). |
| Server starts but claw hangs | The 35B model is slow on CPU; reduce `--ctx-size`, add `--n-gpu-layers`, or test with a smaller model first. |
| `CUDA error: out of memory` | Reduce `--n-gpu-layers`, `--ctx-size`, or both. |
| Plain prompt works but `/code-review` or tools fail | Confirm the model supports OpenAI-compatible tool calls; Qwen3 family does, but check server version ≥ b4720. |
