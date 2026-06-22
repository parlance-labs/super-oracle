---
name: super-oracle
description: "Consult codex-fugu (Sakana Fugu Ultra, an ensemble of frontier models) as a second-opinion oracle for deep code review, hard cross-file debugging, architecture and refactor planning, and research synthesis. Use like a built-in oracle when you want a stronger reasoning model than the main agent. Triggers on: super oracle, codex-fugu, fugu ultra, deep review, second opinion."
---

# Super Oracle (codex-fugu / Fugu Ultra)

A second-opinion oracle for hard reasoning — code review, multi-file debugging,
architecture decisions, and research synthesis. It runs on **Sakana Fugu Ultra**
(a learned orchestrator over frontier models) via the **`codex-fugu` CLI**, so it
is not wired into your harness. You drive it with a file protocol: write a
self-contained briefing, run the script, read the markdown answer. Treat its
output as advice and verify load-bearing claims.

Use it for the hard 10% (subtle correctness, architecture, "what am I missing").
Do not use it for file reads, searches, or routine edits — do those directly.

## Invoke

```bash
scripts/super-oracle.sh -o /abs/path/oracle-out.md /abs/path/briefing.md
```

Then read the output file and act on it. The script forces Fugu Ultra, turns MCP
off, and picks a safe permission posture automatically (see below).

## Write a good briefing (this determines quality)

The oracle has **zero prior context**. A terse prompt yields generic output.
Include: the goal and your role for it; the absolute working dir; files/PRs to
read first; the one sharp question; what you already ruled out; constraints and
non-goals; and the expected output shape (verdict first, then findings with
`file:line` and exact fixes, demanding verbatim evidence). Tell it that it may
spawn its own subagents to parallelize. See `reference/briefing-template.md`.

## Foot-guns (the reasons this script exists)

- **Always Fugu Ultra.** `codex-fugu` defaults to plain `fugu` on a stock
  install. The script forces `-c model=fugu-ultra`; do not drop it.
- **MCP is off by default.** `-c mcp_servers="{}"` does NOT disable MCP in
  `exec` mode (codex deep-merges). The script instead runs with a temp
  `CODEX_HOME` that strips `[mcp_servers.*]` from `config.toml`, killing the
  `Auth required` churn while keeping the Sakana provider, profile, auth, and
  catalog. Pass `-k` only if a run truly needs an MCP server.
- **Fugu Ultra is slow.** Deep orchestration takes minutes. Do not wrap in
  `timeout` (absent on macOS); let it finish.
- **Fresh context every call.** Re-supply everything; there is no cross-call
  memory.
- **Permission posture is approximated, not inherited.** codex does not expose
  the parent agent's approval/sandbox policy to child processes. The script:
  uses `SUPER_ORACLE_SANDBOX` if set; else stays conservative
  (`--sandbox workspace-write`) when it detects it is already inside a Codex
  sandbox; else defaults to `--dangerously-bypass-approvals-and-sandbox` for
  unattended use. Override with `SUPER_ORACLE_BYPASS=0|1`.

## Consume the output

Read the answer, verify the load-bearing claims, apply must-fixes, weigh
optionals, reject what is wrong. For an approval loop, fix then re-run a short
confirmation briefing. Keep briefing/answer files (date-stamped) as an audit trail.
