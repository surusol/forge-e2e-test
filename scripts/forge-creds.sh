#!/usr/bin/env bash
#
# forge-creds.sh — resolve Jira credentials, preferring 1Password.
#
# Sourced by the shell tools; the Python ones call it with --export.
#
#   source "$(dirname "$0")/forge-creds.sh"     # sets JIRA_* in the caller
#   ./forge-creds.sh --export                   # prints KEY=VALUE for eval
#   ./forge-creds.sh --check                    # says where it resolved from
#
# ORDER, and why:
#   1. Already-set environment      an explicit override always wins
#   2. 1Password                    the source of truth
#   3. ~/.config/forge/*.env        fallback, and what CI without `op` uses
#
# 1Password first because a plaintext token on disk drifts. That is not
# hypothetical here: the file and the vault held the same expired token, then
# the vault was rotated and the file was not, and every tool kept failing
# against a credential that had already been fixed. Reading the vault directly
# removes the copy that goes stale.
#
# Configure with:
#   FORGE_OP_ITEM   default "Atlassian surubot"   (the BOT, not the owner)
#   FORGE_OP_VAULT  default "AI keys"
#   FORGE_OP_FIELD  default "api_key"
#   FORGE_PROFILE   default "jira.env"            fallback file
#
# The default is deliberately the bot: card work should be attributed to it, and
# an owner credential used by habit is how a service ends up quietly running with
# admin rights nobody chose.

FORGE_OP_ITEM="${FORGE_OP_ITEM:-Atlassian surubot}"
FORGE_OP_VAULT="${FORGE_OP_VAULT:-AI keys}"
FORGE_OP_FIELD="${FORGE_OP_FIELD:-api_key}"
FORGE_PROFILE="${FORGE_PROFILE:-jira.env}"
FORGE_CRED_SOURCE=""

_forge_from_op() {
  # `op` absent is normal — CI has no vault, and falling through silently is
  # correct there. `op` PRESENT but the item unreadable is different: it means a
  # typo, a renamed item, or a session that needs re-auth, and falling through
  # silently would leave the vault quietly not being the source of truth while
  # everything appears to work. Say so, then fall back anyway.
  command -v op >/dev/null 2>&1 || return 1
  local json
  if ! json="$(op item get "$FORGE_OP_ITEM" --vault "$FORGE_OP_VAULT" --format json 2>/dev/null)" \
     || [[ -z "$json" ]]; then
    echo "forge-creds: 1Password is available but '$FORGE_OP_VAULT/$FORGE_OP_ITEM' could not be read;" >&2
    echo "             falling back to ~/.config/forge/$FORGE_PROFILE. Check the item name," >&2
    echo "             the vault, or run 'op signin'." >&2
    return 1
  fi
  local out
  # Field name passed as argv, not via the environment: these are plain shell
  # variables, not exported, and relying on export makes the failure silent —
  # python raises KeyError, the || fires, and it falls back to the file looking
  # exactly like "1Password had nothing".
  out="$(printf '%s' "$json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
f={ (x.get('label') or x.get('id') or ''): x.get('value') for x in d.get('fields',[]) }
tok = f.get(sys.argv[1])
email = f.get('email') or f.get('username')
url = next((u.get('href') for u in d.get('urls',[]) if 'atlassian.net' in (u.get('href') or '')), None) \
      or f.get('url') or f.get('URL')
if not (tok and email): raise SystemExit(1)
print('JIRA_API_TOKEN=' + tok)
print('JIRA_EMAIL=' + email)
if url: print('JIRA_BASE_URL=' + url.rstrip('/'))
" "$FORGE_OP_FIELD" 2>/dev/null)" || return 1
  [[ -n "$out" ]] || return 1
  # The vault item's url is id.atlassian.com for a login entry, which is not the
  # API host. Only take it when it is actually a site URL.
  while IFS= read -r line; do
    case "$line" in
      JIRA_BASE_URL=*id.atlassian.com*) continue ;;
      *) export "${line?}" ;;
    esac
  done <<<"$out"
  [[ -n "${JIRA_API_TOKEN:-}" && -n "${JIRA_EMAIL:-}" ]]
}

_forge_from_file() {
  local f="$HOME/.config/forge/$FORGE_PROFILE"
  [[ -f "$f" ]] || return 1
  set -a; . "$f"; set +a
  [[ -n "${JIRA_API_TOKEN:-}" && -n "${JIRA_EMAIL:-}" ]]
}

forge_load_creds() {
  if [[ -n "${JIRA_API_TOKEN:-}" && -n "${JIRA_EMAIL:-}" && -n "${JIRA_BASE_URL:-}" ]]; then
    FORGE_CRED_SOURCE="environment"; return 0
  fi
  # The site URL is not a secret, and the vault item cannot supply it: a login
  # entry's url is id.atlassian.com, not the API host. So resolve it separately,
  # nearest-first — the repo knows its own site, and that also lets one machine
  # work against several Jira sites without swapping profiles.
  if [[ -z "${JIRA_BASE_URL:-}" ]]; then
    local root cfg f
    root="$(git rev-parse --show-toplevel 2>/dev/null)"
    cfg="${root:-.}/.forge/config"
    f="$HOME/.config/forge/$FORGE_PROFILE"
    for src in "$cfg" "$f"; do
      [[ -f "$src" ]] || continue
      local u; u="$(sed -n 's/^JIRA_BASE_URL=//p' "$src" | head -1 | tr -d '"')"
      [[ -n "$u" ]] && { export JIRA_BASE_URL="$u"; break; }
    done
  fi

  if _forge_from_op;   then FORGE_CRED_SOURCE="1Password: $FORGE_OP_VAULT/$FORGE_OP_ITEM"
  elif _forge_from_file; then FORGE_CRED_SOURCE="file: ~/.config/forge/$FORGE_PROFILE"
  else return 1; fi
  # A token without a site to send it to is not a resolved credential. Returning
  # 0 here emitted `JIRA_BASE_URL=` and let callers fail later, far from the cause.
  [[ -n "${JIRA_BASE_URL:-}" ]] || return 1
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --export)
      forge_load_creds || { echo "could not resolve Jira credentials" >&2; exit 1; }
      printf 'JIRA_BASE_URL=%s\nJIRA_EMAIL=%s\nJIRA_API_TOKEN=%s\n' \
        "$JIRA_BASE_URL" "$JIRA_EMAIL" "$JIRA_API_TOKEN" ;;
    --check|"")
      if forge_load_creds; then
        printf 'resolved from %s\n  site  %s\n  as    %s\n' "$FORGE_CRED_SOURCE" "$JIRA_BASE_URL" "$JIRA_EMAIL"
      else
        echo "could not resolve Jira credentials." >&2
        echo "  token/email: tried \$JIRA_*, 1Password '$FORGE_OP_VAULT/$FORGE_OP_ITEM', ~/.config/forge/$FORGE_PROFILE" >&2
        echo "  site URL:    tried \$JIRA_BASE_URL, ./.forge/config, ~/.config/forge/$FORGE_PROFILE" >&2
        echo "  (a 1Password login item's url is id.atlassian.com, not the API host, so the" >&2
        echo "   site URL must come from .forge/config or the profile)" >&2
        exit 1
      fi ;;
    *) echo "usage: $0 [--check|--export]" >&2; exit 2 ;;
  esac
fi
