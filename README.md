# AI agent skill for parkrun results

![Format](https://img.shields.io/badge/format-Agent%20Skill-blue)
![Bash](https://img.shields.io/badge/bash-%23121011?logo=gnu-bash&logoColor=white)
![License](https://img.shields.io/github/license/andrewbearsley/parkrun-skill)

Monitor [parkrun](https://www.parkrun.com.au/) results from the public athlete results page. Built as an [OpenClaw](https://openclaw.ai) skill, but the scripts work fine standalone too.

Tracks run history, finish times, positions, age grading, PBs, and event tourism. Reads the public parkrun website directly — no API key or authentication needed.

## Agent quick-start

If you're an AI agent and your user has pointed you at this repo, here's how to install the skill without cloning.

**Requirements:** `curl`, `awk`, `sed` must be available on the system.

**1. Download the skill and scripts:**

```bash
REPO="https://raw.githubusercontent.com/andrewbearsley/parkrun-skill/main"
SKILL_DIR="$HOME/.openclaw/skills/parkrun"
SCRIPT_DIR="$SKILL_DIR/scripts"

mkdir -p "$SCRIPT_DIR"
curl -fsSL "$REPO/skills/parkrun/SKILL.md"         -o "$SKILL_DIR/SKILL.md"
curl -fsSL "$REPO/scripts/parkrun-status.sh"        -o "$SCRIPT_DIR/parkrun-status.sh"
chmod +x "$SCRIPT_DIR"/*.sh
```

**2. Set environment variables:**

The skill requires one environment variable. Ask your user for this if they haven't provided it:

| Variable | Required | What it is | Where to find it |
|----------|----------|-----------|-----------------|
| `PARKRUN_ATHLETE_ID` | Yes | Numeric athlete ID | Your parkrun profile URL: `parkrun.com.au/parkrunner/{ID}` |
| `PARKRUN_DOMAIN` | No | parkrun country domain (default: `www.parkrun.com.au`) | Depends on where you're registered |

Set them in `~/.openclaw/.env` or in your agent's environment.

**3. Verify it works:**

```bash
# Check recent results
$SCRIPT_DIR/parkrun-status.sh

# Check JSON output
$SCRIPT_DIR/parkrun-status.sh --json

# Check summary stats
$SCRIPT_DIR/parkrun-status.sh --summary
```

**4. Read the SKILL.md** for full details, alert thresholds, and heartbeat behaviour. Everything the agent needs is in that file.

## What it does

- Recent parkrun results (event, time, position, age grade, PBs)
- Summary stats (fastest, average, slowest times and age grades)
- Annual best times and age grades
- Event tourism stats (unique events visited, count per event)
- Heartbeat monitoring that stays quiet unless something's noteworthy

## Human setup

No developer accounts, API keys, or OAuth flows needed.

### 1. Find your athlete ID

Your athlete ID is the number in your parkrun profile URL. For example, if your profile is `https://www.parkrun.com.au/parkrunner/2682215/`, your ID is `2682215`.

You can also find it on your parkrun barcode or in your parkrun profile settings.

### 2. Set the environment variable

```bash
export PARKRUN_ATHLETE_ID=2682215
```

For a different country, also set the domain:

```bash
export PARKRUN_DOMAIN=www.parkrun.org.uk
```

### 3. Give your agent the credentials

Add the environment variable to `~/.openclaw/.env`:

```
PARKRUN_ATHLETE_ID=2682215
PARKRUN_DOMAIN=www.parkrun.com.au
```

Then point your agent at this repo and ask it to install the skill.

## Usage

### Results

```bash
./scripts/parkrun-status.sh              # Formatted summary (last 10 results)
./scripts/parkrun-status.sh --raw        # Raw HTML from the results page
./scripts/parkrun-status.sh --json       # Parsed results as JSON
./scripts/parkrun-status.sh --all        # All results
./scripts/parkrun-status.sh --count 5    # Last 5 results
./scripts/parkrun-status.sh --summary    # Summary stats + annual achievements
./scripts/parkrun-status.sh --tourism    # Unique events visited
```

### Heartbeat

If your agent supports heartbeat checks:

```markdown
- [ ] Check parkrun via the parkrun skill. If there's a new result since the
      last check, include a brief summary (event, time, position). Alert me if
      the page is unreachable. Don't message me if there's nothing new.
```

## What it alerts on

| Condition | Severity |
|-----------|----------|
| No parkrun in 14 days | Medium |
| HTTP 403 (site blocking requests) | Medium |
| HTTP 404 (athlete not found) | Medium |
| HTML structure changed | Medium |

All thresholds are configurable in `SKILL.md`. The skill stays quiet when everything's normal.

## Troubleshooting

| Problem | What's going on | Fix |
|---------|-----------------|-----|
| "PARKRUN_ATHLETE_ID environment variable is not set" | Env var not loaded | Set `PARKRUN_ATHLETE_ID` in your environment |
| HTTP 403 | Site is blocking automated requests | Check the URL manually in a browser; the user-agent may need updating |
| HTTP 404 | Wrong athlete ID or wrong country domain | Verify by visiting `https://{domain}/parkrunner/{id}/all/` |
| "Unexpected page structure" | parkrun changed their HTML | Check the page manually; the parser may need updating |
| Results from wrong country | Wrong `PARKRUN_DOMAIN` | Set `PARKRUN_DOMAIN` to the correct country (e.g. `www.parkrun.org.uk`) |

## Data source

This skill reads the public parkrun results page. There is no official parkrun API for athlete results (the previous athlete endpoint was deprecated and the replacement is on hold). One HTTP request per invocation.

## Files

| File | Purpose |
|------|---------|
| `skills/parkrun/SKILL.md` | Skill definition: data source details, alert thresholds, agent instructions |
| `scripts/parkrun-status.sh` | Fetch and display parkrun results |
| `HEARTBEAT.md` | Heartbeat config template |

## License

MIT
