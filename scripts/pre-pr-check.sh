#!/usr/bin/env bash
#
# pre-pr-check.sh — the single verification gate for this repo.
#
# The SAME script runs in three places, so local and CI can never disagree
# about what "passing" means:
#
#   .git/hooks/pre-push          before anything leaves your machine  (--push)
#   --json                       machine-readable result for metrics
#   .github/workflows/verify.yml on every pull request                (--ci)
#   you, by hand                 before opening a PR                  (no flag)
#
# Configure it in .forge/config (sourced, plain KEY=value):
#
#   PROJECT_KEY=WID                  # required — Jira key
#   TEST_CMD="go test ./... -race"   # the test suite. UNSET = no test gate.
#   LINT_CMD="golangci-lint run"     # optional
#   BUILD_CMD="go build ./..."       # optional
#   MUTATION_CMD="npx stryker run"   # proves the tests ASSERT, not just execute.
#   MUTATION_WHEN=ci                 #   ci | always. Include the tool's own
#                                    #   threshold flag so it exits non-zero.
#                                    #   Weight this heavily when an AI writes
#                                    #   the tests: "a test that cannot fail" is
#                                    #   a common AI output and nothing else
#                                    #   detects it.
#   SOURCE_PATHS="cmd internal pkg"  # dirs whose change implies behaviour change
#
#   FORGE_LEVEL=L1                   # maturity level — sets every gate default:
#     L0 Scaffold     day one, no code       traceability + secrets block
#     L1 Building     first real code        + tests, build, migrations
#     L2 Established  real docs and specs    + docs, decisions, contracts, gherkin
#     L3 Load-bearing others depend on it    + requirement coverage, mutation
#
#   Any gate may be set explicitly to override its level default:
#     CONTRACT_GATE  the contract may not move in the same PR as the code it
#                    judges. THE control for AI-written work: if the author of
#                    the implementation can also edit the acceptance criteria,
#                    green means "internally consistent", not "correct".
#     DOC_GATE       docs must move with the code
#     ADR_GATE       decision-shaped diffs need a decision record
#     REQ_TEST_GATE  every MUST requirement is named by some test
#     GHERKIN_GATE   no undefined/pending steps; scenarios name a requirement
#     API_GATE       contract changes land with (or before) handler changes
#     MIGRATION_GATE every new migration documents its rollback
#   Each takes: off | warn | adjudicate | block.
#
#     off         not checked
#     warn        reported, does not stop the run
#     adjudicate  blocks UNLESS a valid override record justifies it
#     block       blocks, full stop
#
#   `adjudicate` is the hybrid setting. A blocked run is not the end of the
#   conversation: it names what must be decided, and the decision is recorded as
#   a file in .forge/overrides/ rather than made by lowering the gate. See
#   CONTRIBUTING.md §14. An override may carry a `verify:` command; if it does,
#   the gate RUNS it, and the override is void unless it passes — so a blocker
#   is lifted by evidence, never by assertion.
#
#   Some rules ignore overrides entirely (see INVIOLABLE below). Those change
#   only by the owner changing the rule itself, in its own reviewed PR.
#
# Lowering FORGE_LEVEL, or a gate, is a REVIEWED CHANGE — this file is
# version-controlled precisely so that turning a check off has an author, a
# date, and a written reason. A gate you can quietly lower is not a gate.
#
# Gates ship as `warn` so a young repo is not blocked by its own scaffolding.
# Flip each to `block` once the project has real tests and real docs — that is
# a one-word change here, no CI edits.
#
# Exit: 0 all gates passed (warnings allowed), 1 a blocking gate failed.

set -uo pipefail

MODE="local"
case "${1:-}" in
  --ci)   MODE="ci"   ;;
  --push) MODE="push" ;;
  --json) MODE="json" ;;
  --help|-h) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "unknown flag: $1 (try --help)" >&2; exit 2 ;;
esac

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 2; }
cd "$ROOT" || exit 2

