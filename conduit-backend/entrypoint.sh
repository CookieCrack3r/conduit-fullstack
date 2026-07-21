#!/bin/sh
# Container entrypoint for the Conduit backend.
#
# Waits for PostgreSQL, applies migrations, optionally creates the admin user,
# and finally hands control to gunicorn (a WSGI server - never the dev server).
set -eu

POSTGRES_HOST="${POSTGRES_HOST:-database}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
GUNICORN_BIND="${GUNICORN_BIND:-0.0.0.0:8000}"
GUNICORN_WORKERS="${GUNICORN_WORKERS:-3}"
DB_WAIT_TIMEOUT="${DB_WAIT_TIMEOUT:-60}"

echo "[entrypoint] waiting for postgres at ${POSTGRES_HOST}:${POSTGRES_PORT} ..."
# The slim image has no netcat, so probe the socket with Python instead.
python - "${POSTGRES_HOST}" "${POSTGRES_PORT}" "${DB_WAIT_TIMEOUT}" <<'PY'
import socket
import sys
import time

host, port, timeout = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
deadline = time.time() + timeout
while time.time() < deadline:
    try:
        with socket.create_connection((host, port), timeout=2):
            print("[entrypoint] postgres is accepting connections")
            sys.exit(0)
    except OSError:
        time.sleep(1)
print("[entrypoint] timed out waiting for postgres", file=sys.stderr)
sys.exit(1)
PY

echo "[entrypoint] applying migrations ..."
python manage.py migrate --noinput

# Create the admin account only when credentials are supplied. `createsuperuser`
# exits non-zero if the account already exists, which is fine on restarts.
if [ -n "${DJANGO_SUPERUSER_EMAIL:-}" ] && [ -n "${DJANGO_SUPERUSER_USERNAME:-}" ]; then
    echo "[entrypoint] ensuring superuser ${DJANGO_SUPERUSER_USERNAME} exists ..."
    python manage.py createsuperuser --noinput \
        --email "${DJANGO_SUPERUSER_EMAIL}" \
        --username "${DJANGO_SUPERUSER_USERNAME}" || \
        echo "[entrypoint] superuser already present, skipping"
fi

echo "[entrypoint] starting gunicorn on ${GUNICORN_BIND} ..."
exec gunicorn conduit.wsgi:application \
    --bind "${GUNICORN_BIND}" \
    --workers "${GUNICORN_WORKERS}" \
    --access-logfile - \
    --error-logfile -
