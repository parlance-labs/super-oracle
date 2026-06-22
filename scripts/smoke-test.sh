#!/usr/bin/env bash
# Minimal-token smoke test: confirms the bundled super-oracle skill can reach
# codex-fugu, runs on fugu-ultra, and returns the expected output. One trivial
# prompt (~handful of tokens). It is cheap, not necessarily fast — Fugu Ultra
# orchestration can take a while. MCP is left on by default, so any cosmetic MCP
# noise that leaks past the filter is reported but does NOT fail the test.
# Exits non-zero only if the oracle is unreachable or the answer is wrong.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$ROOT/plugins/super-oracle/skills/super-oracle/scripts/super-oracle.sh"

command -v codex-fugu >/dev/null 2>&1 || { echo "SKIP: codex-fugu not installed"; exit 0; }
[ -x "$SKILL" ] || { echo "FAIL: skill script not executable: $SKILL"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
printf 'Reply with the single word READY and nothing else.' > "$WORK/briefing.md"

echo ">> running smoke test (fugu-ultra, mcp on)..."
START=$(date +%s)
bash "$SKILL" -o "$WORK/out.md" "$WORK/briefing.md" 2> "$WORK/err.txt" || {
  echo "FAIL: skill invocation errored"; cat "$WORK/err.txt"; exit 1; }
ELAPSED=$(( $(date +%s) - START ))

# The wrapper must report it actually ran Fugu Ultra.
grep -q 'model=fugu-ultra' "$WORK/err.txt" || {
  echo "FAIL: wrapper did not report model=fugu-ultra"; cat "$WORK/err.txt"; exit 1; }

OUT="$(cat "$WORK/out.md" 2>/dev/null || true)"
OUT_STRIPPED="$(tr -d '[:space:]' < "$WORK/out.md" 2>/dev/null || true)"
AUTH=$(grep -c 'Auth required\|OAuth authorization required\|rmcp_client' "$WORK/err.txt" || true)

echo "   elapsed=${ELAPSED}s  output='${OUT}'  leaked_mcp_noise=${AUTH}"
# Hard assertion: codex-fugu reached Fugu Ultra and returned exactly READY.
case "$OUT_STRIPPED" in
  READY) echo "PASS: super-oracle smoke test" ;;
  *) echo "FAIL: expected exactly READY in output, got: '${OUT}'"; exit 1 ;;
esac
# Informational only: the script should filter cosmetic MCP shutdown noise.
[ "$AUTH" -eq 0 ] || echo "NOTE: ${AUTH} MCP shutdown lines leaked past the filter (cosmetic)"
