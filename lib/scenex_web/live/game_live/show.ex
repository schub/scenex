defmodule ScenexWeb.GameLive.Show do
  @moduledoc """
  The game-definition editor. Sections: Settings, Values, Groups, Initial values,
  Events, Labels. Content is edited one working locale at a time; authorization
  comes from the Authoring context (owners/authors edit, else read-only).
  """
  use ScenexWeb, :live_view

  alias Scenex.Authoring
  alias Scenex.Authoring.{DecisionOption, Event, Group, Label, ValueDefinition}
  alias Scenex.I18n
  alias ScenexWeb.LocalizedForm

  @sections ~w(settings values groups initial events labels)a
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
          <.link navigate={~p"/games/#{@game.id}/simulate"} class="btn btn-sm btn-accent btn-soft">
            Dry run
          </.link>
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
              field={@settings_form[:handle]}
              label="Handle (internal, not translated)"
            />
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
              <.form
                for={@value_form}
                phx-change="value_form_changed"
                phx-submit="save_value"
                class="grid gap-3 sm:grid-cols-2"
              >
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
                <.input
                  :if={@value_scope != :per_participant}
                  field={@value_form[:min]}
                  type="number"
                  step="any"
                  label="Min"
                />
                <.input
                  :if={@value_scope != :per_participant}
                  field={@value_form[:max]}
                  type="number"
                  step="any"
                  label="Max"
                />
                <.input
                  :if={@value_scope != :per_participant}
                  field={@value_form[:default_value]}
                  type="number"
                  step="any"
                  label="Default"
                />
                <p
                  :if={@value_scope == :per_participant}
                  class="self-center text-xs opacity-60 sm:col-span-2"
                >
                  Per-participant values are collected from individuals and aren't clamped,
                  so they have no min/max/default.
                </p>
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
                  <th>Handle</th>
                  <th>Name ({@locale})</th>
                  <th>Position</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={g <- @groups}>
                  <td class="font-medium">{g.handle}</td>
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
                  <td colspan="4" class="opacity-70">No groups yet.</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@can_edit?} class="card bg-base-200">
            <div class="card-body">
              <h3 class="font-semibold">{if @editing_group, do: "Edit group", else: "New group"}</h3>
              <.form for={@group_form} phx-submit="save_group" class="grid gap-3 sm:grid-cols-2">
                <.input field={@group_form[:handle]} label="Handle (internal)" />
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

        <%!-- Events --%>
        <div :if={@section == :events} class="space-y-6">
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>#</th>
                  <th>Handle</th>
                  <th>Title ({@locale})</th>
                  <th>Kind</th>
                  <th>Deadline</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={e <- @events} class={e.id == @selected_event_id && "bg-base-200"}>
                  <td>{e.position}</td>
                  <td class="font-medium">{e.handle}</td>
                  <td>{I18n.t!(e.title, @locale, default: "—")}</td>
                  <td>{e.kind}</td>
                  <td class="text-xs">{fmt_deadline(e.deadline_seconds)}</td>
                  <td class="text-right whitespace-nowrap">
                    <button
                      type="button"
                      phx-click="open_event"
                      phx-value-id={e.id}
                      class="btn btn-xs"
                    >
                      Options
                    </button>
                    <button
                      :if={@can_edit?}
                      type="button"
                      phx-click="edit_event"
                      phx-value-id={e.id}
                      class="btn btn-xs"
                    >
                      Edit
                    </button>
                    <button
                      :if={@can_edit?}
                      type="button"
                      phx-click="delete_event"
                      phx-value-id={e.id}
                      data-confirm="Delete this event and all its options?"
                      class="btn btn-xs btn-error btn-soft"
                    >
                      Delete
                    </button>
                  </td>
                </tr>
                <tr :if={@events == []}>
                  <td colspan="6" class="opacity-70">No events yet.</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@can_edit?} class="card bg-base-200">
            <div class="card-body">
              <h3 class="font-semibold">{if @editing_event, do: "Edit event", else: "New event"}</h3>
              <.form for={@event_form} phx-submit="save_event" class="grid gap-3 sm:grid-cols-2">
                <.input field={@event_form[:handle]} label="Handle (internal)" />
                <.input
                  type="text"
                  name={"event[title][#{@locale}]"}
                  value={LocalizedForm.value(@event_form, :title, @locale)}
                  label={"Title (#{@locale})"}
                />
                <.input field={@event_form[:position]} type="number" label="Position" />
                <div class="sm:col-span-2">
                  <.input
                    type="textarea"
                    name={"event[narrative][#{@locale}]"}
                    value={LocalizedForm.value(@event_form, :narrative, @locale)}
                    label={"Narrative (#{@locale}, Markdown)"}
                  />
                </div>
                <.input
                  field={@event_form[:kind]}
                  type="select"
                  label="Kind"
                  options={Enum.map(Event.kinds(), &{Phoenix.Naming.humanize(&1), &1})}
                />
                <.input
                  field={@event_form[:deadline_seconds]}
                  type="number"
                  label="Deadline (seconds, optional)"
                />
                <div class="flex gap-2 sm:col-span-2">
                  <.button variant="primary">Save event</.button>
                  <button
                    :if={@editing_event}
                    type="button"
                    phx-click="new_event"
                    class="btn btn-ghost"
                  >
                    Cancel
                  </button>
                </div>
              </.form>
            </div>
          </div>

          <%!-- Options for the opened event --%>
          <div :if={@selected_event} class="rounded-box border border-base-300 p-4 space-y-6">
            <div class="flex items-center justify-between">
              <h3 class="text-lg font-semibold">
                Options — {I18n.t!(@selected_event.title, @locale, default: "event")}
              </h3>
              <button type="button" phx-click="close_event" class="btn btn-xs btn-ghost">
                Close
              </button>
            </div>

            <p :if={@groups == []} class="opacity-70">Add at least one group first.</p>

            <div :for={group <- @groups} class="space-y-2">
              <div class="flex items-center justify-between">
                <h4 class="font-medium">{I18n.t!(group.name, @locale, default: "—")}</h4>
                <button
                  :if={@can_edit?}
                  type="button"
                  phx-click="new_option"
                  phx-value-group={group.id}
                  class="btn btn-xs"
                >
                  + Option
                </button>
              </div>

              <ul class="space-y-1">
                <li
                  :for={o <- options_for_group(@options, group.id)}
                  class="flex items-center justify-between gap-2 rounded bg-base-200 px-3 py-2"
                >
                  <div class="min-w-0">
                    <span class="text-sm font-medium">{o.handle}</span>
                    <span class="text-sm opacity-70">— {I18n.t!(o.text, @locale, default: "—")}</span>
                    <span :if={o.is_default} class="badge badge-xs badge-info ml-1">default</span>
                    <span :for={l <- o.labels} class={["badge badge-xs ml-1", label_class(l.color)]}>
                      {I18n.t!(l.name, @locale, default: "?")}
                    </span>
                    <span class="ml-1 text-xs opacity-60">
                      {fmt_effects(o.effects, @value_index, @locale)}
                    </span>
                  </div>
                  <div class="whitespace-nowrap">
                    <button
                      :if={@can_edit?}
                      type="button"
                      phx-click="edit_option"
                      phx-value-id={o.id}
                      class="btn btn-xs"
                    >
                      Edit
                    </button>
                    <button
                      :if={@can_edit?}
                      type="button"
                      phx-click="delete_option"
                      phx-value-id={o.id}
                      data-confirm="Delete this option?"
                      class="btn btn-xs btn-error btn-soft"
                    >
                      Delete
                    </button>
                  </div>
                </li>
                <li :if={options_for_group(@options, group.id) == []} class="text-xs opacity-60">
                  No options for this group yet.
                </li>
              </ul>
            </div>

            <%!-- Option editor --%>
            <div :if={@can_edit? and @option_group_id} class="card bg-base-100 border border-base-300">
              <div class="card-body">
                <h4 class="font-semibold">
                  {if @editing_option, do: "Edit option", else: "New option"}
                </h4>
                <.form for={@option_form} phx-submit="save_option" class="space-y-3">
                  <.input field={@option_form[:handle]} label="Handle (internal)" />
                  <.input
                    type="text"
                    name={"option[text][#{@locale}]"}
                    value={LocalizedForm.value(@option_form, :text, @locale)}
                    label={"Option text (#{@locale})"}
                  />
                  <div class="grid gap-3 sm:grid-cols-2">
                    <.input field={@option_form[:position]} type="number" label="Position" />
                    <label class="flex items-center gap-2 self-end pb-2">
                      <input type="hidden" name="option[is_default]" value="false" />
                      <input
                        type="checkbox"
                        name="option[is_default]"
                        value="true"
                        checked={@option_form[:is_default].value in [true, "true"]}
                        class="checkbox checkbox-sm"
                      />
                      <span class="text-sm">Default (applied if deadline lapses)</span>
                    </label>
                  </div>

                  <fieldset :if={@labels != []} class="fieldset">
                    <legend class="fieldset-legend">Labels</legend>
                    <div class="flex flex-wrap gap-3">
                      <label :for={l <- @labels} class="flex items-center gap-1">
                        <input
                          type="checkbox"
                          name="option[labels][]"
                          value={l.id}
                          checked={l.id in @option_label_ids}
                          class="checkbox checkbox-xs"
                        />
                        <span class={["badge badge-sm", label_class(l.color)]}>
                          {I18n.t!(l.name, @locale, default: "?")}
                        </span>
                      </label>
                    </div>
                  </fieldset>

                  <fieldset class="fieldset">
                    <legend class="fieldset-legend">
                      Effects on {I18n.t!(@selected_group_name, @locale, default: "this group")}'s values
                    </legend>
                    <p :if={per_group_values(@value_definitions) == []} class="text-xs opacity-60">
                      Add per-group values first.
                    </p>
                    <div class="grid gap-2 sm:grid-cols-2">
                      <label
                        :for={v <- per_group_values(@value_definitions)}
                        class="flex items-center gap-2 text-sm"
                      >
                        <span class="w-32 truncate">{I18n.t!(v.name, @locale, default: v.key)}</span>
                        <input
                          type="number"
                          step="any"
                          name={"effect[#{v.id}]"}
                          value={Map.get(@option_effects, v.id, "")}
                          placeholder="0"
                          class="input input-bordered input-sm w-24"
                        />
                      </label>
                    </div>
                  </fieldset>

                  <div class="flex gap-2">
                    <.button variant="primary">Save option</.button>
                    <button type="button" phx-click="cancel_option" class="btn btn-ghost">
                      Cancel
                    </button>
                  </div>
                </.form>
              </div>
            </div>
          </div>
        </div>

        <%!-- Labels --%>
        <div :if={@section == :labels} class="space-y-6">
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>Handle</th>
                  <th>Name ({@locale})</th>
                  <th>Color</th>
                  <th>Icon</th>
                  <th>Position</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={l <- @labels}>
                  <td class="font-medium">{l.handle}</td>
                  <td>
                    <span class={["badge badge-sm", label_class(l.color)]}>
                      {I18n.t!(l.name, @locale, default: "—")}
                    </span>
                  </td>
                  <td class="text-xs">{l.color}</td>
                  <td class="text-xs">{l.icon || "—"}</td>
                  <td>{l.position}</td>
                  <td class="text-right whitespace-nowrap">
                    <button
                      :if={@can_edit?}
                      type="button"
                      phx-click="edit_label"
                      phx-value-id={l.id}
                      class="btn btn-xs"
                    >
                      Edit
                    </button>
                    <button
                      :if={@can_edit?}
                      type="button"
                      phx-click="delete_label"
                      phx-value-id={l.id}
                      data-confirm="Delete this label?"
                      class="btn btn-xs btn-error btn-soft"
                    >
                      Delete
                    </button>
                  </td>
                </tr>
                <tr :if={@labels == []}>
                  <td colspan="6" class="opacity-70">No labels yet.</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@can_edit?} class="card bg-base-200">
            <div class="card-body">
              <h3 class="font-semibold">{if @editing_label, do: "Edit label", else: "New label"}</h3>
              <.form for={@label_form} phx-submit="save_label" class="grid gap-3 sm:grid-cols-2">
                <.input field={@label_form[:handle]} label="Handle (internal)" />
                <.input
                  type="text"
                  name={"label[name][#{@locale}]"}
                  value={LocalizedForm.value(@label_form, :name, @locale)}
                  label={"Name (#{@locale})"}
                />
                <.input
                  field={@label_form[:color]}
                  type="select"
                  label="Color"
                  options={Enum.map(Label.colors(), &{Phoenix.Naming.humanize(&1), &1})}
                />
                <.input field={@label_form[:icon]} label="Icon (optional)" />
                <.input field={@label_form[:position]} type="number" label="Position" />
                <div class="flex gap-2 sm:col-span-2">
                  <.button variant="primary">Save label</.button>
                  <button
                    :if={@editing_label}
                    type="button"
                    phx-click="new_label"
                    class="btn btn-ghost"
                  >
                    Cancel
                  </button>
                </div>
              </.form>
            </div>
          </div>
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
         |> assign(
           selected_event: nil,
           selected_event_id: nil,
           options: [],
           option_group_id: nil,
           editing_option: nil,
           option_effects: %{},
           option_label_ids: [],
           selected_group_name: %{}
         )
         |> assign_settings_form(game)
         |> assign_value_form(%ValueDefinition{})
         |> assign_group_form(%Group{})
         |> assign_event_form(%Event{})
         |> assign_label_form(%Label{})
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

  # Live-track the selected scope so bounds fields can hide for per-participant.
  # Rebuild the form from params so typed values survive the re-render.
  def handle_event("value_form_changed", %{"value_definition" => params}, socket) do
    data = socket.assigns.editing_value || %ValueDefinition{}
    attrs = LocalizedForm.merge(params, data, [:name, :description])
    scope = if params["input_scope"] == "per_participant", do: :per_participant, else: :per_group

    {:noreply,
     socket
     |> assign(:value_scope, scope)
     |> assign(
       :value_form,
       to_form(Authoring.change_value_definition(data, attrs), as: :value_definition)
     )}
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

  # ── Events ────────────────────────────────────────────────────────────

  def handle_event("edit_event", %{"id" => id}, socket) do
    {:noreply, assign_event_form(socket, Authoring.get_event!(id))}
  end

  def handle_event("new_event", _params, socket) do
    {:noreply, assign_event_form(socket, %Event{})}
  end

  def handle_event("save_event", %{"event" => params}, socket) do
    with_edit(socket, fn ->
      data = socket.assigns.editing_event || %Event{}
      attrs = LocalizedForm.merge(params, data, [:title, :narrative])

      result =
        if socket.assigns.editing_event,
          do: Authoring.update_event(data, attrs),
          else: Authoring.create_event(socket.assigns.game, attrs)

      case result do
        {:ok, _event} ->
          {:noreply,
           socket |> assign_event_form(%Event{}) |> reload() |> put_flash(:info, "Event saved.")}

        {:error, changeset} ->
          {:noreply, assign(socket, :event_form, to_form(changeset, as: :event))}
      end
    end)
  end

  def handle_event("delete_event", %{"id" => id}, socket) do
    with_edit(socket, fn ->
      event = Authoring.get_event!(id)
      Authoring.delete_event(event)

      socket =
        if socket.assigns.selected_event_id == id,
          do: close_event(socket),
          else: socket

      {:noreply, socket |> assign_event_form(%Event{}) |> reload()}
    end)
  end

  def handle_event("open_event", %{"id" => id}, socket) do
    event = Authoring.get_event!(id)

    {:noreply,
     socket
     |> assign(selected_event: event, selected_event_id: event.id)
     |> cancel_option()
     |> reload_options(event)}
  end

  def handle_event("close_event", _params, socket) do
    {:noreply, close_event(socket)}
  end

  # ── Decision options ──────────────────────────────────────────────────

  def handle_event("new_option", %{"group" => group_id}, socket) do
    {:noreply, assign_option_form(socket, %DecisionOption{group_id: group_id}, group_id)}
  end

  def handle_event("edit_option", %{"id" => id}, socket) do
    option = Authoring.get_decision_option!(id)
    {:noreply, assign_option_form(socket, option, option.group_id)}
  end

  def handle_event("cancel_option", _params, socket) do
    {:noreply, cancel_option(socket)}
  end

  def handle_event("save_option", %{"option" => params} = raw, socket) do
    with_edit(socket, fn ->
      event = socket.assigns.selected_event
      group = Enum.find(socket.assigns.groups, &(&1.id == socket.assigns.option_group_id))
      data = socket.assigns.editing_option || %DecisionOption{}
      attrs = LocalizedForm.merge(params, data, [:text])

      result =
        if socket.assigns.editing_option,
          do: Authoring.update_decision_option(data, attrs),
          else: Authoring.create_decision_option(event, group, attrs)

      case result do
        {:ok, option} ->
          persist_labels(option, params, socket.assigns.labels)
          persist_effects(option, Map.get(raw, "effect", %{}), socket.assigns.value_index)

          {:noreply, socket |> cancel_option() |> reload() |> put_flash(:info, "Option saved.")}

        {:error, changeset} ->
          {:noreply, assign(socket, :option_form, to_form(changeset, as: :option))}
      end
    end)
  end

  def handle_event("delete_option", %{"id" => id}, socket) do
    with_edit(socket, fn ->
      id |> Authoring.get_decision_option!() |> Authoring.delete_decision_option()
      {:noreply, socket |> cancel_option() |> reload()}
    end)
  end

  # ── Labels ────────────────────────────────────────────────────────────

  def handle_event("edit_label", %{"id" => id}, socket) do
    {:noreply, assign_label_form(socket, Authoring.get_label!(id))}
  end

  def handle_event("new_label", _params, socket) do
    {:noreply, assign_label_form(socket, %Label{})}
  end

  def handle_event("save_label", %{"label" => params}, socket) do
    with_edit(socket, fn ->
      data = socket.assigns.editing_label || %Label{}
      attrs = LocalizedForm.merge(params, data, [:name])

      result =
        if socket.assigns.editing_label,
          do: Authoring.update_label(data, attrs),
          else: Authoring.create_label(socket.assigns.game, attrs)

      case result do
        {:ok, _label} ->
          {:noreply,
           socket |> assign_label_form(%Label{}) |> reload() |> put_flash(:info, "Label saved.")}

        {:error, changeset} ->
          {:noreply, assign(socket, :label_form, to_form(changeset, as: :label))}
      end
    end)
  end

  def handle_event("delete_label", %{"id" => id}, socket) do
    with_edit(socket, fn ->
      id |> Authoring.get_label!() |> Authoring.delete_label()
      {:noreply, socket |> assign_label_form(%Label{}) |> reload()}
    end)
  end

  # ── Assigns helpers ───────────────────────────────────────────────────

  defp assign_settings_form(socket, game),
    do: assign(socket, :settings_form, to_form(Authoring.change_game(game), as: :game))

  defp assign_value_form(socket, value) do
    socket
    |> assign(:editing_value, if(value.id, do: value, else: nil))
    |> assign(:value_scope, value.input_scope || :per_group)
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

  defp assign_event_form(socket, event) do
    socket
    |> assign(:editing_event, if(event.id, do: event, else: nil))
    |> assign(:event_form, to_form(Authoring.change_event(event), as: :event))
  end

  defp assign_label_form(socket, label) do
    socket
    |> assign(:editing_label, if(label.id, do: label, else: nil))
    |> assign(:label_form, to_form(Authoring.change_label(label), as: :label))
  end

  defp assign_option_form(socket, option, group_id) do
    group = Enum.find(socket.assigns.groups, &(&1.id == group_id))
    effects = if option.id, do: option.effects, else: []
    labels = if option.id, do: option.labels, else: []

    socket
    |> assign(:editing_option, if(option.id, do: option, else: nil))
    |> assign(:option_group_id, group_id)
    |> assign(:selected_group_name, (group && group.name) || %{})
    |> assign(:option_effects, Map.new(effects, &{&1.value_definition_id, &1.delta}))
    |> assign(:option_label_ids, Enum.map(labels, & &1.id))
    |> assign(:option_form, to_form(Authoring.change_decision_option(option), as: :option))
  end

  defp cancel_option(socket) do
    socket
    |> assign(:editing_option, nil)
    |> assign(:option_group_id, nil)
    |> assign(:option_effects, %{})
    |> assign(:option_label_ids, [])
    |> assign(
      :option_form,
      to_form(Authoring.change_decision_option(%DecisionOption{}), as: :option)
    )
  end

  defp close_event(socket) do
    socket
    |> assign(selected_event: nil, selected_event_id: nil, options: [])
    |> cancel_option()
  end

  # Replace the option's labels with the checked ones.
  defp persist_labels(option, params, all_labels) do
    checked = Map.get(params, "labels", [])
    labels = Enum.filter(all_labels, &(&1.id in checked))
    Authoring.set_option_labels(option, labels)
  end

  # Upsert a delta per value; a blank field clears that effect.
  defp persist_effects(option, effect_params, value_index) do
    for {value_id, raw} <- effect_params, vd = value_index[value_id], not is_nil(vd) do
      case String.trim(to_string(raw)) do
        "" -> :noop
        _ -> Authoring.set_option_effect(option, vd, to_number(raw))
      end
    end
  end

  defp reload(socket) do
    game = socket.assigns.game
    groups = Authoring.list_groups(game)
    value_definitions = Authoring.list_value_definitions(game)

    initials =
      for group <- groups, giv <- Authoring.list_group_initial_values(group), into: %{} do
        {{giv.group_id, giv.value_definition_id}, giv.initial}
      end

    socket =
      assign(socket,
        value_definitions: value_definitions,
        value_index: Map.new(value_definitions, &{&1.id, &1}),
        groups: groups,
        initials: initials,
        events: Authoring.list_events(game),
        labels: Authoring.list_labels(game)
      )

    # Keep an opened event's options in sync after edits.
    if socket.assigns.selected_event do
      reload_options(socket, socket.assigns.selected_event)
    else
      socket
    end
  end

  defp reload_options(socket, event) do
    assign(socket, options: Authoring.list_decision_options(event))
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

  defp options_for_group(options, group_id),
    do: Enum.filter(options, &(&1.group_id == group_id))

  defp fmt_deadline(nil), do: "—"
  defp fmt_deadline(seconds), do: "#{seconds}s"

  defp fmt_effects([], _index, _locale), do: ""

  defp fmt_effects(effects, index, locale) do
    effects
    |> Enum.map(fn e ->
      name =
        case index[e.value_definition_id] do
          nil -> "?"
          vd -> I18n.t!(vd.name, locale, default: vd.key)
        end

      sign = if e.delta >= 0, do: "+", else: ""
      "#{name} #{sign}#{fmt_num(e.delta)}"
    end)
    |> Enum.join(", ")
  end

  defp label_class(:neutral), do: "badge-neutral"
  defp label_class(:primary), do: "badge-primary"
  defp label_class(:secondary), do: "badge-secondary"
  defp label_class(:accent), do: "badge-accent"
  defp label_class(:info), do: "badge-info"
  defp label_class(:success), do: "badge-success"
  defp label_class(:warning), do: "badge-warning"
  defp label_class(:error), do: "badge-error"
  defp label_class(_), do: "badge-neutral"

  def sections, do: @sections
end
