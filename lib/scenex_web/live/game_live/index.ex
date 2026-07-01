defmodule ScenexWeb.GameLive.Index do
  @moduledoc "Lists the games a user can see and lets them create a new one."
  use ScenexWeb, :live_view

  alias Scenex.Authoring
  alias Scenex.I18n

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Games
        <:subtitle>Author and maintain game definitions.</:subtitle>
      </.header>

      <.form for={@form} id="new-game" phx-submit="create" class="mt-6 flex flex-wrap items-end gap-3">
        <.input field={@form[:name]} label="New game name" class="w-64" />
        <.input
          field={@form[:source_locale]}
          type="select"
          label="Source locale"
          options={[{"English (en)", "en"}, {"Deutsch (de)", "de"}, {"Português (pt)", "pt"}]}
        />
        <.button variant="primary" phx-disable-with="Creating…">Create game</.button>
      </.form>

      <div id="games" phx-update="stream" class="mt-8 grid gap-3">
        <div :for={{dom_id, game} <- @streams.games} id={dom_id} class="card bg-base-200">
          <div class="card-body flex-row items-center justify-between py-4">
            <div>
              <.link navigate={~p"/games/#{game.id}"} class="text-lg font-semibold hover:underline">
                {I18n.t!(game.name, game.source_locale, default: "Untitled game")}
              </.link>
              <div class="mt-1 flex gap-2 text-xs">
                <span class="badge badge-sm">{game.visibility}</span>
                <span class="badge badge-sm badge-ghost">source: {game.source_locale}</span>
              </div>
            </div>
            <.link navigate={~p"/games/#{game.id}"} class="btn btn-sm btn-primary btn-soft">
              Open editor
            </.link>
          </div>
        </div>
      </div>

      <p :if={@empty?} class="mt-6 opacity-70">No games yet — create your first one above.</p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    games = Authoring.list_games_for_user(socket.assigns.current_scope.user)

    {:ok,
     socket
     |> assign(:page_title, "Games")
     |> assign(:empty?, games == [])
     |> assign_new_form()
     |> stream(:games, games)}
  end

  @impl true
  def handle_event("create", %{"game" => %{"name" => name, "source_locale" => locale}}, socket) do
    attrs = %{name: %{locale => name}, source_locale: locale}

    case Authoring.create_game(socket.assigns.current_scope.user, attrs) do
      {:ok, game} ->
        {:noreply, push_navigate(socket, to: ~p"/games/#{game.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Name can't be blank.")}
    end
  end

  defp assign_new_form(socket) do
    assign(socket, :form, to_form(%{"name" => "", "source_locale" => "en"}, as: :game))
  end
end
