# Dev notes

Rationale and foot-guns behind `scripts/super-oracle.sh`. Keep this out of the
README (user-facing) — it's for maintainers.

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

## Releasing
Marketplace installs key updates off the plugin `version`. Bump `version` in both
`plugins/super-oracle/.codex-plugin/plugin.json` and
`plugins/super-oracle/.claude-plugin/plugin.json` on every published change and
tag the release.
