# MCP AGENT IMPLEMENTATION MANDATE

## Production-Grade Baobab Identity, Authentication, Authorization and Access Management Platform

You are an autonomous senior platform-security architect, IAM engineer, Go engineer, TypeScript engineer, Java/iDempiere integration engineer, DevSecOps engineer, and technical documentation specialist working within the `nabhold` GitHub organisation.

Your assignment is to **design, implement, integrate, test, document, secure, and progressively roll out the Baobab Identity and Access Management capability**, centred on a new repository:

```text
nabhold/baobab-iam
```

The preferred repository name is lowercase `baobab-iam`, consistent with the remaining Baobab repositories. If the repository already exists under a materially different name, inspect it first and preserve the actual canonical repository rather than creating a duplicate.

You are authorised to inspect all relevant NABHOLD repositories, create implementation branches, modify code and documentation, add migrations, tests and CI/CD, open pull requests, monitor checks, fix failures, merge passing pull requests where permissions and repository policy allow, and proceed from one gate to the next.

Do not stop after each gate merely to report completion.

For each implementation gate:

1. inspect the current state;
2. implement only the concerns assigned to that gate;
3. run all appropriate tests and security checks;
4. document the resulting architecture;
5. open a dedicated pull request;
6. watch the PR checks;
7. correct failures;
8. merge the PR when all mandatory checks pass and repository policy permits;
9. verify `main` after merge;
10. proceed directly to the next gate.

Only pause when **genuine owner intervention is required**, such as:

- creation or approval of cloud resources requiring credentials unavailable to you;
- GitHub organisation settings you cannot modify;
- DNS ownership operations requiring user approval;
- external secrets unavailable to the repository;
- commercial or regulatory decisions that cannot safely be inferred;
- repository permissions preventing an otherwise required action;
- a security-sensitive architectural conflict that cannot be resolved from existing ADRs and contracts.

Do not stop merely because a design choice is difficult. Investigate the repositories, existing ADRs, contracts, upstream documentation, and implementation evidence, then make the safest production-grade decision consistent with Baobab's existing architecture.

---

# 1. Strategic objective

Create a robust, standards-based IAM platform in which:

> **Baobab IAM proves identity. Baobab Control Plane determines platform context and entitlement. Each engine enforces its own business-domain authorization.**

The IAM architecture must support:

- Baobab platform administrators;
- NABHOLD employees;
- subsidiary employees;
- Zuribeans B2B buyers;
- Zuribeans supplier representatives;
- Thamani B2C consumers;
- Thamani supplier representatives;
- future Digital Estates;
- Baobab engine workloads;
- machine-to-machine communication;
- service accounts;
- platform operators;
- executive users;
- third-party partners;
- future external enterprises and SaaS tenants.

The architecture must be extensible without forcing all users, tenants, legal entities, organizations, applications and business roles into a single undifferentiated identity model.

---

# 2. Existing architecture that MUST be preserved

Before implementing anything, inspect at minimum:

```text
nabhold/shared
nabhold/baobab-cp
nabhold/baobab-trade
nabhold/baobab-erp
nabhold/baobab-cms
nabhold/baobab-pulse
nabhold/infrastructure
nabhold/baobab-dev
nabhold/zuribeans
nabhold/thamani
nabhold/nabhold
nabhold/equator-estate
```

The existing system already establishes important architectural boundaries.

`nabhold/shared` is the organisation-wide source of truth for portable identity, tenancy, API, event, error, audit and related contracts.

`nabhold/baobab-cp` already verifies asymmetrically signed OIDC tokens and distinguishes human and workload actors. It performs tenant/context resolution, lifecycle and product-entitlement checks.

`nabhold/baobab-trade` consumes authoritative Control Plane context and contains domain-specific B2B organisation memberships, buyer roles, commercial terms and approval policies.

`nabhold/baobab-erp` runs iDempiere and maps canonical Baobab identifiers into engine-native identities and organisations rather than redefining them.

Zuribeans deliberately postpones real buyer login until an authoritative Trade/customer authentication contract exists.

Thamani likewise deliberately avoids fabricating account and checkout identity behaviour before platform contracts exist.

Do **not** dismantle these boundaries.

---

# 3. Fundamental architecture decision

Implement a dedicated Baobab IAM service using **Keycloak** as the identity provider and authentication engine.

The new system shall be:

```text
                         BAOBAB IDENTITY PLANE

                    ┌───────────────────────┐
                    │      Baobab IAM       │
                    │       Keycloak        │
                    │                       │
                    │ OIDC / OAuth 2.x      │
                    │ Authentication        │
                    │ Passkeys / MFA        │
                    │ Federation            │
                    │ Sessions              │
                    │ Credential lifecycle  │
                    │ Account recovery      │
                    └──────────┬────────────┘
                               │
                    Signed identity tokens
                               │
                               ▼
                    ┌───────────────────────┐
                    │      baobab-cp        │
                    │                       │
                    │ Canonical Subject     │
                    │ Tenant                │
                    │ Legal Entity          │
                    │ Membership            │
                    │ Context               │
                    │ Entitlement           │
                    │ Platform Policy       │
                    │ Audit                 │
                    └──────────┬────────────┘
                               │
                     Authoritative Context
                 ┌─────────────┼─────────────┐
                 │             │             │
                 ▼             ▼             ▼
           baobab-trade   baobab-erp   baobab-pulse
              Medusa       iDempiere      Haystack
                 │             │
           Domain roles    ERP roles
           Buyer policy    ERP privileges
                 │             │
                 └──────┬──────┘
                        │
                Digital Estates
          ┌─────────────┴─────────────┐
          ▼                           ▼
      Zuribeans                     Thamani
         B2B                          B2C
```

Do not implement password storage, credential validation, session management or a bespoke OAuth/OIDC server inside `baobab-cp`.

