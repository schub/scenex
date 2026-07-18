defmodule Scenex.Play.SessionGroup do
  @moduledoc """
  Join row selecting one group of the scenario's pool into one session.

  A session with no rows plays with **all** groups (sessions created before
  group selection existed). The selection is fixed at session creation —
  the event log replays against it, so it must never change afterwards.
  """
  use Ecto.Schema

  alias Scenex.Authoring.Group
  alias Scenex.Play.Session

  @primary_key false
  @foreign_key_type :binary_id

  schema "session_groups" do
    belongs_to :session, Session
    belongs_to :group, Group
  end
end
