#!/usr/bin/env bash
#
# forge-metrics.sh — what this project's governance is actually doing.
#
# Reads git history, override records and gate output. Adds no instrumentation
# and stores no state: everything here is already in the repo, it has just never
# been counted.
#
#   ./scripts/forge-metrics.sh              human summary
#   ./scripts/forge-metrics.sh --json       machine-readable
#   ./scripts/forge-metrics.sh --since 90   window in days (default 90)
#   ./scripts/forge-metrics.sh --otlp       POST to an OpenTelemetry collector
#
# --otlp reads the standard OTEL_EXPORTER_OTLP_ENDPOINT and
# OTEL_EXPORTER_OTLP_HEADERS, so it fits whatever collector the org already runs
# and needs no config of its own. Opt-in and off by default: nothing here phones
# home unless asked, and the script is fully useful with no collector at all.
#
# The metrics are chosen so that each one can change a decision. A number that
# only ever gets nodded at is a vanity metric, and vanity metrics crowd out the
# two or three that would have told you something.
#
# What it deliberately does NOT measure: commits, lines changed, PR counts,
# velocity. Those move with how work is chopped up rather than with whether the
# discipline is holding, and once anyone is judged on them they stop measuring
# anything at all.

set -uo pipefail

FORMAT=human; SINCE=90; OTLP=0
while (( $# )); do
  case "$1" in
    --json)  FORMAT=json; shift ;;
    --otlp)  OTLP=1; shift ;;
    --since) SINCE="$2"; shift 2 ;;
    --help|-h) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 2; }
# shellcheck disable=SC1091
[[ -f .forge/config ]] && source .forge/config
KEY="${PROJECT_KEY:-}"
AFTER="$(date -d "-${SINCE} days" +%F 2>/dev/null || date -v-"${SINCE}"d +%F)"

# ── governance direction ────────────────────────────────────────────────────
# The single most important number here. Every governance system fails the same
# way: under pressure someone lowers a gate "just for now". Because .forge/config
# is version-controlled, that is a diff — so it is countable.
LEVEL_NOW="${FORGE_LEVEL:-L1}"
LEVEL_UPS=0; LEVEL_DOWNS=0; LEVEL_HIST=""
while read -r line; do
  case "$line" in
    +FORGE_LEVEL=*) LEVEL_HIST+="${line#+FORGE_LEVEL=} " ;;
  esac