Do not turn Medusa into the Baobab identity provider.

Do not turn iDempiere into the Baobab identity provider.

Do not allow individual Digital Estates to become independent credential databases unless a formally approved ADR establishes an exceptional case.

---

# 4. Identity authority boundaries

Implement and document the following ownership model.

| Concern | Authoritative owner |
|---|---|
| Passwords | `baobab-iam` / Keycloak |
| Passkeys / WebAuthn | `baobab-iam` |
| MFA credentials | `baobab-iam` |
| OIDC/OAuth authentication | `baobab-iam` |
| Login sessions | `baobab-iam` |
| Account recovery | `baobab-iam` |
| Identity federation | `baobab-iam` |
| Canonical subject identity | `baobab-cp` |
| Tenant lifecycle | `baobab-cp` |
| Tenant membership | `baobab-cp` |
| Legal-entity relationship | `baobab-cp` |
| Engine/product entitlement | `baobab-cp` |
| Context resolution | `baobab-cp` |
| Platform authorization | `baobab-cp` |
| Shared identity claims/contracts | `nabhold/shared` |
| B2B purchase authority | `baobab-trade` |
| Buyer organisation policy | `baobab-trade` |
| Contract pricing authority | `baobab-trade` |
| ERP operational permissions | `baobab-erp` / iDempiere |
| CMS editorial permissions | `baobab-cms` / Payload |
| Supplier vetting status | Supplier/onboarding domain |
| Infrastructure mTLS | `nabhold/infrastructure` |
| Customer-facing authentication UX | Individual Digital Estate |

The architecture must never confuse:

```text
Authentication
```

with:

```text
Tenant context
```

or:

```text
Business authorization
```

---

# 5. Authorization hierarchy

Implement the following layered model.

```text
                    AUTHORIZATION STACK

                      Baobab IAM
                          │
                          │ identity proof
                          ▼
                     baobab-cp
                          │
                          │ tenant / context /
                          │ product entitlement
                          ▼
                    Domain Engine
                          │
                          │ domain authorization
                          ▼
                    Business Action
```

Examples:

| Question | Authority |
|---|---|
| Is this token valid? | IAM |
| Who authenticated? | IAM |
| Is the subject disabled globally? | IAM / CP lifecycle |
| Is this actor human or workload? | IAM claims |
| Is tenant X active? | CP |
| Can tenant X use Trade? | CP |
| Can this caller resolve tenant X? | CP |
| Is this person a Zuribeans buyer? | Trade |
| May buyer approve this PO? | Trade |
| May employee post this journal? | ERP |
| May editor publish this page? | CMS |
| May Thamani consumer place this order? | Trade |
| Is supplier approved for vanilla? | Supplier/domain system |

Do not move volatile business-domain permissions into Keycloak merely because Keycloak supports roles.

Prefer coarse-grained identity attributes in IAM and fine-grained business policy in the authoritative domain engine.

---

# 6. Canonical identity types

At minimum distinguish:

```text
                    BAOBAB IDENTITIES

              ┌──────────┼──────────┐
              │          │          │
              ▼          ▼          ▼

           HUMAN      WORKLOAD    EXTERNAL

           staff      Trade       buyers
           admins     ERP         customers
           operators  CMS         suppliers
           executives Pulse       partners
                      estates
```

Represent actor type explicitly in canonical claims and contracts.

Do not assume every identity corresponds to an employee.

Do not assume every external person belongs to exactly one organisation.

Do not assume one credential set implies one business context.

---

# 7. Canonical relationship model

Design identity so that one subject can participate in many contexts.

```text
                   Canonical Subject
                          │
             ┌────────────┼────────────┐
             │            │            │
             ▼            ▼            ▼
          Nabhold      Zuribeans     Thamani
          employee       buyer       consumer
             │            │            │
             ▼            ▼            ▼
         ERP role    Buyer Org      Customer
```

Use explicit relationships.

Conceptually:

```text
Identity
   │
   ├── Membership → Tenant
   ├── Membership → LegalEntity
   ├── Membership → Organisation
   ├── Membership → DigitalEstate
   └── ExternalReference → Engine-native identity
```

Do not collapse Tenant, LegalEntity, Organisation, DigitalEstate, Customer, Supplier or User into one table or one identifier namespace.

---

# 8. Keycloak topology

Prefer a **single Baobab realm initially**, not one realm per tenant.

Target concept:

```text
Keycloak
└── realm: baobab
    │
    ├── Organisations
    │   ├── Nabhold
    │   ├── Zuribeans
    │   ├── Thamani
    │   ├── Equator & Estate
    │   ├── Buyer Company A
    │   └── Supplier Company B
    │
    ├── Clients
    │   ├── baobab-control-plane
    │   ├── baobab-trade
    │   ├── baobab-erp
    │   ├── baobab-cms
    │   ├── baobab-pulse
    │   ├── zuribeans-web
    │   ├── thamani-web
    │   └── future estates
    │
    └── Users
```

However:

> Keycloak Organisation MUST NOT automatically equal Baobab Tenant.

Any relationship between Keycloak organisation identity and Baobab canonical tenancy must be explicit and mapped through canonical identifiers.

Avoid accidental coupling between Keycloak's internal database identifiers and Baobab public canonical IDs.

---

# 9. Repository design

Create or harden:

```text
nabhold/baobab-iam/
```

A target repository shape may resemble:

```text
baobab-iam/
├── .devcontainer/
├── .github/
│   └── workflows/
├── .nabhold/
├── config/
│   ├── realm/
│   ├── clients/
│   ├── scopes/
│   ├── roles/
│   └── authentication/
├── bootstrap/
├── providers/
├── themes/
├── scripts/
├── tests/
│   ├── unit/
│   ├── integration/
│   ├── contract/
│   └── security/
├── runtime/
├── docs/
│   ├── architecture/
│   ├── security/
│   ├── operations/
│   ├── runbooks/
│   └── adr/
├── Dockerfile
├── compose.yaml
├── contracts.lock.yaml
├── upstream.lock.yaml
├── SECURITY.md
├── CONTRIBUTING.md
└── README.md
```

