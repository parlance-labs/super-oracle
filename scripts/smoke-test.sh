#!/usr/bin/env bash
# Fast, cheap smoke test: confirms the bundled super-oracle skill can reach
# codex-fugu, runs on fugu-ultra, returns output, and emits no MCP auth churn.
# One trivial prompt (~handful of tokens). Exits non-zero on any failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/plugins/super-oracle/skills/super-oracle/scripts/super-oracle.sh"

command -v codex-fugu >/dev/null 2>&1 || { echo "SKIP: codex-fugu not installed"; exit 0; }
[ -x "$SKILL" ] || { echo "FAIL: skill script not executable: $SKILL"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
printf 'Reply with the single word READY and nothing else.' > "$WORK/briefing.md"

echo ">> running smoke test (fugu-ultra, mcp off)..."
START=$(date +%s)
bash "$SKILL" -o "$WORK/out.md" "$WORK/briefing.md" 2> "$WORK/err.txt" || {
  echo "FAIL: skill invocation errored"; cat "$WORK/err.txt"; exit 1; }
ELAPSED=$(( $(date +%s) - START ))

OUT="$(cat "$WORK/out.md" 2>/dev/null || true)"
AUTH=$(grep -c 'Auth required\|OAuth authorization required\|rmcp_client' "$WORK/err.txt" || true)
MODEL_OK=$(grep -c 'model: fugu-ultra\|model=fugu-ultra' "$WORK/err.txt" || true)

echo "   elapsed=${ELAPSED}s  output='${OUT}'  auth_warnings=${AUTH}"
FAIL=0
case "$OUT" in *READY*) : ;; *) echo "FAIL: expected READY in output"; FAIL=1 ;; esac
[ "$AUTH" -eq 0 ] || { echo "FAIL: MCP auth churn leaked into stderr ($AUTH lines)"; FAIL=1; }

[ "$FAIL" -eq 0 ] && echo "PASS: super-oracle smoke test" || exit 1
