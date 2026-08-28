# migrations/ — changing the database's shape, safely

A **migration** is a numbered, ordered script that changes the structure of the
database: adding a table, adding a column, changing an index, backfilling data.

**Never change a live database by hand.** A hand-made change cannot be
reproduced on another environment, reviewed by anyone, or undone reliably — and
nothing records that it happened. The migration file is simultaneously the
change, its documentation, and its audit trail.

## Naming

```
0001_create_users.sql
0002_add_saved_searches.sql
0007_backfill_search_owner.sql
```

Numbers are sequential and **permanent**. A migration that has run anywhere —
including on your laptop — is never edited. Fix a mistake with a *new*
migration, exactly as with an ADR, and for the same reason: the record must show
what actually happened, not a tidied version.

## Every migration documents its rollback

At the top of each file, in a comment: how to undo this, or an explicit
statement that it cannot be undone and why.

```sql
-- 0007_add_saved_searches.sql
-- Requirement: R4
-- Rollback: DROP TABLE saved_searches;
-- Safe to run on a live database: yes (new table, no locks on existing tables)
```

"Cannot be undone" is a valid and important answer — dropping a column destroys
data, and knowing that *before* running it is the point.

## Forward-only

Migrations run forward, in order, and the migrator records which have been
applied. Rolling *back* in production is usually the wrong instinct: a rollback
that drops a column loses everything written since the deploy. Prefer a new
forward migration that undoes the change while keeping the data.

The documented rollback is for the deploy that fails *before* traffic arrives,
and for local development.

## Before every migration: a backup

Automatic, immediately before applying, on any environment holding real data.
Non-negotiable — this is the one class of change that can lose data
irrecoverably.

## The rules

1. Numbered, sequential, never renumbered, never edited after running.
2. Every file names the requirement (`R#`) it serves.
3. Every file documents its rollback path, or states plainly that there is none.
4. Automatic backup before applying to anything with real data.
5. CI proves migrations apply cleanly from empty — a migration that only works
   against *your* database is not a migration.
6. Schema changes that alter what the system can represent usually need an
   **ADR** as well: data shape constrains future work more than almost anything
   else.
7. Backfills (rewriting existing rows) are separate migrations from structural
   changes, and are written to be safely re-runnable.