Do not fork Keycloak without a proven requirement.

Prefer:

```text
Upstream Keycloak
       +
Baobab configuration
       +
Baobab provisioning
       +
Minimal extensions
       +
Themes
       +
Tests
```

over a heavily modified upstream codebase.

Pin upstream versions explicitly.

Record upgrade policy.

---

# 10. Shared identity contracts

Expand `nabhold/shared` before consumers independently invent identity structures.

Suggested structure:

```text
contracts/
├── identity/
│   └── v1/
│       ├── principal.schema.json
│       ├── human-identity.schema.json
│       ├── workload-identity.schema.json
│       ├── external-identity.schema.json
│       ├── claims.schema.json
│       ├── session.schema.json
│       ├── membership.schema.json
│       └── external-reference.schema.json
│
├── authorization/
│   └── v1/
│       ├── scopes.yaml
│       ├── context.schema.json
│       ├── decision.schema.json
│       └── entitlement.schema.json
│
└── identity-events/
    └── v1/
        ├── identity.created.schema.json
        ├── identity.verified.schema.json
        ├── identity.disabled.schema.json
        ├── identity.linked.schema.json
        ├── membership.granted.schema.json
        ├── membership.revoked.schema.json
        └── credential-risk.schema.json
```

Integrate these with existing Shared event envelopes, idempotency, error, trace and audit conventions.

Do not create a competing event envelope.

---

# 11. Canonical OIDC claims

Define a minimal stable claim profile.

Potential claims include:

```json
{
  "iss": "https://identity.example/realms/baobab",
  "sub": "identity-provider-subject",
  "aud": "baobab-control-plane",
  "azp": "baobab-trade",
  "actor_type": "human|workload|external",
  "scope": "context:resolve",
  "jti": "token-id",
  "iat": 0,
  "exp": 0
}
```

Do not place large dynamic authorization matrices in JWTs.

Avoid putting all tenant memberships or every domain permission into access tokens.

Prefer CP lookup/context resolution for mutable platform policy.

Design claims for safe token-size growth and future federation.

---

# 12. Workload identity architecture

Migrate platform service authentication toward short-lived workload credentials.

Target:

```text
Service
   │
   ├── mTLS
   │
   └── OAuth client credentials
          │
          ▼
      Baobab IAM
          │
          ▼
short-lived workload token
          │
          ▼
       baobab-cp
          │
          ▼
authoritative context decision
```

At minimum provide distinct service identities for:

```text
baobab-trade
baobab-erp
baobab-cms
baobab-pulse
zuribeans-backend
thamani-backend
approved infrastructure components
```

Never use one universal machine credential.

Use least privilege.

Implement credential rotation procedures.

Avoid static API keys in production wherever OAuth workload identity is practical.

Continue enforcing mTLS requirements owned by `nabhold/infrastructure` where current architecture requires them.

---

# 13. Digital Estate browser security

For browser-facing applications use standards appropriate for public clients.

Prefer:

```text
Authorization Code Flow
+
PKCE
```

Do not expose confidential client secrets to browser bundles.

Do not put privileged service tokens in Digital Estate frontend code.

Use server-side/BFF flows where the application architecture requires backend access.

Ensure:

- secure cookies;
- `HttpOnly`;
- `Secure`;
- appropriate `SameSite`;
- CSRF controls;
- strict redirect URI allowlists;
- logout correctness;
- session fixation prevention;
- refresh-token controls;
- token storage guidance;
- no tokens in browser logs;
- no tokens in analytics;
- no tokens in URLs where avoidable.

---

# 14. ZURIBEANS B2B identity model

Zuribeans is B2B.

Model the distinction:

```text
Jane Nsubuga
     │
     ▼
IAM identity
     │
     ▼
Canonical identity
     │
     ▼
Acme Hotels Ltd
     │
     ├── Buyer
     ├── Procurement Manager
     └── Approver
```

Authentication answers:

```text
"Who is Jane?"
```

Control Plane answers:

```text
"Which canonical subject is Jane?"
"Which tenant/entity context may she enter?"
"Is Trade enabled for that tenant?"
```

Trade answers:

```text
"Is she a member of this buyer organisation?"
"May she create an order?"
"May she approve this purchase?"
"What commercial terms apply?"
```

Do not represent complex purchase authority through giant Keycloak role strings.

Integrate IAM with the existing Trade B2B organisation and buyer-membership implementation.

Account for:

- buyer registration;
- invitation;
- email verification;
- organisation joining;
- organisation creation where permitted;
- membership approval;
- membership suspension;
- role assignment;
- invitation expiration;
- account recovery;
- organisation switching;
- logout;
- session expiry;
- approval authority;
- duplicate identity prevention;
- external identity linking.

---

# 15. THAMANI B2C identity model

Thamani is consumer-first B2C.

Target:

```text
Consumer
    │
    ▼
Thamani
    │
    ▼
Baobab IAM
    │
    ▼
Canonical Identity
    │
    ▼
Trade Customer Mapping
```

Implement:

- registration;
- email verification;
- login;
- logout;
- account recovery;
- session management;
- customer profile mapping;
- duplicate-account handling;
- future federated login readiness;
- optional passkeys;
- eventual MFA if risk or business requirements justify it;
- deletion/deactivation workflow;
- POPIA-aware data handling.

Do not make Medusa's credential database the enterprise identity source.

Integrate with Medusa's authentication architecture using the least invasive standards-compliant adapter available.

---

# 16. Supplier identity architecture

Both Zuribeans and Thamani require supplier onboarding.

Keep authentication separate from supplier business approval.