done < <(git log --reverse --since="$AFTER" -p --format='' -- .forge/config 2>/dev/null | grep -E '^\+FORGE_LEVEL=')
prev=""
for l in $LEVEL_HIST; do
  if [[ -n "$prev" ]]; then
    if (( ${l#L} > ${prev#L} )); then LEVEL_UPS=$((LEVEL_UPS+1))
    elif (( ${l#L} < ${prev#L} )); then LEVEL_DOWNS=$((LEVEL_DOWNS+1)); fi
  fi
  prev="$l"
done

# A gate turned off is the same act by another route.
count() { grep -cE "$1" "${2:--}" 2>/dev/null | head -1 || true; }
GATES_OFF="$(count '^[A-Z_]+_GATE=off' .forge/config)"; GATES_OFF="${GATES_OFF:-0}"
GATES_WARN="$(count '^[A-Z_]+_GATE=warn' .forge/config)"; GATES_WARN="${GATES_WARN:-0}"
NO_TESTS=0; grep -qE '^TEST_CMD=""' .forge/config 2>/dev/null && NO_TESTS=1

# ── override health ─────────────────────────────────────────────────────────
# An exception rate of zero usually means the gates were quietly disabled
# instead. What matters is the shape: which gate, how long, renewed or resolved.
OV_LIVE=0; OV_EXPIRED=0; OV_NOVERIFY=0; OV_STANDING=0; OV_BY_GATE=""
TODAY="$(date +%F)"
if [[ -d .forge/overrides ]]; then
  for f in .forge/overrides/*.yml .forge/overrides/*.yaml; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == TEMPLATE.* ]] && continue
    exp="$(sed -n 's/^expires: *//p' "$f" | head -1 | tr -d '"')"
    g="$(sed -n 's/^gate: *//p' "$f" | head -1 | tr -d '"')"
    if [[ -n "$exp" && "$exp" < "$TODAY" ]]; then OV_EXPIRED=$((OV_EXPIRED+1)); continue; fi
    OV_LIVE=$((OV_LIVE+1)); OV_BY_GATE+="$g"$'\n'
    grep -q '^verify:' "$f" || OV_NOVERIFY=$((OV_NOVERIFY+1))
    [[ "$(sed -n 's/^scope: *//p' "$f" | head -1)" == "standing" ]] && OV_STANDING=$((OV_STANDING+1))
  done
fi
TOP_GATE=""; TOP_GATE_N=0
if [[ -n "$OV_BY_GATE" ]]; then
  read -r TOP_GATE_N TOP_GATE < <(sort <<<"$OV_BY_GATE" | grep -v '^$' | uniq -c | sort -rn | head -1)
fi
OV_ADDED="$(git log --since="$AFTER" --diff-filter=A --format='' --name-only -- .forge/overrides/ 2>/dev/null | grep -cE '\.ya?ml$' | head -1)"; OV_ADDED="${OV_ADDED:-0}"

# ── traceability ────────────────────────────────────────────────────────────
REQ_TOTAL=0; REQ_COVERED=0
if [[ -f REQUIREMENTS.md ]]; then
  TP=(); for d in test tests spec specs features __tests__; do [[ -d "$d" ]] && TP+=("$d"); done
  while read -r r; do
    [[ -z "$r" ]] && continue
    REQ_TOTAL=$((REQ_TOTAL+1))
    if (( ${#TP[@]} )) && grep -rqE "\b${r}\b" "${TP[@]}" 2>/dev/null; then
      REQ_COVERED=$((REQ_COVERED+1))
    elif grep -rqE "\b${r}\b" --include='*test*' --include='*spec*' --include='*.feature' . 2>/dev/null; then
      REQ_COVERED=$((REQ_COVERED+1))
    fi
  done < <(grep -oE '^#+ *(R[0-9]+)' REQUIREMENTS.md 2>/dev/null | grep -oE 'R[0-9]+' | sort -u)
fi

# ── contract drift ──────────────────────────────────────────────────────────
# Adapted from the AI-native SDLC playbook, which measures drift and blocks none
# of it. We block the same thing, so this counts what the gate ALREADY refused —
# a rising number means people keep trying, which is a signal about the workflow
# rather than about the people.
CONTRACT_COMMITS="$(git log --since="$AFTER" --format='%H' -- REQUIREMENTS.md 'features/*.feature' 2>/dev/null | wc -l)"

# ── decisions ───────────────────────────────────────────────────────────────
ADR_TOTAL=0; ADR_SUPERSEDED=0; ADR_RECENT=0
if [[ -d docs/adr ]]; then
  ADR_TOTAL="$(find docs/adr -name '[0-9][0-9][0-9][0-9]-*.md' 2>/dev/null | wc -l)"
  ADR_SUPERSEDED="$(grep -lE '^status: *Superseded' docs/adr/*.md 2>/dev/null | wc -l)"
  ADR_RECENT="$(git log --since="$AFTER" --diff-filter=A --format='' --name-only -- docs/adr/ 2>/dev/null | grep -cE '[0-9]{4}-.*\.md$' | head -1)"; ADR_RECENT="${ADR_RECENT:-0}"
fi

# ── flow ────────────────────────────────────────────────────────────────────
# Cycle time from the first commit on a card's branch to its merge.
MERGED=0; CYCLE_TOTAL=0; CYCLE_MAX=0
if [[ -n "$KEY" ]]; then
  while read -r sha subject; do
    [[ "$subject" =~ ${KEY}-[0-9]+ ]] || continue
    first="$(git log --format='%ct' "$sha^1..$sha^2" 2>/dev/null | tail -1)"
    [[ -z "$first" ]] && continue
    merged_at="$(git log -1 --format='%ct' "$sha")"
    days=$(( (merged_at - first) / 86400 ))
    MERGED=$((MERGED+1)); CYCLE_TOTAL=$((CYCLE_TOTAL+days))
    (( days > CYCLE_MAX )) && CYCLE_MAX=$days
  done < <(git log --since="$AFTER" --merges --format='%H %s' 2>/dev/null)
fi
CYCLE_AVG=0; (( MERGED > 0 )) && CYCLE_AVG=$(( CYCLE_TOTAL / MERGED ))

pct() { (( $2 == 0 )) && { echo "n/a"; return; }; echo "$(( $1 * 100 / $2 ))%"; }

# ── output ──────────────────────────────────────────────────────────────────
emit_json() {
cat <<JSON
{
  "window_days": $SINCE,
  "governance": {
    "level": "$LEVEL_NOW", "level_raised": $LEVEL_UPS, "level_lowered": $LEVEL_DOWNS,
    "gates_off": $GATES_OFF, "gates_warn": $GATES_WARN, "no_test_cmd": $NO_TESTS
  },
  "overrides": {
    "live": $OV_LIVE, "expired_on_disk": $OV_EXPIRED, "without_verify": $OV_NOVERIFY,
    "standing": $OV_STANDING, "added_in_window": $OV_ADDED,
    "most_overridden_gate": "${TOP_GATE:-none}", "most_overridden_count": ${TOP_GATE_N:-0}
  },
  "traceability": {
    "requirements": $REQ_TOTAL, "covered_by_a_test": $REQ_COVERED,
    "contract_commits_in_window": $CONTRACT_COMMITS
  },
  "decisions": { "total": $ADR_TOTAL, "superseded": $ADR_SUPERSEDED, "added_in_window": $ADR_RECENT },
  "flow": { "cards_merged": $MERGED, "cycle_days_avg": $CYCLE_AVG, "cycle_days_max": $CYCLE_MAX }
}
JSON
}

# Export before rendering, so --otlp composes with either output format.
if (( OTLP )); then
  EP="${OTEL_EXPORTER_OTLP_ENDPOINT:-}"
  [[ -n "$EP" ]] || { echo "--otlp: set OTEL_EXPORTER_OTLP_ENDPOINT (no collector configured)" >&2; exit 2; }
  command -v curl >/dev/null || { echo "--otlp needs curl" >&2; exit 3; }

  # Flatten to OTLP gauges. Every number here is a point-in-time count, so a
  # gauge is the honest instrument — none of it monotonically increases.
  BODY="$(emit_json | OTEL_TS="$(date +%s)000000000" \
      OTEL_SVC="${OTEL_SERVICE_NAME:-forge}" OTEL_KEY="${PROJECT_KEY:-unknown}" \
      python3 "$(dirname "$0")/.forge-otlp.py" 2>/dev/null)"
  [[ -n "$BODY" ]] || { echo "--otlp: could not build payload" >&2; exit 4; }

  HDRS=()
  if [[ -n "${OTEL_EXPORTER_OTLP_HEADERS:-}" ]]; then
    while IFS= read -r h; do [[ -n "$h" ]] && HDRS+=(-H "${h/=/: }"); done \
      < <(tr ',' '\n' <<<"$OTEL_EXPORTER_OTLP_HEADERS")
  fi
  if curl -sf -m 10 -X POST "${EP%/}/v1/metrics" \
       -H 'Content-Type: application/json' "${HDRS[@]}" -d "$BODY" >/dev/null; then
    echo "otlp: exported to ${EP%/}/v1/metrics"
  else
    echo "otlp: export FAILED to ${EP%/}/v1/metrics" >&2; exit 1
  fi
fi

if [[ "$FORMAT" == json ]]; then
  emit_json
  exit 0
fi


B=$'\e[1m'; Y=$'\e[33m'; R=$'\e[31m'; Z=$'\e[0m'
printf '%sForge metrics — last %s days%s\n\n' "$B" "$SINCE" "$Z"

printf '%sGovernance%s\n' "$B" "$Z"
printf '  maturity level        %s  (raised %d, lowered %d)\n' "$LEVEL_NOW" "$LEVEL_UPS" "$LEVEL_DOWNS"
(( LEVEL_DOWNS > 0 )) && printf '  %s^ a level was lowered. Each should have its own PR and a written reason.%s\n' "$Y" "$Z"
printf '  gates off / warn      %d / %d\n' "$GATES_OFF" "$GATES_WARN"
(( NO_TESTS )) && printf '  %sTEST_CMD is empty — nothing here proves the code works.%s\n' "$R" "$Z"

printf '\n%sOverrides%s\n' "$B" "$Z"
printf '  live                  %d   (%d standing, %d with no verify:)\n' "$OV_LIVE" "$OV_STANDING" "$OV_NOVERIFY"
printf '  added in window       %d\n' "$OV_ADDED"
(( OV_EXPIRED > 0 )) && printf '  expired, still on disk %d — harmless, but they read as live policy\n' "$OV_EXPIRED"
if (( TOP_GATE_N >= 3 )); then
  printf '  %s%s overridden %d times — that is a miscalibrated gate, not a careless team.%s\n' "$Y" "$TOP_GATE" "$TOP_GATE_N" "$Z"
  printf '  %sFix the gate, in its own PR.%s\n' "$Y" "$Z"
fi
(( OV_NOVERIFY > 0 )) && printf '  %s%d override(s) rest on assertion alone — nothing re-checks them.%s\n' "$Y" "$OV_NOVERIFY" "$Z"

printf '\n%sTraceability%s\n' "$B" "$Z"
printf '  requirements          %d\n' "$REQ_TOTAL"
printf '  named by a test       %d  (%s)\n' "$REQ_COVERED" "$(pct "$REQ_COVERED" "$REQ_TOTAL")"
printf '  contract commits      %d in window\n' "$CONTRACT_COMMITS"

printf '\n%sDecisions%s\n' "$B" "$Z"
printf '  ADRs                  %d  (%d superseded, %d added in window)\n' "$ADR_TOTAL" "$ADR_SUPERSEDED" "$ADR_RECENT"
(( ADR_TOTAL == 0 )) && printf '  %sNo decision records. Either nothing constraining was chosen, or it was not written down.%s\n' "$Y" "$Z"

printf '\n%sFlow%s\n' "$B" "$Z"
printf '  cards merged          %d\n' "$MERGED"
(( MERGED > 0 )) && printf '  cycle time            %d days avg, %d max\n' "$CYCLE_AVG" "$CYCLE_MAX"

printf '\n%sRead these as questions, not scores.%s No target is set for any of them,\n' "$B" "$Z"
printf 'deliberately — a governance number with a target attached becomes something\n'
printf 'people manage rather than something that tells you anything.\n'
