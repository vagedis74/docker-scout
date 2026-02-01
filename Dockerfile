FROM nginx:1.27-alpine

LABEL org.opencontainers.image.source="https://github.com/OWNER/docker-scout"
LABEL org.opencontainers.image.description="Docker Scout demo — nginx serving a static page"

# Remove default nginx content
RUN rm -rf /usr/share/nginx/html/*

# Copy custom nginx config
COPY app/nginx.conf /etc/nginx/conf.d/default.conf

# Copy static content
COPY app/index.html /usr/share/nginx/html/index.html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/ || exit 1

USER nginx
