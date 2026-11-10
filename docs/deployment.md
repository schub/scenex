# Scenex — Deployment

Scenex runs on a self-hosted **Debian VM** inside a VLAN, under Docker. A
separate **front VM runs nginx**, terminates TLS, and reverse-proxies to the
app VM over the VLAN. The app VM is not directly reachable from the internet.
Postgres already runs as a container on the app VM and is reused.

**Exactly one app instance.** Live session state lives in memory — one process
per running session — so there are no horizontal replicas. Scaling out would
mean distributing those processes, which is a deferred success-problem.

> Examples below use `scenex.org` as the public hostname. The authoritative
> value is whatever the edge nginx serves and `PHX_HOST` is set to in the VM's
> `.env`.

## 1. How deploys actually work

The image is **built on the VM**, not in CI and not pulled from a registry.
`deploy.sh` runs from your laptop and drives the whole thing:

1. `scp`s `server/update.sh` and `server/compose.yml` to the VM's `/tmp`.
2. `ssh -t`s in and, as root, copies them into `/opt/containers/scenex/` and
   runs `update.sh` (you are prompted for the root password).

`update.sh` then, on the VM:

1. Clones or updates `/opt/containers/scenex/src` from
   `https://github.com/schub/scenex.git` and checks out the requested branch
   or tag. The VM clones over **HTTPS** (public repo, no credentials);
   local development pushes over SSH. This is deliberately decoupled.
2. `docker build -t scenex:latest .`
3. Runs migrations in a one-shot container: `/app/bin/migrate`.
4. Ensures `/opt/containers/scenex/media` exists and is owned by `65534:65534`
   — the container runs as `nobody`, and uploads fail silently-ish if this is
   wrong.
5. `docker compose up -d --remove-orphans`.

```bash
./deploy.sh              # deploys main
./deploy.sh v1.5.1       # deploys a tag
```

Tags check out detached, which is fine — `update.sh` only pulls for branches.

Deploying is **manual and separate from releasing**. Cutting a release does
not deploy anything; see [`releasing.md`](releasing.md).

## 2. Layout on the VM

```
/opt/containers/scenex/
  src/           git clone, rebuilt from on each deploy
  compose.yml    copied from server/compose.yml by deploy.sh
  update.sh      copied from server/update.sh by deploy.sh
  .env           secrets and configuration — NOT in git, never overwritten
  media/         uploaded media, bind-mounted to /data/media (owned 65534)
```

`compose.yml` and `update.sh` are overwritten on every deploy, so edit them in
the repo under `server/`, never on the VM. `.env` is the opposite — it lives
only on the VM.

The container joins the external Docker network `postgres_default` so the
existing Postgres container resolves by hostname.

## 3. Environment

Everything below is read at runtime from the VM's `.env`
(see `config/runtime.exs`).

| Variable | Required | Default | Notes |
|---|---|---|---|
| `PHX_SERVER` | yes | — | Set to `true`, or the release boots without a web server |
| `PHX_HOST` | yes | `example.com` | **Public** hostname. Drives HTTPS URL generation and the websocket origin check |
| `PORT` | no | `4000` | Internal HTTP port on the VLAN; TLS is at the edge |
| `SECRET_KEY_BASE` | yes | — | 64+ bytes, from `mix phx.gen.secret`. Boot fails without it |
| `DATABASE_URL` | yes | — | `ecto://scenex:PASS@postgres/scenex_prod`. Boot fails without it |
| `POOL_SIZE` | no | `10` | |
| `ECTO_IPV6` | no | off | Set `true` or `1` to connect to Postgres over IPv6 |
| `MEDIA_DIR` | no | `/data/media` | Where uploads are written inside the container |
| `MEDIA_MAX_UPLOAD_MB` | no | `250` | Per-file upload ceiling |
| `SMTP_RELAY` | no | `brorsen.uberspace.de` | Outbound mail relay |
| `SMTP_USERNAME` | yes | — | Magic-link login breaks without working mail |
| `SMTP_PASSWORD` | yes | — | |
| `SMTP_PORT` | no | `587` | |
| `DNS_CLUSTER_QUERY` | no | — | Unused with a single node |
| `METRICS_PORT` | no | `9568` | Prometheus metrics listener (§8). Never proxy it |
| `GRAFANA_URL` | no | — | With `GRAFANA_TOKEN`: upload dashboards on start, annotate deploys |
| `GRAFANA_TOKEN` | no | — | Grafana service account token, role Editor |
| `GRAFANA_DATASOURCE_ID` | no | `prometheus` | UID of the Prometheus datasource in Grafana |

