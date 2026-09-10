# Gate IAM-4 — Workload Identity, Scope

**Status:** Scoped — phase 1 in progress (this PR)
**Date:** 2026-09-10
**Governing ADR:** `ADR-0007 — Workload Identity and Service-to-Service Authentication`
**Repositories:** `nabhold/baobab-iam` (workload clients, owner), `nabhold/baobab-cp` (canonical workload identity / enforcement), `nabhold/shared` (workload identity contracts)
**Depends on:** Gate IAM-3 (canonical identity spine — complete)
**Out of scope:** mTLS/PKI, gateway TLS termination, certificate rotation — owned entirely by `nabhold/infrastructure` per ADR-0007 §36, §94, §99; that repository is not in scope for this session.

This document records the verified current state of workload identity across all three repositories (a full discovery pass against ADR-0007's 109 sections, cross-checked directly against source in all three repos — not taken at face value from any single summary), the gaps against the ADR, one architectural finding that changes the plan mid-flight (§3), and a phased implementation plan (§4).

---

## 1. What already exists (verified against source)

**`baobab-iam`** already wires `actor_type=workload` via a hardcoded-claim protocol mapper (`config/scopes/actor-type-workload.json`) attached to all 6 `*-workload.json` clients, and grants `context:resolve` as a default scope. `scripts/bootstrap.sh` imports client scopes before clients and no longer double-processes workload clients (a fixed bug, gate-iam-0-discovery R-2/§4.9). `tests/integration/run.sh` §4 already decodes and asserts `actor_type`/`scope`/`iss` on an issued workload token; §8 already asserts independent per-client revocation.

**`baobab-cp`**'s `internal/auth/oidc.go` `Verify()` already enforces `actor_type ∈ {human, workload}`, a `tenant_id` shape check, a ≤15-minute token lifetime (ADR §26), and scope-format validation, and delegates `aud` checking to `go-oidc`'s built-in audience match against a single configured `WorkloadOIDCAudience` (default `baobab-control-plane`). `router.go`'s `authorize()` gates `/v1/context/resolve` and `/v1/resolve` on `actorType=workload` + `context:resolve` scope + non-empty `tenant_id`/`azp`. `WorkloadOnlyProvisioningPolicy` (Gate IAM-3 machinery, not this gate's) auto-provisions a canonical `Principal` for workload actors on first sight.

**`nabhold/shared`** already has most of what ADR-0007 §100 asks `shared` to define: `contracts/control-plane/v1/access-token-claims.schema.json` (the exact §18 claim shape, `aud`/`actor_type` required), `contracts/authorization/v1/scope-registry.yaml` (partial — `context:resolve`'s entry already declares `audience: ["baobab-control-plane"]`, confirming the target audience string phase 1 uses below), `contracts/authorization/v1/delegation.schema.json` (full delegation-metadata contract, already citing ADR-0007 §13-18/§108), `contracts/identity-events/v1/workload-revoked.schema.json`, and `contracts/control-plane/v1/security-policy.yaml` (already declares `transport.workload_to_control_plane.mtls_required: true` with `termination_owner: nabhold/infrastructure`, matching the ADR's ownership split exactly).

## 2. Gaps against ADR-0007 (by repository)

### `baobab-iam`
1. **No `aud` claim mapper on any workload client** (§24-25) — no `oidc-audience-mapper` existed anywhere in `config/`. Every workload token was missing the audience claim `go-oidc` requires, which — combined with gap 2 below — meant neither of `baobab-cp`'s two workload endpoints was reachable end-to-end with a real IAM-issued token. **Fixed in this PR** (§4, phase 1).
2. ~~No `tenant_id` claim mapper~~ — **not a gap to fix this way; see §3.** The original discovery pass proposed adding a static per-client `tenant_id` mapper. Reading ADR-0007 §87-91 directly (not just the summary) shows this is the wrong fix: the ADR explicitly prohibits baking a fixed tenant into a workload's identity. This becomes its own phase (§4, phase 4) once `baobab-cp`'s enforcement model is redesigned, not a claim-mapper addition here.
3. **No machine-readable workload registry** (§42-43, §101) — `find -iname "*registry*"` is empty. New artifact.
4. **No per-endpoint expected-`azp` mechanism** (§20) — Keycloak includes `azp` in client-credentials tokens by default; nothing needs adding on the IAM side, but nothing on the `baobab-cp` side checks it against an expected value either (gap 7).
5. `tests/integration/run.sh` didn't assert `aud` at all (**fixed in this PR**, §4 phase 1) and still doesn't cover the §102 isolation cases beyond independent revocation (wrong-client, wrong-environment, cross-workload impersonation) — deferred to phase 3.

