# Dockerfile – multi‑stage build for Keycloak with Baobab configuration
#
# The upstream quay.io/keycloak/keycloak final-stage image is built on
# ubi9-micro, which intentionally has no package manager (no dnf/microdnf).
# bootstrap.sh (executed inside the running container) needs curl (to poll
# the health endpoint) and jq (to read clientId / merge a dev-only secret
# from the client JSON files). Per Red Hat's documented pattern for adding
# packages to a micro image, they are resolved in a throwaway ubi9 stage
# and their installed files copied into the final image — this avoids
# pulling a package manager, or its transitive attack surface, into the
# shipped image itself.
FROM registry.access.redhat.com/ubi9:9.4 AS tools-build
RUN mkdir -p /mnt/rootfs && \
    dnf install \
      --installroot /mnt/rootfs \
      --releasever 9 \
      --setopt install_weak_deps=false \
      --nodocs \
      -y \
      curl jq \
    && dnf clean all --installroot /mnt/rootfs

FROM quay.io/keycloak/keycloak:26.7.3 AS builder

# Copy custom theme and providers (if any)
COPY themes/ /opt/keycloak/themes/
COPY providers/ /opt/keycloak/providers/

# Copy realm configuration and bootstrap script
COPY config/ /opt/keycloak/config/
COPY scripts/bootstrap.sh /opt/keycloak/bootstrap.sh
RUN chmod +x /opt/keycloak/bootstrap.sh

# Build the Keycloak distribution (optimized)
RUN /opt/keycloak/bin/kc.sh build

# Final stage – minimal distroless image
FROM quay.io/keycloak/keycloak:26.7.3

# curl + jq for bootstrap.sh (see tools-build stage above)
COPY --from=tools-build /mnt/rootfs /

# Copy the built distribution from builder
COPY --from=builder /opt/keycloak/ /opt/keycloak/

# Non‑root user (already set by upstream)
USER 1000

# Health checks
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD /opt/keycloak/bin/kc.sh health || exit 1

EXPOSE 8080
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start", "--optimized", "--http-enabled=true", "--hostname=localhost"]