Mail goes out through an authenticated SMTP relay (Uberspace) which signs DKIM
for the domain itself, so the app only authenticates and sends. TLS is
mandatory (`tls: :always`, `auth: :always`); the certificate-check options are
built at application start rather than in `runtime.exs`, because the library
that builds them isn't loaded yet during the release's config-provider boot
phase — see `Scenex.Application.configure_mailer_tls/0`.

## 4. First-time setup

**Database.** In the existing Postgres container, once:

```sql
CREATE USER scenex WITH PASSWORD '...';
CREATE DATABASE scenex_prod OWNER scenex;
```

**`.env`.** Create `/opt/containers/scenex/.env` with the variables above.

**First deploy.** `./deploy.sh` from your laptop. The clone, build and
migration all happen on the first run.

**Bootstrap an owner account.** There is no registration path that works
before mail is configured, so seed the first account directly — it prints a
one-time magic-link URL valid for 15 minutes:

```bash
docker exec scenex /app/bin/scenex eval 'Scenex.Release.bootstrap_owner("you@example.com")'
```

**Optionally, the demo scenario:**

```bash
docker exec scenex /app/bin/scenex eval 'Scenex.Release.demo_scenario("you@example.com")'
```

That task starts only the Repo, not the endpoint, so it won't fight the
running container for port 4000.

## 5. Edge nginx (front VM)

TLS terminates here and proxies to the app VM over the VLAN. **Websocket
upgrade** and **forwarded headers** are both required — without them LiveView
silently degrades, or its socket connects and then immediately closes.

```nginx
server {
    listen 443 ssl http2;
    server_name scenex.org;

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

The app trusts these via `Plug.RewriteOn` in `endpoint.ex`, and `check_origin`
matches `PHX_HOST`.

If media uploads near `MEDIA_MAX_UPLOAD_MB` are expected, raise
`client_max_body_size` here too — nginx's 1 MB default will reject them before
Phoenix ever sees them.

## 6. CI

`.github/workflows/ci.yml` runs on every push to `main` and `dev` and on every
PR: format check, unused-deps check, compile with warnings as errors, and the
test suite against a Postgres 16 service (Elixir 1.19.5 / OTP 28).

**CI does not build or publish an image, and does not deploy.** Deployment is
the manual path in §1.

## 7. Operations

```bash
docker logs -f scenex                     # logs
docker compose -f /opt/containers/scenex/compose.yml restart
docker exec -it scenex /app/bin/scenex remote   # attach an IEx shell
```

Restarting is safe for live sessions in the sense that no history is lost —
each session rebuilds its board by replaying its event log on restart — but
connected screens will drop and reconnect, so don't do it mid-show.

Back up two things: the `scenex_prod` database, and
`/opt/containers/scenex/media`. Media files are not in the database and are
not recoverable from it.

## 8. Monitoring

Prometheus and Grafana already run as containers on the app VM; Scenex only
provides a scrape target and dashboards
([ADR 0026](adr/0026-metrics-prometheus-grafana.md)). What is measured is
documented in `Scenex.PromEx` and `Scenex.PromEx.ScenexPlugin`.

**Scrape target.** The app serves `GET /metrics` on port `9568`, a listener of
its own that the edge nginx never sees. `compose.yml` exposes it to other
containers but does not publish it on the VM. The Prometheus container needs a
Docker network in common with `scenex` — attach one of them to the other's
network, e.g. `docker network connect postgres_default prometheus`, or add the
network to Prometheus' own compose file so it survives a recreate. Then:

```yaml
scrape_configs:
  - job_name: scenex
    scrape_interval: 15s
    static_configs:
      - targets: ["scenex:9568"]
```

Check it from the Prometheus container: `wget -qO- http://scenex:9568/metrics`.

**Dashboards.** Either set `GRAFANA_URL` (as the Scenex container reaches it,
e.g. `http://grafana:3000`), `GRAFANA_TOKEN` and `GRAFANA_DATASOURCE_ID` in
`.env` — every start then uploads the dashboards to a *Scenex* folder and
marks deploys on them — or render them locally and import by hand:

```bash
GRAFANA_DATASOURCE_ID=<uid> mix scenex.dashboards    # writes tmp/grafana_dashboards/*.json
```

*Scenex - Platform* is the overview: live shows, commands, platform usage,
health. The PromEx dashboards go deeper into Phoenix, LiveView, Ecto and the
BEAM.

**Alert: platform down.** A Grafana alert rule on the Prometheus datasource,
sending to an email contact point (needs SMTP configured in Grafana, e.g. the
`GF_SMTP_*` environment variables):

- Query: `up{job="scenex"}`; condition: last value below 1.
- Pending period: 5 minutes. Set *no data* and *error* handling to
  *Alerting*, so a target that disappears from Prometheus also fires.

This watches the app container, not the public path: a broken edge nginx or
expired certificate does not trigger it.
