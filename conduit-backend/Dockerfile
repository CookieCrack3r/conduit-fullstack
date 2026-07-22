# syntax=docker/dockerfile:1

# =============================================================================
# Stage 1 - build the dependency tree in an isolated virtualenv.
# Nothing from pip's cache or build metadata reaches the final image.
# =============================================================================
FROM python:3.6-slim AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY requirements.txt ./

# 21.3.1 is the last pip release supporting Python 3.6.
# psycopg2-binary ships prebuilt wheels, so no compiler or libpq-dev is needed
# here - which also avoids apt against Debian repositories that are archived.
#
# Caching is disabled via the CLI flag rather than PIP_NO_CACHE_DIR: the pip
# bundled with Python 3.6 reads that variable as a path and crashes on "1".
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade "pip==21.3.1" \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

# =============================================================================
# Stage 2 - runtime image.
# =============================================================================
FROM python:3.6-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:${PATH}" \
    DJANGO_DEBUG=False \
    DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1 \
    POSTGRES_HOST=database \
    POSTGRES_PORT=5432 \
    GUNICORN_BIND=0.0.0.0:8000 \
    GUNICORN_WORKERS=3

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app
COPY . .

# Collect static files at build time so the running container never depends on
# a writable static directory. Required for the admin CSS to load under
# DEBUG=False. Uses the build-time defaults above; no database contact needed.
RUN python manage.py collectstatic --noinput

# The executable bit does not survive a Windows checkout reliably, so set it
# explicitly rather than relying on the copied file mode.
RUN chmod +x /app/entrypoint.sh

# Run as an unprivileged user.
RUN useradd --create-home --uid 10001 appuser \
    && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

ENTRYPOINT ["/app/entrypoint.sh"]