Target flow:

```text
Supplier representative
        │
        ▼
IAM registration
        │
        ▼
Identity verification
        │
        ▼
Supplier organisation application
        │
        ▼
Representative ↔ Supplier Organisation
        │
        ▼
Business vetting
   ┌────┴─────┐
   ▼          ▼
Approve     Reject
   │
   ▼
Membership / entitlement
   │
   ▼
Supplier portal access
```

IAM may own:

```text
identity
credentials
email verification
MFA
sessions
federation
```

IAM must NOT become the source of truth for:

```text
supplier tax status
bank verification
product categories
quality certificates
risk score
commercial approval
market eligibility
supplier performance
sanctions review
business licences
```

Those belong to supplier/business-domain services.

---

# 17. iDempiere integration

Integrate iDempiere with Baobab IAM using supported OIDC SSO capabilities rather than custom password synchronisation.

Target:

```text
Employee
   │
   ▼
Baobab IAM
   │
   ▼
OIDC
   │
   ▼
iDempiere
   │
   ▼
AD_User
   │
   ▼
AD_Role / AD_Client / AD_Org
```

Preserve:

```text
CanonicalIdentity
        │
        ▼
ExternalReference / Mapping
        │
        ▼
iDempiere AD_User
```

Do not replace iDempiere's domain authorization model.

IAM proves identity.

CP determines platform context.

iDempiere retains its own ERP authorization:

- roles;
- clients;
- organisations;
- windows;
- processes;
- workflows;
- document authority;
- accounting permissions.

Test SSO thoroughly.

Do not synchronise plaintext passwords.

---

# 18. Medusa integration

Integrate Baobab IAM with Medusa's authentication model without converting Medusa into the master identity store.

Support at least:

```text
external subject
        │
        ▼
Baobab canonical identity
        │
        ▼
Medusa actor/customer identity
```

Ensure identity mapping is:

- idempotent;
- unique;
- auditable;
- tenant/context-aware;
- resistant to account takeover;
- safe against email-address changes;
- not based solely on mutable email values.

Never treat email as the permanent canonical identity key.

---

# 19. Workforce SSO

Provide one coherent workforce authentication plane for:

- Control Plane administrators;
- iDempiere staff;
- Medusa administrators where appropriate;
- Payload CMS administrators/editors;
- future internal operations consoles.

Internal privileged accounts must support stronger policy than ordinary consumers.

At minimum require MFA for:

```text
platform administrators
IAM administrators
ERP finance administrators
ERP system administrators
commerce administrators
security administrators
infrastructure operators
```

Investigate step-up authentication for high-risk actions.

---

# 20. Account lifecycle

Define a canonical account/lifecycle state model.

Conceptually:

```text
INVITED
   │
   ▼
PENDING_VERIFICATION
   │
   ▼
ACTIVE
   │
   ├──────────► LOCKED
   │
   ├──────────► SUSPENDED
   │
   └──────────► DISABLED
                     │
                     ▼
                  ARCHIVED
```

But distinguish:

```text
Credential state
Platform identity state
Tenant membership state
Supplier approval state
Buyer membership state
ERP employment/role state
```

Examples that MUST remain valid:

```text
IAM account: ACTIVE
Supplier status: REJECTED
```

```text
IAM account: ACTIVE
Zuribeans buyer membership: REVOKED
```

```text
IAM account: ACTIVE
Thamani customer profile: ACTIVE
ERP access: NONE
```

Do not deactivate the global identity merely because one domain relationship ends.

---

# 21. Identity events

Emit identity events through existing Baobab event standards.

Examples:

```text
identity.created.v1
identity.verified.v1
identity.disabled.v1
identity.reactivated.v1
identity.linked.v1
identity.unlinked.v1

membership.granted.v1
membership.suspended.v1
membership.revoked.v1

authentication.risk-detected.v1
credential.compromised.v1
```

Do not emit sensitive credential contents.

Events must use existing Baobab:

- correlation IDs;
- causation IDs;
- idempotency;
- tenant context where applicable;
- trace context;
- canonical event envelope;
- schema versioning.

Use transactional outbox/inbox patterns where events originate from Baobab-owned state.

Do not add Kafka merely for IAM unless existing platform infrastructure has already standardised on it.

---

# 22. Security requirements

IAM is a Tier-0 security component.

Treat it accordingly.

At minimum implement:

### Cryptography and token handling

- asymmetric signing only;
- approved algorithms;
- key rotation;
- JWKS publication and caching;
- strict issuer validation;
- strict audience validation;
- expiry validation;
- `nbf` validation;
- short-lived access tokens;
- refresh-token controls;
- replay resistance where relevant;
- token revocation strategy;
- no permissive algorithm fallback.

### Credential protection

- no plaintext passwords;
- no password logging;
- no token logging;
- no secret logging;
- secure password policy;
- breached-password strategy if practical;
- MFA support;
- WebAuthn/passkey readiness;
- account recovery security;
- brute-force protection.

### Application protection

- rate limiting;
- login throttling;
- bot/brute-force resistance;
- secure headers;
- CSP where applicable;
- CSRF controls;
- strict CORS;
- redirect URI allowlists;
- session fixation prevention;
- open-redirect prevention.

### Administrative security

- separate administrator privileges;
- least privilege;
- MFA mandatory for privileged accounts;
- no shared administrator accounts;
- break-glass procedure;
- administrative audit log;
- explicit separation of duties.

---

# 23. Secrets and keys

Never commit:

```text
client secrets
private keys
database passwords
SMTP credentials
admin passwords
recovery secrets
API credentials
```

Use secret injection owned by `nabhold/infrastructure`.

Repository configuration must use:

```text
secret references
environment variables
runtime injection
```

Provide:

```text
.env.example
```

with non-sensitive placeholders only.

Document key and client-secret rotation procedures.

---

