# Balance check for the Mars Colony scenario (seed it first).
#
# Plays the scenario many times through the real live-session fold
# (`Scenex.Play.Projection`) — the same code a running show uses — and reports
# where Colony Vitality lands and which ending the console would recommend.
#
#     mix run priv/repo/balance_mars_colony.exs [runs]
#
# Each run follows the director's run sheet: What to Bring → Touchdown →
# Green Thumb → Settling In → The Find → The Storm → one Rationing shade
# (picked by Vitality, as the notes say) → Jury-Rig It → Triage → Off the
# Record + Earth's Offer (only if Command called Earth).

Logger.configure(level: :warning)

alias Scenex.{Authoring, Repo}
alias Scenex.Authoring.Scenario
alias Scenex.Engine.{Condition, Index, Sim}
alias Scenex.Play.{Definition, Projection}

runs = String.to_integer(List.first(System.argv()) || "20000")

scenario = Repo.get_by!(Scenario, handle: "mars_colony")
definition = Definition.load(scenario)

element = fn handle ->
  Enum.find(Map.values(definition.elements), &(&1.handle == handle)) ||
    raise "no element #{handle}"
end

group_handle = Map.new(definition.groups, fn {id, g} -> {id, g.handle} end)
key_of = Map.new(definition.value_dimensions, &{&1.id, &1.key})

globals_by_key = fn sim ->
  for {id, v} <- Sim.globals(sim), is_number(v), into: %{}, do: {key_of[id], v}
end

vitality = fn sim ->
  {:ok, v} = Index.evaluate(definition.overall_index_formula, globals_by_key.(sim))
  v
end

bands = Enum.map(definition.overall_index_bands, fn b -> b.label["en"] end)

band = fn v ->
  idx = min(trunc(v / 10 * length(bands)), length(bands) - 1)
  Enum.at(bands, idx)
end

recommended_ending = fn sim ->
  ctx = %{global: globals_by_key.(sim)}

  definition.endings
  |> Enum.filter(&(&1.condition && match?({:ok, true}, Condition.evaluate(&1.condition, ctx))))
  |> Enum.max_by(& &1.priority, fn -> nil end)
  |> case do
    nil -> "(none)"
    e -> e.handle
  end
end

# Same gate semantics as `Scenex.Play.gate_open?/3`: evaluated against the
# board before the element.
gate_open? = fn sim, option ->
  case option.condition do
    nil ->
      true

    condition ->
      self_ctx =
        if option.group_id,
          do:
            for(
              vd <- definition.value_dimensions,
              is_number(Sim.get(sim, vd.id, option.group_id)),
              into: %{},
              do: {vd.key, Sim.get(sim, vd.id, option.group_id)}
            ),
          else: %{}

      match?(
        {:ok, true},
        Condition.evaluate(condition, %{global: globals_by_key.(sim), self: self_ctx})
      )
  end
end

ev = fn p, type, payload -> Projection.apply_event(p, %{type: type, payload: payload}) end

# ── Policies ────────────────────────────────────────────────────────────────
# A policy picks one option from the open ones, given the projection state
# and the deciding scope. :random, :careful (best Vitality after the choice),
# :reckless (worst Vitality after the choice).
pick0 = fn pick0, policy, p, eid, slot_payload, options ->
  pick = fn pol, p, eid, sp, opts -> pick0.(pick0, pol, p, eid, sp, opts) end

  case policy do
    :random ->
      Enum.random(options)

    :mixed ->
      if :rand.uniform() < 0.7,
        do: pick.(:careful, p, eid, slot_payload, options),
        else: Enum.random(options)

    dir when dir in [:careful, :reckless] ->
      scored =
        Enum.map(options, fn o ->
          trial = ev.(p, slot_payload.(o).type, slot_payload.(o).payload)
          {vitality.(trial.sim), :rand.uniform(), o}
        end)
        |> Enum.sort()

      {_, _, o} = if dir == :careful, do: List.last(scored), else: hd(scored)
      _ = eid
      o
  end
end

pick = fn policy, p, eid, slot_payload, options ->
  pick0.(pick0, policy, p, eid, slot_payload, options)
end

