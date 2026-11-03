# Self-contained static site: the validated site/ is baked in, nothing is fetched at runtime.
FROM nginxinc/nginx-unprivileged:1.27-alpine

ARG REVISION=unknown
ARG CREATED=unknown
ARG DATA_UPDATED=unknown
ARG VERSION=dev

LABEL org.opencontainers.image.title="Azure Local Lifecycle" \
      org.opencontainers.image.description="Azure Local releases and end of support dates, served as a static site with JSON, RSS, JSON Feed and ICS data. Rebuilt after the daily data refresh." \
      org.opencontainers.image.source="https://github.com/erikgraa/azure-local-releases" \
      org.opencontainers.image.url="https://lifecycle.azl.graa.dev" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}" \
      org.opencontainers.image.version="${VERSION}" \
      dev.graa.azl.data-updated="${DATA_UPDATED}"

COPY container/nginx.conf /etc/nginx/conf.d/default.conf
COPY container/404.html site/ /usr/share/nginx/html/

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
