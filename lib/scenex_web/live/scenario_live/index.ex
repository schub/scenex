defmodule ScenexWeb.ScenarioLive.Index do
  @moduledoc "Lists the scenarios a user can see and lets them create a new one."
  use ScenexWeb, :live_view

  alias Scenex.Authoring
  alias Scenex.I18n

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Games
        <:subtitle>Author and maintain scenario definitions.</:subtitle>
      </.header>

      <.form
        for={@form}
        id="new-scenario"
        phx-submit="create"
        class="mt-6 flex flex-wrap items-end gap-3"
      >
        <.input field={@form[:name]} label="New scenario name" class="w-64" />
        <.input
          field={@form[:key]}
          label="Key"
          title="Untranslated identifier for authors and the GM — never shown to the audience."
          class="w-48"
        />
        <.input
          field={@form[:source_locale]}
          type="select"
          label="Source locale"
          options={[{"English (en)", "en"}, {"Deutsch (de)", "de"}, {"Português (pt)", "pt"}]}
        />
        <.button variant="primary" phx-disable-with="Creating…">Create scenario</.button>
      </.form>

      <div id="scenarios" phx-update="stream" class="mt-8 grid gap-3">
        <div :for={{dom_id, scenario} <- @streams.scenarios} id={dom_id} class="card bg-base-200">
          <div class="card-body flex-row items-center justify-between py-4">
            <div>
              <.link
                navigate={~p"/scenarios/#{scenario.id}"}
                class="text-lg font-semibold hover:underline"
              >
                {I18n.t!(scenario.name, scenario.source_locale, default: scenario.key)}
              </.link>
              <span class="ml-2 font-mono text-xs opacity-50">{scenario.key}</span>
              <div class="mt-1 flex gap-2 text-xs">
                <span class="badge badge-sm">{scenario.visibility}</span>
                <span class="badge badge-sm badge-ghost">source: {scenario.source_locale}</span>
              </div>
            </div>
            <.link navigate={~p"/scenarios/#{scenario.id}"} class="btn btn-sm btn-primary btn-soft">
              Open editor
            </.link>
          </div>
        </div>
      </div>

      <p :if={@empty?} class="mt-6 opacity-70">No scenarios yet — create your first one above.</p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scenarios = Authoring.list_scenarios_for_user(socket.assigns.current_scope.user)

    {:ok,
     socket
     |> assign(:page_title, "Games")
     |> assign(:empty?, scenarios == [])
     |> assign_new_form()
     |> stream(:scenarios, scenarios)}
  end

  @impl true
  def handle_event(
        "create",
        %{"scenario" => %{"key" => key, "name" => name, "source_locale" => locale}},
        socket
      ) do
    # The name is entered in the source locale; other locales come later.
    attrs = %{key: key, name: %{locale => name}, source_locale: locale}

    case Authoring.create_scenario(socket.assigns.current_scope.user, attrs) do
      {:ok, scenario} ->
        {:noreply, push_navigate(socket, to: ~p"/scenarios/#{scenario.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Name and key can't be blank.")}
    end
  end

  defp assign_new_form(socket) do
    assign(
      socket,
      :form,
      to_form(%{"name" => "", "key" => "", "source_locale" => "en"}, as: :scenario)
    )
  end
end
