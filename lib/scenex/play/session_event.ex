defmodule Scenex.Play.SessionEvent do
  @moduledoc """
  One fact in a session's **append-only log** — the source of truth for live
  play. Rows are never updated or deleted; a mistaken decision is fixed by
  appending a newer one (the projection folds last-wins per decision slot).

  `sequence` is a per-session monotonic counter (unique per session);
  `game_time_ms` stamps the pausable game clock at append time. Payloads are
  language-neutral (ids, not text).

  Event types: `session_started`, `session_paused`, `session_resumed`,
  `element_triggered`, `option_chosen`, `deadline_lapsed`,
  `election_resolved`, `sidequest_adjudicated`, `session_ended`,
  `ending_selected`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Scenex.Play.Session

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "session_events" do
    field :sequence, :integer
    field :type, :string
    field :payload, :map, default: %{}
    field :game_time_ms, :integer, default: 0

    belongs_to :session, Session

    timestamps(updated_at: false)
  end

  def changeset(session_event, attrs) do
    session_event
    |> cast(attrs, [:session_id, :sequence, :type, :payload, :game_time_ms])
    |> validate_required([:session_id, :sequence, :type])
    |> assoc_constraint(:session)
    |> unique_constraint([:session_id, :sequence])
  end
end
