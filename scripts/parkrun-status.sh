#!/usr/bin/env bash
#
# parkrun-status.sh - Fetch parkrun results from the public athlete page
#
# Usage: ./parkrun-status.sh [--raw] [--json] [--all] [--count N] [--summary] [--tourism]
#   --raw       Output raw HTML from the results page
#   --json      Output parsed results as JSON
#   --all       Show all results (not just recent)
#   --count N   Show last N results (default: 10)
#   --summary   Summary stats and annual achievements only
#   --tourism   Unique events attended, with count per event
#
# Requires: curl, awk, sed
# Environment: PARKRUN_ATHLETE_ID

set -euo pipefail

# --- Dependency checks ---

for cmd in curl awk sed; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: Required command '$cmd' not found. Install it and try again." >&2
    exit 1
  fi
done

# --- Configuration ---

PARKRUN_ATHLETE_ID="${PARKRUN_ATHLETE_ID:-}"
PARKRUN_DOMAIN="${PARKRUN_DOMAIN:-www.parkrun.com.au}"
USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

if [ -z "$PARKRUN_ATHLETE_ID" ]; then
  echo "Error: PARKRUN_ATHLETE_ID environment variable is not set." >&2
  echo "Set it to your parkrun athlete ID (numeric, e.g. 2682215)." >&2
  exit 1
fi

if ! [[ "$PARKRUN_ATHLETE_ID" =~ ^[0-9]+$ ]]; then
  echo "Error: PARKRUN_ATHLETE_ID must be numeric, got '${PARKRUN_ATHLETE_ID}'." >&2
  exit 1
fi

if ! [[ "$PARKRUN_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
  echo "Error: PARKRUN_DOMAIN contains invalid characters: '${PARKRUN_DOMAIN}'." >&2
  exit 1
fi

# --- Argument parsing ---

OUTPUT_MODE="formatted"
COUNT=10
SHOW_ALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --raw)     OUTPUT_MODE="raw"; shift ;;
    --json)    OUTPUT_MODE="json"; shift ;;
    --summary) OUTPUT_MODE="summary"; shift ;;
    --tourism) OUTPUT_MODE="tourism"; shift ;;
    --all)     SHOW_ALL=true; shift ;;
    --count)
      shift
      if [[ $# -eq 0 ]] || [[ "$1" == --* ]]; then
        echo "Error: --count requires a numeric value." >&2
        exit 1
      fi
      COUNT="$1"; shift ;;
    --count=*)
      COUNT="${1#--count=}"; shift ;;
    --help|-h)
      echo "Usage: $0 [--raw] [--json] [--all] [--count N] [--summary] [--tourism]"
      echo "  --raw       Output raw HTML from the results page"
      echo "  --json      Output parsed results as JSON"
      echo "  --all       Show all results (not just recent)"
      echo "  --count N   Show last N results (default: 10)"
      echo "  --summary   Summary stats and annual achievements only"
      echo "  --tourism   Unique events attended, with count per event"
      echo ""
      echo "Environment: PARKRUN_ATHLETE_ID, PARKRUN_DOMAIN"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Validate --count is a positive integer
if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -eq 0 ]; then
  echo "Error: --count must be a positive integer, got '$COUNT'." >&2
  exit 1
fi

# --- Temp files (single trap for all) ---

TMPFILE=$(mktemp)
ANNUAL_FILE=$(mktemp)
RESULTS_FILE=$(mktemp)
SPLIT_FILE=$(mktemp)
trap 'rm -f "$TMPFILE" "$ANNUAL_FILE" "$RESULTS_FILE" "$SPLIT_FILE"' EXIT

# --- Fetch results page ---

URL="https://${PARKRUN_DOMAIN}/parkrunner/${PARKRUN_ATHLETE_ID}/all/"

