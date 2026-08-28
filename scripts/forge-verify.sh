#!/usr/bin/env bash
#
# forge-verify.sh — has this repo's copy of the forge machinery drifted?
#
#   ./scripts/forge-verify.sh          human summary
#   ./scripts/forge-verify.sh --json   machine-readable
#
# The files forge-project distributes are COPIES. That is deliberate: a central
# pointer would let the logic running inside a governed repo change without a PR
# in that repo, and CONTRIBUTING.md's whole premise is that every change reaching
# main is a diff the owner reviewed.
#
# The cost of copies is drift. sync-workflows.py removes it from OUTSIDE by
# comparing real content and opening PRs — that is the fixer, and it is ground
# truth. This script is what the repo can tell you from INSIDE, where the master
# copy is not available: which version it was scaffolded from, and whether its
# copies have been edited since.
#
# It reports. It changes nothing.

set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 2; }
M=.forge/manifest
FORMAT=human; [[ "${1:-}" == "--json" ]] && FORMAT=json

if [[ ! -f "$M" ]]; then
  if [[ "$FORMAT" == json ]]; then echo '{"manifest":false}'; else
    echo "No .forge/manifest — this repo predates provenance stamping, or was not"
    echo "scaffolded by forge-project. Nothing to compare against."
  fi
  exit 0
fi

VER="$(sed -n 's/^forge_version: *//p' "$M" | head -1)"
WHEN="$(sed -n 's/^scaffolded_at: *//p' "$M" | head -1)"

MODIFIED=(); MISSING=(); OK=0
while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]+([^:]+):[[:space:]]*([0-9a-f]+)$ ]] || continue
  f="${BASH_REMATCH[1]}"; want="${BASH_REMATCH[2]}"
  if [[ ! -f "$f" ]]; then MISSING+=("$f"); continue; fi
  have="$(sha256sum "$f" | cut -c1-16)"
  if [[ "$have" == "$want" ]]; then OK=$((OK+1)); else MODIFIED+=("$f"); fi
done < "$M"

# A deliberate variant is legitimate; an unrecorded one is a surprise.
OPTOUT=0
grep -qiE '^FORGE_SYNC=off' .forge/config 2>/dev/null && OPTOUT=1

if [[ "$FORMAT" == json ]]; then
  printf '{"manifest":true,"forge_version":"%s","scaffolded_at":"%s","unchanged":%d,"modified":[' \
    "$VER" "$WHEN" "$OK"
  s=""; for f in "${MODIFIED[@]:-}"; do [[ -z "$f" ]] && continue; printf '%s"%s"' "$s" "$f"; s=","; done
  printf '],"missing":['
  s=""; for f in "${MISSING[@]:-}"; do [[ -z "$f" ]] && continue; printf '%s"%s"' "$s" "$f"; s=","; done
  printf '],"sync_optout":%s}\n' "$( ((OPTOUT)) && echo true || echo false )"
  exit 0
fi

B=$'\e[1m'; Y=$'\e[33m'; G=$'\e[32m'; Z=$'\e[0m'
printf '%sForge provenance%s\n' "$B" "$Z"
printf '  scaffolded from  suru-skills %s  (%s)\n' "${VER:-unknown}" "${WHEN:-unknown}"
printf '  unchanged        %d file(s)\n' "$OK"

if (( ${#MODIFIED[@]} )); then
  printf '  %smodified locally%s %d file(s):\n' "$Y" "$Z" "${#MODIFIED[@]}"
  printf '    %s\n' "${MODIFIED[@]}"
  if (( OPTOUT )); then
    printf '  FORGE_SYNC=off is set, so these are recorded as deliberate variants.\n'
  else
    printf '  %sThese differ from what was distributed, and nothing records that as\n' "$Y"
    printf '  intended.%s If deliberate, set FORGE_SYNC=off in .forge/config so\n' "$Z"
    printf '  sync-workflows.py stops trying to revert them. If not, they are drift.\n'
  fi
fi
(( ${#MISSING[@]} )) && { printf '  %smissing%s %d file(s):\n' "$Y" "$Z" "${#MISSING[@]}"; printf '    %s\n' "${MISSING[@]}"; }

printf '\n%sThis says what changed HERE, not whether upstream moved on.%s\n' "$B" "$Z"
printf 'Run sync-workflows.py --discover from suru-skills for that — it compares\n'
printf 'real content across every repo, which is the only ground truth.\n'