### `baobab-cp`
6. **No registry-based workload allowlist** — any token from the configured issuer/audience with a valid `actor_type=workload`/scope/non-empty `tenant_id` passes; no per-client authorization exists (§42-44, and §99's "canonical workload identity" ownership).
7. **No `azp`-specific expected-value enforcement** at any endpoint (§20).
8. **No integration tests** covering the §102 token-validation/isolation negative cases (wrong audience, wrong azp, wrong actor type, revoked credential, cross-workload impersonation) — only unit tests of the verifier/router logic exist.
9. **`tenant_id` is trusted directly from the token as the sole tenant-authorization signal** — see §3. Confirmed by reading the actual handlers, not inferred: `api/context.go`'s `resolveContext` passes `principal.TenantID` straight into `a.store.ResolveContext(...)` as the tenant to resolve against; `api/resolver_handler.go`'s `ResolverHandler.Resolve` accepts an optional request-body `tenant_id` but only to **reject** it if it disagrees with `principal.TenantID` (line 41-44) — it never uses a request-supplied or policy-resolved tenant as the actual source of truth. Both endpoints treat "the workload's own static token claim" as "the tenant this request is authorized for."

### `nabhold/shared`
10. **`scope-registry.yaml` is incomplete** — `contracts/control-plane/v1/openapi.yaml` uses `mapping:read/write/approve/resolve` and `market:read/write/approve`, none of which are defined in the registry (ADR §22-23: "exact scope names SHALL be defined in `nabhold/shared`").
11. **No workload-registry contract** matching §101's illustrative shape (`workloads: <id>: {audience, scopes}`) — `workload-identity.schema.json` is a different artifact (one workload's `Principal` shape: `client_id`/`owner`/`environment`), not a registry enumerating every workload and what it's allowed.
12. **`security-policy.yaml`'s `required_claims` omits `azp`** even though `access-token-claims.schema.json` carries it as optional (§20, §87).
13. **No workload-tenant-entitlement contract** — needed once §3's redesign lands, to describe how a workload's permitted tenants are declared/resolved (CapabilityBinding-style), not part of `workload-identity.schema.json` today.

## 3. Architectural finding: workload identity ≠ tenant access (ADR-0007 §87-91)

The original discovery pass characterized "no `tenant_id` claim mapper in `baobab-iam`" as a straightforward missing-claim gap, matching what `baobab-cp`'s current code expects. Reading ADR-0007 §87-91 directly instead of that summary shows the code itself has the mismatch, not `baobab-iam`'s config:

> §87 Workload Context Resolution: `Workload token → CP validates iss/aud/exp/actor_type/azp/scope → Canonical workload resolution → Requested tenant/entity/context → Policy decision`
> §88 Context SHALL Be Explicit: "`baobab-trade` may operate across multiple tenants, but each request SHALL resolve a permitted tenant context."
> §90 Workload Scope and CP Context: authorization SHALL combine *IAM scope* + *Control Plane context* — `scope: context:resolve` "means the client may invoke the resolver. It does not mean all tenants are authorized."
> §91 No Scope-to-Tenant Shortcut: "This is prohibited: `scope=context:resolve → allow requested tenant`. The requested tenant SHALL still be evaluated."

A single client-credentials token per workload client cannot carry "the one tenant this workload is allowed" as a static claim — engines like `baobab-trade` serve many tenants from one workload identity, and the ADR's own flow diagram puts "requested tenant" and "policy decision" as steps *after* workload identity is established, not encoded inside it. `baobab-cp`'s current code (gap 9) does exactly what §91 prohibits: it uses the token's own `tenant_id` claim as the tenant-authorization decision itself, with no separate policy/entitlement step.

