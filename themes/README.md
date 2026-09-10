# Themes

Custom Keycloak themes for Baobab (per ADR-0002 Section 28) live here, one
subdirectory per theme (e.g. `baobab/`, `thamani/`, `zuribeans/`).

This directory currently exists only so `Dockerfile`'s `COPY themes/
/opt/keycloak/themes/` has a source to copy — no custom theme has been
built yet. Themes remain presentation customizations; they SHALL NOT
contain authorization decisions (ADR-0002 Section 28).