play_event = fn p, handle, policy, stats ->
  el = element.(handle)
  p = ev.(p, "element_triggered", %{"element_id" => el.id})
  before = p.sim

  Enum.reduce(definition.group_ids, {p, stats}, fn gid, {acc, st} ->
    all = Enum.filter(definition.options_by_element[el.id], &(&1.group_id == gid))
    open = Enum.filter(all, &gate_open?.(before, &1))

    st =
      Enum.reduce(all -- open, st, fn o, s ->
        Map.update(s, {:gate_closed, o.handle}, 1, &(&1 + 1))
      end)

    payload = fn o ->
      %{
        type: "option_chosen",
        payload: %{"element_id" => el.id, "group_id" => gid, "option_id" => o.id}
      }
    end

    chosen = pick.(policy, acc, el.id, payload, open)
    st = Map.update(st, {:chosen, chosen.handle}, 1, &(&1 + 1))
    {ev.(acc, "option_chosen", payload.(chosen).payload), st}
  end)
end

play_wildcard = fn p, handle, success? ->
  el = element.(handle)
  outcome = if success?, do: :success, else: :failure
  option = Enum.find(definition.options_by_element[el.id], &(&1.outcome == outcome))

  p
  |> ev.("element_triggered", %{"element_id" => el.id})
  |> ev.("sidequest_adjudicated", %{"element_id" => el.id, "option_id" => option.id})
end

play_vote = fn p, policy, stats ->
  el = element.("earths_offer")
  p = ev.(p, "element_triggered", %{"element_id" => el.id})
  open = Enum.filter(definition.options_by_element[el.id], &gate_open?.(p.sim, &1))

  payload = fn o ->
    %{type: "election_resolved", payload: %{"element_id" => el.id, "option_id" => o.id}}
  end

  chosen = pick.(policy, p, el.id, payload, open)
  stats = Map.update(stats, {:vote, chosen.handle}, 1, &(&1 + 1))
  stats = if length(open) < 3, do: Map.update(stats, :alone_gated, 1, &(&1 + 1)), else: stats
  {ev.(p, "election_resolved", payload.(chosen).payload), stats}
end

command_id = Enum.find(definition.group_ids, &(group_handle[&1] == "command"))

called_earth? = fn p ->
  storm = element.("the_storm")
  oid = get_in(p.decisions, [storm.id, command_id])
  oid && definition.options[oid].handle == "Call Earth"
end

checkpoints = ~w(start what_to_bring touchdown settling_in the_storm rationing end)a

play = fn policy, wildcard_luck ->
  luck = fn ->
    case wildcard_luck do
      :random -> :rand.uniform() < 0.5
      :success -> true
      :failure -> false
    end
  end

  p = Projection.new(definition)
  trace = %{start: vitality.(p.sim)}
  stats = %{}

  {p, stats} = play_event.(p, "what_to_bring", policy, stats)
  trace = Map.put(trace, :what_to_bring, vitality.(p.sim))
  {p, stats} = play_event.(p, "touchdown", policy, stats)
  trace = Map.put(trace, :touchdown, vitality.(p.sim))
  p = play_wildcard.(p, "green_thumb", luck.())
  {p, stats} = play_event.(p, "settling_in", policy, stats)
  p = play_wildcard.(p, "the_find", luck.())
  trace = Map.put(trace, :settling_in, vitality.(p.sim))
  {p, stats} = play_event.(p, "the_storm", policy, stats)
  trace = Map.put(trace, :the_storm, vitality.(p.sim))

  shade =
    if band.(vitality.(p.sim)) in ["Getting By", "Steady", "Thriving"],
      do: "rationing_holding",
      else: "rationing_struggling"

  stats = Map.update(stats, {:shade, shade}, 1, &(&1 + 1))
  {p, stats} = play_event.(p, shade, policy, stats)
  trace = Map.put(trace, :rationing, vitality.(p.sim))
  p = play_wildcard.(p, "jury_rig_it", luck.())
  p = play_wildcard.(p, "triage", luck.())

  {p, stats} =
    if called_earth?.(p) do
      p = play_wildcard.(p, "off_the_record", luck.())
      stats = Map.update(stats, :vote_held, 1, &(&1 + 1))
      play_vote.(p, policy, stats)
    else
      {p, stats}
    end

  trace = Map.put(trace, :end, vitality.(p.sim))
  {trace, recommended_ending.(p.sim), globals_by_key.(p.sim), stats, p.sim}
end

