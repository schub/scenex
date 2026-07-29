defmodule Scenex.Play.Projection do
  @moduledoc """
  The pure fold of a session's event log into the current board.

  Decisions are kept per element in **slots** (a group id for event options,
  `:winner` for elections, `:outcome` for sidequests); re-entering a decision
  overwrites its slot — **last wins**, which is how a GM corrects a mistake
  without ever editing the log. After every event the sim is recomputed from
  the initial values through all triggered elements in trigger order (slots in
  group order), so results never depend on entry order or corrections.

  Pure — no Ecto, no processes. The same fold runs in the session process and
  in its replay-on-restart.

  Every event that moves a board value also records the move in
  `value_changes` / `global_changes` (latest change per cell, stamped with
  the event's game time), so all screens can show a transient "(+2)" without
  timers — freshness is a render-time comparison against the game clock, and
  replay rebuilds the same deltas.

  `baseline_sim` is a second, coarser kind of "what changed": a snapshot of
  `sim` as of the last **consolidation point**, kept until the next one —
  the room's own audience-facing bars stack "since then" on top of it (a
  cap for an increase, a dashed ghost outline for a decrease), rather than
  a fleeting per-decision marker. A consolidation point is whenever a new
  element triggers or the GM closes one out (the natural "moving on" beats)
  or the GM forces one early via `consolidate_values`.
  """

  alias Scenex.Engine.Sim
  alias Scenex.Play.Definition

  defstruct [
    :definition,
    :sim,
    :baseline_sim,
    status: :draft,
    triggered: [],
    triggered_at: %{},
    closed: [],
    sims_before: %{},
    decisions: %{},
    tallies: %{},
    vote_tallies: %{},
    value_changes: %{},
    global_changes: %{},
    ending_id: nil,
    show_numbers: false,
    board_sections: %{globals: true, wellbeing: true, democracy: true, current_beat: true},
    group_values_visible: true,
    active_page_id: nil
  ]

  @type slot :: String.t() | :winner | :outcome
  @type board_section :: :globals | :wellbeing | :democracy | :current_beat
  @type t :: %__MODULE__{}

  def new(%Definition{} = definition) do
    sim = Definition.initial_sim(definition)
    %__MODULE__{definition: definition, sim: sim, baseline_sim: sim}
  end

  @doc "Fold one session event (struct or map with `type`/`payload`/`game_time_ms`)."
  def apply_event(%__MODULE__{} = projection, %{type: type, payload: payload} = event) do
    game_time_ms = Map.get(event, :game_time_ms, 0)

    projection
    |> handle(type, payload, game_time_ms)
    |> recompute()
    |> maybe_consolidate(type)
    |> record_changes(projection, game_time_ms)
  end

  # A new element triggering, or the GM closing one out, are the natural
  # "moving on" beats — whatever changed since the last consolidation point
  # has had its moment, so it becomes the new baseline. "values_consolidated"
  # is the GM forcing that same snapshot early, on demand.
  defp maybe_consolidate(p, type)
       when type in ["element_triggered", "element_closed", "values_consolidated"],
       do: %{p | baseline_sim: p.sim}

  defp maybe_consolidate(p, _type), do: p

  def globals(%__MODULE__{sim: sim}), do: Sim.globals(sim)

  # ── Event handlers ────────────────────────────────────────────────────

  defp handle(p, "session_started", _, _), do: %{p | status: :live}
  defp handle(p, "session_paused", _, _), do: %{p | status: :paused}
  defp handle(p, "session_resumed", _, _), do: %{p | status: :live}
  defp handle(p, "session_ended", _, _), do: %{p | status: :ended}

  defp handle(p, "ending_selected", %{"ending_id" => ending_id}, _),
    do: %{p | ending_id: ending_id}

  # A GM-side display preference, not a game decision — folded into the same
  # log purely so it survives a session-process restart unchanged.
  defp handle(p, "board_numbers_set", %{"visible" => visible}, _),
    do: %{p | show_numbers: visible}

  # Independent show/hide per scoreboard section — also a GM display
  # preference, not a game decision.
  defp handle(p, "board_section_toggled", %{"section" => section, "visible" => visible}, _) do
    %{p | board_sections: Map.put(p.board_sections, String.to_existing_atom(section), visible)}
  end

  # Show/hide the group's own values on every group board — same kind of
  # GM display preference, just for the group screens instead of the wall.
  defp handle(p, "group_values_visibility_set", %{"visible" => visible}, _),
    do: %{p | group_values_visible: visible}

  # A pre-authored full-screen scoreboard page, overriding it entirely —
  # again purely a display preference, unrelated to game state. Works at
  # any session status, including before the show has started.
  defp handle(p, "page_shown", %{"page_id" => page_id}, _), do: %{p | active_page_id: page_id}
  defp handle(p, "page_cleared", _payload, _), do: %{p | active_page_id: nil}

  defp handle(p, "element_triggered", %{"element_id" => element_id}, game_time_ms) do
    if element_id in p.triggered do
      p
    else
      %{
        p
        | triggered: p.triggered ++ [element_id],
          triggered_at: Map.put(p.triggered_at, element_id, game_time_ms)
      }
    end
  end

  # The GM closing out an element manually — no defaults applied, no lock;
  # groups left undecided simply stay undecided (the GM can still enter a
  # decision for them afterward, same as before closing).
  defp handle(p, "element_closed", %{"element_id" => element_id}, _) do
    if element_id in p.closed, do: p, else: %{p | closed: p.closed ++ [element_id]}
  end

  defp handle(
         p,
         "option_chosen",
         %{"element_id" => eid, "group_id" => gid, "option_id" => oid},
         _
       ),
       do: put_decision(p, eid, gid, oid)

  defp handle(
         p,
         "deadline_lapsed",
         %{"element_id" => eid, "group_id" => gid, "option_id" => oid},
         _
       ),
       do: put_decision(p, eid, gid, oid)

  # A lapsed election deadline resolves to the default ballot option.
  defp handle(p, "deadline_lapsed", %{"element_id" => eid, "option_id" => oid}, _),
    do: put_decision(p, eid, :winner, oid)

  # The winner decides; the hand-count tally is kept for presentation.
  defp handle(p, "election_resolved", %{"element_id" => eid, "option_id" => oid} = payload, _) do
    tally =
      for {option_id, count} <- payload["tally"] || %{},
          is_integer(count),
          into: %{},
          do: {option_id, count}

    %{p | vote_tallies: Map.put(p.vote_tallies, eid, tally)}
    |> put_decision(eid, :winner, oid)
  end

  defp handle(p, "sidequest_adjudicated", %{"element_id" => eid, "option_id" => oid}, _),
    do: put_decision(p, eid, :outcome, oid)

  # A hand-count tally for a per-participant value; history accumulates, the
  # latest reading wins for the global (recompute re-applies it to the sim).
  defp handle(p, "tally_recorded", %{"value_id" => vid, "counts" => counts}, game_time_ms) do
    entry = %{counts: normalize_counts(counts), game_time_ms: game_time_ms}
    %{p | tallies: Map.update(p.tallies, vid, [entry], &(&1 ++ [entry]))}
  end

  # Unknown event types are ignored — old logs stay replayable as the
  # vocabulary grows.
  defp handle(p, _type, _payload, _game_time_ms), do: p

  defp put_decision(p, element_id, slot, option_id) do
    decisions =
      Map.update(p.decisions, element_id, %{slot => option_id}, &Map.put(&1, slot, option_id))

    %{p | decisions: decisions}
  end

  # JSONB round-trips tally scores as strings; fold them back to numbers and
  # drop anything malformed (old logs stay replayable).
  defp normalize_counts(counts) when is_map(counts) do
    for {score, count} <- counts,
        parsed = parse_score(score),
        is_integer(count) and count >= 0,
        into: %{},
        do: {parsed, count}
  end

  defp normalize_counts(_counts), do: %{}

  defp parse_score(score) when is_number(score), do: score

  defp parse_score(score) when is_binary(score) do
    case Integer.parse(score) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_score(_score), do: nil

  # ── Recompute ─────────────────────────────────────────────────────────

  defp recompute(%__MODULE__{definition: definition} = p) do
    per_group_ids =
      for spec <- definition.specs,
          spec.input_scope == :per_group,
          into: MapSet.new(),
          do: spec.key

    per_participant_ids =
      for spec <- definition.specs,
          spec.input_scope == :per_participant,
          into: MapSet.new(),
          do: spec.key

    slot_order = definition.group_ids ++ [:winner, :outcome]

    {sim, sims_before} =
      Enum.reduce(p.triggered, {Definition.initial_sim(definition), %{}}, fn eid,
                                                                             {acc, before_map} ->
        before_map = Map.put(before_map, eid, acc)
        slots = Map.get(p.decisions, eid, %{})

        acc =
          Enum.reduce(slot_order, acc, fn slot, s ->
            case slots[slot] do
              nil -> s
              oid -> apply_option(s, definition.options[oid], per_group_ids)
            end
          end)

        {acc, before_map}
      end)

    # The latest tally per per-participant value feeds its global.
    sim =
      Enum.reduce(p.tallies, sim, fn {value_id, entries}, acc ->
        if MapSet.member?(per_participant_ids, value_id),
          do: Sim.record_tally(acc, value_id, List.last(entries).counts),
          else: acc
      end)

    %{p | sim: sim, sims_before: sims_before}
  end

  # ── Change tracking ───────────────────────────────────────────────────
  # Diff the board before/after one event; keep the latest change per cell
  # (a newer change replaces an older one), stamped with the event's game
  # time. Corrections diff against the *recomputed* history, so they show
  # exactly what the correction did to the visible board.

  defp record_changes(%__MODULE__{} = new, %__MODULE__{} = old, game_time_ms) do
    value_changes =
      for spec <- new.definition.specs,
          spec.input_scope == :per_group,
          group_id <- new.definition.group_ids,
          delta =
            cell_delta(Sim.get(old.sim, spec.key, group_id), Sim.get(new.sim, spec.key, group_id)),
          reduce: new.value_changes do
        acc -> Map.put(acc, {spec.key, group_id}, {delta, game_time_ms})
      end

    old_globals = Sim.globals(old.sim)
    new_globals = Sim.globals(new.sim)

    global_changes =
      for spec <- new.definition.specs,
          delta = cell_delta(old_globals[spec.key], new_globals[spec.key]),
          reduce: new.global_changes do
        acc -> Map.put(acc, spec.key, {delta, game_time_ms})
      end

    %{new | value_changes: value_changes, global_changes: global_changes}
  end

  # The delta between two cell readings, or nil when nothing (relevant)
  # changed. A value appearing out of nowhere (first tally) has no delta.
  defp cell_delta(old, new) when is_number(old) and is_number(new) and old != new, do: new - old
  defp cell_delta(_old, _new), do: nil

  defp apply_option(sim, nil, _per_group_ids), do: sim

  # An effect targets its explicit matrix group or falls back to the option's
  # own deciding group (event options) — same semantics as the dry-run.
  defp apply_option(sim, %{group_id: own_group_id, effects: effects}, per_group_ids) do
    Enum.reduce(effects, sim, fn eff, acc ->
      target = eff.group_id || own_group_id

      if target && MapSet.member?(per_group_ids, eff.value_dimension_id),
        do: Sim.apply_effect(acc, eff.value_dimension_id, target, eff.delta),
        else: acc
    end)
  end
end