HTTP_CODE=$(curl -s -w '%{http_code}' -A "$USER_AGENT" "$URL" --max-time 30 -o "$TMPFILE") || {
  echo "Error: Failed to connect to ${PARKRUN_DOMAIN} (network error or timeout)." >&2
  exit 1
}

if [ "$HTTP_CODE" -eq 403 ]; then
  echo "Error: HTTP 403 from ${PARKRUN_DOMAIN}. The site may be blocking automated requests." >&2
  echo "Try visiting the URL manually: $URL" >&2
  exit 1
fi

if [ "$HTTP_CODE" -eq 404 ]; then
  echo "Error: HTTP 404 — athlete ID '${PARKRUN_ATHLETE_ID}' not found on ${PARKRUN_DOMAIN}." >&2
  echo "Check PARKRUN_ATHLETE_ID and PARKRUN_DOMAIN are correct." >&2
  exit 1
fi

if [ "$HTTP_CODE" -ge 400 ]; then
  echo "Error: HTTP $HTTP_CODE from ${PARKRUN_DOMAIN}." >&2
  exit 1
fi

# Validate we got a parkrun results page
if ! grep -q 'Run Date' "$TMPFILE"; then
  echo "Error: Unexpected page structure — could not find results table." >&2
  echo "The parkrun website HTML may have changed. Check the URL manually: $URL" >&2
  exit 1
fi

# --- Raw output ---

if [ "$OUTPUT_MODE" = "raw" ]; then
  cat "$TMPFILE"
  exit 0
fi

# --- Parse athlete info from header ---
# Work from the temp file to avoid broken pipe with large echo

ATHLETE_NAME=$(sed -n 's/.*<h2>\([^<]*\)<span.*/\1/p' "$TMPFILE" | sed 's/[[:space:]]*$//')
ATHLETE_ID_DISPLAY=$(sed -n 's/.*title="parkrun ID">(\([^)]*\)).*/\1/p' "$TMPFILE")
TOTAL_RUNS=$(sed -n 's/.*[^0-9]\([0-9][0-9]*\) parkruns total.*/\1/p' "$TMPFILE")
AGE_CATEGORY=$(sed -n 's/.*Most recent age category was \([A-Z][A-Z0-9-]*\).*/\1/p' "$TMPFILE")

# Fall back to env var for ID display
ATHLETE_ID_DISPLAY="${ATHLETE_ID_DISPLAY:-A${PARKRUN_ATHLETE_ID}}"

# --- Parse summary stats (first table) ---
# The summary table has rows like: <td>Time</td><td>27:09</td><td>41:34</td><td>01:00:32</td>
# Use sed to extract the three values after the label

FASTEST_TIME=""
AVERAGE_TIME=""
SLOWEST_TIME=""

TIME_ROW=$(grep 'Time</td>' "$TMPFILE" | head -1 || true)
if [ -n "$TIME_ROW" ]; then
  # Extract three <td> values after "Time</td>"
  FASTEST_TIME=$(echo "$TIME_ROW" | sed 's/.*Time<\/td><td>\([^<]*\)<\/td>.*/\1/')
  AVERAGE_TIME=$(echo "$TIME_ROW" | sed 's/.*Time<\/td><td>[^<]*<\/td><td>\([^<]*\)<\/td>.*/\1/')
  SLOWEST_TIME=$(echo "$TIME_ROW" | sed 's/.*Time<\/td><td>[^<]*<\/td><td>[^<]*<\/td><td>\([^<]*\)<\/td>.*/\1/')
fi

BEST_AGE_GRADE=""
AVG_AGE_GRADE=""

AGE_ROW=$(grep 'Age Grading</td>' "$TMPFILE" | head -1 || true)
if [ -n "$AGE_ROW" ]; then
  BEST_AGE_GRADE=$(echo "$AGE_ROW" | sed 's/.*Age Grading<\/td><td>\([^<]*\)<\/td>.*/\1/')
  AVG_AGE_GRADE=$(echo "$AGE_ROW" | sed 's/.*Age Grading<\/td><td>[^<]*<\/td><td>\([^<]*\)<\/td>.*/\1/')
