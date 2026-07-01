# Scenex — Deployment

Target: a self-hosted **Debian VM** inside a VLAN, running Docker. A separate **front VM
runs nginx**, terminates TLS, and reverse-proxies to the app VM over the VLAN. The app
VM is **not** directly reachable from the internet. Postgres already runs in a Docker
container on the app VM.

**Single always-on stateful node** — live session state lives in memory (one `GenServer`
per session), so we run exactly one app instance. No horizontal replicas.

> Deploy execution is pending one input: the **public hostname** the front nginx serves
> Scenex on (used for `PHX_HOST`, URL generation, and websocket `check_origin`).

## 1. Build artifact

A production **mix release** bundled into a Docker image via the generated `Dockerfile`
(`mix phx.gen.release --docker`). CI builds it and pushes to **GHCR**
(`ghcr.io/<owner>/scenex:<sha>`). Migrations run via the release command `bin/migrate`.

## 2. Runtime environment variables

Set on the app container (see `config/runtime.exs`):

| Var | Example | Notes |
|---|---|---|
| `PHX_SERVER` | `true` | Starts the web server in the release. |
| `PHX_HOST` | `scenex.example.org` | **Public** hostname. Drives HTTPS URLs + websocket origin check. |
| `PORT` | `4000` | Internal HTTP port on the VLAN (plain HTTP; TLS is at the edge). |
| `SECRET_KEY_BASE` | *(64+ bytes)* | `mix phx.gen.secret`. Keep out of git. |
| `DATABASE_URL` | `ecto://scenex:PASS@postgres/scenex_prod` | Points at the existing Postgres container. |
| `POOL_SIZE` | `10` | Optional. |

## 3. Database

Reuse the existing Postgres container — create a dedicated DB + user once:

```sql
CREATE USER scenex WITH PASSWORD '...';
CREATE DATABASE scenex_prod OWNER scenex;
```

The app container must share a Docker network with the Postgres container so
`DATABASE_URL`'s host (e.g. `postgres`) resolves.

## 4. docker-compose (on the app VM)

Template — adjust the image ref, the external network name, and the Postgres host to
match the existing setup:

```yaml
services:
  app:
    image: ghcr.io/<owner>/scenex:latest
    restart: unless-stopped
    environment:
      PHX_SERVER: "true"
      PHX_HOST: "scenex.example.org"
      PORT: "4000"
      SECRET_KEY_BASE: "${SECRET_KEY_BASE}"
      DATABASE_URL: "ecto://scenex:${DB_PASSWORD}@postgres/scenex_prod"
    ports:
      - "4000:4000"       # published on the VLAN interface for the edge nginx
    networks:
      - db                # the network the existing Postgres container is on
    # Run migrations on start, then boot the server:
    command: >
      sh -c "/app/bin/migrate && /app/bin/server"

networks:
  db:
    external: true        # name of the existing Postgres network
```

## 5. Edge nginx (front VM)

TLS terminates here; proxy to the app VM over the VLAN. **Websocket upgrade** and
**forwarded headers** are both required — without them LiveView silently degrades or
its socket connects-then-closes.

```nginx
server {
    listen 443 ssl http2;
    server_name scenex.example.org;

    # ssl_certificate / ssl_certificate_key ...

    location / {
        proxy_pass http://<app-vm-vlan-ip>:4000;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;      # websockets
        proxy_set_header Connection "upgrade";

        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;  # tells Phoenix it's HTTPS
        proxy_set_header X-Forwarded-Host  $host;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;

        proxy_read_timeout 3600s;                    # keep long-lived LV sockets open
    }
}
```

The app trusts these via `Plug.RewriteOn` in `endpoint.ex`, and `check_origin` matches
`PHX_HOST`.

## 6. CI/CD flow

`.github/workflows/ci.yml` runs compile-as-errors / format / unused-deps / tests on every
push & PR. A future `release.yml` (added when the hostname is set) builds the image, pushes
to GHCR, then SSHes to the VM to `docker compose pull && up -d`. Manual-approval deploy at
first.