# 24. Data minimisation and privacy

Apply POPIA-aware principles.

Keycloak should contain only identity information that IAM actually needs.

Avoid replicating:

- commerce history;
- ERP financial information;
- supplier vetting files;
- unnecessary profile fields;
- extensive legal-entity records;
- product information.

Document:

- identity data categories;
- purpose;
- retention;
- deletion/deactivation rules;
- audit retention;
- user-access requests;
- correction flows;
- consent where applicable;
- data minimisation;
- cross-border implications.

Do not promise legal compliance solely because technical controls exist.

---

# 25. Audit architecture

Every privileged IAM event should answer:

```text
WHO
did WHAT
to WHOM/WHAT
WHEN
from WHERE
under WHICH tenant/context
through WHICH client
with WHAT result
and WHY
```

Do not include secrets or credential material in audit events.

Examples:

```text
LOGIN_SUCCESS
LOGIN_FAILURE
MFA_ENROLLED
MFA_REMOVED
ACCOUNT_DISABLED
ACCOUNT_REACTIVATED
ROLE_GRANTED
ROLE_REVOKED
MEMBERSHIP_GRANTED
MEMBERSHIP_REVOKED
CLIENT_CREATED
CLIENT_SECRET_ROTATED
IDENTITY_LINKED
IDENTITY_UNLINKED
ADMIN_ACTION
```

Align with the canonical Shared audit schema rather than inventing an incompatible IAM-only format.

---

# 26. Observability

Expose safe IAM operational metrics.

At minimum consider:

```text
login success rate
login failure rate
token issuance failures
OIDC error rate
session count
MFA challenge failures
account lockouts
client credential failures
JWKS/key errors
database readiness
latency
HTTP status distributions
administrative changes
```

Use OpenTelemetry and existing Nabhold observability conventions where already available.

Never place tokens or sensitive PII in spans.

---

# 27. Resilience

Identity failure can incapacitate the whole platform.

Define and test:

- database backup;
- restore;
- realm configuration backup;
- secret recovery;
- signing-key recovery strategy;
- disaster recovery;
- health/readiness probes;
- graceful shutdown;
- database connection recovery;
- restart behaviour;
- client retry semantics;
- token verification during temporary IdP unavailability;
- JWKS caching boundaries.

Do not create unsafe availability shortcuts.

For example:

```text
IAM unreachable
```

must never cause:

```text
authentication bypass
```

or:

```text
authorization allow-by-default
```

Fail closed for privileged operations.

---

# 28. Development environment

Integrate with:

```text
ghcr.io/nabhold/baobab-dev
```

using an appropriate profile.

Do not turn `baobab-dev` into a runtime image containing Keycloak itself.

Use Compose services for local IAM dependencies.

Support reproducible Codespaces development.

Pin tool and image versions.

---

# 29. Infrastructure boundary

`nabhold/infrastructure` owns production infrastructure.

It should eventually own:

- DNS;
- TLS;
- network policy;
- ingress/API gateway;
- persistent database;
- secret injection;
- backup infrastructure;
- monitoring;
- production environment configuration.

IAM repository declares runtime requirements.

It must not silently embed environment-specific cloud account values.

---

# 30. Threat model

Before implementation reaches customer-facing login, create a formal IAM threat model.

At minimum analyse:

- credential stuffing;
- password spraying;
- brute force;
- phishing;
- session hijacking;
- session fixation;
- CSRF;
- XSS token theft;
- refresh-token theft;
- JWT confusion;
- `alg=none`;
- issuer spoofing;
- JWKS poisoning;
- key compromise;
- token replay;
- malicious redirect URIs;
- account enumeration;
- email takeover;
- identity linking attacks;
- tenant confusion;
- organisation confusion;
- cross-tenant access;
- privilege escalation;
- service-account compromise;
- compromised workload tokens;
- admin-console compromise;
- forgotten accounts;
- stale memberships;
- insider misuse;
- backup leakage;
- log leakage.

Document mitigations and residual risk.

---

# 31. Do not add an external fine-grained authorization engine yet

Do not introduce:

```text
OpenFGA
SpiceDB
OPA
Cerbos
```

during the initial IAM rollout unless repository evidence demonstrates that existing authorization boundaries are insufficient.

Current intended model:

```text
Keycloak    → identity
baobab-cp   → platform context / entitlement
Trade       → commerce authorization
ERP         → ERP authorization
CMS         → CMS authorization
```

If cross-resource relationship authorization later becomes too complex, write a new ADR before introducing another policy engine.

---

# 32. IMPLEMENTATION GATES

Execute the following gates in sequence.

---

## GATE IAM-0 — Discovery, architecture and threat model

Inspect all affected repositories.

Produce:

```text
docs/adr/0001-baobab-iam-platform.md
docs/architecture/identity-plane.md
docs/security/threat-model.md
docs/security/trust-boundaries.md
docs/architecture/authority-matrix.md
```

Confirm:

- existing CP OIDC validation;
- existing Shared claim contracts;
- Trade auth assumptions;
- iDempiere SSO capabilities;
- Digital Estate auth gaps;
- infrastructure constraints.

Do not implement customer login yet.

### Exit criteria

- identity authority boundaries documented;
- threat model reviewed;
- architecture consistent with CP;
- no competing identity sources;
- PR checks green.

Open PR:

```text
IAM-0: establish Baobab identity architecture and threat model
```

Merge when passing.

Proceed.

---

## GATE IAM-1 — Shared canonical identity contracts

Modify `nabhold/shared`.

Implement versioned:

- identity claims;
- actor types;
- principal schema;
- session schema;
- membership schema;
- workload schema;
- external identity schema;
- identity lifecycle;
- authorization context;
- scopes;
- identity events.

Generate types/packages where the Shared repository already uses generation.

Add compatibility tests.

Update documentation.

### Exit criteria