# ── Report ──────────────────────────────────────────────────────────────────
fmt = fn x -> :erlang.float_to_binary(x * 1.0, decimals: 2) end

pct = fn n, total -> String.pad_leading(fmt.(100 * n / max(total, 1)), 6) <> "%" end

summarize = fn label, results ->
  n = length(results)
  IO.puts("\n== #{label} (#{n} runs)")

  IO.puts("  Vitality by beat (mean / min / max):")

  for c <- checkpoints do
    vs = Enum.map(results, fn {t, _, _, _, _} -> t[c] end)

    IO.puts(
      "    #{String.pad_trailing(to_string(c), 14)} #{fmt.(Enum.sum(vs) / n)}  " <>
        "#{fmt.(Enum.min(vs))}  #{fmt.(Enum.max(vs))}   (#{band.(Enum.sum(vs) / n)})"
    )
  end

  IO.puts("  Recommended ending:")

  results
  |> Enum.frequencies_by(fn {_, e, _, _, _} -> e end)
  |> Enum.sort_by(fn {_, c} -> -c end)
  |> Enum.each(fn {e, c} -> IO.puts("    #{String.pad_trailing(e, 14)} #{pct.(c, n)}") end)

  IO.puts("  Final band:")

  results
  |> Enum.frequencies_by(fn {t, _, _, _, _} -> band.(t[:end]) end)
  |> Enum.each(fn {b, c} -> IO.puts("    #{String.pad_trailing(b, 18)} #{pct.(c, n)}") end)

  IO.puts("  Final globals (mean):")

  for key <- ~w(life_support supplies progress risk) do
    vs = Enum.map(results, fn {_, _, g, _, _} -> g[key] end)
    IO.puts("    #{String.pad_trailing(key, 14)} #{fmt.(Enum.sum(vs) / n)}")
  end

  stats =
    Enum.reduce(results, %{}, fn {_, _, _, s, _}, acc ->
      Map.merge(acc, s, fn _k, a, b -> a + b end)
    end)

  IO.puts("  Shades / vote:")

  for {k, c} <- Enum.sort(stats), match?({:shade, _}, k) or match?({:vote, _}, k) or is_atom(k) do
    IO.puts("    #{String.pad_trailing(inspect(k), 44)} #{pct.(c, n)}")
  end

  # Clamping: how often a team's value ends pinned at 0 or 10.
  pinned =
    for {_, _, _, _, sim} <- results,
        {vid, per_group} <- sim.group_values,
        {gid, v} <- per_group,
        v in [0, 0.0, 10, 10.0],
        do: "#{group_handle[gid]}.#{key_of[vid]}=#{trunc(v)}"

  unless pinned == [] do
    IO.puts("  Values pinned at a bound at the end:")

    pinned
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_, c} -> -c end)
    |> Enum.take(8)
    |> Enum.each(fn {k, c} -> IO.puts("    #{String.pad_trailing(k, 30)} #{pct.(c, n)}") end)
  end

  stats
end

IO.puts("Mars Colony balance check — #{definition.scenario_id}")
IO.puts("Starting Vitality: #{fmt.(vitality.(Definition.initial_sim(definition)))}")

random_results = for _ <- 1..runs, do: play.(:random, :random)
stats = summarize.("Random teams, random wildcard luck", random_results)

IO.puts("  Gates closed (share of runs the option was locked):")

for {{:gate_closed, h}, c} <- Enum.sort(stats) do
  IO.puts("    #{String.pad_trailing(h, 44)} #{pct.(c, runs)}")
end

IO.puts("  Options never chosen at random:")

all_event_options =
  for {_eid, opts} <- definition.options_by_element, o <- opts, o.group_id, do: o.handle

never = Enum.reject(all_event_options, &Map.has_key?(stats, {:chosen, &1}))
IO.puts("    " <> if(never == [], do: "(none)", else: Enum.join(never, ", ")))

summarize.(
  "Mixed teams (70% careful), random wildcard luck",
  for(_ <- 1..1000, do: play.(:mixed, :random))
)

summarize.("Careful teams, lucky wildcards", for(_ <- 1..200, do: play.(:careful, :success)))
summarize.("Careful teams, unlucky wildcards", for(_ <- 1..200, do: play.(:careful, :failure)))

summarize.(
  "Reckless teams, random wildcard luck",
  for(_ <- 1..200, do: play.(:reckless, :random))
)

_ = Authoring
