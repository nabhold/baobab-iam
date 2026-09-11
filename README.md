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
  (workforce SSO, ADR-0009) phase 1 is complete (distinct workforce admin clients, a starter
  role namespace, and a real `baobab-cp` admin-authorization defect fixed) — see
  [Gate IAM-5 scope](./docs/governance/gate-iam-5-workforce-sso-scope.md) for phases 2+.
- **Next:** Finish Gate IAM-2 (environment separation, MFA/Organizations baseline) and Gate
  IAM-5's remaining phases (real OIDC wiring in `baobab-cms`/`baobab-trade`, `baobab-cp`
  role-aware admin authorization), then Gates IAM-6 through IAM-16 now that the identity
  spine underneath them is sound.

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