- no consumer-local conflicting identity contract;
- schema validation passes;
- generated artifacts reproducible;
- versioning documented;
- breaking-change policy documented.

Open dedicated Shared PR.

Merge.

Proceed.

---

## GATE IAM-2 — Scaffold `baobab-iam`

Create or harden repository.

Add:

- Keycloak pinned upstream;
- Dockerfile;
- Compose development stack;
- PostgreSQL;
- health/readiness;
- realm bootstrap;
- client bootstrap;
- configuration validation;
- Codespaces integration;
- `.nabhold/environment.yaml`;
- Foundation gates;
- security scanning;
- dependency scanning;
- image scanning;
- SBOM where established;
- secret scanning;
- README;
- SECURITY;
- operations documentation.

Do not use development mode in production configuration.

### Exit criteria

Local environment boots deterministically.

Realm provisioning is idempotent.

No default production passwords exist.

All Foundation checks pass.

Open PR.

Merge.

Proceed.

---

## GATE IAM-3 — Control Plane identity integration

Modify `baobab-cp` as necessary without making it an IdP.

Implement canonical mapping:

```text
OIDC subject
    │
    ▼
Canonical Identity
    │
    ▼
Membership
    │
    ▼
Tenant / Entity / Product Context
```

Preserve existing OIDC verification constraints.

Add:

- subject registry;
- identity external reference;
- identity status;
- membership resolution;
- audit provenance;
- migration(s);
- unit tests;
- integration tests;
- contract tests.

Do not trust email as identity key.

Do not trust client-provided tenant IDs without canonical resolution.

### Exit criteria

A valid IAM token can resolve canonical context through CP.

Invalid issuer/audience/actor/scope fails closed.

Cross-tenant context attacks fail.

Open PR.

Merge.

Proceed.

---

## GATE IAM-4 — Workload identity

Provision clients for:

```text
baobab-trade
baobab-erp
baobab-cms
baobab-pulse
zuribeans backend
thamani backend
```

Use client-credentials/workload identity.

Integrate with existing CP workload-token validation.

Implement secret rotation documentation.

Ensure services cannot request arbitrary scopes.

Add integration tests.

### Exit criteria

Each service has a unique identity.

Trade cannot impersonate ERP.

Digital Estate cannot impersonate CP administrator.

Invalid scopes fail.

Expired tokens fail.

Open all required per-repository PRs.

Use one logical Gate with clearly related PRs, but do not mix unrelated future work into them.

Merge when passing.

Proceed.

---

## GATE IAM-5 — Workforce SSO

Integrate:

```text
baobab-cp administrative access
baobab-erp / iDempiere
baobab-trade administrative access where appropriate
baobab-cms administrative access
```

Require MFA for privileged users.

Document:

- account provisioning;
- role assignment;
- role removal;
- employee offboarding;
- break-glass access;
- recovery.

Ensure domain roles remain engine-owned.

### Exit criteria

One workforce identity can authenticate across approved applications.

Domain permissions remain separate.

Removing a platform membership removes access appropriately.

Open PRs.

Merge.

Proceed.

---

## GATE IAM-6 — Zuribeans B2B authentication

Implement production-grade buyer authentication.

Support:

```text
registration
invitation
verification
login
logout
organisation association
membership approval
role assignment
account recovery
session expiry
organisation switching where permitted
```

Connect IAM identity to existing Trade buyer organisation/membership model.

Do not put purchase limits or commercial authority in Keycloak.

Use authorization-code + PKCE for public browser clients.

Test:

- wrong-organisation access;
- revoked buyer membership;
- duplicate user;
- email change;
- expired invitation;
- session expiry;
- cross-tenant request;
- inactive tenant;
- Trade entitlement removal.

### Exit criteria

Buyer login works end to end.

Cross-tenant access is impossible under tests.

Trade remains business authority.

Open PRs.

Merge.

Proceed.

---

## GATE IAM-7 — Thamani B2C authentication

Implement:

```text
consumer registration
email verification
login
logout
recovery
customer mapping
session management
profile association
identity deactivation
```

Prepare for future federated login.

Do not require business-grade B2B complexity unnecessarily.

Keep credential data out of Medusa as master identity source.

### Exit criteria

B2C customer authentication works end-to-end.

Customer identity maps safely to Trade.

Duplicate identities are handled predictably.

No secrets are exposed to frontend bundles.

Open PRs.

Merge.

Proceed.

---

## GATE IAM-8 — Supplier identity and onboarding access

Integrate IAM with supplier onboarding workflows.

Support supplier:

- representative identity;
- invitations;
- organisation relationship;
- access approval;
- access suspension;
- revocation;
- multi-representative organisation;
- representative replacement;
- privileged supplier administrators.

Do not equate IAM account activation with supplier business approval.

### Exit criteria

Rejected supplier cannot access protected supplier capability even with valid identity.

Approved representative can access only appropriate organisation context.

Open PRs.

Merge.

Proceed.

---

## GATE IAM-9 — Hardening and production readiness

Perform comprehensive security hardening.

Implement/test:

- MFA;
- passkey/WebAuthn readiness;
- rate limiting;
- brute-force defence;
- session security;
- refresh-token controls;
- logout propagation;
- key rotation;
- client secret rotation;
- backup;
- restore;
- disaster recovery;
- admin recovery;
- audit;
- observability;
- alerting;
- load test;
- failover behaviour;
- chaos/failure scenarios appropriate to IAM;
- dependency security;
- container security;
- image signing/provenance if organisation standard exists.

Conduct a fresh threat-model review against the implementation.

### Exit criteria

Production readiness checklist is entirely satisfied or each exception has an explicit documented owner-approved risk acceptance.

Open final hardening PR.

Merge.

---

# 33. Integration sequence

The overall implementation flow shall be:

