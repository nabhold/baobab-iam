# Gate IAM-5 — Workforce SSO

**Status:** Phase 1 complete. Phase 2a (`baobab-trade` OIDC wiring) complete — `nabhold/baobab-trade#70`. Phase 2b (`baobab-cms` OIDC wiring) explicitly deferred by decision, not merely unstarted — see §5.1. Remaining phases (admin role model in `baobab-cp`, MFA/step-up, lifecycle, audit) are scoped below but not yet implemented — see §5.
**Date:** 2026-09-11
**Governing ADR:** `ADR-0009 — Workforce SSO and Privileged Access`
**Repositories:** `nabhold/baobab-iam` (workforce SSO clients, owner), `nabhold/baobab-cp` (canonical identity, CP administration), `nabhold/baobab-cms`, `nabhold/baobab-trade`, `nabhold/baobab-erp`, `nabhold/baobab-pulse` (engine admin surfaces)
**Depends on:** Gate IAM-3 (canonical identity spine — complete), Gate IAM-4 (workload identity — complete)
**Out of scope (this phase):** MFA/step-up policy mechanics (ADR-0015, Gate IAM-11), identity lifecycle/deprovisioning automation (ADR-0016, Gate IAM-12), audit/observability wiring (ADR-0017, Gate IAM-13-ish) — ADR-0009 itself defers these ("exact assurance policy will be refined in ADR-0015", §39/§82).

The Consolidated Technical Specification's own one-line scope for this gate (§208) is: *"Integrate: Nabhold digital estate, CP administration, CMS admin, Pulse admin, Trade admin with central workforce authentication."* ADR-0009 is 125 sections covering the full workforce/privileged-access programme (SSO, privilege segregation, joiner/mover/leaver, break-glass, executive access, audit). This document scopes Gate IAM-5 to the SSO integration surface specifically, consistent with how Gate IAM-4 scoped ADR-0007 to workload identity rather than every downstream capability-entitlement concern.

---

## 1. Current state (verified against source, 2026-09-11)

A discovery pass across all five engine repos, cross-checked directly against code (not summaries):

**`baobab-iam`** has no workforce/admin SSO client at all before this PR — only bearer-only engine resource-server clients (`baobab-control-plane`, `baobab-cms`, `baobab-trade`, `baobab-erp`, `baobab-pulse`, all `bearerOnly: true`, `standardFlowEnabled: false`, no redirect URIs), the `*-workload.json` service-account clients (Gate IAM-4), and two B2C browser clients (`thamani-web`, `zuribeans-web`, `standardFlowEnabled: true` + PKCE). No client anywhere is set up for an administrator to actually log in. No realm roles are defined (`config/realm/baobab-realm.json` had no `roles` key at all).

**`baobab-cp`** is API-only (no frontend of its own anywhere in the repo). `internal/auth/oidc.go`'s `Verify()` only ever accepts/produces `actor_type ∈ {human, workload}` (line ~71) — matching `internal/domain.Principal`'s own `validPrincipalActorTypes = {human, workload, external}` (`internal/domain/identity.go`). But `api/router.go` gated every admin route (`/v1/tenants*`, `/v1/entitlements`, `/v1/canonical-entities*`, `/v1/capabilities/explain`) on `principal.ActorType == "admin"` — a literal value `Verify()` can never produce. **This meant every admin-gated route in `baobab-cp` has been unreachable by any real IAM-issued token since it was written**, exactly the same class of defect as Gate IAM-4 phase 4's workload-tenant gap: every existing test hand-constructed a synthetic `auth.Principal{ActorType: "admin", ...}` bypassing the verifier entirely, so the bug was invisible to the test suite. **Fixed in this PR** (§4). No CP admin role/permission model exists otherwise — authorization is flat OAuth2 scopes only (`tenant:write`, `canonical:write`, etc.), no RBAC table.

**`baobab-cms`** (Payload CMS 3.x) uses Payload's built-in local email/password auth with no `auth.strategies` customization. The `Users` collection already isolates authorization from the concrete auth mechanism via a `ContextActor` structural interface (`docs/identity/README.md` explicitly anticipates SSO as a future `auth.strategies` addition, and states this needs no change to `src/baobab/context`/`authorization`). Clean, low-risk integration point once phase 2 wires it up. No OIDC/SSO plugin dependency exists yet.

**`baobab-trade`** (Medusa v2.20.1) runs Medusa's default `emailpass` admin auth with zero customization — confirming Gate IAM-0's original finding still holds. Medusa v2 ships `@medusajs/auth-oidc` (backed by `openid-client`) as a first-party, already-available auth-provider module; it is simply not configured in `medusa-config.ts`. This is the lowest-effort real integration target for phase 2 — no bespoke OIDC client code needs to be written, only the provider needs enabling and pointing at Keycloak.

