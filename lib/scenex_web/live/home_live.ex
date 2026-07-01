defmodule ScenexWeb.HomeLive do
  @moduledoc """
  Landing page. Doubles as an end-to-end smoke test for the LiveView
  websocket path: it reports live-socket connectivity and holds a
  server-side counter that only updates over the socket. If the counter
  increments in the browser, the websocket round-trip works — locally now,
  and through the VM's edge proxy once deployed.
  """
  use ScenexWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl space-y-8 py-12 text-center">
        <.header>
          Scenex
          <:subtitle>
            A platform for authoring and running large, role-based simulation games.
          </:subtitle>
        </.header>

        <div class="alert" role="status">
          <.icon
            name={if @connected, do: "hero-bolt", else: "hero-bolt-slash"}
            class="size-6 shrink-0"
          />
          <span>
            LiveView socket:
            <span class="font-semibold">{if @connected, do: "connected", else: "connecting…"}</span>
          </span>
        </div>

        <div class="space-y-3">
          <p class="text-sm opacity-70">
            Websocket smoke test — click to increment a counter held on the server:
          </p>
          <p class="text-4xl font-bold tabular-nums">{@count}</p>
          <.button phx-click="inc" class="btn btn-primary">
            Increment <span aria-hidden="true">+1</span>
          </.button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, count: 0, connected: connected?(socket))}
  end

  @impl true
  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end
end
