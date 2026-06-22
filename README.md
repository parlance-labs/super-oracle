# Super Oracle

A **second-opinion oracle** for coding agents, powered by **Sakana Fugu Ultra**
(a learned orchestrator over frontier models) through the **`codex-fugu`** CLI.

Use it for the hard 10% of work — subtle code review, cross-file debugging,
architecture and refactor decisions, and research synthesis — when you want a
stronger reasoning model than your main agent. It is delivered as a **skill**, so
it works in any coding agent that can run a shell, and it is **packaged as a
plugin** for Codex and Claude Code.

Sakana recommends running Fugu through an OpenAI-style harness; `codex-fugu`
(OpenAI Codex CLI wired to the Sakana API) is that harness, which is why this
oracle is built on it.

## Prerequisites

- [`codex-fugu`](https://sakana.ai/fugu) installed and authenticated:
  ```bash
  curl -fsSL https://sakana.ai/fugu/install | bash
  ```
  This sets up the Sakana provider and your `SAKANA_API_KEY` for the Codex CLI.

## Install

### Codex CLI

```bash
codex plugin marketplace add parlance-labs/super-oracle
# then open the plugin directory and install "Super Oracle"
codex /plugins
```

### Claude Code

```bash
claude plugin marketplace add parlance-labs/super-oracle
claude plugin install super-oracle@parlance-labs
```

Or inside Claude Code: `/plugin marketplace add parlance-labs/super-oracle`
then `/plugin install super-oracle@parlance-labs`.

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
writes the answer to the `-o` file, and picks a safe permission posture. See the
skill's `reference/briefing-template.md` for how to write an effective briefing.

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
  (`--sandbox workspace-write`) when it detects it is already inside a Codex
  sandbox; else defaults to `--dangerously-bypass-approvals-and-sandbox`.
  Override with `SUPER_ORACLE_BYPASS=0|1`.
- **Success = output produced, not exit code.** A broken/expired MCP server can
  make `codex-fugu` exit non-zero even when the answer is fine. The script judges
  success by whether the `-o` file is non-empty, so a bad MCP never breaks a good
  run.
- **Fugu Ultra is slow** (deep orchestration). Expect minutes; do not wrap in
  `timeout`.

## Test

A fast, cheap smoke test (one trivial prompt) confirms codex-fugu works, runs on
fugu-ultra, returns the expected output, and reports any MCP noise that leaked
past the filter (informational only):

```bash
scripts/smoke-test.sh
```

It exits 0 on success, skips cleanly if `codex-fugu` is not installed, and fails
loudly otherwise.

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

## License

MIT — see [LICENSE](LICENSE).