# shellcheck disable=SC1091
[[ -f .forge/config ]] && source .forge/config
PROJECT_KEY="${PROJECT_KEY:-}"
SOURCE_PATHS="${SOURCE_PATHS:-src cmd internal pkg lib app}"
FORGE_LEVEL="${FORGE_LEVEL:-L1}"

# A gate's default comes from the maturity level; an explicit setting overrides.
# lvl <gate-level> => "block" once the project has reached that level, else "warn".
lvl() { local need="$1"; [[ "${FORGE_LEVEL#L}" -ge "${need#L}" ]] && echo block || echo warn; }

# Editing an existing promise ALWAYS fails, at every level — that case is the
# whole point. This setting governs only the milder "added in the wrong order".
CONTRACT_GATE="${CONTRACT_GATE:-$(lvl L2)}"
DOC_GATE="${DOC_GATE:-$(lvl L2)}"
MUTATION_GATE="${MUTATION_GATE:-$(lvl L3)}"
ADR_GATE="${ADR_GATE:-$(lvl L2)}"
GHERKIN_GATE="${GHERKIN_GATE:-$(lvl L2)}"
API_GATE="${API_GATE:-$(lvl L2)}"
MIGRATION_GATE="${MIGRATION_GATE:-$(lvl L1)}"
REQ_TEST_GATE="${REQ_TEST_GATE:-$(lvl L3)}"

# Rules that no override can lift. Each is either a legal/security matter or the
# specific thing that makes the rest of the system meaningful — a gate you can
# argue your way past on the day you most want to is not a gate.
INVIOLABLE="secrets contract-edit migration-edited adr-numbering stray-keys branch-name"

OVERRIDES_DIR="${OVERRIDES_DIR:-.forge/overrides}"
TODAY="$(date +%F)"

FAILED=0
WARNED=0
ADJUDICATED=0
declare -a EVENTS=()
if [[ -t 1 ]]; then R=$'\e[31m'; Y=$'\e[33m'; G=$'\e[32m'; B=$'\e[1m'; Z=$'\e[0m'
else R=""; Y=""; G=""; B=""; Z=""; fi

record() { EVENTS+=("$1|$2|$3"); }   # gate|outcome|detail
# Every blocking outcome is captured, including the hard fails that never pass
# through gate(). Metrics are only useful if nothing is silently absent.
pass() { printf '%s  ok  %s%s\n' "$G" "$Z" "$1"; }
warn() { printf '%s warn %s%s\n' "$Y" "$Z" "$1"; WARNED=$((WARNED+1)); record "${CURRENT:-?}" warn ""; }
fail() { printf '%s FAIL %s%s\n' "$R" "$Z" "$1"; FAILED=$((FAILED+1)); record "${CURRENT:-?}" fail ""; }
skip() { printf '  --   %s\n' "$1"; }
CURRENT=""
section() { CURRENT="$1"; printf '\n%s== %s ==%s\n' "$B" "$1" "$Z"; }

# A gate whose config says `warn` reports but does not block.
# --- override records ------------------------------------------------------
# A flat YAML file in .forge/overrides/ that justifies one gate firing. It is
# committed, so lifting a blocker is a reviewed diff with an author and a date —
# the same property that makes lowering a gate visible.
yval() { sed -n "s/^$2: *//p" "$1" | head -1 | sed 's/^"//;s/"$//'; }

# NOTE: this runs inside $( ), so anything it prints to stdout is captured as
# the return value. Diagnostics go to $OV_DIAG and the caller replays them —
# otherwise a malformed override is silently ignored, which is the worst
# outcome: the gate blocks and nobody can see why the record did not apply.
OV_DIAG="$(mktemp)"; trap 'rm -f "$OV_DIAG" 2>/dev/null' EXIT
ov_note() { printf '%s\n' "$1" >> "$OV_DIAG"; }

