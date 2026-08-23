# syntax=docker/dockerfile:1.19
#
# The web launcher: a Nuxt build with no server behind it, served by nginx.
#
#     docker build -f apps/web/Dockerfile -t super-movies/web .
#
# Built from the repository root like every other image here, so that one
# `.dockerignore` governs them all.
#
# `nuxt generate` with `ssr: false` emits a static bundle — there is no Node in
# this image, and nothing to keep running. See `nuxt.config.ts` for why the app
# is built that way.

ARG NODE_VERSION=24
ARG NGINX_VERSION=1.29

# ── build ────────────────────────────────────────────────────────────────────
FROM node:${NODE_VERSION}-alpine AS build

WORKDIR /app

# The lockfile is optional on purpose: `npm ci` is the right command and refuses
# to run without one, and an app whose lockfile has not been committed yet
# should still produce an image rather than a build failure nobody can act on.
COPY apps/web/package.json apps/web/package-lock.json* ./
RUN --mount=type=cache,target=/root/.npm \
    if [ -f package-lock.json ]; then npm ci; else npm install; fi

COPY apps/web/ ./

# Where the television app's own web build is served. A build argument because
# a static bundle has no server to read an environment variable at run time —
# and it is the one address the downloads page cannot work out for itself.
ARG NUXT_PUBLIC_TV_URL
ENV NUXT_PUBLIC_TV_URL=${NUXT_PUBLIC_TV_URL}

RUN npx nuxi typecheck && npm run build

# ── runtime ──────────────────────────────────────────────────────────────────
#
# The unprivileged variant, not `nginx:alpine`. The stock image's entrypoint
# renders the templates into /etc/nginx/conf.d and writes a pid file, both of
# which need root — so `USER nginx` on top of it produces a container that dies
# on start. This one is built to run as uid 101 and already listens on 8080.
FROM nginxinc/nginx-unprivileged:${NGINX_VERSION}-alpine AS runtime

# Where the API is. A service name in compose, a Service in Kubernetes, a
# host:port anywhere else.
ENV API_UPSTREAM=api:8000

USER root
COPY apps/web/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY deploy/nginx/proxy-api.conf deploy/nginx/app-headers.conf /etc/nginx/
COPY --from=build /app/.output/public /usr/share/nginx/html
USER 101

# Above 1024, so binding it needs no privilege the image does not have.
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --spider -q http://127.0.0.1:8080/health || exit 1