fi

# --- Pre-process HTML: split <tr> tags onto separate lines ---
# The HTML has multiple table rows on single lines. Splitting ensures
# awk can process one row per line.

# Step 1: Join continuation lines (PB text appears on separate lines)
# Step 2: Split <tr> tags onto separate lines
tr '\n' ' ' < "$TMPFILE" | sed 's/<tr>/\
<tr>/g' > "$SPLIT_FILE"

# --- Parse annual achievements (second table) ---
# Rows like: <tr><td>2016</td><td>00:41:28</td><td>33.68%</td></tr>

awk '
  /Best Time<\/th>/ { found = 1 }
  found && /<tr><td>/ {
    line = $0
    gsub(/<[^>]*>/, "|", line)
    gsub(/\|+/, "|", line)
    gsub(/^\||\|$/, "", line)
    n = split(line, a, "|")
    year = ""; btime = ""; bgrade = ""
    for (i = 1; i <= n; i++) {
      gsub(/^[ \t]+|[ \t]+$/, "", a[i])
      if (a[i] == "") continue
      if (year == "") { year = a[i]; continue }
      if (btime == "") { btime = a[i]; continue }
      if (bgrade == "") { bgrade = a[i]; break }
    }
    if (year != "") print year "|" btime "|" bgrade
  }
  found && /<\/table>/ { found = 0 }
' "$SPLIT_FILE" > "$ANNUAL_FILE"

# --- Parse all results (third table) ---
# Each result row: event link, date span, run number link, position, time, age grade, [PB]

