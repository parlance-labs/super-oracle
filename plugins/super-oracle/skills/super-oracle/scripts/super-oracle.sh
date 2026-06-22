#!/usr/bin/env bash
# super-oracle.sh — consult codex-fugu (Sakana Fugu Ultra) as an external oracle.
#
# Self-contained: works as a bundled plugin skill (Codex/Claude) or a plain skill
# (Amp). Reads a briefing from a file or stdin, writes the answer to -o OUTPUT.
#
# Usage:
#   super-oracle.sh -o OUTPUT.md BRIEFING.md
#   super-oracle.sh -o OUTPUT.md < BRIEFING.md
#
# Options:
#   -o OUTPUT   Where to write the oracle's answer (required).
#   -m MODEL    Model (default: fugu-ultra — always the strongest Fugu model).
#   -C DIR      Working directory for the oracle (default: current dir).
#   -n          Turn MCP servers OFF for this run (default: leave them ON).
#   -h          Help.
#
# MCP is left ON by default. codex-fugu starts the MCP servers in
# ~/.codex/config.toml; servers that are not logged in print harmless
# `Auth required` warnings at shutdown but do not block (measured overhead is a
# couple of seconds, immaterial for a long-running oracle). We just filter that
# cosmetic noise from the output. Use -n only if you have an MCP server that
# genuinely hangs or stalls a run; -n runs with a temp CODEX_HOME that strips all
# [mcp_servers.*] from config.toml (note: `-c mcp_servers="{}"` does NOT work in
# exec mode because codex deep-merges config).
#
# Permission posture (read this — true inheritance is impossible):
#   codex does NOT expose the parent agent's approval/sandbox policy to child
#   processes, so the oracle cannot truly "inherit" the parent's flags. It only
#   sees CODEX_SANDBOX / CODEX_SANDBOX_NETWORK_DISABLED. We approximate:
#     - SUPER_ORACLE_SANDBOX=read-only|workspace-write|danger-full-access overrides.
#     - Else if a Codex sandbox signal is present (parent sandboxed us), stay
#       conservative: --sandbox workspace-write (no full bypass).
#     - Else default to --dangerously-bypass-approvals-and-sandbox (unattended).
#   Set SUPER_ORACLE_BYPASS=0 to never bypass; =1 to force bypass.
set -euo pipefail

MODEL="fugu-ultra"; OUTPUT=""; WORKDIR=""; DISABLE_MCP=0
usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":o:m:C:nh" opt; do
  case "$opt" in
    o) OUTPUT="$OPTARG" ;; m) MODEL="$OPTARG" ;; C) WORKDIR="$OPTARG" ;;
    n) DISABLE_MCP=1 ;; h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 1 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 1 ;;
  esac
done
shift $((OPTIND - 1))

[ -z "$OUTPUT" ] && { echo "ERROR: -o OUTPUT is required" >&2; usage 1; }
command -v codex-fugu >/dev/null 2>&1 || {
  echo "ERROR: codex-fugu not found. Install: curl -fsSL https://sakana.ai/fugu/install | bash" >&2; exit 127; }

BRIEFING_SRC=""
if [ "$#" -ge 1 ] && [ "$1" != "-" ]; then
  BRIEFING_SRC="$1"
  [ -f "$BRIEFING_SRC" ] || { echo "ERROR: briefing not found: $BRIEFING_SRC" >&2; exit 1; }
fi

# --- Resolve permission posture (see header) -------------------------------
POSTURE_ARGS=()
if [ -n "${SUPER_ORACLE_SANDBOX:-}" ]; then
  POSTURE_ARGS=(--sandbox "$SUPER_ORACLE_SANDBOX")
elif [ "${SUPER_ORACLE_BYPASS:-}" = "1" ]; then
  POSTURE_ARGS=(--dangerously-bypass-approvals-and-sandbox)
elif [ "${SUPER_ORACLE_BYPASS:-}" = "0" ]; then
  POSTURE_ARGS=(--sandbox workspace-write)
elif [ -n "${CODEX_SANDBOX:-}" ] || [ "${CODEX_SANDBOX_NETWORK_DISABLED:-}" = "1" ]; then
  POSTURE_ARGS=(--sandbox workspace-write)   # parent sandboxed us; do not escalate
else
  POSTURE_ARGS=(--dangerously-bypass-approvals-and-sandbox)   # unattended default
fi

# --- Optionally turn MCP off via a temp CODEX_HOME (only with -n) ----------
REAL_HOME="${CODEX_HOME:-$HOME/.codex}"; TMPHOME=""
cleanup() { [ -n "$TMPHOME" ] && rm -rf "$TMPHOME"; return 0; }
trap cleanup EXIT
if [ "$DISABLE_MCP" -eq 1 ] && [ -f "$REAL_HOME/config.toml" ]; then
  TMPHOME="$(mktemp -d "${TMPDIR:-/tmp}/fugu-home.XXXXXX")"
  shopt -s dotglob nullglob 2>/dev/null || true
  for f in "$REAL_HOME"/*; do
    base="$(basename "$f")"; [ "$base" = "config.toml" ] && continue
    ln -sfn "$f" "$TMPHOME/$base"
  done
  shopt -u dotglob nullglob 2>/dev/null || true
  python3 - "$REAL_HOME/config.toml" "$TMPHOME/config.toml" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
skip = False; out = []
for line in open(src).read().splitlines(keepends=True):
    s = line.lstrip()
    if s.startswith('['):
        skip = s.startswith('[mcp_servers')
    if not skip:
        out.append(line)
open(dst, 'w').write(''.join(out))
PY
  export CODEX_HOME="$TMPHOME"
fi

run() {
  codex-fugu exec "${POSTURE_ARGS[@]}" --skip-git-repo-check \
    -c model="$MODEL" -o "$OUTPUT" -
}

[ -n "$WORKDIR" ] && cd "$WORKDIR"
[ "$DISABLE_MCP" -eq 1 ] && MCP_STATE="off" || MCP_STATE="on"
echo ">> super-oracle: model=$MODEL mcp=$MCP_STATE posture=${POSTURE_ARGS[*]} cwd=$(pwd)" >&2

# Filter the harmless MCP auth/shutdown noise from displayed stderr. This hides
# only those specific cosmetic lines; real errors still surface.
FILTER='rmcp\|MCP client during shutdown\|Auth required\|OAuth authorization required\|Token refresh not possible\|worker quit with fatal'

# A misconfigured/expired MCP server can make codex-fugu exit non-zero even
# though the oracle answered fine. Judge success by whether output was produced,
# not by codex's exit code (so a broken MCP never breaks a good run).
set +e
if [ -n "$BRIEFING_SRC" ]; then
  run < "$BRIEFING_SRC" 2> >(grep -v "$FILTER" >&2)
else
  run 2> >(grep -v "$FILTER" >&2)
fi
rc=$?
set -e

if [ ! -s "$OUTPUT" ]; then
  echo "ERROR: oracle produced no output (codex-fugu exit $rc)" >&2
  exit 1
fi
[ "$rc" -ne 0 ] && echo ">> super-oracle: note: codex-fugu exited $rc (likely an MCP server issue); answer was still produced" >&2
echo ">> super-oracle: done. Wrote $OUTPUT" >&2
