# Writes docs/tutorial/mars-colony-content.md: every value, group, beat,
# option and effect of the seeded Mars Colony scenario, straight from the
# database — so the tutorial's reference never drifts from the content.
#
#     mix run tutorial/reference.exs [output-path]

Logger.configure(level: :warning)

alias Scenex.{Authoring, I18n, Repo}
alias Scenex.Authoring.Scenario

out = List.first(System.argv()) || "docs/tutorial/mars-colony-content.md"
scenario = Repo.get_by!(Scenario, handle: "mars_colony")
t = fn map -> I18n.t(map, "en") || "" end

values = Authoring.list_value_dimensions(scenario)
per_group = Enum.filter(values, &(&1.input_scope == :per_group))
value_name = Map.new(values, &{&1.id, t.(&1.name)})
groups = Authoring.list_groups(scenario)
group_name = Map.new(groups, &{&1.id, t.(&1.name)})
group_pos = Map.new(groups, &{&1.id, &1.position})
value_pos = Map.new(values, &{&1.id, &1.position})
labels = Map.new(Authoring.list_labels(scenario), &{&1.id, &1})

kind = %{event: "Event", election: "Vote", sidequest: "Wildcard"}

fmt = fn n -> if n == trunc(n), do: "#{trunc(n)}", else: "#{n}" end
signed = fn n -> if n > 0, do: "+#{fmt.(n)}", else: fmt.(n) end

effects = fn option ->
  option
  |> Authoring.list_option_effects()
  |> Enum.reject(&(&1.delta == 0))
  |> Enum.sort_by(&value_pos[&1.value_dimension_id])
  |> Enum.group_by(& &1.group_id)
  |> Enum.sort_by(fn {gid, _} -> group_pos[gid] || 0 end)
  |> Enum.map_join("; ", fn {gid, effs} ->
    cells =
      Enum.map_join(effs, ", ", &"#{value_name[&1.value_dimension_id]} #{signed.(&1.delta)}")

    if gid, do: "#{group_name[gid]}: #{cells}", else: cells
  end)
end

option_labels = fn option ->
  option = Repo.preload(option, :labels)
  Enum.map_join(option.labels, " ", fn l -> "#{l.icon} #{t.(l.name)}" end)
end

# Option text without its bold title prefix, for the table.
plain = fn text -> text |> String.replace(~r/^\*\*[^*]+\*\*\s*—\s*/, "") end

esc = fn s -> s |> String.replace("|", "\\|") |> String.replace("\n", " ") end

header = """
# Mars Colony — complete content

> Generated from the database by `tutorial/reference.exs` — don't edit by
> hand; change the scenario (`priv/repo/seeds_mars_colony.exs` or the editor)
> and run `tutorial/run.sh` again.

[← Mars Colony](mars-colony.md) · [Contents](index.md)

**Overall Index:** #{t.(scenario.overall_index_name)} =
`#{scenario.overall_index_formula}` (#{fmt.(scenario.overall_index_min)}–#{fmt.(scenario.overall_index_max)})

"""

value_table =
  "## Values\n\n| Value | Key | Scope | Formula | Range |\n|---|---|---|---|---|\n" <>
    Enum.map_join(values, "\n", fn v ->
      range =
        if v.min,
          do: "#{fmt.(v.min)}–#{fmt.(v.max)}",
          else: "steps 1–#{length(Authoring.list_value_dimension_steps(v))}"

      scope = if v.input_scope == :per_group, do: "per group", else: "per participant"
      formula = if v.input_scope == :per_group, do: "`#{v.aggregation}`", else: "show of hands"
      "| #{t.(v.name)} | `#{v.key}` | #{scope} | #{formula} | #{range} |"
    end) <> "\n\n"

start_table =
  "## Groups and starting values\n\n| Group | " <>
    Enum.map_join(per_group, " | ", &t.(&1.name)) <>
    " |\n|---|" <>
    String.duplicate("---|", length(per_group)) <>
    "\n" <>
    Enum.map_join(groups, "\n", fn g ->
      initial =
        Map.new(Authoring.list_group_initial_values(g), &{&1.value_dimension_id, &1.initial})

      "| #{t.(g.name)} | " <> Enum.map_join(per_group, " | ", &fmt.(initial[&1.id] || 0)) <> " |"
    end) <> "\n\n"

beats =
  "## Timeline\n\n" <>
    Enum.map_join(Authoring.list_timeline_elements(scenario), "\n", fn el ->
      options =
        el
        |> Authoring.list_decision_options()
        |> Enum.sort_by(&{group_pos[&1.group_id] || 0, &1.position})

      deadline = if el.deadline_seconds, do: " · ⏱ #{div(el.deadline_seconds, 60)} min", else: ""

      rows =
        case el.kind do
          :event ->
            "| Group | Option | Labels | Effects | Gate |\n|---|---|---|---|---|\n" <>
              Enum.map_join(options, "\n", fn o ->
                default = if o.is_default, do: " ⏱", else: ""
                gate = if o.condition, do: "`#{o.condition}`", else: ""

                "| #{group_name[o.group_id]} | **#{esc.(o.handle)}**#{default} — #{esc.(plain.(t.(o.text)))} | #{option_labels.(o)} | #{effects.(o)} | #{gate} |"
              end)

          _ ->
            "| Outcome | Effects | Gate |\n|---|---|---|\n" <>
              Enum.map_join(options, "\n", fn o ->
                name = if o.outcome, do: "#{o.outcome}: #{o.handle}", else: o.handle
                default = if o.is_default, do: " ⏱", else: ""
                gate = if o.condition, do: "`#{o.condition}`", else: ""
                "| **#{esc.(name)}**#{default} | #{effects.(o)} | #{gate} |"
              end)
        end

      "### #{el.position}. #{t.(el.title)} (`#{el.handle}`)\n\n*#{kind[el.kind]}#{deadline}*\n\n#{rows}\n"
    end) <> "\n⏱ after an option = the default applied when the deadline runs out.\n\n"

endings =
  "## Endings\n\n| Ending | Condition | Priority |\n|---|---|---|\n" <>
    Enum.map_join(Authoring.list_endings(scenario), "\n", fn e ->
      "| #{t.(e.title)} | `#{e.condition}` | #{e.priority} |"
    end) <> "\n"

File.write!(out, header <> value_table <> start_table <> beats <> endings)
IO.puts("Wrote #{out}")
_ = labels
