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

      <.form for={@form} id="new-session" phx-submit="create" class="mt-6 space-y-4">
        <div class="flex items-end gap-3">
          <.input field={@form[:label]} label="New session (venue / date)" class="w-72" />
          <.input
            field={@form[:locale]}
            type="select"
            label="Play language (audience screens)"
            options={I18n.locale_options()}
            class="w-44"
          />
        </div>

        <fieldset :if={@groups != []}>
          <legend class="mb-1 text-sm font-medium">
            Groups in this show <span class="opacity-60">(pick at least two for the venue)</span>
          </legend>
          <div class="flex flex-wrap gap-x-6 gap-y-2">
            <label
              :for={group <- @groups}
              class="label cursor-pointer justify-start gap-2 p-0 text-base-content"
            >
              <input
                type="checkbox"
                name="session[group_ids][]"
                value={group.id}
                checked
                class="checkbox checkbox-sm"
              />
              <span>{group_name(group, @scenario)}</span>
            </label>
          </div>
        </fieldset>

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
         |> assign(:groups, Authoring.list_groups(scenario))
         |> assign(
           :form,
           to_form(%{"label" => "", "locale" => scenario.source_locale}, as: :session)
         )
         |> reload()}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "You cannot run sessions for this scenario.")
         |> push_navigate(to: ~p"/scenarios")}
    end
  end

  @impl true
  def handle_event("create", %{"session" => %{"label" => label} = params}, socket) do
    user = socket.assigns.current_scope.user

    attrs = %{
      label: label,
      locale: params["locale"] || socket.assigns.scenario.source_locale,
      group_ids: submitted_group_ids(params, socket.assigns.groups)
    }

    case Play.create_session(user, socket.assigns.scenario, attrs) do
      {:ok, session} ->
        {:noreply, push_navigate(socket, to: ~p"/sessions/#{session.id}/console")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, create_error(changeset))}
    end
  end

  defp reload(socket) do
    assign(socket, :sessions, Play.list_sessions(socket.assigns.scenario))
  end

  # Unchecked checkboxes send nothing, so an absent key means "none checked" —
  # except for scenarios without groups, where no selection exists to make.
  defp submitted_group_ids(_params, []), do: nil
  defp submitted_group_ids(params, _groups), do: List.wrap(params["group_ids"])

  defp create_error(changeset) do
    case changeset.errors[:groups] do
      {message, _} -> "Groups: #{message}."
      nil -> "Label can't be blank."
    end
  end

  defp group_name(group, scenario) do
    I18n.t!(group.name, scenario.source_locale, default: group.handle)
  end

  defp gm_label(session, current_user) do
    case session.created_by do
      %{id: id} when id == current_user.id -> "you"
      %{email: email} -> email
      nil -> "unknown"
    end
  end
end
