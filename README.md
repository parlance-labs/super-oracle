# Super Oracle

A **second-opinion oracle** for coding agents, powered by
[Sakana Fugu Ultra](https://console.sakana.ai/models) (an orchestrator over
frontier models) through the [`codex-fugu`](https://console.sakana.ai/get-started)
CLI. Your main agent shells out to it for the hard 10% — subtle review, cross-file
debugging, architecture calls — when you want a stronger model.

It ships as a **skill** (works in any agent with a shell) packaged as a **plugin**
for Codex and Claude Code.

> Invoke it *from* Codex, Claude Code, or Amp — not from inside a `codex-fugu`
> session.

## Prerequisites

- [`codex-fugu`](https://console.sakana.ai/get-started) installed and
  authenticated (see Sakana's
  [Get Started docs](https://console.sakana.ai/get-started)):
  ```bash
  curl -fsSL https://sakana.ai/fugu/install | bash
  ```
- `codex-fugu` must be on the `PATH` of the process running your agent. Launch
  the agent from a shell where `codex-fugu --version` works (GUI-launched agents
  may not inherit it).

## Install

### Codex CLI

```bash
codex plugin marketplace add parlance-labs/super-oracle
codex plugin add super-oracle@parlance-labs
```

### Claude Code

```bash
claude plugin marketplace add parlance-labs/super-oracle
claude plugin install super-oracle@parlance-labs
```

Or inside Claude Code: `/plugin marketplace add parlance-labs/super-oracle`
then `/plugin install super-oracle@parlance-labs`. Run `/reload-plugins` (or
restart Claude Code) to activate it.

### Amp (or any agent that uses SKILL.md)

Amp uses skills, not Codex/Claude plugins. Point Amp at the bundled skill:

```bash
git clone https://github.com/parlance-labs/super-oracle
# add to ~/.config/amp/settings.json:
#   "amp.skills.path": "/path/to/super-oracle/plugins/super-oracle/skills"
```

…or symlink `plugins/super-oracle/skills/super-oracle` into `~/.config/agents/skills/`.

## Use

Ask your agent to "use the super oracle" for a review/plan/debug task, or call
the script directly:

```bash
plugins/super-oracle/skills/super-oracle/scripts/super-oracle.sh \
  -o oracle-out.md briefing.md
```

The script always uses `fugu-ultra`, leaves your MCP servers on (see below),
writes the answer to the `-o` file, and picks an unattended permission posture
(see below). See the skill's `reference/briefing-template.md` for how to write an
effective briefing.

## Design notes (the foot-guns this encodes)

- **Always Fugu Ultra.** `codex-fugu` defaults to plain `fugu`; the script forces
  `-c model=fugu-ultra`.
- **MCP left on by default.** Unauthenticated MCP servers print harmless
  `Auth required` warnings at shutdown but don't block — measured overhead is ~2s,
  immaterial for a long-running oracle — so the script leaves your MCP servers on
  and just filters the cosmetic noise. Pass `-n` to turn MCP off if a server
  genuinely hangs. (`-c mcp_servers="{}"` does *not* disable MCP in `exec` mode
  because codex deep-merges; `-n` strips `[mcp_servers.*]` via a temp `CODEX_HOME`.)
- **Permission posture is approximated, not inherited.** Codex does not expose
  the parent agent's approval/sandbox policy to child processes (only
  `CODEX_SANDBOX` / `CODEX_SANDBOX_NETWORK_DISABLED`). The script uses
  `SUPER_ORACLE_SANDBOX` if set; else stays conservative
  (`--sandbox workspace-write`) when it detects a Codex sandbox signal
  (`CODEX_SANDBOX` is a backend marker like `seatbelt`, not a policy value); else
  defaults to `--dangerously-bypass-approvals-and-sandbox`. Force with
  `SUPER_ORACLE_BYPASS=0|1`. For review-only runs, set
  `SUPER_ORACLE_SANDBOX=read-only`.
- **Success = output produced, not exit code.** A broken/expired MCP server can
  make `codex-fugu` exit non-zero even when the answer is fine. The script judges
  success by whether the `-o` file is non-empty, so a bad MCP never breaks a good
  run.
- **Fugu Ultra is slow** (deep orchestration). Expect minutes; do not wrap in
  `timeout`.

## Test

A minimal-token smoke test confirms `codex-fugu` works and runs on `fugu-ultra`.
It's cheap, not necessarily fast (Fugu Ultra can take a while). Exits 0 on
success, skips if `codex-fugu` isn't installed.

```bash
scripts/smoke-test.sh
```

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

## Releasing

Marketplace installs key updates off the plugin `version`. Bump `version` in both
`plugins/super-oracle/.codex-plugin/plugin.json` and `.claude-plugin/plugin.json`
on every published change (and tag the release) so installed copies update.

## License

MIT — see [LICENSE](LICENSE).
