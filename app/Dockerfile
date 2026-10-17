# Unprivileged nginx: runs as non-root (UID 101) and listens on 8080
FROM nginxinc/nginx-unprivileged:1.27-alpine

# Bake the version and color into the image so each release is easy to recognise
ARG APP_VERSION=v1
ARG APP_COLOR=blue
ARG BUILD_TIME=unknown

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html

USER root
RUN case "$APP_COLOR" in \
      green) HEX="#3fb950" ;; \
      blue)  HEX="#4493f8" ;; \
      *)     HEX="#ff9900" ;; \
    esac && \
    sed -i -e "s/__APP_VERSION__/${APP_VERSION}/g" -e "s/__APP_COLOR__/${APP_COLOR}/g" \
           -e "s/__APP_COLOR_HEX__/${HEX}/g" -e "s/__BUILD_TIME__/${BUILD_TIME}/g" \
           /usr/share/nginx/html/index.html && \
    printf '{"version":"%s","color":"%s","built":"%s"}\n' "$APP_VERSION" "$APP_COLOR" "$BUILD_TIME" \
      > /usr/share/nginx/html/version.json
USER 101

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1