**`baobab-pulse`** has no admin UI or console of any kind (confirmed: no `admin`/`console` paths, no frontend directory) and no authentication layer at all, human or machine. It is explicitly out of this phase's scope — there is nothing to integrate SSO with yet. Revisit once Pulse grows an operator-facing surface.

**`baobab-erp`** is not part of this gate's explicit scope per the Consolidated Spec's §208 line (ERP SSO is `ADR-0014`/Gate IAM-10's concern) and was not re-investigated here.

---

## 2. Gaps against ADR-0009

1. **No distinct workforce admin client registrations** (§9-10) — fixed in phase 1 for CP/CMS/Trade (§4).
2. **No workforce role namespace** (§102-103) — fixed in phase 1: a starter realm-role catalog (§4).
3. **`baobab-cp`'s admin routes were unreachable by any real human token** (§3, §93 — "IAM login succeeds but application access denied" is expected only when authorization is correctly evaluated, not when the actor-type check itself is unsatisfiable) — fixed in phase 1 (§4).
4. **No actual SSO wiring in any engine's admin UI** (§6) — CMS and Trade both have clean, identified integration points (§1) but neither is wired yet. Deferred to phase 2 (§5).
5. **No CP admin role model beyond flat scopes** (§14-16) — the new `cp:platform-admin`/`cp:tenant-admin` realm roles (§4) give IAM-side vocabulary, but nothing in `baobab-cp` yet maps a workforce token's roles into scoped authorization decisions beyond the existing flat per-route scopes. Deferred to phase 3 (§5).
6. **MFA is not enforced for any client, privileged or not** (§37-40) — deferred to ADR-0015/Gate IAM-11 per ADR-0009's own text.
7. **No joiner/mover/leaver process, break-glass mechanism, or access-review tooling** (§29-36, §53-67) — deferred; these require `baobab-cp`'s workforce-membership model (§27) to exist first, which is itself downstream of this gate's SSO plumbing.
8. **No audit correlation for privileged actions** (§96-101) — deferred to ADR-0017/Gate IAM-13-ish.

---

## 3. Architectural note: "admin" was never a real actor type

The `baobab-cp` defect in §1/§2.3 is worth stating plainly because it's easy to miss: this was not a missing feature, it was a self-inconsistency already present in the codebase. `internal/domain/identity_test.go`'s own `TestPrincipalValidateRejectsUnknownActorType` explicitly asserts `"admin"` is an *invalid* canonical actor_type (only `human`/`workload`/`external` are valid) — the same file that defines the correct vocabulary also (in a different package, `api/router.go`) violated it. ADR-0009 §3's core principle — "one workforce identity does not mean one universal workforce privilege" — is exactly the fix's shape: a workforce user authenticates as `actor_type=human` like anyone else; scope/role claims, not a separate magic actor type, are what admin routes should (and, after this PR, do) gate on.

---

## 4. Phase 1 (this PR)

**`baobab-iam`:**
- Three new distinct workforce SSO clients (ADR-0009 §9's own naming examples): `baobab-control-plane-admin` (public + PKCE S256 — `baobab-cp` has no session/cookie layer of its own, so its eventual admin console authenticates directly against Keycloak the same way `thamani-web`/`zuribeans-web` already do, then presents the access token as a Bearer credential), `baobab-cms-admin` and `baobab-trade-admin` (both confidential — Payload and Medusa's admin auth both run server-side and can hold a client secret). All three: `standardFlowEnabled: true`, `actor-type-human` default scope, distinct from and additional to the pre-existing bearer-only engine clients (§9-10's "no universal admin client" + independent redirect URIs/audiences/revocation).
- A starter workforce realm-role catalog in `config/realm/baobab-realm.json` (§102-103's namespaced naming: `iam:security-admin`, `iam:helpdesk`, `cp:platform-admin`, `cp:tenant-admin`, `trade:operator`, `cms:editor`, `cms:publisher`) — deliberately small and directly traceable to ADR-0009's own named examples rather than attempting to enumerate every conceivable role (§104's role-explosion warning). None are added to `defaultRoles` (§13 least privilege, §87-88 no privileged JIT provisioning).
- `tests/integration/run.sh` §11-12: the new admin clients are provisioned as distinct SSO-capable (not bearer-only) registrations with PKCE and the `actor-type-human` scope, alongside (not replacing) their engine counterparts; the new realm roles exist and none of them leak into `default-roles-baobab`.

**`baobab-cp`:**
- `api/router.go`: every `a.authorize(a.adminVerifier, "admin", ...)` call now requires `"human"` — the actor type real workforce tokens actually carry — instead of the never-producible `"admin"` literal. Scope-per-route gating (`tenant:write`, `canonical:write`, `capabilities:explain`, etc.) is unchanged.
- `api/capability_explain_handler.go`: its own separate inline `principal.ActorType != "admin"` check fixed the same way.
- Test fixtures in `api/router_test.go` and `api/capability_explain_handler_test.go` updated from a synthetic `ActorType: "admin"` to `ActorType: "human"`, matching what `Verify()` can actually produce; `TestCapabilityExplainHandlerRejectsNonAdmin`'s workload-principal negative case is untouched and still passes, confirming actor-type separation still holds.
- `go build`, `go vet`, `gofmt -l`, `go test -race ./...` all green.

**Deliberately not touched:** no OIDC wiring inside `baobab-cms` or `baobab-trade` themselves (phase 2), no CP-side role-to-scope mapping (phase 3), no MFA/step-up configuration (ADR-0015/Gate IAM-11).

---

## 5. Remaining phases (scoped, not yet implemented)

2a. ~~**`baobab-trade` — real OIDC wiring.**~~ **Done — `nabhold/baobab-trade#70`.** Enabled Medusa's bundled `@medusajs/auth-oidc` provider in `medusa-config.ts` pointed at `baobab-trade-admin` — no bespoke client code, only configuration (registering `@medusajs/medusa/auth` explicitly, with `emailpass` kept alongside the new conditional `oidc` entry so nothing regresses when `BAOBAB_IAM_OIDC_ISSUER` is unset). `npm run format:check`/`lint`/`typecheck`/`test`/`build` all green, `build` exercised in both the SSO-enabled and SSO-disabled configurations.

### 5.1 `baobab-cms` — real OIDC wiring, deferred by decision

Unlike Trade, Payload CMS has no official or community OIDC auth-provider plugin (checked directly against the npm registry — nothing matching `payload`+`oidc`/`sso`/`keycloak` exists as of 2026-09-11). Wiring SSO here means writing a custom `auth.strategies` implementation from scratch using `openid-client` (the same underlying library Medusa's own official module uses) — authorization-redirect construction, PKCE/state/nonce handling, token exchange, ID-token verification, and session issuance, mapped onto `Users`' existing `canonicalActorId`/`platformAdministrator` fields per the repo's own anticipated integration point (`docs/identity/README.md`).

This is qualitatively different from phase 2a: net-new security-critical authentication code, not configuration of an already-audited module. Given that risk profile, the decision (2026-09-11, explicit check-in) was to **defer this to its own dedicated phase** rather than build it in the same pass as the rest of Gate IAM-5's lower-risk work, so it can get focused design/security attention (state/PKCE correctness, redirect-URI validation, token verification) rather than being rushed alongside phase 1/2a. Not started; no code exists yet in `baobab-cms` for this.

3. **`baobab-cp` — role-aware admin authorization.** Map the new `cp:platform-admin`/`cp:tenant-admin` realm roles (carried in a human token's `roles` claim once phase 2-adjacent CP-console work exists) onto `router.go`'s admin routes, rather than the current flat per-scope gating alone — giving ADR-0009 §14-16's privilege-segregation model actual teeth in `baobab-cp`, not just IAM-side vocabulary.
4. **Workforce membership model in `baobab-cp`** (§27-28) — the `CanonicalIdentity → WorkforceMembership → {LegalEntity, Tenant, status}` relationship ADR-0009 needs for joiner/mover/leaver (§29-36) and executive cross-tenant access (§24-26) to be real rather than conceptual.
5. **MFA/step-up** — ADR-0015, Gate IAM-11; explicitly out of this gate per ADR-0009's own text.
6. **Break-glass, access review, audit correlation** (§53-67, §96-101) — depend on 3-4 existing first.
7. **`baobab-pulse` admin surface** — revisit once Pulse has an operator-facing console to integrate; nothing to wire today.
8. **`baobab-erp`** — owned by Gate IAM-10 (`ADR-0014`), not this gate.

Each phase gets its own PR, full local validation, and a check-in loop to green/merge before the next phase starts, matching Gate IAM-3/IAM-4's discipline.

---

## 6. Required tests not yet covered

ADR-0009 §108-111's full test list (SSO cross-application, MFA, separation-of-duties, lifecycle, cross-tenant, break-glass, offboarding, access-review) is aspirational for the *whole* gate, not phase 1 — most of it depends on phases 2-6 existing first. Phase 1's own tests (§4) cover only: distinct client registration, PKCE/actor-type-human wiring, and least-privilege role provisioning. This is recorded explicitly rather than silently, per this session's established documentation discipline (see Gate IAM-4's scope doc §6-8 for the same pattern).