**Decision (made 2026-09-10, via explicit check-in):** ship the unambiguous ADR §24-25 fix (the `aud` claim mapper, gap 1) now as phase 1, and treat the tenant-context/entitlement redesign as its own dedicated phase (§4, phase 4) once the registry (phase 2-3) exists to build the entitlement check against, rather than bolt an ADR-violating `tenant_id` mapper onto `baobab-iam` in the meantime. `baobab-cp`'s two workload endpoints remain unreachable with a real per-tenant request until phase 4 ships — this was already true before this session (gap 1 alone blocked them), so phase 1 doesn't regress anything; it only fixes the audience half of the blocker.

## 4. Phased plan

Bounded, one concern per PR, matching this session's established pattern.

1. **`baobab-iam` — `aud` claim mapper (this PR).** Adds an `oidc-audience-mapper` (`aud=baobab-control-plane`) directly to the `context:resolve` client scope — every workload client that already carries that scope (all 6) picks it up with one change, matching `nabhold/shared`'s existing `scope-registry.yaml` declaration for `context:resolve` exactly, no per-client duplication needed. Adds an `aud` assertion to `tests/integration/run.sh` §4. Does **not** touch `tenant_id` (§3) or `azp` (Keycloak already includes it by default; nothing to add here).
2. **`nabhold/shared` — contract completion** (gaps 10-12, and start of 13): fill in `mapping:*`/`market:*` scopes in `scope-registry.yaml`; add `azp` to `security-policy.yaml`'s `required_claims`; add `contracts/identity/v1/workload-registry.schema.json` (per §101's shape) plus a canonical instance file enumerating the 6 known workloads (`baobab-cms`, `baobab-erp`, `baobab-pulse`, `baobab-trade`, `thamani-backend`, `zuribeans-backend`) with their audiences/scopes/owner/environment/rotation-owner (§42's full field list).
3. **`baobab-iam` — workload registry as source of provisioning** (gap 3): `scripts/bootstrap.sh` reads phase 2's registry file (vendored) to drive which `*-workload.json` clients exist/what scopes+audiences they get; expand `tests/integration/run.sh` with the remaining §102 isolation cases not yet covered (wrong-environment credential, cross-workload impersonation attempt).
4. **`baobab-cp` — tenant-context redesign + registry-based enforcement** (gaps 6, 7, 9, and §3): replace the direct `principal.TenantID`-as-authorization pattern in `api/context.go` and `api/resolver_handler.go` with an explicit requested-tenant parameter validated against a workload-entitlement check (CapabilityBinding-style, per §89 "IAM SHALL not own those business/platform relationships" — this lives in `baobab-cp`, not `baobab-iam`); load phase 2's registry at startup and reject workload tokens for clients not present in it, with `azp` checked against the registry entry's expected client. Add the §102 integration test categories not yet covered (wrong audience, wrong azp, wrong actor type, revoked credential, cross-workload impersonation, unauthorized/disabled tenant).
5. **Workload lifecycle states** (§45: `PROVISIONED/ACTIVE/SUSPENDED/REVOKED/RETIRED`) — fold into phase 2's registry schema (a `status` field) and phase 4's enforcement (reject non-`ACTIVE`); sized as its own phase only if phases 2-4 turn out too large to absorb it.

Each phase gets its own PR, full local validation before push, and a check-in loop to green/merge before the next phase starts — the same discipline used for Gate IAM-3's 6 phases.

## 5. Explicitly not in this scope

- **mTLS, certificate issuance/rotation, gateway TLS termination** (§34-41, §94, §99, §103) — confirmed entirely owned by `nabhold/infrastructure`, which is not attached to this session. `shared`'s `security-policy.yaml` already carries the contract-level declaration (`mtls_required: true`); actual enforcement is out of reach here and isn't invented.
- **Delegation chains** (§13-18, §108) — `contracts/authorization/v1/delegation.schema.json` already exists as a contract; no repository has code consuming it yet, and ADR-0007 doesn't make this gate depend on it. Left for a later gate once a concrete delegation use case exists.
- **Rotation tooling/automation** (§103-105) — platform-wide exercises owned across `infrastructure`/security, not the three application repos this gate covers.
