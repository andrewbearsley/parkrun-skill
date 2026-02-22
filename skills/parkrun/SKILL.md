---
name: parkrun
description: Monitor parkrun results by scraping the public athlete results page.
version: 1.0.0
homepage: https://github.com/andrewbearsley/openclaw-parkrun
metadata: {"openclaw": {"requires": {"bins": ["curl", "awk", "sed"], "env": ["PARKRUN_ATHLETE_ID"]}, "primaryEnv": "PARKRUN_ATHLETE_ID"}}
---

# parkrun Skill

You can monitor parkrun results by scraping the public athlete results page. This skill scrapes the athlete's "all results" page to extract run history, PBs, and event tourism stats.

**Data Source:** Public HTML page at `https://{domain}/parkrunner/{id}/all/`
**Authentication:** None required. parkrun results pages are public. Just need the athlete ID.

**Important:** There is no official parkrun API for athlete results. This skill scrapes the public HTML page. Limit to one request per invocation — no rapid polling.

**Script paths:** All `scripts/` paths below are relative to the skill's install directory. If installed via the agent quick-start, that's `~/.openclaw/skills/parkrun/scripts/`. Adjust paths based on where you installed the skill.

**All times are in MM:SS or HH:MM:SS format as displayed on the parkrun website.**

---

## Configuration

These are the default alert thresholds. The user may edit them here to suit their preferences.

**Result staleness:**
- No parkrun in **14 days**: medium alert (parkrun is weekly, so 14 days = 2 missed weeks)

**Domain:**
- Default: `www.parkrun.com.au`
- Configurable via `PARKRUN_DOMAIN` environment variable
- Other countries: `www.parkrun.org.uk`, `www.parkrun.co.za`, `www.parkrun.us`, etc.

---

## Error Handling

The scrape can fail in several ways. Handle each:

### HTTP errors

| Error | Handling |
|-------|----------|
| HTTP 403 (Forbidden) | The site is blocking the request. The user-agent header may need updating. Alert: "parkrun page returned 403 — try visiting the URL manually to check." |
| HTTP 404 (Not found) | Wrong athlete ID or domain. Alert: "parkrun athlete not found — check PARKRUN_ATHLETE_ID and PARKRUN_DOMAIN." |
| Connection timeout / network error | Log and skip this check. Alert if it persists across multiple heartbeats. |
| Unexpected HTML structure | The expected table headers (`Run Date`, `Run Number`, etc.) are missing. Alert: "parkrun page structure may have changed — the scraper could not find the results table." |

### Common setup issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| "PARKRUN_ATHLETE_ID environment variable is not set" | Env var not loaded | Set `PARKRUN_ATHLETE_ID` in the environment |
| HTTP 404 | Wrong athlete ID or wrong domain | Verify the ID by visiting `https://{domain}/parkrunner/{id}/all/` in a browser |
| No results parsed | HTML structure changed | Check the page manually; the scraper may need updating |
| Results from wrong country | Wrong domain | Set `PARKRUN_DOMAIN` to the correct country domain (e.g. `www.parkrun.org.uk`) |

---

## Data Available

The athlete results page contains three tables:

### 1. Summary Stats

Fastest, average (mean), and slowest values for:
- **Time** — e.g. 27:09 / 41:34 / 01:00:32
- **Age Grading** — e.g. 52.96% / 37.50% / 24.37%
- **Overall Position** — e.g. 11 / 164.64 / 428

### 2. Annual Achievements

Best time and best age grade per year. One row per year the athlete has a result.

### 3. All Results

Every parkrun the athlete has completed, most recent first. Each row contains:

| Field | Example |
|-------|---------|
| Event | Chelsea Bicentennial |
| Run Date | 31/01/2026 |
| Run Number | 432 |
| Position | 346 |
| Time | 48:27 |
| Age Grade | 31.20% |
| PB? | PB (or empty) |

Plus header info: athlete name, total parkrun count, age category, club memberships (100 club etc.).

---

## Scraping Details

```bash
# Easiest: use the helper script
scripts/parkrun-status.sh --json

# Or fetch manually:
curl -s -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
  "https://www.parkrun.com.au/parkrunner/2682215/all/" --max-time 30
```

