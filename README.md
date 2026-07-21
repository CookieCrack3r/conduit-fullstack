# Conduit Container

A containerised fullstack deployment of the [RealWorld "Conduit"](https://github.com/gothinkster/realworld) demo application: an Angular 17 frontend, a Django 1.10 REST backend, and a PostgreSQL database, orchestrated with Docker Compose.

## Table of Contents

- [Description](#description)
  - [Repository layout](#repository-layout)
  - [Architecture](#architecture)
- [Quickstart](#quickstart)
  - [Prerequisites](#prerequisites)
  - [Run it](#run-it)
- [Usage](#usage)
  - [Configuration reference](#configuration-reference)
  - [Build-time vs. runtime configuration](#build-time-vs-runtime-configuration)
  - [Deploying to a remote VM](#deploying-to-a-remote-vm)
  - [Common operations](#common-operations)
  - [Logs](#logs)
  - [Data persistence](#data-persistence)
- [Implementation notes](#implementation-notes)
  - [Why these version pins](#why-these-version-pins)
  - [Known issues](#known-issues)
  - [Security notes](#security-notes)
- [Troubleshooting](#troubleshooting)

## Description

The purpose of this repository is to keep an **outdated application runnable** by containerising it. The upstream code targets Python 3.5-era Django and will not start on a modern interpreter; pinning the runtime inside an image solves that without rewriting the application.

Nothing in the application's business logic was modified. The changes here are limited to what containerisation and external configuration require.

### Repository layout

| Path | Contents |
| --- | --- |
| `conduit-backend/` | Django 1.10 REST API, its `Dockerfile` and `entrypoint.sh` |
| `conduit-frontend/` | Angular 17 client, its `Dockerfile` and `nginx.conf` |
| `docker-compose.yaml` | Service, network and volume definitions |
| `.env.example` | Template for the local `.env` (never commit the real one) |

### Architecture

```
browser
  ├── :8282  frontend   nginx serving the compiled Angular bundle
  └── :8000  backend    gunicorn + Django, static files via WhiteNoise
                            │
                            └── database   PostgreSQL 13 (internal network only)
```

The browser talks to **both** the frontend and the backend directly. The database is not published to the host; it is reachable only from inside the `conduit` Compose network.

## Quickstart

### Prerequisites

- Docker Engine 24+ with the Compose V2 plugin
- Ports `8282` and `8000` free on the host

### Run it

```bash
cp .env.example .env
# Edit .env: set PUBLIC_HOST, DJANGO_SECRET_KEY and the passwords.
docker compose up -d --build
```

Then open <http://localhost:8282>.

The admin panel lives at <http://localhost:8000/admin/>, using the `DJANGO_SUPERUSER_*` credentials from your `.env`.

## Usage

### Configuration reference

All configuration is supplied through `.env`. Compose provides defaults for everything except the three secrets, which have no sensible default and fail fast if missing.

| Variable | Default | Purpose |
| --- | --- | --- |
| `PUBLIC_HOST` | `localhost` | Host/IP the browser uses. Drives the API URL, `ALLOWED_HOSTS` and the CORS whitelist. |
| `FRONTEND_PORT` | `8282` | Host port for the Angular app |
| `BACKEND_PORT` | `8000` | Host port for the API |
| `DJANGO_SECRET_KEY` | *required* | Django cryptographic signing key |
| `DJANGO_DEBUG` | `False` | Never enable in a deployed environment |
| `GUNICORN_WORKERS` | `3` | WSGI worker processes |
| `POSTGRES_DB` | `conduit` | Database name |
| `POSTGRES_USER` | `conduit` | Database user |
| `POSTGRES_PASSWORD` | *required* | Database password |
| `DJANGO_SUPERUSER_USERNAME` | *(empty)* | Admin account, created on first start |
| `DJANGO_SUPERUSER_EMAIL` | *(empty)* | Admin login (the `USERNAME_FIELD` is the email) |
| `DJANGO_SUPERUSER_PASSWORD` | *(empty)* | Admin password |

Setting `PUBLIC_HOST` is normally the only change needed — every derived value follows from it.

### Build-time vs. runtime configuration

This distinction causes the most confusion, so it is worth stating plainly:

**Angular resolves its API URL at build time.** `scripts/set-env.js` writes `src/environments/environment.ts` from the `API_URL` variable before `ng build` runs, and the value is compiled into the JavaScript bundle. Consequences:

- `API_URL` is passed as a Docker **build argument**, not as a container environment variable. Setting it under `environment:` has no effect.
- Changing `PUBLIC_HOST` requires a **rebuild**: `docker compose up -d --build`. A plain restart keeps the old value.
- `API_URL` must never point at an internal service name such as `http://backend:8000`. That name is resolved by the *browser*, which has no access to the Compose network.

The backend, by contrast, reads everything at runtime, so a restart is enough for its variables.

### Deploying to a remote VM

Set the public address in `.env` on the VM and rebuild:

```bash
PUBLIC_HOST=<your-vm-address>
```

```bash
docker compose up -d --build
```

The frontend is then reachable on port `8282` of that address. Make sure the VM firewall or cloud security group allows inbound traffic on `8282` and `8000` — the browser needs both.

### Common operations

```bash
docker compose ps                       # service status
docker compose up -d --build            # rebuild and restart after changes
docker compose restart backend          # restart a single service
docker compose down                     # stop, keeping the database volume
docker compose down -v                  # stop and DELETE all database data

docker compose exec backend python manage.py createsuperuser
docker compose exec database psql -U conduit -d conduit
```

### Logs

```bash
docker compose logs -f                          # follow everything
docker compose logs -f backend                  # one service
docker logs conduit-backend > backend-logs.txt  # persist to a file
```

Gunicorn writes its access and error logs to stdout/stderr, so they appear in `docker logs` rather than inside the container's filesystem.

### Data persistence

PostgreSQL data lives in the named volume `postgres_data`, mounted at `/var/lib/postgresql/data`. It survives `docker compose down` and rebuilds. Only `docker compose down -v` removes it.

Back it up with:

```bash
docker compose exec database pg_dump -U conduit conduit > backup.sql
```

## Implementation notes

### Why these version pins

The upstream application is from 2017 and its dependency graph is fragile. These pins are deliberate:

| Pin | Reason |
| --- | --- |
| `python:3.6-slim` | Django 1.10 fails on Python 3.8+ (`__classcell__` propagation) and on 3.12+ (`django.utils.six` uses the removed `find_module` API) |
| `psycopg2-binary==2.8.6` | psycopg2 2.9 changed datetime handling in a way that breaks Django < 3.1 |
| `whitenoise==3.3.1` | WhiteNoise 4.0 dropped support for Django 1.10 |
| `postgres:13-alpine` | New enough to be maintained, old enough for Django 1.10's PostgreSQL backend |
| `node:20-alpine` | Matches the `engines` field in `package.json` |

`psycopg2-binary` is used rather than `psycopg2` so that no compiler or `libpq-dev` is needed — which also avoids running `apt-get` against Debian repositories that have since been archived.

### Known issues

The upstream application has known functional bugs that are out of scope here and were left untouched. A freshly created database is empty, so article lists and tags render blank until content is created through the UI.

### Security notes

- The real `.env` is git-ignored. Only `.env.example`, with placeholder values, is tracked.
- No IP addresses or credentials are committed; the deployment address is supplied via `PUBLIC_HOST` at runtime.
- The backend image runs as the unprivileged user `appuser` (UID 10001).
- The database publishes no host port.
- `DJANGO_DEBUG` defaults to `False` in both the image and Compose.
- **Upstream weakness, deliberately not fixed:** `UserManager.create_superuser` in `conduit/apps/authentication/models.py` falls back to the hard-coded password `securepass` when `DJANGO_SUPERUSER_PASSWORD` is unset or shorter than four characters. Always set a strong `DJANGO_SUPERUSER_PASSWORD`.

## Troubleshooting

**The frontend loads but no data appears, and the browser console shows a CORS error.**
The API URL baked into the bundle does not match where the backend actually runs. Check `PUBLIC_HOST` in `.env` and rebuild with `--build` — a restart alone will not change it.

**`DisallowedHost` in the backend logs.**
`PUBLIC_HOST` is not part of `DJANGO_ALLOWED_HOSTS`. It is derived automatically, so this usually means `.env` was edited without restarting the backend.

**The admin panel renders without styling.**
Static files are collected during the image build. Rebuild the backend image: `docker compose build backend`.

**The backend exits with "timed out waiting for postgres".**
The database did not become healthy within 60 seconds. Check `docker compose logs database`; raise `DB_WAIT_TIMEOUT` if the host is slow.
