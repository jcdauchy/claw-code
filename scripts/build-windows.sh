#!/usr/bin/env bash
# build-windows.sh — Build claw.exe for Windows via Docker cross-compilation.
#
# Runs inside WSL2 (or any Linux shell with Docker access).  Docker Desktop on
# Windows exposes the daemon to WSL2 automatically; no extra configuration is
# needed beyond having Docker Desktop running.
#
# Prerequisites:
#   - Docker Desktop running on the Windows host (or dockerd on native Linux)
#   - Internet access for the initial image pull (~1 GB rust:1.91 base layer)
#
# Usage:
#   bash scripts/build-windows.sh              # outputs to <repo>/dist/claw.exe
#   bash scripts/build-windows.sh /tmp/out     # outputs to /tmp/out/claw.exe
#
# The resulting claw.exe is a self-contained Windows PE binary; copy it to any
# directory on the Windows PATH (e.g. C:\Users\<you>\bin\) and run it from
# PowerShell or Command Prompt without further dependencies.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_DIR="$REPO_ROOT/rust"
OUT_DIR="${1:-$REPO_ROOT/dist}"
if [[ $# -gt 0 && ( "$1" == "--help" || "$1" == "-h" ) ]]; then
    sed -n '2,20p' "$0" | sed 's/^# //; s/^#//'
    exit 0
fi

# Resolve git metadata — passed into Docker as build args and picked up by build.rs.
GIT_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo 'unknown')"
GIT_BRANCH="$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo 'unknown')"

mkdir -p "$OUT_DIR"

echo "▶ claw Windows build" >&2
echo "  git sha    : $GIT_SHA" >&2
echo "  git branch : $GIT_BRANCH" >&2
echo "  context    : $RUST_DIR" >&2
echo "  output  : $OUT_DIR/claw.exe" >&2
echo "" >&2

# ── Step 1 + 2: build and export in one pass via BuildKit --output ───────────
# BuildKit streams the final-stage filesystem directly to $OUT_DIR without
# creating an intermediate container.  This works with FROM scratch images
# (docker create fails on scratch because there is no default command).
# Docker Desktop always uses BuildKit; on plain dockerd, DOCKER_BUILDKIT=1
# enables it.
echo "[1/2] docker build + export (x86_64-pc-windows-gnu via mingw-w64)…" >&2
DOCKER_BUILDKIT=1 docker build \
    --build-arg "GIT_SHA=$GIT_SHA" \
    --build-arg "GIT_BRANCH=$GIT_BRANCH" \
    -f "$RUST_DIR/Dockerfile.windows" \
    --output "type=local,dest=$OUT_DIR" \
    "$RUST_DIR"

# ── Step 2: report ──────────────────────────────────────────────────────────
echo "[2/2] Done." >&2
echo "" >&2
ls -lh "$OUT_DIR/claw.exe" >&2
echo "" >&2

# Convert the WSL path to a Windows path if running inside WSL so the user
# can paste it directly into Explorer or a PowerShell prompt.
if command -v wslpath > /dev/null 2>&1; then
    WIN_PATH="$(wslpath -w "$OUT_DIR/claw.exe" 2>/dev/null || echo '')"
    if [[ -n "$WIN_PATH" ]]; then
        echo "  Windows path : $WIN_PATH" >&2
    fi
fi

echo "" >&2
echo "  To install — copy to a directory on your Windows PATH, for example:" >&2
echo "    cp '$OUT_DIR/claw.exe' /mnt/c/Users/\$USER/bin/claw.exe" >&2
echo "" >&2
echo "  Then from PowerShell:" >&2
echo "    claw --version" >&2
