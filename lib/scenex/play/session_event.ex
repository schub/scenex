defmodule Scenex.Play.SessionEvent do
  @moduledoc """
  One fact in a session's **append-only log** — the source of truth for live
  play. Rows are never updated or deleted; a mistaken decision is fixed by
  appending a newer one (the projection folds last-wins per decision slot).

  `sequence` is a per-session monotonic counter (unique per session);
  `game_time_ms` stamps the pausable game clock at append time. Payloads are
  language-neutral (ids, not text).

  Game events: `session_started`, `session_paused`, `session_resumed`,
  `element_triggered`, `trigger_undone`, `element_closed`, `option_chosen`,
  `deadline_lapsed`, `election_resolved`, `sidequest_adjudicated`,
  `tally_recorded`, `values_consolidated`, `session_ended`,
  `ending_selected`. Display preferences ride the same log so they survive a
  restart: `board_numbers_set`, `board_section_toggled`,
  `group_values_visibility_set`, `page_shown`, `page_cleared`,
  `ballot_visibility_set`, `decisions_visibility_set`,
  `sidequest_visibility_set`.
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
