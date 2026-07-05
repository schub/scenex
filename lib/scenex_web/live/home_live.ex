defmodule ScenexWeb.HomeLive do
  @moduledoc "Public landing page — routes visitors into the app or to sign in."
  use ScenexWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl space-y-8 py-16 text-center">
        <.header>
          Scenex
          <:subtitle>
            A platform for authoring and running large, role-based simulation games.
          </:subtitle>
        </.header>

        <div class="flex justify-center gap-3">
          <.link :if={@current_scope} navigate={~p"/scenarios"} class="btn btn-primary">
            Go to your scenarios <span aria-hidden="true">→</span>
          </.link>

          <.link :if={!@current_scope} navigate={~p"/users/log-in"} class="btn btn-primary">
            Log in
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
