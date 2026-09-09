# Client Secret Rotation

Workload client secrets must be rotated periodically or after any suspected compromise.

## Prerequisites

- Access to Keycloak Admin Console or the `kcadm.sh` CLI.
- The new secret must be generated with high entropy (e.g., `openssl rand -base64 32`).

## Rotation steps

1. **Generate a new secret**:
   ```bash
   NEW_SECRET=$(openssl rand -base64 32)