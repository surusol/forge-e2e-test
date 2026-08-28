<!--
Before opening: read CONTRIBUTING.md.

TITLE FORMAT — the title must START WITH the key and a colon:
    FTEST-12: saved-search storage
The Jira rules match on the title starting with the key. Any other shape means
the card silently never moves. CI rejects it so that failure is loud.

CI rejects this PR unless: the title starts with FTEST-<n>: and the
branch carries the same key, the
body names a requirement (R#), the body answers the ADR line, and every box
below is ticked. Tick a box only if it is actually true. If an item genuinely
does not apply, strike it through with a reason — ~~item~~ n/a: <why> — rather
than ticking it falsely or deleting it.
-->

## Jira
Closes FTEST-___

## Requirement served
R___

## ADR
<!-- The ADR this implements (e.g. ADR-0007), or `N/A — <reason>`. An ADR is
required for anything that constrains future changes: a dependency, a service
or module boundary, data shape, a protocol or public interface, auth, hosting,
or a deliberately accepted risk. See docs/adr/0000-record-architecture-decisions.md -->
ADR: 

## What & why (plain language)
<!-- Written for a reviewer who will NOT read the whole diff. What changed,
what behaviour is different now, and why. 20+ words, no jargon. If most of this
was written by an LLM, this section is the main thing a human will actually
read — make it honest about what you are unsure of. -->


## How it was tested
<!-- NAME the tests: test_reorder_threshold, features/limits.feature:12.
"Ran it locally" is not test evidence — it is not repeatable and nobody else
can check it. -->



## Checklist
- [ ] Branch/PR name contains the `FTEST-<n>` key, and mentions **no other** card's key
- [ ] Scope matches the card — no unrelated changes
- [ ] `./scripts/pre-pr-check.sh` passes locally
- [ ] Tests cover the behaviour this PR adds or changes, and the suite is green
- [ ] Each new test was seen to **fail** before the code made it pass
- [ ] This PR does **not** edit `REQUIREMENTS.md` or a `.feature` file — the contract moves in its own PR, approved first
- [ ] Docs updated **in this PR** — not deferred (`docs/`, `README`, `REQUIREMENTS.md` as applicable)
- [ ] Decision-shaped choices are recorded in an ADR, or the ADR line above says why not
- [ ] No secrets committed
- [ ] Any schema change is a numbered migration with a documented rollback
- [ ] Does not weaken a security wall in CONTRIBUTING.md §6
