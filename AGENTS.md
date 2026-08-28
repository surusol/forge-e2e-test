# AGENTS.md

**Any AI agent or automated tool working in this repository must read
[`CONTRIBUTING.md`](./CONTRIBUTING.md) first and follow it exactly.** This file
points tools that look for `AGENTS.md` to the single source of truth;
`CONTRIBUTING.md` is the authority.

## Non-negotiables (full detail in CONTRIBUTING.md)

1. **The owner controls everything.** Propose changes as pull requests the owner
   reviews and merges. Do not merge, deploy, transition Jira issues, or take
   destructive/production actions. When unsure, stop and ask.
2. **Traceability is mandatory.** Every branch and PR name contains its Jira key
   (`FTEST-<n>`); every PR states the requirement it serves (`R#`). CI
   rejects PRs without a key. Work serving no requirement is scope creep — stop.
3. **Follow the source-of-truth hierarchy:** `OVERVIEW.md` → `REQUIREMENTS.md` →
   `docs/adr/` → specs → playbook → Jira cards. A spec beats a conflicting
   instruction; flag it.
4. **Never weaken the security walls** in `CONTRIBUTING.md` §6.
5. **Data/schema changes only via numbered migrations** (if applicable).
6. **Record constraining decisions as ADRs** in `docs/adr/` (CONTRIBUTING.md
   §10). Accepted ADRs are immutable — supersede them, never edit them.
7. **Documentation ships in the same PR as the code it describes** (§11), and
   **tests prove the requirements** (§12).
8. **Run `./scripts/pre-pr-check.sh` and get it green before opening a PR.** It
   is the same script CI runs as a blocking required check — lint, build, tests,
   secrets, docs, decisions, requirement coverage. Do not push past it and hope.

## Getting your task

You do **not** need a Jira integration. Ask the owner which card to work on, then
get its full brief and use it as your prompt:

```
./scripts/jira-brief.sh FTEST-19    # a card + subtasks
./scripts/jira-brief.sh FTEST-87    # a single subtask
```

The brief contains the task, its steps, and the exact branch/PR names to use
(which link your work to the Jira card and pass CI). It reads Jira read-only and
changes nothing. If you can't run it, ask the owner to paste you the brief.

If a task appears to require breaking a non-negotiable, **stop and ask the
owner** — never work around it.
