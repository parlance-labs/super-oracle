# Super Oracle

A **second-opinion oracle** for coding agents, powered by
[Sakana Fugu Ultra](https://console.sakana.ai/models) (an orchestrator over
frontier models) through the [`codex-fugu`](https://console.sakana.ai/get-started)
CLI.

It ships as a **skill** (works in any agent with a shell) packaged as a **plugin**
for Codex and Claude Code.

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

Or symlink `plugins/super-oracle/skills/super-oracle` into `~/.config/agents/skills/`.

## Use

Ask your agent to "use the super oracle" for a review/plan/debug task, or call
the script directly:

```bash
plugins/super-oracle/skills/super-oracle/scripts/super-oracle.sh \
  -o oracle-out.md briefing.md
```

It writes the answer to the `-o` file. See the skill's
`reference/briefing-template.md` for how to write an effective briefing, and
[Options](#options) for flags.

## Options

| Flag / env | Effect |
|---|---|
| `-o FILE` | Where the answer is written (required). |
| `-n` | Turn MCP servers off for this run (default: on). |
| `-C DIR` | Working directory for the oracle. |
| `SUPER_ORACLE_SANDBOX=read-only` | Recommended for review-only runs. |
| `SUPER_ORACLE_BYPASS=0\|1` | Force `workspace-write` / full bypass. |

Always runs `fugu-ultra`. Expect minutes per call, so don't wrap it in `timeout`.

## License

MIT. See [LICENSE](LICENSE).
