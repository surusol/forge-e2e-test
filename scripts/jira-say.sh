#!/usr/bin/env bash
#
# jira-say.sh — post and read agent handoff notes on a Jira card.
#
# Cards as an ASYNC HANDOFF BUS between agents: the conversation lives on the work item it is
# about, is attributable, survives session boundaries, and the owner reads it in the same place
# they manage everything else. See reference/agent-comms.md for when NOT to use it (it is a
# handoff bus, not a message bus — no locking, no ordering, and polling latency).
#
# Usage:
#   jira-say.sh WID-12 --read [--since 30m] [--agent NAME] [--json]
#   jira-say.sh WID-12 --agent builder --status blocked --needs owner "message text"
#   jira-say.sh --inbox [--since 30m] [--agent NAME]      # cards that changed recently
#
#   --status   working | done | blocked | question | fyi   (default: fyi)
#   --needs    owner | reviewer | <agent-name> | none      (default: none)
#
# Every note carries a one-line machine-readable header, so a human skims who/what/what-next
# and an agent greps it:
#
#   [agent: builder] [status: blocked] [needs: owner]
#   Migration verified, 97/97 runs resolve. Blocked on WID-17 — that gate is the owner's.
#
# Config from ./.forge/config (PROJECT_KEY, JIRA_BASE_URL); credentials from env
# (JIRA_EMAIL / JIRA_API_TOKEN) or ~/.config/forge/jira.env. Needs only read:jira-work +
# write:jira-work — the same two scopes the transition workflow uses.
#
# Requires: bash, curl, jq.

set -euo pipefail

CFG="$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.forge/config"
[[ -f "$CFG" ]] && { set -a; . "$CFG"; set +a; }
# Credentials: environment, then 1Password, then ~/.config/forge/jira.env.
# 1Password before the file because a plaintext copy on disk drifts — the two
# held the same expired token here, the vault was rotated, the file was not, and
# every tool failed against a credential that had already been fixed.
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/forge-creds.sh"
forge_load_creds || true
: "${JIRA_BASE_URL:?set JIRA_BASE_URL (in .forge/config or env)}"
: "${JIRA_EMAIL:?set JIRA_EMAIL}"; : "${JIRA_API_TOKEN:?set JIRA_API_TOKEN}"
for b in curl jq; do command -v "$b" >/dev/null || { echo "need $b" >&2; exit 3; }; done

# ALWAYS go through api.atlassian.com, never the site URL. A SCOPED API token (the kind
# Atlassian's newer token UI mints) is rejected on the site URL with a bare 401, and on the
# gateway returns the far more useful "scope does not match". A classic token works on BOTH.
# So the gateway is the only choice that supports either token type. The cloud id resolves
# from the site URL with no authentication, so this costs one cheap request.
SITE="${JIRA_BASE_URL%/}"
if [[ "$SITE" == *api.atlassian.com* ]]; then
  API="$SITE/rest/api/3"
else
  CLOUD_ID="${JIRA_CLOUD_ID:-$(curl -sf "$SITE/_edge/tenant_info" | jq -r .cloudId)}"
  [[ -z "$CLOUD_ID" || "$CLOUD_ID" == null ]] && { echo "could not resolve cloudId from $SITE" >&2; exit 3; }
  API="https://api.atlassian.com/ex/jira/$CLOUD_ID/rest/api/3"
fi
# NOT `curl -sf`. With -f curl prints nothing and exits non-zero, which under `set -e` makes
# the whole script die in silence -- a 401 and a typo look identical, and you cannot tell a
# scope problem from a wrong URL. Capture the status, surface the body on failure.
api(){
  local body status
  body=$(curl -s -w '\n%{http_code}' -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
         -H 'Accept: application/json' "$@") || { echo "curl failed (network?)" >&2; return 1; }
  status=${body##*$'\n'}; body=${body%$'\n'*}
  if [[ "$status" == 2* ]]; then printf '%s' "$body"; return 0; fi
  echo "jira: HTTP $status" >&2
  printf '%s\n' "$body" | head -c 400 >&2; echo >&2
  return 1
}

KEY="" MODE="" AGENT="" STATUS="fyi" NEEDS="none" SINCE="" TEXT="" JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --read)   MODE=read;   shift ;;
    --inbox)  MODE=inbox;  shift ;;
    --agent)  AGENT="$2";  shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --needs)  NEEDS="$2";  shift 2 ;;
    --since)  SINCE="$2";  shift 2 ;;
    --json)   JSON=1;      shift ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    -*) echo "unknown flag $1" >&2; exit 2 ;;
    *) [[ -z "$KEY" ]] && KEY="$1" || TEXT="$1"; shift ;;
  esac
