# Gate IAM-3 (remainder) — CanonicalIdentity / ExternalIdentity Layer, Scope

**Status:** Scoping — not yet implemented
**Date:** 2026-09-10
**Governing ADR:** `ADR-0004 — Canonical Identity and External Identity Mapping`
**Repositories:** `nabhold/baobab-cp` (runtime owner), `nabhold/shared` (contract owner), `nabhold/baobab-iam` (authentication subject)
**Depends on:** Gate IAM-0 discovery (R-3, now fixed in `nabhold/baobab-cp#63`); ADR-0003, ADR-0005

This document scopes the second half of Gate IAM-3: introducing a real `CanonicalIdentity`/`ExternalIdentity(issuer, subject)` layer. It does not implement anything — it records what already exists, what's missing, and the two decisions that need to be made before implementation starts, per ADR-0004 §75 ("do not implement duplicate concepts if existing CP entities already fulfil these roles").

---

## 1. What already exists (verified against source)

**Wire contracts already match the ADR almost exactly** — `nabhold/shared` doesn't need new schemas, just Go implementations of what's already there:

| ADR-0004 concept (§3, §6, §75) | Existing contract | Match |
|---|---|---|
| `CanonicalIdentity{id, actor_type, status, created_at, updated_at}` | `contracts/identity/v1/principal.schema.json` | Field-for-field identical (named `Principal`, not `CanonicalIdentity` — see Question 1) |
| `ExternalIdentity{id, canonical_identity_id, issuer, subject, provider_type, status, created_at, last_seen_at}` | `contracts/identity/v1/external-identity.schema.json` | Field-for-field identical (`principal_id` instead of `canonical_identity_id`) |
| Human-specific attributes | `contracts/identity/v1/human-identity.schema.json` | Already exists (`display_name`, `email`, `verified`) |
| Workload-specific attributes | `contracts/identity/v1/workload-identity.schema.json` | Already exists (`client_id`, `owner`, `environment`) |

**The verified `(issuer, subject)` extraction point already exists** — `internal/auth/oidc.go`'s `OIDCVerifier.Verify` returns `Principal{Subject: c.Subject, Issuer: token.Issuer, ...}` per request, and its own comment already anticipates this ADR: *"per ADR-0004 a stable canonical identity is ultimately keyed by (issuer, subject), not subject alone."* This `Principal` is baobab-cp's own ephemeral, per-request auth type — unrelated to the shared `Principal` contract above despite the name collision (Question 1 again). Nothing today turns this per-request `(issuer, subject)` into a durable, persisted identity. ADR-0004 §11's flow (`Extract iss+sub → Find ExternalIdentity → CanonicalIdentity`) has no implementation past "extract."

