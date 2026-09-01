# claude-statusline

A status line for [Claude Code](https://code.claude.com) that shows, on one line:

```
Fable 5 | xhigh | ctx 14% (144k/1M) | $8.90 | 5h 8% (39m) · 7d 74% (2d9h) · fable 67% (2d9h) left
```

- **Model name** (cyan) — the session's active model
- **Effort level** (magenta), with a yellow `⚡ULTRA` badge when ultracode is detected
- **Context usage** — percent of the context window used plus tokens/window size, color-coded (green < 50%, yellow ≥ 50%, red ≥ 80%)
- **Session cost** — the running API-equivalent dollar estimate for the current session
- **Subscription usage remaining** — percent **left** (not used) for the 5-hour and weekly limits, plus the model-scoped weekly limit (e.g. Fable), each with a dim countdown to its reset (`39m`, `3h12m`, `2d9h`). Colors: green > 40% left, yellow ≤ 40%, red ≤ 15%.

## Install

```sh
cp statusline.sh ~/.claude/statusline.sh
```

Then point Claude Code at it in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh"
  }
}
```

## Requirements

- Linux with GNU coreutils (`date -d`, `stat -c`) — macOS would need BSD-compatible tweaks
- `jq` and `curl`
- A Claude subscription login (`~/.claude/.credentials.json`) for the model-scoped weekly segment; everything else works without it

## How the model-scoped (Fable) segment works

Claude Code's status line payload only exposes the subscription-wide 5-hour and
weekly buckets. The per-model weekly limit shown by `/usage` comes from an
**undocumented** OAuth endpoint (`GET https://api.anthropic.com/api/oauth/usage`).
The script queries it with the local Claude Code OAuth token, caches the response
at `~/.cache/claude-statusline-usage.json` for 60 seconds, and refreshes it in a
background subshell so rendering never blocks on the network.

Caveats:

- The endpoint is undocumented and may change or disappear; if the fetch fails,
  the model-scoped segment silently drops out and the rest keeps working.
- The token is read from `~/.claude/.credentials.json` and sent only to
  `api.anthropic.com` over HTTPS — the same call Claude Code makes for `/usage`.
- Ultracode isn't exposed to status lines at all; the badge lights on an
  `ultracode: true` payload field (future-proofing) or `effort.level == "max"`,
  so it can stay dark on versions that report neither.

Every field degrades gracefully: missing payload fields render as `?`/`0`, and
absent rate limits (e.g. API-key billing) hide the usage segment entirely.
