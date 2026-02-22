# Heartbeat - parkrun

Add the following checklist item to the agent's workspace `HEARTBEAT.md` to enable
automatic parkrun result monitoring on the heartbeat cycle:

```markdown
- [ ] Check parkrun via the parkrun skill. If there's a new result since the
      last check, include a brief summary (event, time, position). Alert me if
      the page is unreachable. Don't message me if there's nothing new.
```

## What the agent will do on each heartbeat

1. Fetch the athlete's results page from parkrun
2. Parse the most recent result
3. Compare the date to the last known result (from agent memory)
4. Check for alert conditions (page unreachable, stale data)
5. **Only notify the user if there's a new result or something is wrong.** Silent otherwise

## Alert thresholds

| Condition | Action |
|-----------|--------|
| No parkrun in 14 days | Medium alert (2 missed weeks) |
| Page unreachable (403, timeout) | Alert if it persists across multiple heartbeats |
| HTML structure changed | Alert (scraper may need updating) |
| New PB | Mention in the result summary |
