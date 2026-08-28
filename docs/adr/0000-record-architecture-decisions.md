---
adr: 0000
title: Record architecture decisions
status: Accepted
date: 2026-08-28
requirements: []
supersedes: []
superseded-by: []
---

# ADR-0000 — Record architecture decisions

## Context

Forge E2E Test is built by a mix of humans and LLM contributors, over a long
enough period that nobody will remember why any given choice was made. Tickets
close and take their reasoning with them; chat history is unsearchable in
practice; `CONTRIBUTING.md` says *how* we work, `REQUIREMENTS.md` says *what*
must be true, but neither records *why we chose this way of achieving it*.

Without a decision log, every past choice looks arbitrary to whoever arrives
next — so it gets re-litigated, or worse, quietly reversed by someone who
assumed it was accidental.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| A. Architecture Decision Records in-repo | Versioned with the code; reviewed in the same PR; greppable; tool-agnostic | Costs ~15 min per decision |
| B. A wiki page of decisions | Easy to edit | Drifts from the code; no review gate; nobody reads it |
| C. Rely on tickets and PR descriptions | Zero extra work | Reasoning is scattered and dies when the ticket closes |
| D. Do nothing | Zero extra work | The failure mode described above |

## Decision

We record architecture decisions as **ADRs** in `docs/adr/`, one file per
decision, named `NNNN-kebab-case-title.md`, starting at 0001. This file is
ADR-0000 and establishes the convention.

An ADR is required for any choice that **constrains future changes**:

- adding, removing or replacing a dependency, service, or third-party provider;
- a module/service boundary, or where responsibility for something lives;
- data shape: schema design, storage engine, serialization format, retention;
- a protocol or public interface others will code against;
- authentication, authorization, or trust-boundary design;
- hosting, deployment topology, or anything with recurring cost;
- deliberately accepting a known risk or deferring work ("we will not do X yet,
  because…").

An ADR is **not** required for a choice that is cheap to reverse and local in
effect — naming, file layout within a module, an implementation detail behind a
stable interface. When genuinely unsure, write one: they are short.

**Accepted ADRs are immutable.** Never edit the Context, Decision, or
Consequences of an accepted ADR to reflect new thinking. Instead:

1. Write a new ADR that states the new decision.
2. Set the new ADR's `supersedes: [NNNN]`.
3. Change the old ADR's `status` to `Superseded` and set its
   `superseded-by: [MMMM]`.

Status changes and typo fixes are the only permitted edits to an accepted ADR.
This makes the directory a decision *log*, showing the path of reasoning over
time, rather than a snapshot that hides the fact anything ever changed.

**Statuses:** `Proposed` (open for discussion in its PR) → `Accepted` (the
owner merged it) → `Superseded` (a later ADR replaced it), or `Rejected` (we
considered and declined it — keep the file; a recorded no is as useful as a
recorded yes).

Every PR states the ADR it implements, or `N/A` with a reason, and CI enforces
that the line is present. `docs/adr/TEMPLATE.md` is the form to copy.

## Consequences

- **Easier:** any contributor — human or LLM — can reconstruct why the system
  is shaped this way by reading one directory in commit order. New contributors
  onboard from the repo rather than from someone's memory. Re-litigation ends
  with "see ADR-0012."
- **Harder:** a real decision now costs a short document and a review cycle
  before code lands. This is deliberate friction, applied only to choices that
  are expensive to undo.
- **Locked in:** the numbering and the immutability rule. Renumbering ADRs
  breaks every inbound reference from PRs, cards, and other ADRs.

## Revisit when

Never, in the general case. If the *format* becomes a burden, amend it with a
new ADR that supersedes this one — do not silently start writing them
differently.
