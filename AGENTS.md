# Dev notes

Rationale and foot-guns behind `scripts/super-oracle.sh`. Keep this out of the
README (user-facing) — it's for maintainers.

## Repository layout

```
super-oracle/
├── .agents/plugins/marketplace.json      # Codex marketplace
├── .claude-plugin/marketplace.json       # Claude Code marketplace
├── plugins/super-oracle/
│   ├── .codex-plugin/plugin.json         # Codex manifest
│   ├── .claude-plugin/plugin.json        # Claude manifest
│   └── skills/super-oracle/              # the portable skill (used by Amp too)
│       ├── SKILL.md
│       ├── reference/briefing-template.md
│       └── scripts/super-oracle.sh
└── scripts/smoke-test.sh
```

## Test

A minimal-token smoke test confirms `codex-fugu` works and runs on `fugu-ultra`.
Cheap, not necessarily fast. Exits 0 on success, skips if `codex-fugu` isn't
installed.

```bash
scripts/smoke-test.sh
```

## Always Fugu Ultra
`codex-fugu` defaults to plain `fugu`. The script forces `-c model=fugu-ultra`
and intentionally exposes no model flag.

## MCP left on by default
Unauthenticated MCP servers print harmless `Auth required` warnings at shutdown
but don't block — measured overhead ~2s, immaterial for a long-running oracle.
So we leave MCP on and just filter the cosmetic stderr noise. `-n` turns it off
for a server that genuinely hangs.

`-c mcp_servers="{}"` does NOT disable MCP in `exec` mode (codex deep-merges
config). `-n` instead runs with a temp `CODEX_HOME` whose `config.toml` has all
`[mcp_servers.*]` tables stripped (requires `python3`).

## Permission posture is approximated, not inherited
Codex does not expose the parent's approval/sandbox policy to children — only
`CODEX_SANDBOX` and `CODEX_SANDBOX_NETWORK_DISABLED`. `CODEX_SANDBOX` is a
backend marker (`seatbelt` on macOS), NOT a `--sandbox` policy value, so it can't
be passed through. Logic:

1. `SUPER_ORACLE_SANDBOX` (validated) wins.
2. `SUPER_ORACLE_BYPASS=1` → bypass; `=0` → `workspace-write`.
3. Else any `CODEX_SANDBOX` / `CODEX_SANDBOX_NETWORK_DISABLED` signal → stay
   conservative (`workspace-write`), never escalate.
4. Else (unattended) → `--dangerously-bypass-approvals-and-sandbox`.

## Success = output produced, not exit code
A broken/expired MCP server can make `codex-fugu` exit non-zero even when the
answer is fine. The script judges success by whether the `-o` file is non-empty.
The `-o` file is truncated before any failure-prone step (missing dependency,
`-n` rewrite, `cd`, run) so a stale file can never look like success.

The post-run tail intentionally runs under `set +e` and ends with an explicit
`exit 0`. Reason (found by dogfooding): with `set -e`, a benign `[ test ] && echo`
short-circuit can make a *successful* run exit non-zero, so callers that chain on
the exit code break. Because the tail has no `set -e`, every operation that must
not fail silently (recovering `answer.md` into `-o`, enumerating artifacts,
appending the manifest) is guarded with an explicit `if ! ...; then ... exit 1`.
Keep that pattern when editing the tail; do not re-add `set -e` there.

## Two-channel output (control plane vs data plane)
`codex-fugu`'s `-o` captures ONLY the final assistant message. A long answer the
oracle writes to a file would otherwise be lost (and an earlier review run was
wasted when such a file got deleted as "stray output"). Fix:

- **Control plane** = `-o`: the script prepends an output contract telling the
  oracle to put its full answer in the final message.
- **Data plane** = `SUPER_ORACLE_ARTIFACTS_DIR` (default `OUTPUT.artifacts`):
  the only sanctioned place for supporting files. Cleared/recreated each run,
  removed at the end if empty so it doesn't litter.

Robustness: if `-o` is empty but `$ARTIFACTS_DIR/answer.md` exists it's recovered
into `-o`; any artifacts are listed as a manifest appended to `-o` with a
"do not delete before reading" note. Never treat oracle-emitted files as
disposable.

Footgun (found by real runs, not fakes): the oracle runs with our perms and sees
the exported `$SUPER_ORACLE_ARTIFACTS_DIR`, so it can delete its own artifacts dir
mid-run. The tail therefore treats a MISSING artifacts dir as "no artifacts" (not
an error); only a `find` failure on a dir that still exists is fatal. An earlier
"wrapper exits 1 on a successful real run" mystery was exactly this.

## Progress heartbeat
A long run feels dead without feedback, so a background `heartbeat` prints to
stderr every `SUPER_ORACLE_PROGRESS_INTERVAL` seconds (default 120; `-p`
overrides; `0` disables). It reports elapsed time, idle time, and the oracle's
latest output line, read from a temp log that mirrors the filtered stderr. It is
started right before the run and `stop_heartbeat`'d right after (also in
`cleanup`), and writes only to stderr so `-o` is never touched.

Footgun (found by a tmux test, not unit tests): the stderr filter MUST use `grep
--line-buffered`. Without it grep block-buffers when its stdout is a pipe, so the
oracle's reasoning shows up in one clump at the end and the heartbeat log stays
empty (no latest line, wrong idle time). Keep `--line-buffered` on `GREP_LB`.

## Releasing
Marketplace installs key updates off the plugin `version`. Bump `version` in both
`plugins/super-oracle/.codex-plugin/plugin.json` and
`plugins/super-oracle/.claude-plugin/plugin.json` on every published change and
tag the release.
