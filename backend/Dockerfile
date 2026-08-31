ARG APP_VERSION=dev
ARG BUILD_DATE=unknown

FROM python:3.13.15-slim-bookworm AS runtime

ARG APP_VERSION
ARG BUILD_DATE

LABEL org.opencontainers.image.version=$APP_VERSION \
      org.opencontainers.image.created=$BUILD_DATE

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_CACHE_DIR=/tmp/uv-cache \
    APP_VERSION=$APP_VERSION \
    BUILD_DATE=$BUILD_DATE

WORKDIR /app
COPY --from=ghcr.io/astral-sh/uv:0.12.3 /uv /uvx /bin/
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY main.py alembic.ini ./
COPY development_seed.py ./
COPY migrations ./migrations
COPY scripts ./scripts

USER 65532:65532
EXPOSE 8000
CMD ["uv", "run", "--no-sync", "gunicorn", "--bind", "0.0.0.0:8000", "--workers", "1", "--threads", "4", "--timeout", "60", "main:app"]
