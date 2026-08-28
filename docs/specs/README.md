# Specifications — which form to use when

A **specification** says what the system does, exactly. This project keeps its
specs in forms a **machine reads**, so a spec that disagrees with the code
becomes a build failure instead of a discovery six months later.

That is the whole idea. A paragraph saying "the limit is 50" cannot fail when
the code says 100. A test, a schema or a contract file can.

## The forms

| If you are describing… | Write it in | Enforced by |
|---|---|---|
| Behaviour a user can see | `features/*.feature` (Gherkin) | Step definitions run as tests; an unbound step fails the build |
| An HTTP endpoint | `api/openapi.yaml` (OpenAPI) | Spec is linted; clients and stubs are generated from it |
| A service-to-service message | `api/proto/*.proto` (protobuf) | `buf lint` + `buf breaking` against the base branch |
| A change to the database's shape | `migrations/NNNN_*.sql` | Applied in CI; rollback documented |
| A threshold, limit, price or balance number | `data/*.yaml` | Schema-validated; the file *is* that behaviour's documentation |
| **Why** any of the above is shaped this way | `docs/adr/NNNN-*.md` | Numbering and supersede links linted |

Only the directories this project actually uses exist. If a form you need is
missing, that is a decision to make (and record), not an oversight to route
around — see `docs/adr/`.

## Choosing

**Start with Gherkin for anything a user can observe.** It is the only artefact
that is simultaneously readable by a non-technical owner as acceptance criteria
and executable by CI as assertions. The same sentences do both jobs, which is
the tightest available link between "what we agreed" and "what is proven".

**Use a contract (OpenAPI / protobuf) the moment anything else calls you.**
Another service, a mobile app, a client's integration. Write the contract
**before** the code: written afterwards it is documentation of whatever got
built, including its accidents. Written first, it is a decision others can
review and build against.

**Put every magic number in `data/`.** A limit of 50 buried in a source file is
a product decision hidden inside an implementation detail — invisible in review,
unfindable later, and the most reliable source of "why is it like this?"
questions nobody can answer.

**Reach for an ADR when the choice constrains future work.** Specs say *what*;
ADRs say *why this and not the alternatives*.

## The rule that keeps them honest

**One fact, one home.** If a limit is defined in `data/limits.yaml`, no document
restates it — they link to it. Duplicated facts are precisely how two documents
come to disagree, and the reader has no way to know which one is stale.

## Where each form is documented

- Gherkin — `features/README.md`
- HTTP and RPC contracts — `api/README.md`
- Database changes — `migrations/README.md`
- Tuning data — `data/README.md`
- Decisions — `docs/adr/0000-record-architecture-decisions.md`