awk '
  /Run Date<\/th>/ { found = 1 }
  found && /<\/table>/ { found = 0 }
  found && /<tr><td>/ {
    line = $0
    split("", clean)

    # Extract event name: first "results/">TEXT</a>
    event = ""
    tmp = line
    if (match(tmp, /results\/">/) > 0) {
      tmp = substr(tmp, RSTART + RLENGTH)
      if (match(tmp, /</) > 0) {
        event = substr(tmp, 1, RSTART - 1)
      }
    }

    # Extract date from format-date span
    date = ""
    tmp = line
    if (match(tmp, /format-date">/) > 0) {
      tmp = substr(tmp, RSTART + RLENGTH)
      if (match(tmp, /</) > 0) {
        date = substr(tmp, 1, RSTART - 1)
      }
    }

    # Now strip all HTML tags and parse remaining fields
    gsub(/<[^>]*>/, "|", line)
    gsub(/\|+/, "|", line)
    gsub(/^\||\|$/, "", line)
    n = split(line, raw, "|")

    # Collect non-empty trimmed fields
    j = 0
    for (i = 1; i <= n; i++) {
      gsub(/^[ \t]+|[ \t]+$/, "", raw[i])
      if (raw[i] != "" && raw[i] != "View summary stats for this parkrunner") {
        j++
        clean[j] = raw[i]
      }
    }

    # Skip event name and date occurrences to get: run_number, position, time, age_grade, [PB]
    run_num = ""; pos = ""; time_val = ""; age_grade = ""; pb = ""
    idx = 0
    for (i = 1; i <= j; i++) {
      if (clean[i] == event) continue
      if (clean[i] == date) continue
      idx++
      if (idx == 1) run_num = clean[i]
      else if (idx == 2) pos = clean[i]
      else if (idx == 3) time_val = clean[i]
      else if (idx == 4) age_grade = clean[i]
      else if (idx == 5) pb = clean[i]
    }

    # Strip all spaces from PB field (HTML has lots of whitespace padding)
    gsub(/ /, "", pb)

    if (event != "" && date != "") {
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", event, date, run_num, pos, time_val, age_grade, pb
    }
  }
' "$SPLIT_FILE" > "$RESULTS_FILE"

# Count results
RESULT_COUNT=0
if [ -s "$RESULTS_FILE" ]; then
  RESULT_COUNT=$(wc -l < "$RESULTS_FILE" | tr -d ' ')
fi

# --- Output helpers ---

print_athlete_header() {
  echo ""
  echo "  ${ATHLETE_NAME} (${ATHLETE_ID_DISPLAY})"
  echo "  ${TOTAL_RUNS:-?} parkruns | PB: ${FASTEST_TIME:-?} | Age cat: ${AGE_CATEGORY:-?}"
  echo "  ============================================"
}

print_footer() {
  echo ""
  echo "  ============================================"
  echo "  ${1:-Fetched at: $(date '+%Y-%m-%d %H:%M:%S')}"
  echo "  ============================================"
}

# --- Summary output ---

if [ "$OUTPUT_MODE" = "summary" ]; then
  print_athlete_header
  echo ""
  echo "  Summary Stats"
  echo "  ------------------------------------"
  printf "    %-18s %s\n" "Fastest Time:" "${FASTEST_TIME:-?}"
  printf "    %-18s %s\n" "Average Time:" "${AVERAGE_TIME:-?}"
  printf "    %-18s %s\n" "Slowest Time:" "${SLOWEST_TIME:-?}"
  printf "    %-18s %s\n" "Best Age Grade:" "${BEST_AGE_GRADE:-?}"
  printf "    %-18s %s\n" "Avg Age Grade:" "${AVG_AGE_GRADE:-?}"

  if [ -s "$ANNUAL_FILE" ]; then
    echo ""
    echo "  Annual Achievements"
    echo "  ------------------------------------"
    printf "    %-6s  %-12s  %s\n" "Year" "Best Time" "Best Age Grade"
    while IFS='|' read -r year btime bgrade; do
      printf "    %-6s  %-12s  %s\n" "$year" "$btime" "$bgrade"
    done < "$ANNUAL_FILE"
  fi

  print_footer
  exit 0
fi

# --- Tourism output ---

if [ "$OUTPUT_MODE" = "tourism" ]; then
  if [ "$RESULT_COUNT" -eq 0 ]; then
    echo "No results found."
    exit 0
  fi

  print_athlete_header

  TOURISM=$(awk -F'\t' '{count[$1]++} END {for (e in count) printf "%d\t%s\n", count[e], e}' "$RESULTS_FILE" | sort -rn)
  EVENT_COUNT=$(echo "$TOURISM" | wc -l | tr -d ' ')

  echo ""
  echo "  Events Visited: ${EVENT_COUNT}"
  echo ""

  echo "$TOURISM" | while IFS=$'\t' read -r cnt event; do
    if [ "$cnt" -eq 1 ]; then
      printf "    %-30s %3d run\n" "$event" "$cnt"
    else
      printf "    %-30s %3d runs\n" "$event" "$cnt"
    fi
  done

  print_footer
  exit 0
fi

# --- JSON output ---

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr -d '\n\r'
}

if [ "$OUTPUT_MODE" = "json" ]; then
  echo "{"
  echo "  \"athlete\": {"
  echo "    \"name\": \"$(json_escape "${ATHLETE_NAME}")\","
  echo "    \"id\": \"$(json_escape "${ATHLETE_ID_DISPLAY}")\","
  echo "    \"total_runs\": ${TOTAL_RUNS:-0},"
  echo "    \"age_category\": \"$(json_escape "${AGE_CATEGORY}")\","
  echo "    \"summary\": {"
  echo "      \"fastest\": \"$(json_escape "${FASTEST_TIME}")\","
  echo "      \"average\": \"$(json_escape "${AVERAGE_TIME}")\","
  echo "      \"slowest\": \"$(json_escape "${SLOWEST_TIME}")\","
  echo "      \"best_age_grade\": \"$(json_escape "${BEST_AGE_GRADE}")\","
  echo "      \"avg_age_grade\": \"$(json_escape "${AVG_AGE_GRADE}")\""
  echo "    }"
  echo "  },"

  # Annual achievements
  echo "  \"annual\": ["
  if [ -s "$ANNUAL_FILE" ]; then
    awk -F'|' '
      function jesc(s) {
        gsub(/\\/, "\\\\", s)
        gsub(/"/, "\\\"", s)
        return s
      }
      NR > 1 { printf ",\n" }
      { printf "    {\"year\": %s, \"best_time\": \"%s\", \"best_age_grade\": \"%s\"}", $1, jesc($2), jesc($3) }
      END { printf "\n" }
    ' "$ANNUAL_FILE"
  fi
  echo "  ],"

  # Results
  echo "  \"results\": ["
  if [ "$RESULT_COUNT" -gt 0 ]; then
    if [ "$SHOW_ALL" = true ]; then
      LIMIT="$RESULT_COUNT"
    else
      LIMIT="$COUNT"
    fi

    # Use awk to limit and format JSON (avoids subshell variable issues)
    awk -F'\t' -v limit="$LIMIT" -v show_all="$SHOW_ALL" '
      function jesc(s) {
        gsub(/\\/, "\\\\", s)
        gsub(/"/, "\\\"", s)
        gsub(/\t/, "\\t", s)
        gsub(/\n/, "\\n", s)
        gsub(/\r/, "\\r", s)
        return s
      }
      BEGIN { first = 1 }
      {
        if (show_all != "true" && NR > limit) exit
        pb = $7
        gsub(/ /, "", pb)
        pb_bool = (pb == "PB") ? "true" : "false"

        pos = $4; gsub(/[^0-9]/, "", pos)
        rn = $3; gsub(/[^0-9]/, "", rn)
        if (pos == "") pos = "0"
        if (rn == "") rn = "0"

        if (!first) printf ",\n"
        printf "    {\"event\": \"%s\", \"date\": \"%s\", \"run_number\": %s, \"position\": %s, \"time\": \"%s\", \"age_grade\": \"%s\", \"pb\": %s}", jesc($1), jesc($2), rn, pos, jesc($5), jesc($6), pb_bool
        first = 0
      }
      END { if (!first) printf "\n" }
    ' "$RESULTS_FILE"
  fi
  echo "  ]"
  echo "}"
  exit 0
fi

# --- Formatted output (default) ---

if [ "$RESULT_COUNT" -eq 0 ]; then
  echo "No results found for athlete ${ATHLETE_ID_DISPLAY} on ${PARKRUN_DOMAIN}."
  exit 0
fi

print_athlete_header

# Determine how many to show
if [ "$SHOW_ALL" = true ]; then
  DISPLAY_COUNT="$RESULT_COUNT"
  LABEL="all"
else
  if [ "$COUNT" -gt "$RESULT_COUNT" ]; then
    DISPLAY_COUNT="$RESULT_COUNT"
  else
    DISPLAY_COUNT="$COUNT"
  fi
  LABEL="last ${DISPLAY_COUNT}"
fi

# Use awk to format results (avoids subshell variable scoping issues)
awk -F'\t' -v limit="$DISPLAY_COUNT" -v show_all="$SHOW_ALL" '
  {
    if (show_all != "true" && NR > limit) exit
    event = $1; date = $2; run_num = $3; pos = $4
    time_val = $5; age_grade = $6; pb = $7
    pb_marker = (pb == "PB") ? " *PB*" : ""

    printf "\n  %s  %s%s\n", date, event, pb_marker
    print "  ------------------------------------"
    printf "    %-18s %s\n", "Position:", pos
    printf "    %-18s %s\n", "Time:", time_val
    printf "    %-18s %s\n", "Age Grade:", age_grade
  }
' "$RESULTS_FILE"

print_footer "${DISPLAY_COUNT} of ${RESULT_COUNT} results (${LABEL}) | Fetched at: $(date '+%Y-%m-%d %H:%M:%S')"
