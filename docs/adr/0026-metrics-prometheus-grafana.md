# 0026. Platform metrics: Prometheus format via PromEx, viewed in Grafana

- **Status:** Accepted
- **Date:** 2026-11-09

## Context

There is no production monitoring. `ScenexWeb.Telemetry` defines the stock
Phoenix, Ecto and VM metrics, but they only feed LiveDashboard, which is
mounted in dev only (`/dev/dashboard`). Nothing tells us how a live show is
doing — sessions running, players connected, latency — or how the platform is
used over time.

The goal is a Grafana dashboard of the platform's important metrics.

## Decision

Expose metrics in Prometheus format from the app with
[PromEx](https://hexdocs.pm/prom_ex), scraped by Prometheus, viewed in Grafana.

- Use PromEx's built-in plugins (BEAM, Application, Phoenix, Phoenix LiveView,
  Ecto) and their bundled Grafana dashboards for health.
- Add a Scenex plugin for domain metrics, erring on the side of more:
  - *live shows* (polled): running sessions, connected clients by role (GM,
    group, display);
  - *play activity* (`:telemetry.execute` in `Scenex.Play`): events appended
    by type, beats triggered, decisions confirmed, GM corrections, sessions
    started and finished;
  - *platform* (polled from the database): users, scenarios, sessions,
    pending invitations, media count and bytes.
- Serve `/metrics` on a separate port that the edge nginx does not proxy, so
  it is never public.
- Scrape it with the Prometheus container that already runs on the app VM,
  and add the dashboards to the Grafana container there. Both are existing
  infrastructure; Scenex only contributes the scrape target and dashboard
  JSON.
- Alert by email when the platform is down: a Grafana alert on the Scenex
  scrape target being down for 5 minutes.
- Instrumentation lives in the contexts, never in `Scenex.Engine`
  ([0002](0002-pure-engine.md)).

## Alternatives considered

- **InfluxDB** — push model, thin Elixir support, every dashboard built by
  hand.
- **OpenTelemetry** — built for many services and distributed tracing; more
  moving parts than one app on one VM needs.
- **Plain `TelemetryMetricsPrometheus`** — reuses the existing `metrics/0`
  list, but comes without ready-made dashboards.

## Consequences

- Health dashboards on day one; only the Scenex-specific panels are custom.
- A new dependency and a second listening port on the app container.
- No new services to run: Prometheus and Grafana are already on the VM.

- The down alert sees the app, not the public path: an outage of the edge
  nginx or TLS goes unnoticed. A blackbox probe of the public URL would close
  that gap.

## Open

- Which Docker network lets the Prometheus container reach the `scenex`
  container, and does Grafana already have SMTP configured for email alerts?
- Is 5 minutes the right threshold?

## Sources

- `lib/scenex_web/telemetry.ex`, `lib/scenex_web/router.ex` (LiveDashboard
  under `dev_routes`).
- [`deployment.md`](../deployment.md) — single app VM behind an edge nginx.