```text
IAM-0
Architecture
    │
    ▼
IAM-1
Shared Contracts
    │
    ▼
IAM-2
Keycloak / baobab-iam
    │
    ▼
IAM-3
Control Plane Identity Registry
    │
    ▼
IAM-4
Workload Identity
    │
    ▼
IAM-5
Workforce SSO
    │
    ├──────────────┐
    ▼              ▼
IAM-6            IAM-7
Zuribeans B2B    Thamani B2C
    │              │
    └───────┬──────┘
            ▼
          IAM-8
      Supplier Access
            │
            ▼
          IAM-9
    Production Hardening
```

Do not reorder IAM-6/7 before the identity foundation is stable.

---

# 34. Required tests

At minimum implement appropriate automated tests covering:

### Token verification

- correct issuer;
- wrong issuer;
- correct audience;
- wrong audience;
- expired token;
- future `nbf`;
- unsupported algorithm;
- bad signature;
- stale key;
- wrong actor type;
- missing scope.

### Tenancy

- correct tenant;
- inactive tenant;
- wrong tenant;
- user without membership;
- cross-tenant access;
- valid user with wrong entity;
- entitlement revoked.

### Identity mapping

- first login;
- repeat login;
- duplicate email;
- changed email;
- linked external identity;
- disabled identity;
- reactivated identity.

### Workloads

- correct service;
- wrong client;
- missing scope;
- expired client token;
- revoked service credential;
- service attempting human endpoint.

### B2B

- organisation member;
- non-member;
- suspended member;
- wrong organisation;
- expired invitation;
- purchase authority delegated;
- purchase authority denied.

### B2C

- registration;
- verification;
- recovery;
- customer mapping;
- logout;
- account disabled.

### Supplier

- applicant;
- approved;
- rejected;
- suspended;
- wrong supplier organisation.

---

# 35. Security testing

Add appropriate:

```text
SAST
dependency scanning
container scanning
secret scanning
configuration scanning
OIDC negative tests
authorization negative tests
cross-tenant tests
fuzz/property tests where valuable
```

Never report a security test as passing merely because the happy path succeeds.

IAM testing should strongly emphasise **negative authorization tests**.

---

# 36. CI/CD requirements

Use existing Nabhold Shared reusable workflows wherever applicable.

GitHub Actions must follow organisation policy, including immutable SHA pinning where required.

CI should fail on:

- tests;
- lint;
- typecheck/build;
- schema incompatibility;
- insecure configuration;
- detected secrets;
- critical vulnerabilities according to organisational policy;
- container scanning failures;
- reproducibility violations;
- contract compatibility failures.

No PR may be merged merely because a reviewer believes a failing security gate is inconvenient.

---

# 37. Production-readiness checklist

The final IAM programme is not complete until all applicable items are verified.

## Architecture

- [ ] Dedicated IAM authority exists.
- [ ] CP is not an IdP.
- [ ] Engines are not identity masters.
- [ ] Tenant ≠ LegalEntity ≠ Organisation.
- [ ] Canonical identity mapping exists.
- [ ] Domain authorization remains domain-owned.

## Protocols

- [ ] OIDC implemented.
- [ ] OAuth workload identity implemented.
- [ ] Authorization Code + PKCE implemented for public clients.
- [ ] JWKS verification implemented.
- [ ] Issuer validation enforced.
- [ ] Audience validation enforced.

## Human security

- [ ] MFA available.
- [ ] MFA mandatory for privileged workforce.
- [ ] Account recovery tested.
- [ ] Lockout/brute-force controls tested.
- [ ] Session expiry tested.
- [ ] Logout tested.

## Workloads

- [ ] Unique service identities.
- [ ] Least-privilege scopes.
- [ ] Rotation procedure.
- [ ] Short-lived tokens.
- [ ] mTLS integration where required.
- [ ] Static shared production API keys eliminated where practical.

## Tenancy

- [ ] Cross-tenant tests.
- [ ] Membership revocation tests.
- [ ] Tenant deactivation tests.
- [ ] Product entitlement tests.
- [ ] Entity-context tests.

## ERP

- [ ] iDempiere OIDC SSO.
- [ ] Canonical identity mapping.
- [ ] ERP domain roles preserved.
- [ ] No password replication.

## Trade

- [ ] Medusa IAM adapter.
- [ ] Canonical customer mapping.
- [ ] B2B organisation membership preserved.
- [ ] Trade domain authorization preserved.

## Zuribeans

- [ ] Buyer login.
- [ ] Buyer invitation.
- [ ] Organisation membership.
- [ ] Access revocation.
- [ ] B2B context switching tested where enabled.

## Thamani

- [ ] Consumer registration.
- [ ] Consumer login.
- [ ] Account recovery.
- [ ] Customer mapping.
- [ ] Session controls.

## Suppliers

- [ ] Supplier representatives supported.
- [ ] Business approval separate from authentication.
- [ ] Revocation supported.
- [ ] Organisation isolation verified.

## Privacy

- [ ] Identity data inventory.
- [ ] Data minimisation.
- [ ] Retention documented.
- [ ] PII redaction.
- [ ] No credentials in logs.
- [ ] POPIA considerations documented.

## Operations

- [ ] Health endpoint.
- [ ] Readiness endpoint.
- [ ] Metrics.
- [ ] Traces.
- [ ] Audit.
- [ ] Alerts.
- [ ] Backup.
- [ ] Restore tested.
- [ ] Key recovery documented.
- [ ] DR runbook.
- [ ] Admin recovery runbook.
- [ ] Secret rotation runbook.

## Supply chain

- [ ] Upstream Keycloak pinned.
- [ ] Dependencies locked.
- [ ] Containers scanned.
- [ ] CI actions pinned.
- [ ] SBOM generated where required.
- [ ] Foundation gate passing.

---

# 38. Documentation deliverables

The finished programme must leave behind documentation sufficient for another competent engineer to operate IAM without reverse-engineering the codebase.

