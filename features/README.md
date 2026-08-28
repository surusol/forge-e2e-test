# features/ — executable behaviour

Every file here describes behaviour a user can observe, in **Gherkin**: a
structured-English format that is both readable as acceptance criteria and
executable as tests. This practice is called **BDD** — Behaviour-Driven
Development.

## What a feature file looks like

```gherkin
Feature: Saved searches
  As someone who runs the same query repeatedly
  I want to save a search and re-run it
  So that I do not rebuild it every time

  # R4 — users can re-run past queries
  Scenario: Re-running a saved search
    Given I have a saved search named "overdue invoices"
    When I re-run it
    Then I see the invoices overdue as of today

  # R4, R11 — the per-user cap
  Scenario: Reaching the saved-search limit
    Given I have 50 saved searches
    When I try to save another
    Then I am told the limit is reached
    And no new search is saved
```

**The vocabulary:**

- **Feature** — one capability. One file.
- **Scenario** — one concrete case of it. Aim for one behaviour per scenario.
- **Given** — the starting state. **When** — the action. **Then** — the
  observable result. Never assert in a `Given`, never act in a `Then`.
- **Step definition** — the code each line is bound to. It lives in
  `features/steps/` and does the actual work.

## Why this form and not a plain test

A plain test proves something, but only a developer can read it. A prose spec is
readable but proves nothing. Gherkin is the only artefact where **the same
sentences** serve as the acceptance criteria you agreed to and the assertions CI
runs on every change. When they diverge, the build breaks — which is the entire
point.

An unbound step (`Given I have a saved search` with no matching code) fails
rather than being silently skipped. That is what stops this from becoming a
third stale specification surface.

## The rules

1. **Every scenario names its requirement** in a comment (`# R4`) or a tag
   (`@R4`). This is the link the requirement-coverage gate looks for. A scenario
   naming no requirement is behaviour nobody asked for.
2. **Write in the user's language, never the implementation's.** `Then I see the
   overdue invoices`, not `Then the API returns 200 with a JSON array`. If a
   scenario mentions a database table or an HTTP status, it is testing the
   implementation, and it will break every time you refactor without a single
   user-visible thing having changed.
3. **One behaviour per scenario.** A scenario with four `When`s is four
   scenarios, and when it fails you will not know which behaviour broke.
4. **Cover the edges, not just the happy path.** Empty, at the limit, over the
   limit, conflicting, dependency unavailable, two users racing. The happy path
   is the case least likely to break in production.
5. **No `pending` or undefined steps on the default branch.** A pending step is
   a test that proves nothing while displaying a reassuring green tick — worse
   than no test, because it is counted as coverage.
6. **`Background:` for setup shared by every scenario in a file.** If it is
   shared by only some, it belongs in those scenarios.

## Where scenarios come from

From the acceptance criteria in `REQUIREMENTS.md`, usually close to verbatim.
That is the intended workflow: write the criterion falsifiably during planning,
then transcribe it here. If a criterion cannot be transcribed into
`Given/When/Then`, it was not falsifiable — fix the requirement, not the
scenario.

## Running them

```bash
# whatever this project's TEST_CMD is — see .forge/config
```

The `GHERKIN_GATE` setting in `.forge/config` decides whether undefined or
pending steps warn or block.
