defmodule ScenexWeb.GameLive.Show do
  @moduledoc """
  The game-definition editor. Sections: Settings, Values, Groups, Initial values.
  Content is edited one working locale at a time; authorization comes from the
  Authoring context (owners/authors edit, everyone else is read-only).
  """
  use ScenexWeb, :live_view

  alias Scenex.Authoring
  alias Scenex.Authoring.{Group, ValueDefinition}
  alias Scenex.I18n
  alias ScenexWeb.LocalizedForm

  @sections ~w(settings values groups initial)a
  @locale_choices ~w(en de pt es it)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {I18n.t!(@game.name, @locale, default: "Untitled game")}
        <:subtitle>
          <span class="badge badge-sm">{@game.visibility}</span>
          <span :if={not @can_edit?} class="badge badge-sm badge-warning">read-only ({@role})</span>
        </:subtitle>
        <:actions>
          <.link navigate={~p"/games"} class="btn btn-sm btn-ghost">← All games</.link>
        </:actions>
      </.header>

      <div class="mt-4 flex items-center gap-2 text-sm">
        <span class="opacity-70">Working locale:</span>
        <div class="join">
          <button
            :for={loc <- @locales}
            type="button"
            phx-click="set_locale"
            phx-value-locale={loc}
            class={["btn btn-xs join-item", loc == @locale && "btn-primary"]}
          >
            {loc}
          </button>
        </div>
      </div>

      <div role="tablist" class="tabs tabs-box mt-4 w-fit">
        <button
          :for={s <- sections()}
          type="button"
          role="tab"
          phx-click="section"
          phx-value-section={s}
          class={["tab", s == @section && "tab-active"]}
        >
          {Phoenix.Naming.humanize(s)}
        </button>
      </div>

      <div class="mt-6">
        <%!-- Settings --%>
        <div :if={@section == :settings}>
          <.form for={@settings_form} phx-submit="save_settings" class="max-w-xl space-y-4">
            <.input
              type="text"
              name={"game[name][#{@locale}]"}
              value={LocalizedForm.value(@settings_form, :name, @locale)}
              label={"Name (#{@locale})"}
            />
            <.input
              type="textarea"
              name={"game[description][#{@locale}]"}
              value={LocalizedForm.value(@settings_form, :description, @locale)}
              label={"Description (#{@locale}, Markdown)"}
            />
            <.input
              field={@settings_form[:visibility]}
              type="select"
              label="Visibility"
              options={[{"Draft", :draft}, {"Invite only", :invite_only}, {"Published", :published}]}
            />
            <.input field={@settings_form[:source_locale]} label="Source locale" />
            <.button :if={@can_edit?} variant="primary">Save settings</.button>
          </.form>
        </div>

        <%!-- Values --%>
        <div :if={@section == :values} class="space-y-6">
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>Key</th>
                  <th>Name</th>
                  <th>Scope</th>
                  <th>Aggregation</th>
                  <th>Range</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={v <- @value_definitions}>
                  <td class="font-mono text-xs">{v.key}</td>
                  <td>{I18n.t!(v.name, @locale, default: "—")}</td>
                  <td>{v.input_scope}</td>
                  <td class="font-mono text-xs">{v.aggregation}</td>
                  <td class="text-xs">{fmt_range(v)}</td>
                  <td class="text-right whitespace-nowrap">
                    <button
                      :if={@can_edit?}
                      type="button"
                      phx-click="edit_value"
                      phx-value-id={v.id}
                      class="btn btn-xs"
                    >
                      Edit
                    </button>
                    <button
                      :if={@can_edit?}
                      type="button"
                      phx-click="delete_value"
                      phx-value-id={v.id}
                      data-confirm="Delete this value?"
                      class="btn btn-xs btn-error btn-soft"
                    >
                      Delete
                    </button>
                  </td>
                </tr>
                <tr :if={@value_definitions == []}>
                  <td colspan="6" class="opacity-70">No values yet.</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@can_edit?} class="card bg-base-200">
            <div class="card-body">
              <h3 class="font-semibold">{if @editing_value, do: "Edit value", else: "New value"}</h3>
              <.form for={@value_form} phx-submit="save_value" class="grid gap-3 sm:grid-cols-2">
                <.input field={@value_form[:key]} label="Key (slug)" />
                <.input
                  field={@value_form[:input_scope]}
                  type="select"
                  label="Input scope"
                  options={[{"Per group", :per_group}, {"Per participant", :per_participant}]}
                />
                <.input
                  type="text"
                  name={"value_definition[name][#{@locale}]"}
                  value={LocalizedForm.value(@value_form, :name, @locale)}
                  label={"Name (#{@locale})"}
                />
                <.input field={@value_form[:aggregation]} label="Aggregation formula" />
                <div class="sm:col-span-2">
                  <.input
                    type="textarea"
                    name={"value_definition[description][#{@locale}]"}
                    value={LocalizedForm.value(@value_form, :description, @locale)}
                    label={"Description (#{@locale}, Markdown)"}
                  />
                </div>
                <.input field={@value_form[:min]} type="number" step="any" label="Min" />
                <.input field={@value_form[:max]} type="number" step="any" label="Max" />
                <.input field={@value_form[:default_value]} type="number" step="any" label="Default" />
                <.input field={@value_form[:position]} type="number" label="Position" />
                <div class="flex gap-2 sm:col-span-2">
                  <.button variant="primary">Save value</.button>
                  <button
                    :if={@editing_value}
                    type="button"
                    phx-click="new_value"
                    class="btn btn-ghost"
                  >
                    Cancel
                  </button>
                </div>
              </.form>
              <p class="text-xs opacity-60">
                Aggregations: min, max, avg, median, sum — combine with + - * / and parentheses,
                e.g. <code>(avg + min) / 2</code>.
              </p>
            </div>
          </div>
        </div>

        <%!-- Groups --%>
        <div :if={@section == :groups} class="space-y-6">
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Position</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={g <- @groups}>
                  <td>{I18n.t!(g.name, @locale, default: "—")}</td>
                  <td>{g.position}</td>
                  <td class="text-right whitespace-nowrap">
                    <button
                      :if={@can_edit?}
                      type="button"
                      phx-click="edit_group"
                      phx-value-id={g.id}
                      class="btn btn-xs"
                    >
                      Edit
                    </button>
                    <button
                      :if={@can_edit?}
                      type="button"
                      phx-click="delete_group"
                      phx-value-id={g.id}
                      data-confirm="Delete this group?"
                      class="btn btn-xs btn-error btn-soft"
                    >
                      Delete
                    </button>
                  </td>
                </tr>
                <tr :if={@groups == []}>
                  <td colspan="3" class="opacity-70">No groups yet.</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@can_edit?} class="card bg-base-200">
            <div class="card-body">
              <h3 class="font-semibold">{if @editing_group, do: "Edit group", else: "New group"}</h3>
              <.form for={@group_form} phx-submit="save_group" class="grid gap-3 sm:grid-cols-2">
                <.input
                  type="text"
                  name={"group[name][#{@locale}]"}
                  value={LocalizedForm.value(@group_form, :name, @locale)}
                  label={"Name (#{@locale})"}
                />
                <.input field={@group_form[:position]} type="number" label="Position" />
                <div class="sm:col-span-2">
                  <.input
                    type="textarea"
                    name={"group[description][#{@locale}]"}
                    value={LocalizedForm.value(@group_form, :description, @locale)}
                    label={"Description (#{@locale}, Markdown)"}
                  />
                </div>
                <div class="flex gap-2 sm:col-span-2">
                  <.button variant="primary">Save group</.button>
                  <button
                    :if={@editing_group}
                    type="button"
                    phx-click="new_group"
                    class="btn btn-ghost"
                  >
                    Cancel
                  </button>
                </div>
              </.form>
            </div>
          </div>
        </div>

        <%!-- Initial values --%>
        <div :if={@section == :initial} class="space-y-4">
          <% pg = per_group_values(@value_definitions) %>
          <p :if={pg == [] or @groups == []} class="opacity-70">
            Add at least one per-group value and one group first.
          </p>
          <.form
            :if={pg != [] and @groups != []}
            for={to_form(%{}, as: :initial)}
            phx-submit="save_initials"
            class="space-y-4"
          >
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Group \ Value</th>
                    <th :for={v <- pg}>{I18n.t!(v.name, @locale, default: v.key)}</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={g <- @groups}>
                    <td class="font-medium">{I18n.t!(g.name, @locale, default: "—")}</td>
                    <td :for={v <- pg}>
                      <input
                        type="number"
                        step="any"
                        name={"initial[#{g.id}][#{v.id}]"}
                        value={Map.get(@initials, {g.id, v.id}, v.default_value)}
                        disabled={not @can_edit?}
                        class="input input-bordered input-sm w-24"
                      />
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <.button :if={@can_edit?} variant="primary">Save initial values</.button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Authoring.get_game_for_user(id, socket.assigns.current_scope.user) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Game not found.")
         |> push_navigate(to: ~p"/games")}

      {game, role} ->
        {:ok,
         socket
         |> assign(
           game: game,
           role: role,
           can_edit?: role in [:owner, :author],
           section: :settings,
           locale: game.source_locale,
           locales: Enum.uniq([game.source_locale | @locale_choices]),
           page_title: I18n.t!(game.name, game.source_locale, default: "Game")
         )
         |> assign_settings_form(game)
         |> assign_value_form(%ValueDefinition{})
         |> assign_group_form(%Group{})
         |> reload()}
    end
  end

  # ── Navigation & locale ───────────────────────────────────────────────

  @impl true
  def handle_event("section", %{"section" => section}, socket) do
    {:noreply, assign(socket, :section, String.to_existing_atom(section))}
  end

  def handle_event("set_locale", %{"locale" => locale}, socket) do
    {:noreply, assign(socket, :locale, locale)}
  end

  # ── Settings ──────────────────────────────────────────────────────────

  def handle_event("save_settings", %{"game" => params}, socket) do
    with_edit(socket, fn ->
      attrs = LocalizedForm.merge(params, socket.assigns.game, [:name, :description])

      case Authoring.update_game(socket.assigns.game, attrs) do
        {:ok, game} ->
          {:noreply,
           socket
           |> assign(:game, game)
           |> assign_settings_form(game)
           |> put_flash(:info, "Settings saved.")}

        {:error, changeset} ->
          {:noreply, assign(socket, :settings_form, to_form(changeset, as: :game))}
      end
    end)
  end

  # ── Values ────────────────────────────────────────────────────────────

  def handle_event("edit_value", %{"id" => id}, socket) do
    {:noreply, assign_value_form(socket, Authoring.get_value_definition!(id))}
  end

  def handle_event("new_value", _params, socket) do
    {:noreply, assign_value_form(socket, %ValueDefinition{})}
  end

  def handle_event("save_value", %{"value_definition" => params}, socket) do
    with_edit(socket, fn ->
      data = socket.assigns.editing_value || %ValueDefinition{}
      attrs = LocalizedForm.merge(params, data, [:name, :description])

      result =
        if socket.assigns.editing_value,
          do: Authoring.update_value_definition(data, attrs),
          else: Authoring.create_value_definition(socket.assigns.game, attrs)

      case result do
        {:ok, _vd} ->
          {:noreply,
           socket
           |> assign_value_form(%ValueDefinition{})
           |> reload()
           |> put_flash(:info, "Value saved.")}

        {:error, changeset} ->
          {:noreply, assign(socket, :value_form, to_form(changeset, as: :value_definition))}
      end
    end)
  end

  def handle_event("delete_value", %{"id" => id}, socket) do
    with_edit(socket, fn ->
      id |> Authoring.get_value_definition!() |> Authoring.delete_value_definition()
      {:noreply, socket |> assign_value_form(%ValueDefinition{}) |> reload()}
    end)
  end

  # ── Groups ────────────────────────────────────────────────────────────

  def handle_event("edit_group", %{"id" => id}, socket) do
    {:noreply, assign_group_form(socket, Authoring.get_group!(id))}
  end

  def handle_event("new_group", _params, socket) do
    {:noreply, assign_group_form(socket, %Group{})}
  end

  def handle_event("save_group", %{"group" => params}, socket) do
    with_edit(socket, fn ->
      data = socket.assigns.editing_group || %Group{}
      attrs = LocalizedForm.merge(params, data, [:name, :description])

      result =
        if socket.assigns.editing_group,
          do: Authoring.update_group(data, attrs),
          else: Authoring.create_group(socket.assigns.game, attrs)

      case result do
        {:ok, _group} ->
          {:noreply,
           socket
           |> assign_group_form(%Group{})
           |> reload()
           |> put_flash(:info, "Group saved.")}

        {:error, changeset} ->
          {:noreply, assign(socket, :group_form, to_form(changeset, as: :group))}
      end
    end)
  end

  def handle_event("delete_group", %{"id" => id}, socket) do
    with_edit(socket, fn ->
      id |> Authoring.get_group!() |> Authoring.delete_group()
      {:noreply, socket |> assign_group_form(%Group{}) |> reload()}
    end)
  end

  # ── Initial values grid ───────────────────────────────────────────────

  def handle_event("save_initials", %{"initial" => grid}, socket) do
    with_edit(socket, fn ->
      groups = Map.new(socket.assigns.groups, &{&1.id, &1})
      values = Map.new(socket.assigns.value_definitions, &{&1.id, &1})

      for {group_id, cells} <- grid,
          {value_id, raw} <- cells,
          group = groups[group_id],
          vd = values[value_id],
          not is_nil(group) and not is_nil(vd) do
        Authoring.set_group_initial_value(group, vd, to_number(raw))
      end

      {:noreply, socket |> reload() |> put_flash(:info, "Initial values saved.")}
    end)
  end

  # ── Assigns helpers ───────────────────────────────────────────────────

  defp assign_settings_form(socket, game),
    do: assign(socket, :settings_form, to_form(Authoring.change_game(game), as: :game))

  defp assign_value_form(socket, value) do
    socket
    |> assign(:editing_value, if(value.id, do: value, else: nil))
    |> assign(
      :value_form,
      to_form(Authoring.change_value_definition(value), as: :value_definition)
    )
  end

  defp assign_group_form(socket, group) do
    socket
    |> assign(:editing_group, if(group.id, do: group, else: nil))
    |> assign(:group_form, to_form(Authoring.change_group(group), as: :group))
  end

  defp reload(socket) do
    game = socket.assigns.game
    groups = Authoring.list_groups(game)

    initials =
      for group <- groups, giv <- Authoring.list_group_initial_values(group), into: %{} do
        {{giv.group_id, giv.value_definition_id}, giv.initial}
      end

    assign(socket,
      value_definitions: Authoring.list_value_definitions(game),
      groups: groups,
      initials: initials
    )
  end

  defp with_edit(socket, fun) do
    if socket.assigns.can_edit?,
      do: fun.(),
      else: {:noreply, put_flash(socket, :error, "This game is read-only for you.")}
  end

  defp to_number(raw) when is_binary(raw) do
    case Float.parse(String.trim(raw)) do
      {number, _rest} -> number
      :error -> 0.0
    end
  end

  defp to_number(_), do: 0.0

  defp per_group_values(value_definitions),
    do: Enum.filter(value_definitions, &(&1.input_scope == :per_group))

  defp fmt_range(%{min: min, max: max}) do
    if is_nil(min) and is_nil(max), do: "—", else: "#{fmt_num(min)}–#{fmt_num(max)}"
  end

  defp fmt_num(nil), do: "∗"
  defp fmt_num(number), do: to_string(number)

  def sections, do: @sections
end