**A generic entity-mapping infrastructure exists, but for a different domain concept:**
- `registry.canonical_entity` (`entity_type text NOT NULL`, `tenant_id text` nullable, no CHECK constraint on `entity_type`'s values) — used today with `entity_type = 'PRODUCT'` by the Mapping/resolution domain (Gate 1/2 work).
- `registry.external_reference` (`canonical_entity_id uuid NOT NULL REFERENCES registry.canonical_entity ... ON DELETE CASCADE`, `provider`, `provider_key`, `external_url`) — the Postgres table backing engine-mapping records.
- `domain.ExternalReference` (`internal/domain/resolution.go`) — the matching Go struct (`CanonicalEntityID`, `EngineID`, `EngineInstanceID`, `NativeType`, `NativeID`, `ExternalURL`, `Status`, `Metadata`). **Has no repository implementation at all yet** — grep confirms no Postgres or in-memory CRUD exists for it, only a foreign-key reference from `Mapping.ExternalReferenceID`.

ADR-0004 §24 directs reusing this infrastructure "where appropriate" for `CanonicalIdentity → engine-native actor` mappings (Medusa customer, `AD_User`, Payload user) — but `registry.canonical_entity` today represents *business entities* (products, in the one entity_type used so far), not *actors*, and its `external_reference` table's FK is hard-wired to `canonical_entity_id`. Reusing it for identities either means identity rows physically living in `registry.canonical_entity` (Question 2), or a parallel identity-scoped reference table.

---

## 2. Two decisions needed before implementation

### Question 1 — Naming: `Principal` vs `CanonicalIdentity`

`nabhold/shared`'s existing contract is called `Principal`; ADR-0004 calls the same concept `CanonicalIdentity` throughout. `internal/auth.Principal` in `baobab-cp` is a *third*, unrelated thing (the ephemeral per-request auth struct) that already uses the name `Principal`. Three options:
- **(a)** Treat the shared contract as authoritative — build `domain.CanonicalIdentity` in Go but keep serializing to/from `principal.schema.json` as-is (accept the name mismatch between Go and wire, documented).
- **(b)** Rename the shared contract file/title to `CanonicalIdentity` to match the ADR (a breaking contract change, however nothing consumes `principal.schema.json` yet — same "safe to make now" situation as the Session/AuthenticationAssurance rename).
- **(c)** Keep `Principal` everywhere in `shared` and `baobab-cp`'s new domain code, treat ADR-0004's "CanonicalIdentity" as the conceptual name only, not a required identifier — reserve `Identity`-prefixed names for `internal/auth.Principal` disambiguation instead.

### Question 2 — Where do identity rows live relative to `registry.canonical_entity`?

- **(a) Reuse `registry.canonical_entity`** with a new `entity_type = 'IDENTITY'` (or `'CANONICAL_IDENTITY'`) value, leaving `tenant_id` NULL for those rows (satisfies ADR-0004 §43's "no permanent tenant_id" rule since the column is nullable). Identity-to-engine mappings then reuse `registry.external_reference` and `domain.ExternalReference` exactly as ADR-0004 §24 suggests, with zero new mapping infrastructure.
- **(b) New parallel tables** (`identity.canonical_identity`, `identity.external_identity`, `identity.identity_reference`), keeping the Mapping/resolution domain's entity registry (products) and the identity domain (people/workloads) in separate schemas even though their shapes rhyme. Cleaner separation of two genuinely different concepts (a product is not an actor), at the cost of a second mapping-table implementation ADR-0004 §24 explicitly says to avoid "if appropriate."

My assessment: (b) is more defensible long-term — `registry.canonical_entity`'s `status` column already defaults to lowercase `'active'` while ADR-0004 wants uppercase `ACTIVE`/`SUSPENDED`/`DISABLED`/`ARCHIVED` (matching every other lifecycle status in this codebase), and "one table holds both SKUs and people" is a stretch of "where appropriate." But (a) is real infrastructure reuse the ADR explicitly asks to consider, and `domain.ExternalReference` having zero existing persistence either way means the effort delta between (a) and (b) is smaller than it looks — this is genuinely a judgment call, not something to decide unilaterally.

---

## 3. Proposed phased plan (pending the two decisions above)

Sized against this session's established PR pattern (bounded, one concern per PR, real Postgres tests, ADR citations):

1. **Domain types + migration**: `domain.CanonicalIdentity`, `domain.ExternalIdentity` (or the chosen naming from Question 1), matching the shared contracts; new migration for whichever table strategy Question 2 resolves to; `UNIQUE(issuer, subject)` constraint (ADR-0004 §7, §54).
2. **Repository layer**: `ResolveIdentity(ctx, issuer, subject) (CanonicalIdentity, error)` and `CreateIdentity`/`LinkExternalIdentity` on a new interface, in-memory + Postgres implementations — mirrors the `MappingScopeWriter` pattern from Gate 2 exactly.
3. **First-authentication provisioning**: the resolve-or-create flow (ADR-0004 §12, §56 — transactional create, re-read on uniqueness conflict for concurrent first-logins). **Provisioning policy by actor type is explicitly out of scope per ADR-0004 §13** ("exact rules SHALL be defined by later domain-specific ADRs") — this phase should build the *mechanism* (a pluggable policy hook) without hardcoding which actor types get auto-provisioned, since no such ADR exists yet for humans. Workloads are the one case ADR-0007 already covers server-side provisioning for, so may be safe to wire concretely.
4. **Wire into the request path**: insert identity resolution between `OIDCVerifier.Verify` and `auth.NewOperationContext` in `internal/auth/operation_context.go` — every authenticated request resolves `(iss, sub)` to a `CanonicalIdentity` transparently (ADR-0004 §39's preferred pattern), rather than exposing `POST /internal/identity/resolve` as a caller-facing endpoint.
5. **Engine-reference mapping** (Medusa/ERP/CMS actors): implements ADR-0004 §24-27, contingent on Question 2's answer.
6. **Linking/unlinking/merge**: ADR-0004 §15-22 — explicit, audited, security-sensitive flows. Materially the largest remaining piece; likely its own multi-PR effort given §77's required test list (valid linking, failed second auth, duplicate subject, same-email-different-subject, unlink-with-alternative-credential, unlink-final-credential-denied, merge auditability).

Phases 1-4 are the minimum to make Gate IAM-3 substantively "real identity, not just a verified token." Phases 5-6 are real ADR-0004 scope but sizable enough to warrant separate check-ins, consistent with this session's bounded-slice practice.

## 4. Explicitly not in this scope

- Merge/split identity operations (§19-22) — deferred to their own pass given the auditability requirements.
- Actor-type-specific provisioning policy (§13) — belongs to domain-specific ADRs that don't exist yet (Zuribeans/Thamani/Supplier).
- The `/v1/resolve` response-shape gap flagged in `nabhold/baobab-cp#63` — unrelated to identity, tracked separately.
