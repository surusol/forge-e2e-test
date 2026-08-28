# Contributing to Forge E2E Test

**Read this before doing anything in this repository — human or LLM.** It is the
single source of truth for *how* work happens here. Follow it exactly.

If you are an AI agent (any coding assistant), these rules bind you; when in
doubt, **stop and ask the owner rather than improvise.**

---

## 1. Prime directive: the owner controls everything

- **You propose; the owner disposes.** Every change reaches the default branch
  and production only as a pull request the **owner** reviews and merges. No
  agent merges its own PR, deploys, or transitions board items (the board is the
  owner's after initial setup).
- **When unsure, stop.** Ask the owner a specific question. Do not guess on
  security, scope, or destructive actions.

## 2. Source-of-truth hierarchy

If two sources conflict, the higher one wins — and you flag it, you do not
silently pick one.

```
docs/OVERVIEW.md   ← north star (what & why, plain language)
  └ REQUIREMENTS.md ← numbered requirements R1..Rn (the contract)
      └ docs/adr/*.md   ← decision log: WHY we build it this way (immutable)
          └ docs specs      ← detail as needed
              └ execution playbook
                  └ Jira FTEST cards
```

`REQUIREMENTS.md` says what must be true. `docs/adr/` says why we chose this
way of making it true. The test suite says whether it currently is true.

## 3. How work is structured

- Work is **Jira issues** in project `FTEST` ().
  Epics = phases/themes; Tasks = build steps; Subtasks = one-shot pieces.
- **Getting a task if your tool has no Jira connector:** run the read-only
  exporter and use its output as your prompt —
  ```
  ./scripts/jira-brief.sh FTEST-19    # a card + its subtasks
  ./scripts/jira-brief.sh FTEST-87    # a single subtask
  ```
  It prints a self-contained brief: the task, its steps, and these rules, with
  the exact branch/PR names to use. It only reads Jira. If you can't run it, ask
  the owner to paste you a brief.
- **One card → one focused PR.** Don't bundle unrelated work or expand scope
  without the owner amending the card.

## 4. Branch & PR naming — MUST include the Jira key (CI-enforced)

- Branch: `<type>/FTEST-<n>-<short-slug>` (types: `feat` `fix` `sec`
  `docs` `chore`).
- **PR title must START WITH `FTEST-<n>: `** followed by a summary —
  `FTEST-12: saved-search storage`. Not "contains", not "mentions":
  **starts with**, colon, space, summary.

  This is not style. The Jira Automation rules match with a `STARTS_WITH`
  comparison against the PR title, so a title in any other shape matches no
  rule and the card **silently never moves** — no error, no notification, the
  board just quietly stops describing reality. CI enforces the exact shape the
  automation expects so that failure becomes loud instead.
- The title's key and the branch's key must be the **same card**. If they
  disagree, the automation follows the title while a reviewer reads the branch.
- PR body must name the requirement served (`R#`). A PR missing it is rejected.
- The key is what links your work to the Jira card. No key = no traceability =
  rejected.
- **Reference only THIS card's key** — in the branch, PR title, PR body, and
  commit messages. A PR is linked to *every* `FTEST-nnn` it mentions
  on any of those four surfaces, and the merge automation transitions all of
  them. Naming another card closes work nobody did.

  This is checked on all four surfaces, by two different things, because no one
  place can see them all:

  | Surface | Checked by |
  |---|---|
  | Branch name | defines *this* card's key — the others are compared against it |
  | Commit messages | `pre-pr-check.sh`, locally and in CI |
  | PR title | the `stray-keys` CI job |
  | PR body | the `stray-keys` CI job |

  It matters doubly if the repo squash-merges: GitHub builds the squash commit
  message from the PR title and body, so a stray key there becomes permanent
  history.

  **To refer to other work**, describe it in words — "the CI-pipeline card", not
  `FTEST-10`. **To record a real dependency**, add an issue link on the
  Jira card itself (Blocks / Relates to). That is what the link field is for: it
  is structured, visible on both cards, and — unlike prose — transitions
  nothing.

## 5. Requirement traceability

Every PR names the requirement(s) it serves. Work serving no requirement is
scope creep — stop, or the owner amends `REQUIREMENTS.md` (its own PR) first.

## 6. Security walls you must never weaken

1. **No secrets in the repo.** Use encrypted secrets or a secret manager.
2. **Least privilege.** Tokens and integrations get the narrowest scope that works.
3. **Human approval for risky or destructive actions.** Anything that deletes
   data, touches production, or acts on third parties needs an explicit human
   decision — never automated by an LLM or by convenience code.
4. **Untrusted input stays untrusted.** Validate external and model-generated
   content before it drives actions or is rendered.
5. **Single blast radius by default.** Prefer one-target actions; gate any bulk
   operation behind an explicit staged rollout.

## 7. Data/schema changes

If this project has a database, schema changes happen only through numbered
migration files, each run preceded by an automatic backup, each documenting its
rollback. Never ad-hoc-edit a live database.

## 8. CI gates — nothing lands red

**One script is the gate: `./scripts/pre-pr-check.sh`.** It runs in three
places and means the same thing in all three, so "it passed locally" and "it
passed CI" can never diverge:

| Where | When | Authority |
|---|---|---|
| `.git/hooks/pre-push` | before your commits leave your machine | advisory — bypassable with `git push --no-verify` |
| `.github/workflows/verify.yml` | on every PR | **blocking** — a required status check |
| your terminal | whenever you want | advisory |

Run it before you open a PR:

```bash
./scripts/pre-pr-check.sh
```

It checks branch naming and stray card keys, secrets, **lint/build/tests**,
docs-as-code (§11), decision records (§10), and requirement coverage (§12).
Stack-specific commands live in `.forge/config` — not in the workflow — so the
same script works everywhere.

Gates marked `warn` in `.forge/config` report without blocking; the owner
tightens them to `block` as the project matures. `TEST_CMD` failing is **always**
blocking, at every maturity level.

### Weakening a gate is itself a reviewed change

`.forge/config` is version-controlled on purpose. Turning a gate from `block`
to `warn`, emptying `TEST_CMD`, narrowing `SOURCE_PATHS`, or dropping a job
from the required-checks list shows up as a **diff in a PR the owner reviews** —
exactly like amending `REQUIREMENTS.md`. It needs its own PR and a written
reason, and it never rides along inside a feature PR.

A gate you can quietly lower is not a gate. If a check is wrong, fix the check
in the open; do not route around it.

The local hook is deliberately bypassable and deliberately not the authority.
Branch protection is: `main` takes pull requests only, and the merge button
stays disabled until `Verify` and the `pr-checks` jobs are green. Do not work
around a red check — fix it, or say out loud why the check is wrong and fix the
check in its own PR.

## 9. Commit conventions

Small, focused commits; clear messages (what and why). Match surrounding style;
don't reformat unrelated lines. Don't leave reviewer-directed comments in code —
that's what the PR body is for.

## 10. Decisions are recorded (ADRs)

Any choice that **constrains future changes** gets an ADR in `docs/adr/` before
or alongside the code that implements it: dependencies and third-party
services, module/service boundaries, data shape and storage, protocols and
public interfaces, auth and trust boundaries, hosting and recurring cost, and
deliberately accepted risks or deferrals.

Cheap-to-reverse, local choices do not need one. When unsure, write one — they
are a page.

- Copy `docs/adr/TEMPLATE.md` → `docs/adr/NNNN-kebab-title.md`, next number, no
  reuse. Numbers are permanent identifiers.
- **An accepted ADR is never edited.** Changed your mind? Write a new ADR,
  set its `supersedes:`, and flip the old one's `status:` to `Superseded` with
  a `superseded-by:`. Status changes and typo fixes are the only edits allowed.
- Every PR answers the `ADR:` line — a number, or `N/A — <reason>`. CI enforces
  that the line is answered, not that an ADR exists.

The rules and the full trigger list are in
`docs/adr/0000-record-architecture-decisions.md`, which is itself an ADR.

## 11. Docs-as-code — documentation moves with the code

Documentation lives in this repo, in Markdown, and is reviewed in the same pull
request as the change it describes. **A follow-up documentation PR is not
acceptable** — that is how docs rot, and a doc that is confidently wrong is
worse than no doc at all.

- A PR that changes behaviour updates the doc that describes that behaviour, in
  the same PR. `pre-pr-check.sh` flags source changes with no accompanying doc
  change (`DOC_GATE`).
- **One fact, one home.** If something is stated in `REQUIREMENTS.md`, other
  documents link to it rather than restating it. Duplicated facts are how two
  documents come to disagree.
- If a fact can be checked by a machine, do not write it in prose — encode it in
  a type, a schema, a config file, or a test. Prose is for *why*; code, schemas
  and tests are for *what*.
- Stale beats missing only when it is marked: if a doc is known-wrong and you
  cannot fix it now, mark it deprecated at the top rather than leaving it
  looking authoritative.

## 12. The build is the spec

A written acceptance criterion nothing checks is a wish. The suite is what
actually holds the product to its requirements over time.

- **Acceptance criteria must be falsifiable.** "Fast", "reliable", "intuitive"
  cannot be tested, so they cannot be shipped against. Write the criterion so a
  machine could disagree with it — "p95 search latency under 400 ms at 1 000
  indexed items" — at requirement-writing time, before any code exists. This is
  where test quality is actually decided; everything downstream inherits it.
- Every MUST requirement in `REQUIREMENTS.md` names the test(s) that prove it,
  and each such test names its requirement ID (`R7`) in its name or a comment.
  `pre-pr-check.sh` reports requirements no test mentions (`REQ_TEST_GATE`).
- **A test that has never failed has proved nothing.** Write the test first, or
  break the code deliberately once and watch it go red. CI can check that a test
  exists and is named for `R7`; only you can check that it would notice if the
  behaviour were wrong. Where the stack supports it, `MUTATION_CMD` automates
  that judgement — it breaks the code on purpose and fails if the suite stays
  green.
- **Contract-first where a contract exists.** OpenAPI/protobuf/SQL schema files
  are the source of truth; clients, stubs and docs are generated from them, not
  hand-written alongside them.
- Tunable behaviour (thresholds, limits, balance, pricing) lives in
  version-controlled data files, not constants scattered through the code. The
  data file is the documentation of that behaviour.
- A bug fix lands with a test that fails before it and passes after. No test,
  no fix — you have no evidence it is fixed or that it stays fixed.

## 13. Working with AI contributors

Most code here is written by LLMs. That does not change the rules — it changes
which rules are load-bearing, because it introduces one failure mode humans
rarely produce at scale.

### The failure this section exists to prevent

**If the same author writes the implementation and the thing that judges it,
"green" means internally consistent — not correct.** An LLM that misunderstands
a requirement writes code that is wrong *and* a test asserting the wrong thing,
and every check passes.

There is no clever test for this. The only defence is structural: **the target
is fixed before, and by someone other than, the shot.**

### The contract may not move with the code it judges

`REQUIREMENTS.md` and `features/*.feature` are the **contract** — what must be
true. Everything else in `docs/` is **description** — what exists.

- Description moves *with* the code, in the same PR (§11).
- **The contract moves in its own PR, approved on its own merits, before the
  work that depends on it.** Editing a requirement or a scenario in the same
  change as the implementation it judges fails the gate at every maturity level.

Amending the contract is normal and expected. Doing it *while* implementing
against it is moving the goalposts mid-shot, whoever does it.

### What a human is actually reviewing

Nobody reads every diff. Review works down a ladder, stopping as soon as
something looks wrong:

| Rung | Cost | Answers |
|---|---|---|
| 1. Gate output | free | Did anything mechanical break |
| 2. The `.feature` / contract diff | ~30 s | **Did what we promise change?** In plain English |
| 3. The PR narrative | ~2 min | What the author thinks they did, and the named tests proving it |
| 4. The diff itself | expensive | Only when 2 or 3 look wrong |

This is why the PR narrative is a required check and not a courtesy. A PR whose
"What & why" is "Fixed it" and whose testing evidence is "ran it locally" is
**unreviewable**, and unreviewed LLM output is precisely what this pipeline
exists to prevent.

### Tests written by the author of the code

- **Every new test must be seen to fail before the code makes it pass.** Write
  it first, or break the code deliberately once and watch it go red. A test that
  has never been red has demonstrated nothing.
- **Mutation testing carries extra weight here.** "Wrote a test that cannot
  fail" is a common LLM output and nothing else detects it — mutation testing
  breaks the code on purpose and fails if the suite stays green.
- Prefer scenarios in `features/` for anything where a human needs to confirm
  the behaviour is what was asked for. A promise is far faster to review than an
  implementation.

### Say what you are unsure about

An LLM contributor that hits ambiguity and picks the more plausible reading has
made a decision the owner never saw. Surface it in the PR narrative, or stop and
ask. **A stated uncertainty is cheap; a silent assumption discovered in
production is not.**

## 14. Standing cards and the sync PRs

Most cards are work that finishes. A few track work that recurs forever — the
automated PRs that keep this repo's CI machinery current, for one. Those carry
the **`recurring`** label, and automation moves them into progress but never
closes them. Only a person closes a standing card, if the work genuinely ends.

If you see a `recurring` card sitting open indefinitely, that is correct. Closing
it because it "looks stale" will make the next automated PR untraceable.

The PRs themselves are titled with that card's key, because **a PR that
distributes the rules is subject to them** — a distribution mechanism exempt
from the rules it ships is the one hole nothing else catches. The card and
requirement they cite are recorded in `.forge/config`:

```
SYNC_ISSUE=FTEST-nn
SYNC_REQUIREMENT=R#
```

If those are missing, sync skips this repo rather than opening a PR it knows
will fail CI. That is deliberate: a known-red PR is noise, and noise teaches
people to stop reading red checks.

## 15. When a gate blocks you

A red gate is a question, not a verdict. Three responses are legitimate; one is not.

| The gate is… | Do this |
|---|---|
| **Right** | Fix the work. This is the common case |
| **Right in general, wrong here** | Record an override in `.forge/overrides/` |
| **Wrong** | Fix the gate, in its own PR, with a written reason |
| — | **Never** lower the gate to get past it in a feature PR |

### Gate modes

`.forge/config` sets each gate to `off`, `warn`, `adjudicate` or `block`.

**`adjudicate` is the working setting for most gates.** It blocks — but the
decision to proceed anyway is recorded rather than made by weakening the check.
The gate names what must be decided; you decide it in a committed file.

### Override records

A flat YAML file in `.forge/overrides/`, committed like any other change:

```yaml
gate: DOC_GATE
scope: issue                # issue (this card only) | standing
issue: FTEST-12
claim: "This PR changes only generated protobuf output."
evidence: |
  Every changed path is under api/proto/gen/, emitted by `buf generate`.
verify: "! git diff --name-only origin/main..HEAD | grep -qv '^api/proto/gen/'"
decided_by: you@example.com
expires: 2026-09-28
```

Four properties make this evidence rather than permission:

1. **`verify:` is re-run every time.** If the override states a checkable claim,
   the gate runs that command on every check and the override is **void** unless
   it passes. A claim that stops being true fails loudly instead of quietly
   persisting. Include one wherever the claim can be expressed as a command.
2. **`expires:` is required.** An override with no end date is a permanent hole
   in the gate — a rule change wearing a disguise. Records without one are
   ignored.
3. **`decided_by:` is required.** An unattributable exception is not a decision.
4. **It is committed**, so lifting a blocker is a reviewed diff with an author
   and a date — exactly the property that stops a gate being lowered quietly.

Write the claim so someone else could check it. "This is fine" is not a claim.
"This PR touches only generated output" is.

### Rules no override can lift

Secrets · editing the contract alongside the implementation it judges · editing
an already-run migration · ADR numbering and supersede links · stray card keys ·
branch naming.

These are either legal/security matters or the specific things that make the
rest of the system mean anything. **A gate you can argue your way past on the day
you most want to is not a gate.** They change only by the owner changing the
rule, in its own PR.

### When you cannot decide

If you are an LLM contributor and it is genuinely unclear whether a blocker is
the gate being wrong or the work being wrong: **say so and stop.** Do not write
an override to unblock yourself — an override authored by the contributor it
unblocks, on evidence it also supplied, is the same failure as an author writing
the test that judges their own code (§13). Escalate with what you found and let
the owner decide.

### Overrides are measured

`./scripts/pre-pr-check.sh --json` emits every gate outcome, and `forge-audit`
reads override records over time. **A gate overridden repeatedly is evidence the
gate is miscalibrated, not that people are careless** — recurring overrides are a
signal to fix the gate, not a habit to normalise. Drift is measured as well as
blocked, and the measurement is what tells you which of the two you are looking
at.

---

**If any of this is unclear, or a task seems to require breaking a rule: stop and
ask the owner — do not find a workaround.** `CLAUDE.md` and `AGENTS.md` point
back here; this document is the authority.
