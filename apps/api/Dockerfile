# syntax=docker/dockerfile:1.19
#
# The API. Build from the *repository root*, not from this directory:
#
#     docker build -f apps/api/Dockerfile -t super-movies/api .
#
# It has to be the root because this is a uv workspace — `api` is resolved
# against the lockfile at the top of the tree, and against two sibling packages
# in `packages/python/`.

ARG PYTHON_VERSION=3.13

# ── build ────────────────────────────────────────────────────────────────────
FROM ghcr.io/astral-sh/uv:python${PYTHON_VERSION}-bookworm-slim AS build

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    # The base image already has the interpreter; letting uv fetch another one
    # would put a second Python in the layer for nothing.
    UV_PYTHON_DOWNLOADS=never

WORKDIR /app

# Manifests before sources, so that editing a route does not re-resolve and
# re-download every dependency. `--no-install-workspace` is what makes the split
# work: it builds the third-party half of the environment and stops.
COPY pyproject.toml uv.lock ./
COPY apps/api/pyproject.toml apps/api/
COPY packages/python/kinostrain/pyproject.toml packages/python/kinostrain/
COPY packages/python/sweet-tv/pyproject.toml packages/python/sweet-tv/
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --all-packages --no-install-workspace

COPY packages/python/ packages/python/
COPY apps/api/ apps/api/

# `--all-packages`, not `--package api`: the API imports `kinostrain` and
# `sweet_tv` without declaring either in its own dependencies, so a narrower
# sync produces an environment that installs cleanly and fails on the first
# request to /catalogue. `--no-editable` puts real packages in site-packages
# rather than .pth files pointing at a source tree the runtime stage drops.
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --all-packages --no-editable

# ── runtime ──────────────────────────────────────────────────────────────────
FROM python:${PYTHON_VERSION}-slim-bookworm AS runtime

# Unbuffered so logs arrive while the container is running rather than when it
# stops; no .pyc on top of the ones already compiled into the venv.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/app/.venv/bin:$PATH" \
    # 127.0.0.1 is the right default for a laptop and useless in a container:
    # nothing outside the network namespace could ever reach it.
    API_HOST=0.0.0.0 \
    API_PORT=8000

# A system user with no shell and no home. Nothing here needs to write to disk.
RUN groupadd --system --gid 1001 api \
 && useradd --system --uid 1001 --gid api --no-create-home --shell /usr/sbin/nologin api

WORKDIR /app

COPY --from=build --chown=api:api /app/.venv /app/.venv
# Migrations travel with the image so that `alembic upgrade head` is something
# this container can do, rather than something that needs a checkout beside it.
COPY --from=build --chown=api:api /app/apps/api/alembic.ini /app/alembic.ini
COPY --from=build --chown=api:api /app/apps/api/migrations /app/migrations

USER api
EXPOSE 8000

# urllib rather than curl: adding a package to the runtime image so a health
# check can make one HTTP request is a poor trade.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2).status==200 else 1)"

# The console script, so `API_HOST`/`API_PORT` are read from settings the same
# way they are everywhere else. `api admin ...` still works: `docker run --rm -it
# <image> api admin you@example.com`.
CMD ["api"]
