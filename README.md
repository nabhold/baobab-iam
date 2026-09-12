# Baobab IAM (`baobab-iam`)

> **Baobab IAM** is the central authentication and identity provider for the Baobab platform. It implements **who** you are, while the Control Plane (`baobab-cp`) determines **where** and **what** you are entitled to, and domain engines enforce business authorization.

---

## Status

- **Architecture:** [ADR-0001 through ADR-0018](./docs/adr/README.md)
- **Implementation:** Gate IAM-2 (Keycloak foundation) hardening in progress — see
  [Gate IAM-0 discovery](./docs/governance/gate-iam-0-discovery.md) for the verified
  implementation state and open risks (notably R-1: the pinned Keycloak image digest in
  `upstream.lock.yaml` is still a placeholder pending registry access). Gate IAM-3's
  Control Plane identity spine (`CanonicalIdentity`/`ExternalIdentity`, in `baobab-cp`) and
  Gate IAM-4 (workload identity, ADR-0007) are **complete** — see
  [Gate IAM-3 scope](./docs/governance/gate-iam-3-canonical-identity-scope.md) and
  [Gate IAM-4 scope](./docs/governance/gate-iam-4-workload-identity-scope.md). Gate IAM-5
  (workforce SSO, ADR-0009) phase 1 (distinct workforce admin clients, a starter role
  namespace, a real `baobab-cp` admin-authorization defect fixed) and phase 2a
  (`baobab-trade` OIDC wiring, `nabhold/baobab-trade#70`) are complete. Phase 2b
  (`baobab-cms` OIDC wiring) is explicitly deferred to its own phase — see
  [Gate IAM-5 scope](./docs/governance/gate-iam-5-workforce-sso-scope.md) §5.1. Gate IAM-6
  (Zuribeans B2B, ADR-0010) phase 1 (Keycloak Organizations enabled, verified end-to-end
  against a real Keycloak instance) is complete — see
  [Gate IAM-6 scope](./docs/governance/gate-iam-6-zuribeans-b2b-scope.md) for phases 2+
  (`baobab-cp` canonical-entity wiring, cross-buyer isolation against real tokens). Gate
  IAM-7 (Thamani B2C, ADR-0011) is **scoped, not yet implemented** — discovery found two
  genuine architectural forks (where the customer OIDC redirect terminates; how a guest
  order's claim proof is delivered) that need their own decisions before code — see
  [Gate IAM-7 scope](./docs/governance/gate-iam-7-thamani-b2c-scope.md) §3. Gate IAM-8
  (Supplier Identity, ADR-0012) is **scoped, not yet implemented** — discovery found no
  repository anywhere owns "supplier domain" logic yet (a bigger blocker than Gate IAM-7's
  forks), so implementation is deferred pending that ownership decision — see
  [Gate IAM-8 scope](./docs/governance/gate-iam-8-supplier-identity-scope.md) §3. Gate
  IAM-9 (Medusa Integration, ADR-0013) found most of its scope already satisfied by Gate
  IAM-5's admin OIDC wiring, plus one real gap fixed — `authMethodsPerActor` was unset,
  making the admin `oidc` provider also implicitly reachable by the customer actor
  (`nabhold/baobab-trade#71`) — see
  [Gate IAM-9 scope](./docs/governance/gate-iam-9-medusa-integration-scope.md). Gate IAM-10
  (ERP Integration, ADR-0014) found iDempiere 13 ships a real, pluggable, built-in OIDC
  mechanism (`org.idempiere.ui.sso.oidc`) — a workforce SSO client (`baobab-erp-admin`) is
  provisioned for it, and `baobab-erp`'s previously-unauthenticated
  `/context/resolve*`/`/mapping/resolve*` endpoints now validate workload tokens. Ships
  against one explicit, documented deviation from ADR-0014 §9 (the stock plugin matches by
  email/username, not `issuer+subject`) — see
  [Gate IAM-10 scope](./docs/governance/gate-iam-10-erp-integration-scope.md) §2.
- **Next:** Finish Gate IAM-2 (environment separation, MFA/Organizations baseline), Gate
  IAM-5's remaining phases (`baobab-cms` OIDC wiring, `baobab-cp` role-aware admin
  authorization), Gate IAM-6's remaining phases, the shared Gate IAM-7/IAM-9
  customer-OIDC-termination decision, Gate IAM-8's supplier-domain ownership decision, and
  Gate IAM-10's remaining phases (closing its ADR-0014 §9 deviation, AD_User/Role/Client/Org
  provisioning), then Gates IAM-11 through IAM-16 now that the identity spine underneath
  them is sound.

---

## What this repository is

`baobab-iam` runs **Keycloak** as the authentication runtime. It owns:

- Authentication (OIDC, OAuth, MFA, passkeys)
- Credential management
- Authentication sessions
- Account recovery
- Identity federation
- Workload client credentials

It does **not** own:

- Tenant lifecycle (that is `baobab-cp`)
- Business authorization (that is domain engines)
- Commerce or ERP data

---

## Relationship with other repositories

| Repository | Relationship |
|------------|--------------|
| `nabhold/shared` | Consumes canonical identity, scope, and event contracts. |
| `nabhold/baobab-cp` | Validates tokens from this service and resolves canonical identity/context. |
| `nabhold/baobab-trade` | Authenticates buyers, customers, and administrators via this service. |
| `nabhold/baobab-erp` | Uses OIDC SSO for workforce and integration identities. |
| `nabhold/infrastructure` | Provides production runtime, database, and network. |

---

## Tech stack

| Concern | Choice |
|---------|--------|
| Identity provider | Keycloak 26.7.3 |
| Database | PostgreSQL 17 |
| Container | Distroless image, version-pinned (digest pin pending registry access — see R-1) |
| Configuration | JSON realm exports + idempotent bootstrap |
| CI/CD | Reusable workflows from `nabhold/shared` |

---

## Getting started

Clone the repository and start the local development stack:

```bash
git clone git@github.com:nabhold/baobab-iam.git
cd baobab-iam
cp .env.example .env
make dev-up
make bootstrap
make test
```

Run the ADR-0002 Section 48 verification suite against a running, bootstrapped stack:

```bash
BOOTSTRAP_WORKLOAD_CLIENT_SECRET=dev-secret make bootstrap
BOOTSTRAP_WORKLOAD_CLIENT_SECRET=dev-secret ./tests/integration/run.sh
```