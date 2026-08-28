# CLAUDE.md — agent working notes

You are working in **Forge E2E Test**. Before doing anything, read
**`CONTRIBUTING.md`** — it is the authoritative, tool-agnostic guide for how all
contributors (human or LLM) work here. Everything below is a quick orientation
and does not override it.

## Essentials

- **The owner controls everything.** Propose changes as PRs; the owner reviews
  and merges. Never merge your own PR, deploy, or transition Jira issues. When
  unsure, stop and ask.
- **Source of truth:** `OVERVIEW.md` → `REQUIREMENTS.md` → `docs/adr/` → specs
  → playbook → Jira `FTEST` cards. Spec beats a conflicting
  instruction; flag it, don't silently pick one.
- **Branch/PR naming is mandatory + CI-enforced:** `feat/FTEST-<n>-slug`,
  PR title contains the key, PR body names the requirement (R#).
- **Never weaken the security walls** in `CONTRIBUTING.md` §6.
- **Data/schema changes only via numbered migrations** (if applicable).
- **Record decisions.** Anything that constrains future changes — a dependency,
  a boundary, data shape, an interface, auth, hosting, an accepted risk — gets
  an ADR in `docs/adr/` (§10). Accepted ADRs are immutable: supersede, never
  edit. Every PR answers the `ADR:` line.
- **Docs move with the code** (§11) — same PR, never a follow-up. **Tests prove
  the requirements** (§12) — a fix lands with a test that failed before it.
- **`./scripts/pre-pr-check.sh` must pass before you open a PR.** The same
  script is a required check in CI, so a red result there is a red merge button.

## A typical session

1. The owner says "do FTEST-<n>" (or gives you a brief from
   `scripts/jira-brief.sh`).
2. Branch `feat/FTEST-<n>-<slug>` off the default branch.
3. Do exactly what the card specifies — no more. Spec beats card; flag conflicts.
4. Update the docs and add/extend the tests **in the same change**.
5. Run `./scripts/pre-pr-check.sh` until it is green.
6. Open a PR (the template auto-fills) with the key, R#, the `ADR:` line, a
   plain-language summary, and how-tested. Tick every checklist box honestly —
   CI rejects unticked boxes. **Stop — the owner merges.**

## Getting a task without pasting

`./scripts/jira-brief.sh FTEST-<n>` prints the card + subtasks + rules,
read-only. Use it or ask the owner for a brief.