**Key points:**
- A browser-style User-Agent header is required or the site returns 403.
- The page returns all results in a single HTML response (no pagination).
- Results are in a `<table>` with headers: Event, Run Date, Run Number, Pos, Time, Age Grade, PB?
- Event names are extracted from link text within the first `<td>`.
- Dates are in `dd/mm/yyyy` format inside a `<span class="format-date">`.
- The PB column contains the text "PB" for personal bests, or is empty.

---

## Heartbeat Behaviour

When this skill is invoked during a heartbeat check, follow this procedure:

### 1. Fetch results

```bash
scripts/parkrun-status.sh --json --count 1
```

This fetches the page and returns the most recent result as JSON. One HTTP request to parkrun.

### 2. Check for errors

If the script exits non-zero:
- **HTTP 403:** Alert: "parkrun page returned 403 — the site may be blocking automated requests."
- **HTTP 404:** Alert: "parkrun athlete not found — check PARKRUN_ATHLETE_ID and PARKRUN_DOMAIN."
- **Network error / timeout:** Skip silently, retry next heartbeat.
- **Unexpected HTML:** Alert: "parkrun page structure may have changed."

### 3. Parse and evaluate

From the most recent result, extract:
- **Event** — which parkrun
- **Date** — when (dd/mm/yyyy)
- **Time** — finish time
- **Position** — finishing position
- **Age Grade** — age-graded percentage
- **PB** — whether it was a personal best

Compare the date to your last known result (from agent memory).

### 4. Alert conditions

| Condition | Severity | Message |
|-----------|----------|---------|
| No parkrun in 14 days | Medium | No parkrun result in the last 14 days |
| HTTP 403 (blocked) | Medium | parkrun page returned 403 — site may be blocking requests |
| HTTP 404 (not found) | Medium | parkrun athlete not found — check PARKRUN_ATHLETE_ID |
| HTML structure changed | Medium | parkrun page structure may have changed — scraper needs updating |
| New PB | Note | New PB at {event}: {time} (position {pos}) |

### 5. Reporting

- **New result since last heartbeat:** "Completed parkrun #{run_number} at {event} in {time} (position {pos}, age grade {age_grade})."
- **New PB:** Add "New PB!" to the summary.
- **Nothing new:** Do NOT send a message. No noisy "no update" messages.
- **Alert condition detected:** Send the alert regardless of whether there's a new result.

---

## Responding to User Queries

When the user asks about their parkrun results (e.g. "how was my parkrun?", "what's my PB?", "how many different parkruns have I done?"):

### Latest result

1. Run `scripts/parkrun-status.sh --json --count 1`
2. Format a clear summary:

```
Latest parkrun: Chelsea Bicentennial (31/01/2026)
  Position:     346
  Time:         48:27
  Age Grade:    31.20%
```

### PB and stats

1. Run `scripts/parkrun-status.sh --summary`
2. Present the summary stats:

```
parkrun Stats (164 parkruns):
  Fastest:     27:09
  Average:     41:34
  Slowest:     01:00:32
  Best Grade:  52.96%
```

### Event tourism

1. Run `scripts/parkrun-status.sh --tourism`
2. Present the unique events count and breakdown

### Recent results

1. Run `scripts/parkrun-status.sh` for the last 10
2. For a specific count: `scripts/parkrun-status.sh --count 20`
3. For all results: `scripts/parkrun-status.sh --all`

### Results for a time period

1. Run `scripts/parkrun-status.sh --json --all`
2. Filter by date in the JSON output
3. Present concisely — don't dump raw data

### Convenience script

One helper script in the skill's parent project:

- **`scripts/parkrun-status.sh`** Scrape and display parkrun results. Run with `--raw`, `--json`, `--all`, `--count N`, `--summary`, `--tourism`.

---

## Tips

- parkrun happens every Saturday morning (some events on other days, but Saturday is standard).
- The page returns all results in a single response, so there's no pagination to handle.
- Dates on the page are in dd/mm/yyyy format (Australian locale). Other country domains may differ.
- Age grading percentages let you compare performance across age groups and genders.
- The 100 Club, 250 Club, etc. are milestones for completing that many parkruns.
- Event names can change over time. The same physical location may have had a different name in the past.
- If the user runs at multiple parkruns in different countries, they'll need separate PARKRUN_DOMAIN configs or the results may be incomplete.
