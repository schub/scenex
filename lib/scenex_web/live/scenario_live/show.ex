defmodule ScenexWeb.ScenarioLive.Show do
  @moduledoc """
  The scenario-definition editor. Sections: Settings, Values, Groups, Initial values,
  Timeline, Labels, Endings. Content is edited one working locale at a time;
  authorization comes from the Authoring context (owners/authors edit, else
  read-only). The options panel is kind-aware: events edit per-group options
  with own-value effects; elections and sidequests edit options with an
  outcome matrix (per-group deltas).
  """
  use ScenexWeb, :live_view

  alias Scenex.Authoring
  alias Scenex.Authoring.{DecisionOption, Ending, TimelineElement, Group, Label, ValueDimension}
  alias Scenex.I18n
  alias ScenexWeb.LocalizedForm

  @sections ~w(settings values groups initial timeline labels endings)a
  @locale_choices Scenex.I18n.locales()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {I18n.t!(@scenario.name, @locale, default: "Untitled scenario")}
        <:subtitle>
          <span class="badge badge-sm">{@scenario.visibility}</span>
          <span :if={not @can_edit?} class="badge badge-sm badge-warning">read-only ({@role})</span>
        </:subtitle>
        <:actions>
          <.link
            navigate={~p"/scenarios/#{@scenario.id}/simulate"}
            class="btn btn-sm btn-accent btn-soft"
          >
            Dry run
          </.link>
          <.link
            :if={@can_edit?}
            navigate={~p"/scenarios/#{@scenario.id}/sessions"}
            class="btn btn-sm btn-primary btn-soft"
          >
            Sessions
          </.link>
          <.link navigate={~p"/scenarios"} class="btn btn-sm btn-ghost">← All scenarios</.link>
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
          :for={s <- sections(@role)}
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
              name={"scenario[name][#{@locale}]"}
              value={LocalizedForm.value(@settings_form, :name, @locale)}
              label={"Name (#{@locale})"}
            />
            <.input
              type="text"
              name={"scenario[tagline][#{@locale}]"}
              value={LocalizedForm.value(@settings_form, :tagline, @locale)}
              label={"Tagline (#{@locale}, one line)"}
            />
            <.input
              type="textarea"
              name={"scenario[description][#{@locale}]"}
              value={LocalizedForm.value(@settings_form, :description, @locale)}
              label={"Description (#{@locale}, Markdown)"}
            />
            <.input
              type="textarea"
              name={"scenario[director_notes][#{@locale}]"}
              value={LocalizedForm.value(@settings_form, :director_notes, @locale)}
              label={"Director's notes (#{@locale}, GM/performers only)"}
            />
            <.input
              field={@settings_form[:visibility]}
              type="select"
              label="Visibility"
              options={[{"Draft", :draft}, {"Invite only", :invite_only}, {"Published", :published}]}
            />
            <.input field={@settings_form[:source_locale]} label="Source locale" />
            <.input
              field={@settings_form[:change_highlight_seconds]}
              type="number"
              min="0"
              label="Change highlight (seconds a value change stays marked on the boards)"
            />
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
                <tr :for={v <- @value_dimensions}>
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
                <tr :if={@value_dimensions == []}>
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
                  name={"value_dimension[name][#{@locale}]"}
                  value={LocalizedForm.value(@value_form, :name, @locale)}
                  label={"Name (#{@locale})"}
                />
                <.input field={@value_form[:aggregation]} label="Aggregation formula" />
                <div class="sm:col-span-2">
                  <.input
                    type="textarea"
                    name={"value_dimension[description][#{@locale}]"}
                    value={LocalizedForm.value(@value_form, :description, @locale)}
                    label={"Description (#{@locale}, Markdown)"}
                  />
                </div>
                <div class="sm:col-span-2">
                  <.input
                    type="textarea"
                    name={"value_dimension[director_notes][#{@locale}]"}
                    value={LocalizedForm.value(@value_form, :director_notes, @locale)}
                    label={"Director's notes (#{@locale}, GM only)"}
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
                <div class="sm:col-span-2">
                  <.input
                    type="textarea"
                    name={"group[director_notes][#{@locale}]"}
                    value={LocalizedForm.value(@group_form, :director_notes, @locale)}
                    label={"Director's notes (#{@locale}, GM only)"}
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
          <% pg = per_group_values(@value_dimensions) %>
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
        <div :if={@section == :timeline} class="space-y-6">
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
                <tr
                  :for={e <- @timeline_elements}
                  class={e.id == @selected_timeline_element_id && "bg-base-200"}
                >
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
                      phx-click="delete_timeline_element"
                      phx-value-id={e.id}
                      data-confirm="Delete this timeline element and all its options?"
                      class="btn btn-xs btn-error btn-soft"
                    >
                      Delete
                    </button>
                  </td>
                </tr>
                <tr :if={@timeline_elements == []}>
                  <td colspan="6" class="opacity-70">No timeline elements yet.</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@can_edit?} class="card bg-base-200">
            <div class="card-body">
              <h3 class="font-semibold">
                {if @editing_event, do: "Edit element", else: "New element"}
              </h3>
              <.form for={@event_form} phx-submit="save_event" class="grid gap-3 sm:grid-cols-2">
                <.input field={@event_form[:handle]} label="Handle (internal)" />
                <.input
                  type="text"
                  name={"timeline_element[title][#{@locale}]"}
                  value={LocalizedForm.value(@event_form, :title, @locale)}
                  label={"Title (#{@locale})"}
                />
                <.input field={@event_form[:position]} type="number" label="Position" />
                <div class="sm:col-span-2">
                  <.input
                    type="textarea"
                    name={"timeline_element[narrative][#{@locale}]"}
                    value={LocalizedForm.value(@event_form, :narrative, @locale)}
                    label={"Narrative (#{@locale}, Markdown)"}
                  />
                </div>
                <div class="sm:col-span-2">
                  <.input
                    type="textarea"
                    name={"timeline_element[director_notes][#{@locale}]"}
                    value={LocalizedForm.value(@event_form, :director_notes, @locale)}
                    label={"Director's notes (#{@locale}, GM only)"}
                  />
                </div>
                <.input
                  field={@event_form[:kind]}
                  type="select"
                  label="Kind"
                  options={Enum.map(TimelineElement.kinds(), &{Phoenix.Naming.humanize(&1), &1})}
                />
                <.input
                  field={@event_form[:deadline_seconds]}
                  type="number"
                  label="Deadline (seconds, optional)"
                />
                <div class="flex gap-2 sm:col-span-2">
                  <.button variant="primary">Save element</.button>
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

          <%!-- Options for the opened timeline_element --%>
          <div
            :if={@selected_timeline_element}
            class="rounded-box border border-base-300 p-4 space-y-6"
          >
            <div class="flex items-center justify-between">
              <h3 class="text-lg font-semibold">
                Options — {I18n.t!(@selected_timeline_element.title, @locale, default: "element")}
                <span class="badge badge-sm ml-2">{@selected_timeline_element.kind}</span>
              </h3>
              <button type="button" phx-click="close_event" class="btn btn-xs btn-ghost">
                Close
              </button>
            </div>

            <%!-- Event: one option set per group --%>
            <div :if={@selected_timeline_element.kind == :event} class="space-y-6">
              <p :if={@groups == []} class="opacity-70">Add at least one group first.</p>

              <div :for={group <- @groups} class="space-y-2">
                <div class="flex items-center justify-between">
                  <h4 class="font-medium">{I18n.t!(group.name, @locale, default: group.handle)}</h4>
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
                  <.option_row
                    :for={o <- options_for_group(@options, group.id)}
                    option={o}
                    locale={@locale}
                    value_index={@value_index}
                    groups_index={@groups_index}
                    can_edit?={@can_edit?}
                  />
                  <li :if={options_for_group(@options, group.id) == []} class="text-xs opacity-60">
                    No options for this group yet.
                  </li>
                </ul>
              </div>
            </div>

            <%!-- Election: one ballot for the whole room --%>
            <div :if={@selected_timeline_element.kind == :election} class="space-y-2">
              <div class="flex items-center justify-between">
                <h4 class="font-medium">Ballot options (all players vote; majority wins)</h4>
                <button :if={@can_edit?} type="button" phx-click="new_option" class="btn btn-xs">
                  + Option
                </button>
              </div>

              <ul class="space-y-1">
                <.option_row
                  :for={o <- @options}
                  option={o}
                  locale={@locale}
                  value_index={@value_index}
                  groups_index={@groups_index}
                  can_edit?={@can_edit?}
                />
                <li :if={@options == []} class="text-xs opacity-60">No ballot options yet.</li>
              </ul>
            </div>

            <%!-- Sidequest: success / failure outcome bundles --%>
            <div :if={@selected_timeline_element.kind == :sidequest} class="space-y-4">
              <div :for={outcome <- [:success, :failure]} class="space-y-2">
                <div class="flex items-center justify-between">
                  <h4 class="font-medium">{Phoenix.Naming.humanize(outcome)}</h4>
                  <button
                    :if={@can_edit? and outcome_option(@options, outcome) == nil}
                    type="button"
                    phx-click="new_outcome"
                    phx-value-outcome={outcome}
                    class="btn btn-xs"
                  >
                    + Define {outcome}
                  </button>
                </div>

                <ul class="space-y-1">
                  <.option_row
                    :if={outcome_option(@options, outcome)}
                    option={outcome_option(@options, outcome)}
                    locale={@locale}
                    value_index={@value_index}
                    groups_index={@groups_index}
                    can_edit?={@can_edit?}
                  />
                  <li :if={outcome_option(@options, outcome) == nil} class="text-xs opacity-60">
                    Not defined yet{if outcome == :failure,
                      do: " (optional — failing may simply cost the opportunity)"}.
                  </li>
                </ul>
              </div>
            </div>

            <%!-- Option editor --%>
            <div :if={@can_edit? and @option_editor?} class="card bg-base-100 border border-base-300">
              <div class="card-body">
                <h4 class="font-semibold">
                  {if @editing_option, do: "Edit option", else: "New option"}
                  <span :if={@option_outcome} class="badge badge-sm ml-1">{@option_outcome}</span>
                </h4>
                <.form for={@option_form} phx-submit="save_option" class="space-y-3">
                  <input
                    :if={@option_outcome}
                    type="hidden"
                    name="option[outcome]"
                    value={@option_outcome}
                  />
                  <.input field={@option_form[:handle]} label="Handle (internal)" />
                  <.input
                    type="text"
                    name={"option[text][#{@locale}]"}
                    value={LocalizedForm.value(@option_form, :text, @locale)}
                    label={"Option text (#{@locale})"}
                  />
                  <.input
                    type="textarea"
                    name={"option[director_notes][#{@locale}]"}
                    value={LocalizedForm.value(@option_form, :director_notes, @locale)}
                    label={"Director's notes (#{@locale}, GM only)"}
                  />
                  <div class="grid gap-3 sm:grid-cols-2">
                    <.input field={@option_form[:position]} type="number" label="Position" />
                    <label
                      :if={@selected_timeline_element.kind != :sidequest}
                      class="flex items-center gap-2 self-end pb-2"
                    >
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

                  <.input
                    :if={@selected_timeline_element.kind != :sidequest}
                    field={@option_form[:condition]}
                    label={condition_label(@selected_timeline_element.kind)}
                    placeholder={condition_placeholder(@selected_timeline_element.kind)}
                  />

                  <fieldset
                    :if={@selected_timeline_element.kind != :sidequest and @labels != []}
                    class="fieldset"
                  >
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

                  <%!-- Event: effects on the deciding group's own values --%>
                  <fieldset :if={@selected_timeline_element.kind == :event} class="fieldset">
                    <legend class="fieldset-legend">
                      Effects on {I18n.t!(@selected_group_name, @locale, default: "this group")}'s values
                    </legend>
                    <p :if={per_group_values(@value_dimensions) == []} class="text-xs opacity-60">
                      Add per-group values first.
                    </p>
                    <div class="grid gap-2 sm:grid-cols-2">
                      <label
                        :for={v <- per_group_values(@value_dimensions)}
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
                    <p class="text-xs opacity-60">Blank = no effect.</p>
                  </fieldset>

                  <%!-- Election/sidequest: the outcome matrix --%>
                  <fieldset :if={@selected_timeline_element.kind != :event} class="fieldset">
                    <legend class="fieldset-legend">Outcome matrix (per-group deltas)</legend>
                    <p
                      :if={per_group_values(@value_dimensions) == [] or @groups == []}
                      class="text-xs opacity-60"
                    >
                      Add per-group values and groups first.
                    </p>
                    <div class="overflow-x-auto">
                      <table class="table table-sm">
                        <thead>
                          <tr>
                            <th>Group \ Value</th>
                            <th :for={v <- per_group_values(@value_dimensions)}>
                              {I18n.t!(v.name, @locale, default: v.key)}
                            </th>
                          </tr>
                        </thead>
                        <tbody>
                          <tr :for={g <- @groups}>
                            <td class="font-medium">{I18n.t!(g.name, @locale, default: g.handle)}</td>
                            <td :for={v <- per_group_values(@value_dimensions)}>
                              <input
                                type="number"
                                step="any"
                                name={"matrix[#{g.id}][#{v.id}]"}
                                value={Map.get(@option_matrix, {g.id, v.id}, "")}
                                placeholder="0"
                                class="input input-bordered input-sm w-20"
                              />
                            </td>
                          </tr>
                        </tbody>
                      </table>
                    </div>
                    <p class="text-xs opacity-60">Blank = no effect on that group.</p>
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
                <div class="sm:col-span-2">
                  <.input
                    type="textarea"
                    name={"label[director_notes][#{@locale}]"}
                    value={LocalizedForm.value(@label_form, :director_notes, @locale)}
                    label={"Director's notes (#{@locale}, GM only)"}
                  />
                </div>
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

        <%!-- Endings --%>
        <div :if={@section == :endings} class="space-y-6">
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>Handle</th>
                  <th>Title ({@locale})</th>
                  <th>Condition</th>
                  <th>Priority</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={e <- @endings}>
                  <td class="font-medium">{e.handle}</td>
                  <td>{I18n.t!(e.title, @locale, default: "—")}</td>
                  <td class="font-mono text-xs">{e.condition || "—"}</td>
                  <td>{e.priority}</td>
                  <td class="text-right whitespace-nowrap">
                    <button
                      :if={@can_edit?}
                      type="button"
                      phx-click="edit_ending"
                      phx-value-id={e.id}
                      class="btn btn-xs"
                    >
                      Edit
                    </button>
                    <button
                      :if={@can_edit?}
                      type="button"
                      phx-click="delete_ending"
                      phx-value-id={e.id}
                      data-confirm="Delete this ending?"
                      class="btn btn-xs btn-error btn-soft"
                    >
                      Delete
                    </button>
                  </td>
                </tr>
                <tr :if={@endings == []}>
                  <td colspan="5" class="opacity-70">
                    No endings yet. Endings are the authored final scenes — the final global
                    values recommend which ones fit, and the GM picks.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@can_edit?} class="card bg-base-200">
            <div class="card-body">
              <h3 class="font-semibold">
                {if @editing_ending, do: "Edit ending", else: "New ending"}
              </h3>
              <.form for={@ending_form} phx-submit="save_ending" class="grid gap-3 sm:grid-cols-2">
                <.input field={@ending_form[:handle]} label="Handle (internal)" />
                <.input
                  type="text"
                  name={"ending[title][#{@locale}]"}
                  value={LocalizedForm.value(@ending_form, :title, @locale)}
                  label={"Title (#{@locale})"}
                />
                <div class="sm:col-span-2">
                  <.input
                    type="textarea"
                    name={"ending[narrative][#{@locale}]"}
                    value={LocalizedForm.value(@ending_form, :narrative, @locale)}
                    label={"Narrative (#{@locale}, Markdown)"}
                  />
                </div>
                <div class="sm:col-span-2">
                  <.input
                    type="textarea"
                    name={"ending[director_notes][#{@locale}]"}
                    value={LocalizedForm.value(@ending_form, :director_notes, @locale)}
                    label={"Director's notes (#{@locale}, GM only)"}
                  />
                </div>
                <.input
                  field={@ending_form[:condition]}
                  label="Condition (optional — global(key) only)"
                  placeholder="e.g. global(risk) >= 8"
                />
                <.input field={@ending_form[:priority]} type="number" label="Priority (higher first)" />
                <div class="flex gap-2 sm:col-span-2">
                  <.button variant="primary">Save ending</.button>
                  <button
                    :if={@editing_ending}
                    type="button"
                    phx-click="new_ending"
                    class="btn btn-ghost"
                  >
                    Cancel
                  </button>
                </div>
              </.form>
            </div>
          </div>
        </div>

        <%!-- Members (owner only) --%>
        <div :if={@section == :members && @role == :owner} class="space-y-6">
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>Email</th>
                  <th>Role</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={m <- @members}>
                  <td>{m.user.email}</td>
                  <td><span class="badge badge-sm">{m.role}</span></td>
                  <td class="text-right">
                    <button
                      :if={m.role != :owner}
                      type="button"
                      phx-click="remove_member"
                      phx-value-id={m.id}
                      data-confirm={"Remove #{m.user.email} from this scenario?"}
                      class="btn btn-xs btn-error btn-soft"
                    >
                      Remove
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@pending_invitations != []}>
            <h3 class="mb-2 font-semibold">Pending invitations</h3>
            <div class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr>
                    <th>Email</th>
                    <th>Role</th>
                    <th>Invited</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={i <- @pending_invitations}>
                    <td>{i.email}</td>
                    <td><span class="badge badge-sm">{i.role}</span></td>
                    <td class="text-sm opacity-70">
                      {Calendar.strftime(i.inserted_at, "%Y-%m-%d")}
                    </td>
                    <td class="text-right">
                      <button
                        type="button"
                        phx-click="revoke_invitation"
                        phx-value-id={i.id}
                        data-confirm={"Revoke the invitation for #{i.email}?"}
                        class="btn btn-xs btn-error btn-soft"
                      >
                        Revoke
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <div class="card bg-base-200">
            <div class="card-body">
              <h3 class="font-semibold">Invite someone</h3>
              <p class="text-sm opacity-70">
                If they already have an account they're added right away; otherwise they
                receive an email with a link to create their account and join.
              </p>
              <form phx-submit="invite_member" class="flex flex-wrap items-end gap-3">
                <div class="grow">
                  <.input
                    type="email"
                    name="invite[email]"
                    value=""
                    label="Email"
                    placeholder="person@example.com"
                    required
                  />
                </div>
                <.input
                  type="select"
                  name="invite[role]"
                  value="author"
                  label="Role"
                  options={[{"Author", "author"}, {"Viewer", "viewer"}]}
                />
                <.button variant="primary">Invite</.button>
              </form>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Authoring.get_scenario_for_user(id, socket.assigns.current_scope.user) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Scenario not found.")
         |> push_navigate(to: ~p"/scenarios")}

      {scenario, role} ->
        {:ok,
         socket
         |> assign(
           scenario: scenario,
           role: role,
           can_edit?: role in [:owner, :author],
           section: :settings,
           locale: scenario.source_locale,
           locales: Enum.uniq([scenario.source_locale | @locale_choices]),
           page_title: I18n.t!(scenario.name, scenario.source_locale, default: "Scenario")
         )
         |> assign(
           selected_timeline_element: nil,
           selected_timeline_element_id: nil,
           options: [],
           option_editor?: false,
           option_group_id: nil,
           option_outcome: nil,
           editing_option: nil,
           option_effects: %{},
           option_matrix: %{},
           option_label_ids: [],
           selected_group_name: %{}
         )
         |> assign_settings_form(scenario)
         |> assign_value_form(%ValueDimension{})
         |> assign_group_form(%Group{})
         |> assign_event_form(%TimelineElement{})
         |> assign_label_form(%Label{})
         |> assign_ending_form(%Ending{})
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

  def handle_event("save_settings", %{"scenario" => params}, socket) do
    with_edit(socket, fn ->
      attrs =
        LocalizedForm.merge(params, socket.assigns.scenario, [
          :name,
          :tagline,
          :description,
          :director_notes
        ])

      case Authoring.update_scenario(socket.assigns.scenario, attrs) do
        {:ok, scenario} ->
          {:noreply,
           socket
           |> assign(:scenario, scenario)
           |> assign_settings_form(scenario)
           |> put_flash(:info, "Settings saved.")}

        {:error, changeset} ->
          {:noreply, assign(socket, :settings_form, to_form(changeset, as: :scenario))}
      end
    end)
  end

  # ── Members (owner only) ──────────────────────────────────────────────

  def handle_event(
        "invite_member",
        %{"invite" => %{"email" => email, "role" => role}},
        %{assigns: %{role: :owner}} = socket
      ) do
    role = if role == "viewer", do: :viewer, else: :author
    inviter = socket.assigns.current_scope.user

    socket =
      case Authoring.invite_member(
             socket.assigns.scenario,
             inviter,
             email,
             role,
             &url(~p"/invites/#{&1}")
           ) do
        {:ok, :member_added} ->
          put_flash(socket, :info, "#{email} already had an account and was added as #{role}.")

        {:ok, :invitation_sent} ->
          put_flash(socket, :info, "Invitation sent to #{email}.")

        {:error, :already_member} ->
          put_flash(socket, :error, "#{email} is already a member of this scenario.")

        {:error, %Ecto.Changeset{} = changeset} ->
          {field, {msg, _}} = List.first(changeset.errors)
          put_flash(socket, :error, "Could not invite: #{field} #{msg}.")
      end

    {:noreply, reload_members(socket)}
  end

  def handle_event("remove_member", %{"id" => id}, %{assigns: %{role: :owner}} = socket) do
    membership = Enum.find(socket.assigns.members, &(&1.id == id))

    socket =
      if membership && membership.role != :owner do
        {:ok, _} = Authoring.remove_member(membership)
        put_flash(socket, :info, "#{membership.user.email} removed.")
      else
        socket
      end

    {:noreply, reload_members(socket)}
  end

  def handle_event("revoke_invitation", %{"id" => id}, %{assigns: %{role: :owner}} = socket) do
    invitation = Enum.find(socket.assigns.pending_invitations, &(&1.id == id))

    socket =
      if invitation do
        {:ok, _} = Authoring.revoke_invitation(invitation)
        put_flash(socket, :info, "Invitation for #{invitation.email} revoked.")
      else
        socket
      end

    {:noreply, reload_members(socket)}
  end

  # ── Values ────────────────────────────────────────────────────────────

  def handle_event("edit_value", %{"id" => id}, socket) do
    {:noreply, assign_value_form(socket, Authoring.get_value_dimension!(id))}
  end

  def handle_event("new_value", _params, socket) do
    {:noreply, assign_value_form(socket, %ValueDimension{})}
  end

  # Live-track the selected scope so bounds fields can hide for per-participant.
  # Rebuild the form from params so typed values survive the re-render.
  def handle_event("value_form_changed", %{"value_dimension" => params}, socket) do
    data = socket.assigns.editing_value || %ValueDimension{}
    attrs = LocalizedForm.merge(params, data, [:name, :description, :director_notes])
    scope = if params["input_scope"] == "per_participant", do: :per_participant, else: :per_group

    {:noreply,
     socket
     |> assign(:value_scope, scope)
     |> assign(
       :value_form,
       to_form(Authoring.change_value_dimension(data, attrs), as: :value_dimension)
     )}
  end

  def handle_event("save_value", %{"value_dimension" => params}, socket) do
    with_edit(socket, fn ->
      data = socket.assigns.editing_value || %ValueDimension{}
      attrs = LocalizedForm.merge(params, data, [:name, :description, :director_notes])

      result =
        if socket.assigns.editing_value,
          do: Authoring.update_value_dimension(data, attrs),
          else: Authoring.create_value_dimension(socket.assigns.scenario, attrs)

      case result do
        {:ok, _vd} ->
          {:noreply,
           socket
           |> assign_value_form(%ValueDimension{})
           |> reload()
           |> put_flash(:info, "Value saved.")}

        {:error, changeset} ->
          {:noreply, assign(socket, :value_form, to_form(changeset, as: :value_dimension))}
      end
    end)
  end

  def handle_event("delete_value", %{"id" => id}, socket) do
    with_edit(socket, fn ->
      id |> Authoring.get_value_dimension!() |> Authoring.delete_value_dimension()
      {:noreply, socket |> assign_value_form(%ValueDimension{}) |> reload()}
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
      attrs = LocalizedForm.merge(params, data, [:name, :description, :director_notes])

      result =
        if socket.assigns.editing_group,
          do: Authoring.update_group(data, attrs),
          else: Authoring.create_group(socket.assigns.scenario, attrs)

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
      values = Map.new(socket.assigns.value_dimensions, &{&1.id, &1})

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
    {:noreply, assign_event_form(socket, Authoring.get_timeline_element!(id))}
  end

  def handle_event("new_event", _params, socket) do
    {:noreply, assign_event_form(socket, %TimelineElement{})}
  end

  def handle_event("save_event", %{"timeline_element" => params}, socket) do
    with_edit(socket, fn ->
      data = socket.assigns.editing_event || %TimelineElement{}
      attrs = LocalizedForm.merge(params, data, [:title, :narrative, :director_notes])

      result =
        if socket.assigns.editing_event,
          do: Authoring.update_timeline_element(data, attrs),
          else: Authoring.create_timeline_element(socket.assigns.scenario, attrs)

      case result do
        {:ok, _event} ->
          {:noreply,
           socket
           |> assign_event_form(%TimelineElement{})
           |> reload()
           |> put_flash(:info, "TimelineElement saved.")}

        {:error, changeset} ->
          {:noreply, assign(socket, :event_form, to_form(changeset, as: :timeline_element))}
      end
    end)
  end

  def handle_event("delete_timeline_element", %{"id" => id}, socket) do
    with_edit(socket, fn ->
      timeline_element = Authoring.get_timeline_element!(id)
      Authoring.delete_timeline_element(timeline_element)

      socket =
        if socket.assigns.selected_timeline_element_id == id,
          do: close_event(socket),
          else: socket

      {:noreply, socket |> assign_event_form(%TimelineElement{}) |> reload()}
    end)
  end

  def handle_event("open_event", %{"id" => id}, socket) do
    timeline_element = Authoring.get_timeline_element!(id)

    {:noreply,
     socket
     |> assign(
       selected_timeline_element: timeline_element,
       selected_timeline_element_id: timeline_element.id
     )
     |> cancel_option()
     |> reload_options(timeline_element)}
  end

  def handle_event("close_event", _params, socket) do
    {:noreply, close_event(socket)}
  end

  # ── Decision options ──────────────────────────────────────────────────

  def handle_event("new_option", %{"group" => group_id}, socket) do
    {:noreply, assign_option_form(socket, %DecisionOption{group_id: group_id}, group_id)}
  end

  # Election options belong to the whole room — no group.
  def handle_event("new_option", _params, socket) do
    {:noreply, assign_option_form(socket, %DecisionOption{}, nil)}
  end

  # Sidequest outcome bundles: success or failure, group bound at adjudication.
  def handle_event("new_outcome", %{"outcome" => outcome}, socket) do
    outcome = String.to_existing_atom(outcome)
    {:noreply, assign_option_form(socket, %DecisionOption{outcome: outcome}, nil)}
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
      timeline_element = socket.assigns.selected_timeline_element
      group = Enum.find(socket.assigns.groups, &(&1.id == socket.assigns.option_group_id))
      data = socket.assigns.editing_option || %DecisionOption{}
      attrs = LocalizedForm.merge(params, data, [:text, :director_notes])

      result =
        if socket.assigns.editing_option,
          do: Authoring.update_decision_option(data, attrs),
          else: Authoring.create_decision_option(timeline_element, group, attrs)

      case result do
        {:ok, option} ->
          if timeline_element.kind != :sidequest do
            persist_labels(option, params, socket.assigns.labels)
          end

          case timeline_element.kind do
            :event ->
              persist_effects(option, Map.get(raw, "effect", %{}), socket.assigns.value_index)

            _matrix_kind ->
              persist_matrix(
                option,
                Map.get(raw, "matrix", %{}),
                socket.assigns.value_index,
                socket.assigns.groups_index
              )
          end

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
      attrs = LocalizedForm.merge(params, data, [:name, :director_notes])

      result =
        if socket.assigns.editing_label,
          do: Authoring.update_label(data, attrs),
          else: Authoring.create_label(socket.assigns.scenario, attrs)

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

  # ── Endings ───────────────────────────────────────────────────────────

  def handle_event("edit_ending", %{"id" => id}, socket) do
    {:noreply, assign_ending_form(socket, Authoring.get_ending!(id))}
  end

  def handle_event("new_ending", _params, socket) do
    {:noreply, assign_ending_form(socket, %Ending{})}
  end

  def handle_event("save_ending", %{"ending" => params}, socket) do
    with_edit(socket, fn ->
      data = socket.assigns.editing_ending || %Ending{}
      attrs = LocalizedForm.merge(params, data, [:title, :narrative, :director_notes])

      result =
        if socket.assigns.editing_ending,
          do: Authoring.update_ending(data, attrs),
          else: Authoring.create_ending(socket.assigns.scenario, attrs)

      case result do
        {:ok, _ending} ->
          {:noreply,
           socket
           |> assign_ending_form(%Ending{})
           |> reload()
           |> put_flash(:info, "Ending saved.")}

        {:error, changeset} ->
          {:noreply, assign(socket, :ending_form, to_form(changeset, as: :ending))}
      end
    end)
  end

  def handle_event("delete_ending", %{"id" => id}, socket) do
    with_edit(socket, fn ->
      id |> Authoring.get_ending!() |> Authoring.delete_ending()
      {:noreply, socket |> assign_ending_form(%Ending{}) |> reload()}
    end)
  end

  # ── Assigns helpers ───────────────────────────────────────────────────

  defp assign_settings_form(socket, scenario),
    do:
      assign(socket, :settings_form, to_form(Authoring.change_scenario(scenario), as: :scenario))

  defp assign_value_form(socket, value) do
    socket
    |> assign(:editing_value, if(value.id, do: value, else: nil))
    |> assign(:value_scope, value.input_scope || :per_group)
    |> assign(
      :value_form,
      to_form(Authoring.change_value_dimension(value), as: :value_dimension)
    )
  end

  defp assign_group_form(socket, group) do
    socket
    |> assign(:editing_group, if(group.id, do: group, else: nil))
    |> assign(:group_form, to_form(Authoring.change_group(group), as: :group))
  end

  defp assign_event_form(socket, timeline_element) do
    socket
    |> assign(:editing_event, if(timeline_element.id, do: timeline_element, else: nil))
    |> assign(
      :event_form,
      to_form(Authoring.change_timeline_element(timeline_element), as: :timeline_element)
    )
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
    {matrix_cells, own_cells} = Enum.split_with(effects, & &1.group_id)

    socket
    |> assign(:editing_option, if(option.id, do: option, else: nil))
    |> assign(:option_editor?, true)
    |> assign(:option_group_id, group_id)
    |> assign(:option_outcome, option.outcome)
    |> assign(:selected_group_name, (group && group.name) || %{})
    |> assign(:option_effects, Map.new(own_cells, &{&1.value_dimension_id, &1.delta}))
    |> assign(
      :option_matrix,
      Map.new(matrix_cells, &{{&1.group_id, &1.value_dimension_id}, &1.delta})
    )
    |> assign(:option_label_ids, Enum.map(labels, & &1.id))
    |> assign(
      :option_form,
      to_form(
        Authoring.change_decision_option(option, %{}, socket.assigns.selected_timeline_element),
        as: :option
      )
    )
  end

  defp cancel_option(socket) do
    socket
    |> assign(:editing_option, nil)
    |> assign(:option_editor?, false)
    |> assign(:option_group_id, nil)
    |> assign(:option_outcome, nil)
    |> assign(:option_effects, %{})
    |> assign(:option_matrix, %{})
    |> assign(:option_label_ids, [])
    |> assign(
      :option_form,
      to_form(Authoring.change_decision_option(%DecisionOption{}), as: :option)
    )
  end

  defp assign_ending_form(socket, ending) do
    socket
    |> assign(:editing_ending, if(ending.id, do: ending, else: nil))
    |> assign(:ending_form, to_form(Authoring.change_ending(ending), as: :ending))
  end

  defp close_event(socket) do
    socket
    |> assign(selected_timeline_element: nil, selected_timeline_element_id: nil, options: [])
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
        "" -> Authoring.delete_option_effect(option, vd)
        _ -> Authoring.set_option_effect(option, vd, to_number(raw))
      end
    end
  end

  # Upsert the outcome matrix (group × value → delta); blank clears the cell.
  defp persist_matrix(option, matrix_params, value_index, groups_index) do
    for {group_id, cells} <- matrix_params,
        group = groups_index[group_id],
        not is_nil(group),
        {value_id, raw} <- cells,
        vd = value_index[value_id],
        not is_nil(vd) do
      case String.trim(to_string(raw)) do
        "" -> Authoring.delete_option_effect(option, vd, group)
        _ -> Authoring.set_option_effect(option, vd, group, to_number(raw))
      end
    end
  end

  defp reload(socket) do
    scenario = socket.assigns.scenario
    groups = Authoring.list_groups(scenario)
    value_dimensions = Authoring.list_value_dimensions(scenario)

    initials =
      for group <- groups, giv <- Authoring.list_group_initial_values(group), into: %{} do
        {{giv.group_id, giv.value_dimension_id}, giv.initial}
      end

    socket =
      assign(socket,
        value_dimensions: value_dimensions,
        value_index: Map.new(value_dimensions, &{&1.id, &1}),
        groups: groups,
        groups_index: Map.new(groups, &{&1.id, &1}),
        initials: initials,
        timeline_elements: Authoring.list_timeline_elements(scenario),
        labels: Authoring.list_labels(scenario),
        endings: Authoring.list_endings(scenario)
      )
      |> reload_members()

    # Keep an opened timeline_element's options in sync after edits.
    if socket.assigns.selected_timeline_element do
      reload_options(socket, socket.assigns.selected_timeline_element)
    else
      socket
    end
  end

  defp reload_options(socket, timeline_element) do
    assign(socket, options: Authoring.list_decision_options(timeline_element))
  end

  defp with_edit(socket, fun) do
    if socket.assigns.can_edit?,
      do: fun.(),
      else: {:noreply, put_flash(socket, :error, "This scenario is read-only for you.")}
  end

  defp to_number(raw) when is_binary(raw) do
    case Float.parse(String.trim(raw)) do
      {number, _rest} -> number
      :error -> 0.0
    end
  end

  defp to_number(_), do: 0.0

  defp per_group_values(value_dimensions),
    do: Enum.filter(value_dimensions, &(&1.input_scope == :per_group))

  defp fmt_range(%{min: min, max: max}) do
    if is_nil(min) and is_nil(max), do: "—", else: "#{fmt_num(min)}–#{fmt_num(max)}"
  end

  defp fmt_num(nil), do: "∗"
  defp fmt_num(number), do: to_string(number)

  defp options_for_group(options, group_id),
    do: Enum.filter(options, &(&1.group_id == group_id))

  defp fmt_deadline(nil), do: "—"
  defp fmt_deadline(seconds), do: "#{seconds}s"

  defp fmt_effects([], _value_index, _groups_index, _locale), do: ""

  defp fmt_effects(effects, value_index, groups_index, locale) do
    Enum.map_join(effects, ", ", fn e ->
      name =
        case value_index[e.value_dimension_id] do
          nil -> "?"
          vd -> I18n.t!(vd.name, locale, default: vd.key)
        end

      prefix =
        case e.group_id && groups_index[e.group_id] do
          nil -> ""
          g -> I18n.t!(g.name, locale, default: g.handle) <> ": "
        end

      sign = if e.delta >= 0, do: "+", else: ""
      "#{prefix}#{name} #{sign}#{fmt_num(e.delta)}"
    end)
  end

  defp outcome_option(options, outcome), do: Enum.find(options, &(&1.outcome == outcome))

  defp condition_label(:election), do: "Condition (optional gate — global(key) only)"
  defp condition_label(_kind), do: "Condition (optional gate — self(key), global(key))"

  defp condition_placeholder(:election), do: "e.g. global(risk) >= 7"
  defp condition_placeholder(_kind), do: "e.g. self(resources) >= 3"

  attr :option, :map, required: true
  attr :locale, :string, required: true
  attr :value_index, :map, required: true
  attr :groups_index, :map, required: true
  attr :can_edit?, :boolean, required: true

  defp option_row(assigns) do
    ~H"""
    <li class="flex items-center justify-between gap-2 rounded bg-base-200 px-3 py-2">
      <div class="min-w-0">
        <span class="text-sm font-medium">{@option.handle}</span>
        <span class="text-sm opacity-70">— {I18n.t!(@option.text, @locale, default: "—")}</span>
        <span :if={@option.is_default} class="badge badge-xs badge-info ml-1">default</span>
        <span :if={@option.condition} class="badge badge-xs badge-warning ml-1 font-mono">
          {@option.condition}
        </span>
        <span :for={l <- @option.labels} class={["badge badge-xs ml-1", label_class(l.color)]}>
          {I18n.t!(l.name, @locale, default: "?")}
        </span>
        <span class="ml-1 text-xs opacity-60">
          {fmt_effects(@option.effects, @value_index, @groups_index, @locale)}
        </span>
      </div>
      <div class="whitespace-nowrap">
        <button
          :if={@can_edit?}
          type="button"
          phx-click="edit_option"
          phx-value-id={@option.id}
          class="btn btn-xs"
        >
          Edit
        </button>
        <button
          :if={@can_edit?}
          type="button"
          phx-click="delete_option"
          phx-value-id={@option.id}
          data-confirm="Delete this option?"
          class="btn btn-xs btn-error btn-soft"
        >
          Delete
        </button>
      </div>
    </li>
    """
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

  # Member emails and pending invitations are owner-only data; everyone else
  # gets empty lists (the section is hidden for them anyway).
  defp reload_members(%{assigns: %{role: :owner, scenario: scenario}} = socket) do
    assign(socket,
      members: Authoring.list_members(scenario),
      pending_invitations: Authoring.list_pending_invitations(scenario)
    )
  end

  defp reload_members(socket), do: assign(socket, members: [], pending_invitations: [])

  # The members section (invitations, roles) is owner-only.
  def sections(:owner), do: @sections ++ [:members]
  def sections(_role), do: @sections
end
