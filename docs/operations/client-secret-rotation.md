# Client Secret Rotation

Workload client secrets must be rotated periodically or after any suspected compromise.

## Prerequisites

- Access to Keycloak Admin Console or the `kcadm.sh` CLI.
- The new secret must be generated with high entropy (e.g., `openssl rand -base64 32`).
- An admin access token in `$ADMIN_TOKEN` (see `tests/integration/run.sh`'s `get_admin_token`
  for the exact call) and `$KC_URL` pointing at the Keycloak instance, if using the Admin API
  examples below rather than `kcadm.sh`.

## Rotation steps

1. **Generate a new secret**:
   ```bash
   NEW_SECRET=$(openssl rand -base64 32)
   ```
2. **Update Keycloak** — set the client's secret to the new value via the Admin API (replace
   `{uuid}` with the client's internal id from
   `GET /admin/realms/baobab/clients?clientId={clientId}`):
   ```bash
   curl -sf -X PUT -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
     "$KC_URL/admin/realms/baobab/clients/{uuid}/client-secret" \
     -d "{\"value\": \"$NEW_SECRET\"}"
   ```
   (`kcadm.sh update clients/{uuid} -s "secret=$NEW_SECRET" -r baobab` works equally well from
   the Keycloak Admin CLI.)
3. **Deploy the new secret to the workload** — via this platform's secret-management boundary
   (ADR-0002 §25), never by hand-editing a running service's config. Exactly how depends on
   which system consumes the client (e.g. `baobab-erp`'s `baobab.iam.workload.client.secret`
   system property, `nabhold/baobab-cp`'s own workload configuration) — see that system's own
   deployment docs for its specific mechanism.
4. **Verify the new secret works and the old one is rejected**:
   ```bash
   # New secret succeeds:
   curl -s -o /dev/null -w "%{http_code}\n" -X POST "$KC_URL/realms/baobab/protocol/openid-connect/token" \
     -d "client_id={clientId}" -d "client_secret=$NEW_SECRET" -d "grant_type=client_credentials"
   # Old secret is rejected (401):
   curl -s -o /dev/null -w "%{http_code}\n" -X POST "$KC_URL/realms/baobab/protocol/openid-connect/token" \
     -d "client_id={clientId}" -d "client_secret=$OLD_SECRET" -d "grant_type=client_credentials"
   ```
   Setting a new secret via step 2 immediately invalidates the old one — Keycloak holds only
   one secret value per client, with no overlap window where both work. For a **routine**
   rotation (not an incident), this means step 3 SHALL be ready to run immediately after step
   2, or the workload will start failing to authenticate the moment step 2 completes — plan
   for that brief gap (or a coordinated deploy) rather than being surprised by it. For the
   **incident** case (`security-incident-runbook.md` §3), this is moot: the client is already
   disabled before rotation starts, so there's no live traffic to disrupt.