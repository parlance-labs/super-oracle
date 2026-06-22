#!/usr/bin/env bash
# super-oracle.sh — consult codex-fugu (Sakana Fugu Ultra) as an external oracle.
#
# Self-contained: works as a bundled plugin skill (Codex/Claude) or a plain skill
# (Amp). Reads a briefing from a file or stdin, writes the answer to -o OUTPUT.
# Drive it FROM your main agent (Codex/Claude/Amp); never run it from inside a
# codex-fugu session (that asks Fugu Ultra to consult itself).
#
# Usage:
#   super-oracle.sh -o OUTPUT.md BRIEFING.md
#   super-oracle.sh -o OUTPUT.md < BRIEFING.md
#
# Options:
#   -o OUTPUT   Where to write the oracle's answer (required).
#   -C DIR      Working directory for the oracle (default: current dir).
#   -n          Turn MCP servers OFF for this run (default: leave them ON).
#   -h          Help.
#
# Always Fugu Ultra. The model is fixed to fugu-ultra (codex-fugu defaults to
# plain `fugu`); there is intentionally no model flag.
#
# MCP is left ON by default. codex-fugu starts the MCP servers in
# ~/.codex/config.toml; servers that are not logged in print harmless
# `Auth required` warnings at shutdown but do not block (measured overhead is a
# couple of seconds, immaterial for a long-running oracle). We just filter that
# cosmetic noise. Use -n only if you have an MCP server that genuinely hangs;
# -n runs with a temp CODEX_HOME that strips all [mcp_servers.*] from config.toml
# (note: `-c mcp_servers="{}"` does NOT work in exec mode because codex
# deep-merges config). -n requires python3.
#
# Permission posture (read this — true inheritance is impossible):
#   codex does NOT expose the parent agent's approval/sandbox policy to child
#   processes, so the oracle cannot truly "inherit" the parent's flags. It only
#   sees CODEX_SANDBOX / CODEX_SANDBOX_NETWORK_DISABLED. We approximate:
#     - SUPER_ORACLE_SANDBOX=read-only|workspace-write|danger-full-access wins.
#     - Else SUPER_ORACLE_BYPASS=1 forces bypass; =0 forces workspace-write.
#     - Else if a Codex sandbox signal is present (CODEX_SANDBOX is a backend
#       marker like "seatbelt", or the network-disabled flag is set), stay
#       conservative with --sandbox workspace-write rather than escalating.
#     - Else default to --dangerously-bypass-approvals-and-sandbox (unattended).
#   For pure review/advice runs, prefer SUPER_ORACLE_SANDBOX=read-only.
set -euo pipefail

MODEL="fugu-ultra"; OUTPUT=""; WORKDIR=""; DISABLE_MCP=0
usage() { sed -n '2,46p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while getopts ":o:C:nh" opt; do
  case "$opt" in
    o) OUTPUT="$OPTARG" ;; C) WORKDIR="$OPTARG" ;;
    n) DISABLE_MCP=1 ;; h) usage 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage 1 ;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage 1 ;;
  esac
done
shift $((OPTIND - 1))

[ -z "$OUTPUT" ] && { echo "ERROR: -o OUTPUT is required" >&2; usage 1; }

