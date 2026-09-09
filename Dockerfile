# Dockerfile – multi‑stage build for Keycloak with Baobab configuration
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