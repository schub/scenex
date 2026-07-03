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
  """

  alias Scenex.Engine.Sim
  alias Scenex.Play.Definition

  defstruct [
    :definition,
    :sim,
    status: :draft,
    triggered: [],
    triggered_at: %{},
    decisions: %{},
    ending_id: nil
  ]

  @type slot :: String.t() | :winner | :outcome
  @type t :: %__MODULE__{}

  def new(%Definition{} = definition) do
    %__MODULE__{definition: definition, sim: Definition.initial_sim(definition)}
  end

  @doc "Fold one session event (struct or map with `type`/`payload`/`game_time_ms`)."
  def apply_event(%__MODULE__{} = projection, %{type: type, payload: payload} = event) do
    game_time_ms = Map.get(event, :game_time_ms, 0)
    projection |> handle(type, payload, game_time_ms) |> recompute()
  end

  def globals(%__MODULE__{sim: sim}), do: Sim.globals(sim)

  # ── Event handlers ────────────────────────────────────────────────────

  defp handle(p, "session_started", _, _), do: %{p | status: :live}
  defp handle(p, "session_paused", _, _), do: %{p | status: :paused}
  defp handle(p, "session_resumed", _, _), do: %{p | status: :live}
  defp handle(p, "session_ended", _, _), do: %{p | status: :ended}

  defp handle(p, "ending_selected", %{"ending_id" => ending_id}, _),
    do: %{p | ending_id: ending_id}

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

  defp handle(p, "election_resolved", %{"element_id" => eid, "option_id" => oid}, _),
    do: put_decision(p, eid, :winner, oid)

  defp handle(p, "sidequest_adjudicated", %{"element_id" => eid, "option_id" => oid}, _),
    do: put_decision(p, eid, :outcome, oid)

  # Unknown event types are ignored — old logs stay replayable as the
  # vocabulary grows.
  defp handle(p, _type, _payload, _game_time_ms), do: p

  defp put_decision(p, element_id, slot, option_id) do
    decisions =
      Map.update(p.decisions, element_id, %{slot => option_id}, &Map.put(&1, slot, option_id))

    %{p | decisions: decisions}
  end

  # ── Recompute ─────────────────────────────────────────────────────────

  defp recompute(%__MODULE__{definition: definition} = p) do
    per_group_ids =
      for spec <- definition.specs,
          spec.input_scope == :per_group,
          into: MapSet.new(),
          do: spec.key

    slot_order = definition.group_ids ++ [:winner, :outcome]

    sim =
      Enum.reduce(p.triggered, Definition.initial_sim(definition), fn eid, acc ->
        slots = Map.get(p.decisions, eid, %{})

        Enum.reduce(slot_order, acc, fn slot, s ->
          case slots[slot] do
            nil -> s
            oid -> apply_option(s, definition.options[oid], per_group_ids)
          end
        end)
      end)

    %{p | sim: sim}
  end

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