find_override() { # find_override <VAR_NAME> -> echoes file path, or nothing
  local want="$1" f g scope exp iss
  : > "$OV_DIAG"
  [[ -d "$OVERRIDES_DIR" ]] || return 1
  for f in "$OVERRIDES_DIR"/*.yml "$OVERRIDES_DIR"/*.yaml; do
    [[ -f "$f" ]] || continue
    g="$(yval "$f" gate)";        [[ "$g" == "$want" ]] || continue

    # Expiry. An override with no end date is a permanent hole, so it is void.
    exp="$(yval "$f" expires)"
    if [[ -z "$exp" ]]; then
      ov_note "override $f has no expires: — ignored (a permanent exception is a rule change, not an override)"; continue
    fi
    # ISO dates compare correctly as strings; no date(1) portability trap.
    if [[ "$exp" < "$TODAY" ]]; then
      ov_note "override $f expired on $exp — ignored"; continue
    fi

    # Scope. `standing` applies anywhere; `issue` only to its own card.
    scope="$(yval "$f" scope)"; iss="$(yval "$f" issue)"
    if [[ "$scope" == "issue" ]]; then
      [[ -n "$iss" && "$BRANCH" == *"$iss"* ]] || continue
    fi

    [[ -n "$(yval "$f" decided_by)" ]] || { ov_note "override $f names no decided_by — ignored"; continue; }
    printf '%s' "$f"; return 0
  done
  return 1
}

# The part that makes this evidence rather than assertion: if the override
# states a machine-checkable claim, the claim is re-run here, every time.
override_holds() { # override_holds <file>
  local f="$1" v; v="$(yval "$f" verify)"
  [[ -z "$v" ]] && return 0
  if ( eval "$v" ) >/tmp/forge-override.log 2>&1; then return 0; fi
  printf '      verify command failed: %s\n' "$v"
  sed 's/^/        | /' /tmp/forge-override.log | tail -n 10
  return 1
}

gate() { # gate <setting> <message> <var-name> [rule-id]
  local mode="$1" msg="$2" var="$3" rule="${4:-}"

  # Inviolable rules ignore both the configured mode and any override.
  if [[ -n "$rule" && " $INVIOLABLE " == *" $rule "* ]]; then
    fail "$msg"; record "$var" inviolable "$rule"; return
  fi

  case "$mode" in
    off)   skip "$var is off"; record "$var" off "" ;;
    warn)  warn "$msg (gate=warn — set $var=adjudicate or block in .forge/config to enforce)"
           record "$var" warn "" ;;
    adjudicate)
      local ov
      ov="$(find_override "$var")"; local found=$?
      # Replay anything find_override rejected, so a malformed record is visible.
      if [[ -s "$OV_DIAG" ]]; then while IFS= read -r l; do warn "$l"; done < "$OV_DIAG"; fi
      if (( found == 0 )); then
        if override_holds "$ov"; then
          ADJUDICATED=$((ADJUDICATED+1))
          printf '%s over %s%s\n' "$Y" "$Z" "$msg"
          printf '      lifted by %s — %s, until %s\n' \
            "$ov" "$(yval "$ov" decided_by)" "$(yval "$ov" expires)"
          record "$var" overridden "$ov"
        else
          fail "$msg
       An override exists ($ov) but its own verify: check FAILED, so the claim
       it rests on is not true right now. Fix the claim or withdraw the override."
          record "$var" override-void "$ov"
        fi
      else
        fail "$msg
       This gate is set to adjudicate: it blocks, but the decision is reviewable.
       If this is genuinely correct work, record why in $OVERRIDES_DIR/ (see
       CONTRIBUTING.md §14) — with a verify: command if the claim is checkable.
       Do NOT lower $var to get past it."
        record "$var" blocked ""
      fi ;;
    *)     fail "$msg"; record "$var" blocked "" ;;
  esac
}

# ── what changed ─────────────────────────────────────────────────────────────
BASE="${FORGE_BASE_REF:-origin/${DEFAULT_BRANCH:-main}}"
git rev-parse --verify -q "$BASE" >/dev/null 2>&1 || BASE="${DEFAULT_BRANCH:-main}"
if MERGE_BASE="$(git merge-base HEAD "$BASE" 2>/dev/null)"; then
  CHANGED="$(git diff --name-only "$MERGE_BASE"..HEAD)"
else
  MERGE_BASE=""
  CHANGED="$(git diff --name-only HEAD~1..HEAD 2>/dev/null || true)"
fi
changed_matching() { [[ -n "$CHANGED" ]] && grep -qE "$1" <<<"$CHANGED"; }
SRC_RE="$(tr ' ' '|' <<<"$(echo "$SOURCE_PATHS" | xargs)")"

section "Scope"
printf '  maturity: %s  (contract=%s doc=%s adr=%s gherkin=%s api=%s migration=%s req-test=%s)\n' \
  "$FORGE_LEVEL" "$CONTRACT_GATE" "$DOC_GATE" "$ADR_GATE" "$GHERKIN_GATE" "$API_GATE" "$MIGRATION_GATE" "$REQ_TEST_GATE"
if [[ -z "$CHANGED" ]]; then
  skip "no changes against $BASE — nothing to verify"
else
  printf '  %s file(s) changed against %s\n' "$(wc -l <<<"$CHANGED")" "$BASE"
fi

# ── 1. branch naming ─────────────────────────────────────────────────────────
section "Traceability"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ -z "$PROJECT_KEY" ]]; then
  skip "no PROJECT_KEY in .forge/config — branch-name check skipped"
elif [[ "$BRANCH" == "${DEFAULT_BRANCH:-main}" ]]; then
  skip "on the default branch — branch-name check not applicable"
elif [[ "$BRANCH" =~ ^(feat|fix|sec|docs|chore)/${PROJECT_KEY}-[0-9]+-[a-z0-9._-]+$ ]]; then
  pass "branch '$BRANCH' matches <type>/${PROJECT_KEY}-<n>-<slug>"
else
  fail "branch '$BRANCH' must match <type>/${PROJECT_KEY}-<n>-<slug> — types: feat fix sec docs chore (CONTRIBUTING.md §4)"
fi

# Referencing another card's key anywhere in the branch's commits will transition
# that card on merge. This is the single most common traceability accident.
if [[ -n "$PROJECT_KEY" && -n "$MERGE_BASE" ]]; then
  MY_KEY="$(grep -oE "${PROJECT_KEY}-[0-9]+" <<<"$BRANCH" | head -1)"
  if [[ -n "$MY_KEY" ]]; then
    STRAY="$(git log --format='%s%n%b' "$MERGE_BASE"..HEAD \
             | grep -oE "${PROJECT_KEY}-[0-9]+" | sort -u | grep -vFx "$MY_KEY" || true)"
    [[ -n "$STRAY" ]] && fail "commits mention other cards: $(tr '\n' ' ' <<<"$STRAY")— merging would close them (CONTRIBUTING.md §4)"
  fi
fi

# ── 2. secrets ───────────────────────────────────────────────────────────────
section "Secrets"
if command -v gitleaks >/dev/null 2>&1; then
  if gitleaks detect --no-banner --redact -q >/dev/null 2>&1; then
    pass "gitleaks found no secrets"
  else
    fail "gitleaks flagged a potential secret — do not push; rotate anything real"
  fi
else
  skip "gitleaks not installed — CI still scans (see reference/ci-hardening.md)"
fi
if changed_matching '(^|/)\.env$|\.pem$|\.p12$|id_rsa'; then
  fail "a credential-shaped file is in the diff: $(grep -E '(^|/)\.env$|\.pem$|\.p12$|id_rsa' <<<"$CHANGED" | tr '\n' ' ')"
fi

# ── 3. lint / build / test ───────────────────────────────────────────────────
section "Build and tests"
run_cmd() { # run_cmd <label> <cmd>
  local label="$1" cmd="$2"
  [[ -z "$cmd" ]] && { skip "no ${label^^}_CMD in .forge/config — $label gate off"; return; }
  printf '  running: %s\n' "$cmd"
  if ( eval "$cmd" ) >/tmp/forge-$label.log 2>&1; then
    pass "$label passed"
  else
    fail "$label FAILED — nothing lands until this is green"
    tail -n 30 "/tmp/forge-$label.log" | sed 's/^/      | /'
  fi
}
run_cmd lint  "${LINT_CMD:-}"
run_cmd build "${BUILD_CMD:-}"
run_cmd test  "${TEST_CMD:-}"

# Coverage says a line ran. Mutation says something ASSERTED about it — it is
# the only mechanical check that a test would notice if the code were wrong.
# Slow, so it is usually CI-only: set MUTATION_WHEN=ci.
if [[ -z "${MUTATION_CMD:-}" ]]; then
  gate "$MUTATION_GATE" "no MUTATION_CMD configured — nothing proves the tests would notice if the code were wrong. This matters most when an AI writes both" MUTATION_GATE
elif [[ "${MUTATION_WHEN:-ci}" == "ci" && "$MODE" != "ci" ]]; then
  skip "mutation testing runs in CI only (MUTATION_WHEN=${MUTATION_WHEN:-ci})"
else
  MUT_BEFORE=$FAILED
  run_cmd mutation "$MUTATION_CMD"
  # run_cmd already failed hard; downgrade to the configured strictness.
  if (( FAILED > MUT_BEFORE )) && [[ "$MUTATION_GATE" != "block" ]]; then
    FAILED=$MUT_BEFORE
    warn "mutation testing failed its threshold (gate=$MUTATION_GATE — set MUTATION_GATE=block to enforce)"
  fi
fi
[[ -z "${TEST_CMD:-}" ]] && warn "no TEST_CMD configured — this repo has no automated proof it works. Set it in .forge/config."

# ── 4. docs move with the code ───────────────────────────────────────────────
section "Docs-as-code"
if [[ -z "$CHANGED" ]]; then
  skip "no changes"
elif changed_matching "^(${SRC_RE})/"; then
  # REQUIREMENTS.md is deliberately NOT in this list. It is the contract being
  # judged, not documentation of what was built — letting it satisfy this gate
  # would reward an author for amending the target to match the shot.
  if changed_matching '^(docs/|README)'; then
    pass "source changed and documentation changed in the same commit range"
  else
    gate "$DOC_GATE" "source changed under ${SOURCE_PATHS// /, } but no doc changed — a follow-up doc PR is not acceptable (CONTRIBUTING.md §11)" DOC_GATE
  fi
else
  skip "no source-path changes"
fi

# ── 4b. the contract may not move with the code it judges ────────────────────
#
# The control that matters most when an AI writes the implementation. A test
# suite written by the same author as the code encodes that author's
# understanding — so "green" means internally consistent, not correct. The only
# structural defence is that the thing being tested against is fixed BEFORE, and
# by someone OTHER than, the thing being tested.
#
# Amending the contract stays entirely legitimate. It just has to be its own PR,
# judged on its own merits, before the work that depends on it.
section "Contract integrity"
CONTRACT_RE='^(REQUIREMENTS\.md|features/.*\.feature)$'
if [[ -z "$CHANGED" ]]; then
  skip "no changes"
elif ! changed_matching "$CONTRACT_RE"; then
  skip "contract untouched"
elif ! changed_matching "^(${SRC_RE})/"; then
  pass "contract changed alone — this is the right shape for a contract change"
elif [[ -z "$MERGE_BASE" ]]; then
  gate "$CONTRACT_GATE" "contract and implementation changed together (cannot classify without a merge base)" CONTRACT_GATE
else
  # Editing an existing promise is the dangerous case. Adding a new one
  # alongside new code is merely the wrong order.
  MODIFIED="$(git diff --diff-filter=M --name-only "$MERGE_BASE"..HEAD 2>/dev/null | grep -E "$CONTRACT_RE" || true)"
  ADDED="$(git diff --diff-filter=A --name-only "$MERGE_BASE"..HEAD 2>/dev/null | grep -E "$CONTRACT_RE" || true)"
  if [[ -n "$MODIFIED" ]]; then
    fail "the goalposts moved: $(tr '\n' ' ' <<<"$MODIFIED")was EDITED in the same change as the implementation it judges.
       Split this: amend the contract in its own PR, get it approved, then implement against it.
       (An implementer who can edit the acceptance criteria is not being tested by them.)"
  elif [[ -n "$ADDED" ]]; then
    gate "$CONTRACT_GATE" "new contract file(s) $(tr '\n' ' ' <<<"$ADDED")added alongside the implementation — land the spec first, approved, then build against it" CONTRACT_GATE
  fi
fi

# ── 5. decision-shaped changes need an ADR ───────────────────────────────────
section "Decision record"
DECISION_RE='(^|/)(package\.json|go\.mod|Cargo\.toml|pyproject\.toml|requirements\.txt|Gemfile|pom\.xml|build\.gradle|composer\.json)$|(^|/)(Dockerfile|docker-compose\.ya?ml)$|(^|/)(schema|migrations)/|\.proto$|(^|/)openapi\.(ya?ml|json)$'
if [[ -z "$CHANGED" ]]; then
  skip "no changes"
elif changed_matching "$DECISION_RE"; then
  TRIGGER="$(grep -E "$DECISION_RE" <<<"$CHANGED" | head -3 | tr '\n' ' ')"
  if changed_matching '^docs/adr/[0-9]{4}-'; then
    pass "decision-shaped change accompanied by an ADR"
  else
    gate "$ADR_GATE" "changed $TRIGGER without an ADR in docs/adr/ — dependencies, schemas and interfaces constrain future work (ADR-0000)" ADR_GATE
  fi
else
  skip "no decision-shaped files touched"
fi

# ADR hygiene: a superseded ADR must point forward, and numbers must be unique.
if [[ -d docs/adr ]]; then
  ADR_FAILED_BEFORE=$FAILED
  DUPES="$(find docs/adr -name '[0-9][0-9][0-9][0-9]-*.md' 2>/dev/null \
           | while IFS= read -r f; do basename "$f" | cut -c1-4; done | sort | uniq -d)"
  [[ -n "$DUPES" ]] && fail "duplicate ADR numbers: $(tr '\n' ' ' <<<"$DUPES")— numbers are permanent identifiers, never reuse one"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if grep -qi '^status: *Superseded' "$f" && ! grep -qE '^superseded-by: *\[[0-9]' "$f"; then
      fail "$f is Superseded but names no successor in superseded-by:"
    fi
  done < <(find docs/adr -name '[0-9][0-9][0-9][0-9]-*.md' 2>/dev/null)
  (( FAILED == ADR_FAILED_BEFORE )) && pass "ADR numbering and supersede links consistent"
fi


# ── 6. specs: Gherkin ────────────────────────────────────────────────────────
section "Gherkin"
if [[ ! -d features ]]; then
  skip "no features/ — this project did not adopt Gherkin"
else
  G_BEFORE=$FAILED
  # A scenario naming no requirement is behaviour nobody asked for. The gate
  # looks for `# R4` or `@R4` in the six lines above each Scenario.
  ORPHANS=""
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    while IFS=: read -r ln _; do
      ctx="$(sed -n "$(( ln > 6 ? ln-6 : 1 )),${ln}p" "$f")"
      grep -qE '[#@]\s*R[0-9]+|@R[0-9]+' <<<"$ctx" || ORPHANS+="$f:$ln "
    done < <(grep -nE '^\s*Scenario( Outline)?:' "$f")
  done < <(find features -name '*.feature' 2>/dev/null)
  if [[ -n "$ORPHANS" ]]; then
    gate "$GHERKIN_GATE" "scenarios naming no requirement: ${ORPHANS% } — tag each with # R<n> or @R<n> (features/README.md)" GHERKIN_GATE
  fi

  # A pending/undefined step is a test that proves nothing while showing green.
  PENDING="$(grep -rlniE '^\s*(@(wip|pending|todo|skip)|#\s*(pending|undefined))' features --include='*.feature' 2>/dev/null | tr '\n' ' ')"
  [[ -n "$PENDING" ]] && gate "$GHERKIN_GATE" "pending/wip scenarios on this branch: ${PENDING% } — a pending step is counted as coverage while proving nothing" GHERKIN_GATE

  (( FAILED == G_BEFORE )) && [[ -z "$PENDING" && -z "$ORPHANS" ]] && pass "every scenario names a requirement; none pending"
fi

# ── 7. specs: contracts (OpenAPI / protobuf) ─────────────────────────────────
section "Contracts"
if [[ ! -e api/openapi.yaml && ! -e api/openapi.yml && ! -d api/proto ]]; then
  skip "no api/ contract — this project did not adopt one"
elif [[ -z "$CHANGED" ]]; then
  skip "no changes"
else
  # Contract-first: a handler change with no contract change means the spec was
  # written after the code, at which point it is documentation, not a contract.
  HANDLER_RE="^(${SRC_RE})/.*(handler|route|controller|endpoint|api|server|service)"
  if changed_matching "$HANDLER_RE"; then
    if changed_matching '^api/'; then
      pass "handler change accompanied by a contract change"
    else
      gate "$API_GATE" "changed request-handling code without touching api/ — write the contract first (api/README.md)" API_GATE
    fi
  else
    skip "no handler changes"
  fi

  if changed_matching '^api/proto/' && command -v buf >/dev/null 2>&1; then
    buf lint >/dev/null 2>&1 && pass "buf lint clean" || fail "buf lint failed — run 'buf lint'"
    if [[ -n "$MERGE_BASE" ]]; then
      buf breaking --against ".git#ref=$MERGE_BASE" >/tmp/forge-buf.log 2>&1 \
        && pass "no breaking protobuf changes vs the base branch" \
        || gate "$API_GATE" "buf breaking: this change breaks existing callers — needs an ADR and a major version bump (api/README.md)" API_GATE
    fi
  fi

  if changed_matching '^api/openapi\.ya?ml$'; then
    if command -v spectral >/dev/null 2>&1; then
      spectral lint api/openapi.y*ml >/dev/null 2>&1 && pass "OpenAPI lints clean" || fail "spectral lint failed on api/openapi.yaml"
    elif command -v python3 >/dev/null 2>&1; then
      python3 -c "import yaml,sys; yaml.safe_load(open([p for p in ('api/openapi.yaml','api/openapi.yml') if __import__('os').path.exists(p)][0]))" 2>/dev/null \
        && pass "OpenAPI parses (install spectral for real linting)" \
        || fail "api/openapi.yaml is not valid YAML"
    fi
  fi
fi

# ── 8. specs: migrations ─────────────────────────────────────────────────────
section "Migrations"
if [[ ! -d migrations ]]; then
  skip "no migrations/ — this project has no database"
elif [[ -z "$CHANGED" ]]; then
  skip "no changes"
else
  NEW_MIG="$(grep -E '^migrations/[0-9]+.*\.(sql|py|js|ts|go)$' <<<"$CHANGED" || true)"
  if [[ -z "$NEW_MIG" ]]; then
    skip "no migration changes"
  else
    M_BEFORE=$FAILED
    while IFS= read -r m; do
      [[ -z "$m" || ! -f "$m" ]] && continue
      grep -qiE 'rollback|irreversible|cannot be undone' "$m" \
        || gate "$MIGRATION_GATE" "$m documents no rollback path — state how to undo it, or that it cannot be undone and why (migrations/README.md)" MIGRATION_GATE
      grep -qE '\bR[0-9]+\b' "$m" \
        || gate "$MIGRATION_GATE" "$m names no requirement (R<n>)" MIGRATION_GATE
    done <<<"$NEW_MIG"

    # An applied migration is a historical record; editing one rewrites history
    # that other environments have already acted on.
    if [[ -n "$MERGE_BASE" ]]; then
      EDITED="$(git diff --diff-filter=M --name-only "$MERGE_BASE"..HEAD -- migrations/ 2>/dev/null | tr '\n' ' ')"
      [[ -n "$EDITED" ]] && fail "existing migration(s) modified: ${EDITED% }— migrations are never edited after running; write a new one"
    fi
    (( FAILED == M_BEFORE )) && pass "new migrations document rollback and name a requirement"
  fi
fi

# ── 9. the build is the spec: every MUST requirement names a test ────────────
section "Requirement coverage"
if [[ ! -f REQUIREMENTS.md ]]; then
  skip "no REQUIREMENTS.md"
else
  # A requirement is covered when its ID appears in the test tree: a file named
  # like a test, a file under a test directory, or a Gherkin scenario.
  TEST_PATHS=()
  for d in test tests spec specs features __tests__; do [[ -d "$d" ]] && TEST_PATHS+=("$d"); done
  UNCOVERED=""
  while IFS= read -r req; do
    found=""
    (( ${#TEST_PATHS[@]} )) && grep -rqE "\b${req}\b" "${TEST_PATHS[@]}" 2>/dev/null && found=1
    [[ -z "$found" ]] && grep -rqE "\b${req}\b" --include='*test*' --include='*spec*' --include='*.feature' . 2>/dev/null && found=1
    [[ -z "$found" ]] && UNCOVERED+="$req "
  done < <(grep -oE '^#+ *(R[0-9]+)' REQUIREMENTS.md | grep -oE 'R[0-9]+' | sort -u)
  if [[ -z "$UNCOVERED" ]]; then
    pass "every requirement ID appears in the test tree"
  else
    gate "$REQ_TEST_GATE" "requirements with no test naming them: ${UNCOVERED% } — an acceptance criterion nothing checks is a wish (CONTRIBUTING.md §12)" REQ_TEST_GATE
  fi
fi

# ── verdict ──────────────────────────────────────────────────────────────────
# Metrics. Drift is measured as well as blocked: a gate overridden repeatedly is
# evidence the GATE is miscalibrated, not that the team is careless. forge-audit
# reads these over time.
if [[ "$MODE" == "json" || -n "${FORGE_JSON:-}" ]]; then
  {
    printf '{"level":"%s","branch":"%s","failed":%d,"warned":%d,"overridden":%d,"events":[' \
      "$FORGE_LEVEL" "$BRANCH" "$FAILED" "$WARNED" "$ADJUDICATED"
    sep=""
    for e in "${EVENTS[@]:-}"; do
      [[ -z "$e" ]] && continue
      IFS='|' read -r g o d <<<"$e"
      printf '%s{"gate":"%s","outcome":"%s","detail":"%s"}' "$sep" "$g" "$o" "$d"; sep=","
    done
    printf ']}\n'
  } > "${FORGE_JSON:-/dev/stdout}"
fi

printf '\n%s────────────────────────────────────────%s\n' "$B" "$Z"
if (( ADJUDICATED > 0 )); then
  printf '%s%d gate(s) lifted by recorded override.%s Each is a committed decision with an\n' "$Y" "$ADJUDICATED" "$Z"
  printf 'author, a date and an expiry — not a lowered gate. If the same override keeps\n'
  printf 'recurring, the gate is probably wrong: fix the gate, in its own PR.\n'
fi
if (( FAILED > 0 )); then
  printf '%sBLOCKED%s — %d failure(s), %d warning(s).\n' "$R" "$Z" "$FAILED" "$WARNED"
  [[ "$MODE" == "push" ]] && printf 'Fix them, or `git push --no-verify` to override (CI will still refuse the merge).\n'
  exit 1
fi
printf '%sPASS%s — 0 failures, %d warning(s).\n' "$G" "$Z" "$WARNED"
(( WARNED > 0 )) && printf 'Warnings are gates still set to `warn` in .forge/config. Tighten them when ready.\n'
exit 0
