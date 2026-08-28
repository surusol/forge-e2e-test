#!/usr/bin/env bash
#
# jira-brief.sh — print a paste-ready task brief for a Jira card or subtask.
#
# Generic forge-project exporter. Hand a task to ANY coding tool/LLM that has no
# Jira connector: run it, copy the output, paste it as the tool's prompt. The
# brief is self-contained (task, subtasks/checklist, and the naming rules so the
# tool's branch/PR links back to the card and passes CI). READ-ONLY.
#
# Usage:  ./scripts/jira-brief.sh <KEY>-<n>
#
# Project context is read from ./.forge/config (KEY=VALUE):
#     PROJECT_KEY=WID
#     JIRA_BASE_URL=https://acme.atlassian.net
#     REPO=alice/widgets
# Credentials from env (JIRA_EMAIL / JIRA_API_TOKEN, and JIRA_BASE_URL if not in
# config) or ~/.config/forge/jira.env. Use a scoped READ-ONLY token when sharing.
#
# Requires: bash, curl, jq.

set -euo pipefail

KEY="${1:-}"
[[ -z "$KEY" ]] && { echo "usage: $(basename "$0") <PROJECTKEY>-<number>" >&2; exit 2; }

# project config
CFG="$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.forge/config"
[[ -f "$CFG" ]] && { set -a; . "$CFG"; set +a; }
# credentials
# Credentials: environment, then 1Password, then ~/.config/forge/jira.env.
# 1Password before the file because a plaintext copy on disk drifts — the two
# held the same expired token here, the vault was rotated, the file was not, and
# every tool failed against a credential that had already been fixed.
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/forge-creds.sh"
forge_load_creds || true
: "${JIRA_BASE_URL:?set JIRA_BASE_URL (in .forge/config or env)}"
: "${JIRA_EMAIL:?set JIRA_EMAIL}"; : "${JIRA_API_TOKEN:?set JIRA_API_TOKEN}"
REPO="${REPO:-<owner>/<repo>}"

for b in curl jq; do command -v "$b" >/dev/null || { echo "need $b" >&2; exit 3; }; done
API="${JIRA_BASE_URL%/}"
api(){ curl -sf -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" "$API/rest/api/3/$1"; }

FLATTEN='def blocktext:
  def node:
    if type=="array" then (map(node)|join(""))
    elif type=="object" then
      (if .type=="text" then .text
       elif .type=="hardBreak" then "\n"
       elif .type=="listItem" then ("- "+((.content//[])|node)+"\n")
       elif .type=="paragraph" then (((.content//[])|node)+"\n")
       else ((.content//[])|node) end)
    else "" end;
  ((.content//[])|node)|rtrimstr("\n");'

ISSUE=$(api "issue/${KEY}?fields=summary,description,labels,issuetype,parent,subtasks,status") \
  || { echo "error: could not fetch $KEY (check key and access)" >&2; exit 4; }

SUMMARY=$(jq -r '.fields.summary' <<<"$ISSUE")
TYPE=$(jq -r '.fields.issuetype.name' <<<"$ISSUE")
STATUS=$(jq -r '.fields.status.name' <<<"$ISSUE")
# R + digits, not merely "starts with R" — "Runner"/"Refactor" are not requirements.
RLABELS=$(jq -r '[.fields.labels[]|select(test("^R[0-9]+$"))]|join(", ")' <<<"$ISSUE")
DESC=$(jq -r "$FLATTEN .fields.description // {} | blocktext" <<<"$ISSUE")
PARENT=$(jq -r '.fields.parent.key // empty' <<<"$ISSUE")
SLUG=$(printf '%s' "$SUMMARY" | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/^[0-9.]+ //; s/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40)

cat <<EOF
# TASK ${KEY} — ${SUMMARY}

- Type: ${TYPE}   Status: ${STATUS}
- Requirement(s) served: ${RLABELS:-see parent}
$( [[ -n "$PARENT" ]] && echo "- Part of: ${PARENT}" )
- Repo: ${REPO}  (READ CONTRIBUTING.md FIRST)

## What to do

${DESC}
EOF

SUBKEYS=$(jq -r '.fields.subtasks[]?.key' <<<"$ISSUE")
if [[ -n "$SUBKEYS" ]]; then
  echo; echo "## Steps (do these in order — each is one focused unit of work)"; echo
  while read -r sk; do
    [[ -z "$sk" ]] && continue
    S=$(api "issue/${sk}?fields=summary,description,status")
    echo "### ${sk} — $(jq -r '.fields.summary' <<<"$S")  [$(jq -r '.fields.status.name' <<<"$S")]"
    jq -r "$FLATTEN .fields.description // {} | blocktext" <<<"$S"; echo
  done <<<"$SUBKEYS"
else
  CMT=$(api "issue/${KEY}/comment?maxResults=50" || echo '{}')
  CHECK=$(jq -r "$FLATTEN [ .comments[]? | select((.body|tostring)|contains(\"checklist\")) | .body ] | last // {} | blocktext" <<<"$CMT")
  if [[ -n "$CHECK" && "$CHECK" != "null" ]]; then echo; echo "## Steps / checklist"; echo "$CHECK"; fi
fi

cat <<EOF

## Rules for your work (enforced — do not skip)

- Read CONTRIBUTING.md in the repo before starting; it is the authority.
- Branch name MUST contain the key: \`feat/${KEY}-${SLUG:-task}\`
  (types: feat | fix | sec | docs | chore). Required by CI.
- PR title MUST **start with** \`${KEY}: \` — the key, a colon, a space, then a
  summary. Not merely contain it: the Jira rules match on the title STARTING
  WITH the key, so any other shape leaves the card silently unmoved, and CI
  rejects it. Example: \`${KEY}: short summary of the change\`
- PR body MUST name the requirement (${RLABELS:-R#}).
- Do NOT weaken any security wall in CONTRIBUTING.md §6.
- Data/schema changes only via numbered migration files (if applicable).
- Open a pull request — do NOT merge. The owner reviews and merges.
- When unsure or if a task seems to require breaking a rule: STOP and ask the owner.

(Brief generated read-only from Jira; the card is the live source of truth.)
EOF