done
[[ -z "$MODE" && -n "$TEXT" ]] && MODE=post
[[ -z "$MODE" ]] && { echo "nothing to do: give --read, --inbox, or a message" >&2; exit 2; }

# ---- inbox: which cards moved recently. ONE JQL call, never a per-card poll loop --------
# Polling every card individually is how a handful of agents turn into hundreds of calls a
# minute. Ask the server which cards changed, then read only those.
if [[ "$MODE" == inbox ]]; then
  JQL="updated >= -${SINCE:-30m}"
  [[ -n "${PROJECT_KEY:-}" ]] && JQL="project = ${PROJECT_KEY} AND $JQL"
  api --get "$API/search/jql" --data-urlencode "jql=$JQL ORDER BY updated DESC" \
      --data-urlencode 'fields=summary,status,updated' --data-urlencode 'maxResults=50' \
    | jq -r '.issues[]? | "\(.key)\t\(.fields.status.name)\t\(.fields.summary)"' \
    | column -t -s$'\t' 2>/dev/null || true
  exit 0
fi

[[ -z "$KEY" ]] && { echo "need an issue key" >&2; exit 2; }

# ---- read ------------------------------------------------------------------------------
if [[ "$MODE" == read ]]; then
  RAW=$(api "$API/issue/$KEY/comment?orderBy=created&maxResults=100")
  # ADF: text lives in nested content[].content[].text. Flatten before matching, or the
  # header regex silently never matches and the card looks empty.
  FLAT=$(jq -c '[.comments[]? | {
      author: (.author.displayName // "?"), created: .created,
      body: ([.. | objects | select(.type=="text") | .text] | join(" "))
    }]' <<<"$RAW")
  [[ -n "$AGENT" ]] && FLAT=$(jq -c --arg a "$AGENT" '[.[] | select(.body | test("\\[agent: *"+$a+" *\\]";"i"))]' <<<"$FLAT")
  if [[ -n "$SINCE" ]]; then
    CUT=$(date -u -d "-${SINCE//m/ min} ${SINCE//[0-9]/}" +%s 2>/dev/null || date -u +%s)
    FLAT=$(jq -c --argjson cut "$CUT" '[.[] | select((.created|sub("\\.[0-9]+";"")|sub("[+-][0-9]{4}$";"Z")|fromdateiso8601) >= $cut)]' <<<"$FLAT" 2>/dev/null || echo "$FLAT")
  fi
  if [[ "$JSON" == 1 ]]; then echo "$FLAT" | jq .; exit 0; fi
  jq -r '.[] | "\(.created[0:16])  \(.author)\n  \(.body)\n"' <<<"$FLAT"
  exit 0
fi

# ---- post ------------------------------------------------------------------------------
[[ -z "$TEXT" ]] && { echo "no message text" >&2; exit 2; }
HDR="[agent: ${AGENT:-unknown}] [status: ${STATUS}] [needs: ${NEEDS}]"
BODY=$(jq -n --arg h "$HDR" --arg t "$TEXT" '{body:{type:"doc",version:1,content:[
    {type:"paragraph",content:[{type:"text",text:$h}]},
    {type:"paragraph",content:[{type:"text",text:$t}]}]}}')
api -X POST -H 'Content-Type: application/json' --data "$BODY" "$API/issue/$KEY/comment" \
  | jq -r '"posted \(.id) on '"$KEY"'"'
