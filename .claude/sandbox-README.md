# Sandbox tiers — containing the agent, not just the diff

Everything else in this skill inspects a **diff**: what landed in the repo, after
the fact. None of it constrains what an agent can read, touch or send **while it
runs**. This directory is that missing layer.

The distinction matters most where it is hardest to argue: *"we instructed the
agent not to"* is a hope. *"the process could not reach anything outside these
domains, enforced by the OS"* is a control, and it is the kind someone auditing
you can actually verify.

## Why permission rules are not enough

Permission rules match on the **shape of a tool call**, before it runs. The
sandbox constrains the **running process**, at the OS level.

That difference is not academic. Deny `Bash(curl:*)` and this still works:

```bash
python3 -c "import urllib.request; urllib.request.urlopen('https://…')"
```

A shell is a universal escape hatch, and you cannot enumerate your way to safety
— the set of ways to make a network request is unbounded. The sandbox does not
try to enumerate. It stops the process reaching anything off the allowlist,
however the request was spelled, including from child processes.

Both layers are real and they compose; the docs are explicit that paths and
domains from permission rules and sandbox settings are **merged** into the final
configuration.

## The three tiers

| File | Tier | For | Scope it belongs in |
|---|---|---|---|
| `open.settings.json` | **Open** | your own work, no third-party data | project or user |
| `client.settings.json` | **Client** | a client's code, no production access | **project** `.claude/settings.json` |
| `regulated.managed-settings.json` | **Regulated** | client data under a compliance regime | **managed** settings, deployed by MDM |

Each is a starting point to tailor. **Every deny trades against capability** —
copying the regulated tier onto a repo that needs six package registries just
means someone turns the sandbox off, which is worse than never having set it up.

### Scope is not a detail

Three rules bite here, and getting them wrong produces a config that silently
does nothing:

- **`.` resolves differently per scope.** In project settings it is the project
  root; in `~/.claude/settings.json` it is `~/.claude`. The Client tier's
  `denyRead: ["~/"]` + `allowRead: ["."]` pair only works from **project**
  settings — in user settings it would block the project instead.
- **`strictAllowlist` is ignored in project settings.** It takes effect only in
  user, managed, or `--settings` scope. That is why the Client tier prompts on an
  unlisted domain and only the Regulated tier refuses.
- **Array keys merge across scopes.** `allowedDomains`, `allowRead` and
  `excludedCommands` accumulate, so without `allowManagedDomainsOnly` and
  `allowManagedReadPathsOnly` an operator can append entries that widen the
  policy. Boolean keys like `enabled` and `failIfUnavailable` do not merge —
  managed wins.

`excludedCommands` has **no** managed-only lockdown. A developer can always
append to it, so keep any managed list narrow.

## Setup

**macOS** — nothing to install; the sandbox uses the built-in Seatbelt framework.

**Linux / WSL2** — two packages:

```bash
sudo apt-get install bubblewrap socat     # or: sudo dnf install bubblewrap socat
```

The optional seccomp filter adds Unix-domain-socket blocking:
`npm install -g @anthropic-ai/sandbox-runtime`.

Run **`/sandbox`** to see resolved settings and what is missing. The dependency
check runs at startup, so restart Claude Code after installing. WSL1 is not
supported — bubblewrap needs kernel features only WSL2 has. Native Windows is
not supported; run inside WSL2.

## Verify it, do not assume it

A sandbox you have not tested is a claim, not a control. From a repo carrying the
tier, ask Claude to run each of these — every one should be refused:

```bash
cat ~/.ssh/id_rsa                                  # credential deny
curl -s https://example.com                        # unlisted domain
python3 -c "import urllib.request; urllib.request.urlopen('https://example.com')"
echo x > ~/escaped.txt                             # write outside the project
```

The third is the one that matters: it is the escape hatch a permission rule
misses and the sandbox catches. If it succeeds, your network layer is not on.

## Choosing a tier is a decision

Data classification constrains everything downstream, so **record the tier and
its reasoning in an ADR** and reference it from `docs/security-model.md`. The
question the ADR must answer is not "which tier" but "what happens if this is
wrong" — whose data, under what agreement, and what the exposure is.

## Honest limits

- The built-in proxy enforces the allowlist on the **requested hostname** and by
  default does **not** terminate or inspect TLS. If your threat model needs
  inspection, see the experimental `network.tlsTerminate` setting or a custom
  proxy.
- Filesystem isolation and network isolation are **independent layers**. Turning
  the filesystem layer off while auto-allowing commands lets a sandboxed command
  write files that later commands read or run — shell startup files, things on
  `$PATH`, `~/.claude/settings.json` — and widen its own access next run.
- The sandbox covers **Bash and its children**. In-process tools such as
  `WebFetch` follow permission rules instead.
- Managed settings need an MDM or admin console. Without one you get the first
  two tiers, which are still worth having — they just protect against accident
  and drift rather than against a determined operator.