At minimum:

```text
README.md

docs/
├── architecture/
│   ├── overview.md
│   ├── identity-plane.md
│   ├── authority-model.md
│   ├── tenancy.md
│   ├── workload-identity.md
│   ├── digital-estate-auth.md
│   ├── zuribeans-b2b.md
│   ├── thamani-b2c.md
│   ├── suppliers.md
│   └── idempiere-sso.md
│
├── security/
│   ├── threat-model.md
│   ├── trust-boundaries.md
│   ├── token-policy.md
│   ├── mfa-policy.md
│   └── admin-security.md
│
├── operations/
│   ├── deployment.md
│   ├── backups.md
│   ├── restore.md
│   ├── key-rotation.md
│   ├── client-rotation.md
│   └── disaster-recovery.md
│
└── runbooks/
    ├── compromised-account.md
    ├── compromised-client.md
    ├── compromised-signing-key.md
    ├── locked-admin.md
    ├── user-offboarding.md
    └── iam-outage.md
```

Keep diagrams current.

---

# 39. Final target architecture

The resulting Baobab platform should resemble:

```text
                            NABHOLD
                               │
                        BAOBAB PLATFORM
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
          ▼                    ▼                    ▼
      BAOBAB IAM          BAOBAB CP              SHARED
       Keycloak              Go                Contracts
          │                    │
          │ Identity           │ Context
          │ Authentication     │ Tenancy
          │ Credentials        │ Entitlement
          │ Sessions           │ Canonical IDs
          │ MFA                │ Policy
          │ Federation         │ Audit
          │                    │
          └────────────┬───────┘
                       │
          ┌────────────┼─────────────┐
          │            │             │
          ▼            ▼             ▼
        TRADE          ERP           CMS
        Medusa       iDempiere      Payload
          │            │             │
          └────────────┼─────────────┘
                       │
                     PULSE
                    Haystack
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
    Zuribeans        Thamani        Nabhold
       B2B             B2C         Corporate
```

The governing rule remains:

```text
Authentication
     ↓
Baobab IAM

Platform identity/context
     ↓
Baobab Control Plane

Business authorization
     ↓
Authoritative domain engine
```

---

# 40. Definition of success

At programme completion, the following scenario must work coherently.

```text
Human / Workload
       │
       ▼
Baobab IAM
       │
       │ authenticated identity
       ▼
baobab-cp
       │
       │ canonical identity
       │ tenant
       │ legal entity
       │ market
       │ entitlement
       ▼
Domain Engine
       │
       │ domain authorization
       ▼
Business Operation
       │
       ▼
Canonical Audit/Event
```

A single authenticated human may have different valid relationships with multiple Baobab entities without receiving duplicate credential accounts.

Revoking one domain relationship must not necessarily destroy the person's global identity.

A compromised service identity must not compromise every Baobab service.

A browser application must never receive a backend client secret.

An inactive tenant must not become accessible merely because a cryptographically valid IAM token exists.

A valid login must never imply unrestricted authorization.

A valid Keycloak organisation membership must never automatically imply Baobab tenancy.

Engine-native users must remain mapped identities, not canonical identity authorities.

---

# 41. Working discipline

Be conservative with security and aggressive against unnecessary complexity.

Prefer:

```text
standards
explicit boundaries
short-lived credentials
least privilege
versioned contracts
canonical IDs
negative tests
auditability
boring reliable infrastructure
```

over:

```text
custom cryptography
shared passwords
unbounded JWT claims
implicit tenancy
email-as-primary-key
giant global role lists
cross-engine database access
duplicated identity stores
security-by-header
premature policy engines
```

Do not implement clever abstractions when established standards solve the problem.

Do not weaken security merely to get an integration test green.

Do not rewrite Keycloak.

Do not rewrite Medusa authentication unnecessarily.

Do not rewrite iDempiere authentication unnecessarily.

Integrate them through standards.

---

# 42. Reporting

After each Gate PR is successfully merged, keep a concise implementation ledger containing:

| Gate | Repositories | PR(s) | Checks | Merge | Verification |
|---|---|---|---|---|---|
| IAM-0 | ... | ... | PASS | yes | PASS |
| IAM-1 | ... | ... | PASS | yes | PASS |
| ... | ... | ... | ... | ... | ... |

Update this ledger as you work.

Do not pause merely to present it.

When the entire programme is complete, provide a final report covering:

1. every Gate;
2. every PR;
3. repositories modified;
4. architecture delivered;
5. IAM clients created;
6. canonical contracts added;
7. migrations added;
8. tests added;
9. security controls implemented;
10. workload identities created;
11. Zuribeans integration;
12. Thamani integration;
13. supplier integration;
14. ERP SSO integration;
15. operational runbooks;
16. unresolved risks;
17. explicit deferred work;
18. post-production recommendations.

Any deferred feature must state **why** it was deferred and what objective evidence should trigger its implementation.

---

# FINAL INSTRUCTION

Start with **Gate IAM-0**.

First inspect the actual current code and documentation across the relevant repositories rather than assuming the architecture described above is fully implemented.

Reconcile this mandate with the current repository state and existing accepted ADRs.

Where repository reality differs from this prompt, preserve valid newer architectural decisions unless doing so would violate the fundamental identity authority model.

Then implement the IAM programme **methodically, gate by gate, PR by PR, through production readiness**.

Do not pause between gates.

Only stop when owner intervention is genuinely required.

The final outcome must be a Baobab IAM platform that is secure enough to become the common authentication foundation for:

```text
Baobab Control Plane
Baobab Trade
Baobab ERP
Baobab CMS
Baobab Pulse
Zuribeans
Thamani
Nabhold
Equator & Estate
future Baobab Digital Estates
future external tenants
```

without making any one engine, storefront, or legal entity the master identity system for the whole platform.