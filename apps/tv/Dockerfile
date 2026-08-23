# syntax=docker/dockerfile:1.19
#
# The television app, as a web build served by nginx.
#
#     cd apps/tv && flutter build web --release && cd ../..
#     docker build -f apps/tv/Dockerfile -t super-movies/tv .
#
# **This image packages a bundle you built; it does not build one.** That is not
# the usual shape and it is deliberate: every published Flutter image still
# carries Dart 3.12 (`ghcr.io/cirruslabs/flutter:stable`, `:beta` and every
# version tag, checked), while this workspace requires ^3.13.0 — so a
# self-contained build stage cannot resolve dependencies at all today. The
# alternative, downloading a pinned SDK tarball inside the image, trades a
# 30-second build for a 1 GB one on every layer miss.
#
# The release workflow builds the bundle with `subosito/flutter-action` pinned
# to the same version this repo develops on, which is the version-exactness the
# base image cannot currently give. Revisit when a matching tag ships.
#
# This is not how the app reaches a living room — that is the APK the release
# workflow attaches. It is how you put the same code in front of somebody
# without handing them an Android box.

ARG NGINX_VERSION=1.29

FROM nginxinc/nginx-unprivileged:${NGINX_VERSION}-alpine AS runtime

ENV API_UPSTREAM=api:8000

USER root
COPY apps/tv/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY deploy/nginx/proxy-api.conf deploy/nginx/app-headers.conf /etc/nginx/
# Fails loudly when the bundle is missing, which is the whole contract above.
COPY apps/tv/build/web /usr/share/nginx/html
USER 101

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --spider -q http://127.0.0.1:8080/health || exit 1