# Normalize output to an absolute path now, before any cd, so -C and relative
# paths behave predictably (output lands relative to the caller's cwd).
ORIGPWD="$(pwd)"
case "$OUTPUT" in /*) ;; *) OUTPUT="$ORIGPWD/$OUTPUT" ;; esac
OUTDIR="$(dirname "$OUTPUT")"
[ -d "$OUTDIR" ] || { echo "ERROR: output directory not found: $OUTDIR" >&2; exit 1; }

[ "$#" -le 1 ] || { echo "ERROR: expected at most one briefing file" >&2; usage 1; }
BRIEFING_SRC=""
if [ "$#" -ge 1 ] && [ "$1" != "-" ]; then
  BRIEFING_SRC="$1"
  case "$BRIEFING_SRC" in /*) ;; *) BRIEFING_SRC="$ORIGPWD/$BRIEFING_SRC" ;; esac
  [ -f "$BRIEFING_SRC" ] || { echo "ERROR: briefing not found: $BRIEFING_SRC" >&2; exit 1; }
  if [ -e "$OUTPUT" ] && [ "$OUTPUT" -ef "$BRIEFING_SRC" ]; then
    echo "ERROR: output must not be the same file as the briefing" >&2; exit 1
  fi
fi

# Clear any stale output now, before the failure-prone setup below (missing
# dependency, -n rewrite, cd, run), so a failed invocation can never be mistaken
# for a prior success by an output-based caller.
: > "$OUTPUT" || { echo "ERROR: cannot write output: $OUTPUT" >&2; exit 1; }

command -v codex-fugu >/dev/null 2>&1 || {
  echo "ERROR: codex-fugu not found. Install: https://console.sakana.ai/get-started" >&2; exit 127; }

# --- Resolve permission posture (see header) -------------------------------
valid_sandbox() {
  case "$1" in read-only|workspace-write|danger-full-access) return 0 ;; *) return 1 ;; esac
}
if [ -n "${SUPER_ORACLE_BYPASS:-}" ] && [ "$SUPER_ORACLE_BYPASS" != "0" ] && [ "$SUPER_ORACLE_BYPASS" != "1" ]; then
  echo "ERROR: SUPER_ORACLE_BYPASS must be 0 or 1" >&2; exit 2
fi
POSTURE_ARGS=()
if [ -n "${SUPER_ORACLE_SANDBOX:-}" ]; then
  valid_sandbox "$SUPER_ORACLE_SANDBOX" || {
    echo "ERROR: SUPER_ORACLE_SANDBOX must be read-only, workspace-write, or danger-full-access" >&2; exit 2; }
  POSTURE_ARGS=(--sandbox "$SUPER_ORACLE_SANDBOX")
elif [ "${SUPER_ORACLE_BYPASS:-}" = "1" ]; then
  POSTURE_ARGS=(--dangerously-bypass-approvals-and-sandbox)
elif [ "${SUPER_ORACLE_BYPASS:-}" = "0" ]; then
  POSTURE_ARGS=(--sandbox workspace-write)
elif [ -n "${CODEX_SANDBOX:-}" ] || [ "${CODEX_SANDBOX_NETWORK_DISABLED:-}" = "1" ]; then
  # Parent already sandboxed us. CODEX_SANDBOX is a backend marker (e.g.
  # "seatbelt"), not a --sandbox policy value, so treat it as a boolean signal
  # and stay conservative instead of escalating to a full bypass.
  POSTURE_ARGS=(--sandbox workspace-write)
else
  POSTURE_ARGS=(--dangerously-bypass-approvals-and-sandbox)   # unattended default
fi

# --- Optionally turn MCP off via a temp CODEX_HOME (only with -n) ----------
REAL_HOME="${CODEX_HOME:-$HOME/.codex}"; TMPHOME=""
cleanup() { [ -n "$TMPHOME" ] && rm -rf "$TMPHOME"; return 0; }
trap cleanup EXIT
if [ "$DISABLE_MCP" -eq 1 ] && [ -f "$REAL_HOME/config.toml" ]; then
  command -v python3 >/dev/null 2>&1 || {
    echo "ERROR: -n requires python3 to rewrite config.toml" >&2; exit 127; }
  TMPHOME="$(mktemp -d "${TMPDIR:-/tmp}/fugu-home.XXXXXX")"
  shopt -s dotglob nullglob 2>/dev/null || true
  for f in "$REAL_HOME"/*; do
    base="$(basename "$f")"; [ "$base" = "config.toml" ] && continue
    ln -sfn "$f" "$TMPHOME/$base"
  done
  shopt -u dotglob nullglob 2>/dev/null || true
  python3 - "$REAL_HOME/config.toml" "$TMPHOME/config.toml" <<'PY'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
skip = False; out = []
for line in open(src, encoding="utf-8").read().splitlines(keepends=True):
    m = re.match(r'^\s*\[\s*([A-Za-z0-9_.-]+)', line)
    if m:
        name = m.group(1)
        skip = name == "mcp_servers" or name.startswith("mcp_servers.")
    if not skip:
        out.append(line)
open(dst, "w", encoding="utf-8").write("".join(out))
PY
  export CODEX_HOME="$TMPHOME"
fi

run() {
  codex-fugu exec --ephemeral "${POSTURE_ARGS[@]}" --skip-git-repo-check \
    -c model="$MODEL" -o "$OUTPUT" -
}

[ -n "$WORKDIR" ] && cd "$WORKDIR"
[ "$DISABLE_MCP" -eq 1 ] && MCP_STATE="off" || MCP_STATE="on"
echo ">> super-oracle: model=$MODEL mcp=$MCP_STATE posture=${POSTURE_ARGS[*]} cwd=$(pwd)" >&2

# Filter the harmless MCP auth/shutdown noise from displayed stderr. Patterns are
# kept narrow so real errors still surface.
FILTER='(MCP client during shutdown|OAuth authorization required|Token refresh not possible|Auth required)'

# A misconfigured/expired MCP server can make codex-fugu exit non-zero even
# though the oracle answered fine. Judge success by whether output was produced,
# not by codex's exit code (so a broken MCP never breaks a good run).
set +e
if [ -n "$BRIEFING_SRC" ]; then
  run < "$BRIEFING_SRC" 2> >(grep -Ev "$FILTER" >&2)
else
  run 2> >(grep -Ev "$FILTER" >&2)
fi
rc=$?
set -e

if [ ! -s "$OUTPUT" ]; then
  echo "ERROR: oracle produced no output (codex-fugu exit $rc; some MCP noise may have been filtered)" >&2
  exit 1
fi
[ "$rc" -ne 0 ] && echo ">> super-oracle: note: codex-fugu exited $rc (likely an MCP server issue); answer was still produced" >&2
echo ">> super-oracle: done. Wrote $OUTPUT" >&2
