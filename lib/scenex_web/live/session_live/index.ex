defmodule ScenexWeb.SessionLive.Index do
  @moduledoc "Lists a scenario's sessions and creates new ones (GM entry point)."
  use ScenexWeb, :live_view

  alias Scenex.{Authoring, Play}
  alias Scenex.I18n

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Sessions — {I18n.t!(@scenario.name, @scenario.source_locale, default: @scenario.handle)}
        <:subtitle>One session is one live run of this scenario.</:subtitle>
        <:actions>
          <.link navigate={~p"/scenarios/#{@scenario.id}"} class="btn btn-sm btn-ghost">
            ← Editor
          </.link>
        </:actions>
      </.header>

      <.form for={@form} id="new-session" phx-submit="create" class="mt-6 flex items-end gap-3">
        <.input field={@form[:label]} label="New session (venue / date)" class="w-72" />
        <.button variant="primary" phx-disable-with="Creating…">Create session</.button>
      </.form>

      <div class="mt-8 space-y-3">
        <div :for={session <- @sessions} class="card bg-base-200">
          <div class="card-body flex-row items-center justify-between py-4">
            <div>
              <span class="text-lg font-semibold">{session.label}</span>
              <span class="badge badge-sm ml-2">{session.status}</span>
              <span class="ml-2 text-xs opacity-60">created {session.inserted_at}</span>
              <span class="ml-2 text-xs opacity-60">
                GM: {gm_label(session, @current_scope.user)}
              </span>
            </div>
            <.link
              :if={Play.gm?(session, @current_scope.user, @role)}
              navigate={~p"/sessions/#{session.id}/console"}
              class="btn btn-sm btn-primary"
            >
              Open console
            </.link>
          </div>
        </div>
        <p :if={@sessions == []} class="opacity-70">No sessions yet — create the first one above.</p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => scenario_id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Authoring.get_scenario_for_user(scenario_id, user) do
      {scenario, role} when role in [:owner, :author] ->
        {:ok,
         socket
         |> assign(scenario: scenario, role: role, page_title: "Sessions")
         |> assign(:form, to_form(%{"label" => ""}, as: :session))
         |> reload()}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "You cannot run sessions for this scenario.")
         |> push_navigate(to: ~p"/scenarios")}
    end
  end

  @impl true
  def handle_event("create", %{"session" => %{"label" => label}}, socket) do
    user = socket.assigns.current_scope.user

    case Play.create_session(user, socket.assigns.scenario, %{label: label}) do
      {:ok, session} ->
        {:noreply, push_navigate(socket, to: ~p"/sessions/#{session.id}/console")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Label can't be blank.")}
    end
  end

  defp reload(socket) do
    assign(socket, :sessions, Play.list_sessions(socket.assigns.scenario))
  end

  defp gm_label(session, current_user) do
    case session.created_by do
      %{id: id} when id == current_user.id -> "you"
      %{email: email} -> email
      nil -> "unknown"
    end
  end
end
