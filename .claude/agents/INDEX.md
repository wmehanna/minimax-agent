# Claude Code - Agent Index

## Available Agents

| Agent | Path | Description |
|-------|------|-------------|
| `autonomous-loop` | `.claude/agents/autonomous-loop/prompt.md` | Self-running agent that picks up GitHub Issues and processes them continuously |

## Usage

```bash
# Trigger autonomous loop manually
openclaw agent --message "/autonomous-loop" --expect-final

# Via cron (every 15 min)
openclaw cron add --every 15m --message "/autonomous-loop" --expect-final --announce --to 1618533723 --name "minimax-agent-autonomous"
```
