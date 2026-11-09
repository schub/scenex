# Prepares the tutorial database: one confirmed account with a password, owning
#
#   * Common Ground — the tutorial's main example, loaded from the folder
#     tutorial/common_ground/export.sh writes (COMMON_GROUND_DIR), and
#   * Mars Colony — the second example (priv/repo/seeds_mars_colony.exs).
#
# Run by tutorial/run.sh:
#
#     SCENEX_DEV_DATABASE=scenex_tutorial mix run tutorial/setup.exs

Logger.configure(level: :info)

alias Scenex.{Accounts, Authoring, Repo}
alias Scenex.Authoring.Scenario

email = System.get_env("TUTORIAL_EMAIL", "director@scenex.example")
password = System.get_env("TUTORIAL_PASSWORD", "common-ground-2026")

common_ground_dir =
  System.get_env("COMMON_GROUND_DIR", Path.expand("../../data/common-ground", File.cwd!()))

user =
  Repo.get_by(Accounts.User, email: email) ||
    elem(
      Accounts.register_invited_user(email, %{password: password, password_confirmation: password}),
      1
    )

# ── Common Ground ───────────────────────────────────────────────────────────
# Rows are copied verbatim (same ids, so media links in the content keep
# working), in foreign-key order.
tables = ~w(scenarios value_dimensions value_dimension_steps groups group_initial_values
            labels timeline_elements decision_options option_effects decision_option_labels
            endings pages overall_index_bands media_files)

unless File.exists?(Path.join(common_ground_dir, "scenarios.csv")) do
  raise """
  No Common Ground export in #{common_ground_dir}.
  Create it with tutorial/common_ground/export.sh (see that file), or point
  COMMON_GROUND_DIR at an existing export.
  """
end

[scenario_id] =
  common_ground_dir
  |> Path.join("scenarios.csv")
  |> File.stream!()
  |> Enum.at(1)
  |> String.split(",", parts: 2)
  |> Enum.take(1)

if old = Repo.get(Scenario, scenario_id), do: Repo.delete!(old)

# Exports taken before the key/name consolidation (migration
# 20261026223649) carry the old column names; map them onto the new ones.
legacy_columns = %{
  "handle" => "key",
  "narrative" => "description",
  "text" => "name",
  "label" => "name"
}

copy_script =
  Enum.map_join(tables, "\n", fn table ->
    file = Path.join(common_ground_dir, "#{table}.csv")

    columns =
      file
      |> File.stream!()
      |> Enum.at(0)
      |> String.trim()
      |> String.split(",")
      |> Enum.map_join(",", &Map.get(legacy_columns, &1, &1))

    "\\copy #{table}(#{columns}) from '#{file}' csv header"
  end)

script_path = Path.join(System.tmp_dir!(), "scenex-tutorial-import.sql")
File.write!(script_path, "\\set ON_ERROR_STOP on\n" <> copy_script <> "\n")

repo = Repo.config()

{output, status} =
  System.cmd(
    "psql",
    [
      "-q",
      "-h",
      repo[:hostname],
      "-U",
      repo[:username],
      "-d",
      repo[:database],
      "-f",
      script_path
    ],
    env: [{"PGPASSWORD", repo[:password]}],
    stderr_to_stdout: true
  )

if status != 0, do: raise("Importing Common Ground failed:\n" <> output)

common_ground = Repo.get!(Scenario, scenario_id)
{:ok, _} = Authoring.add_member(common_ground, user, :owner)

media_dir = Application.fetch_env!(:scenex, Scenex.Media)[:dir]

for id <- common_ground_dir |> Path.join("media") |> File.ls!() do
  File.cp_r!(Path.join([common_ground_dir, "media", id]), Path.join(media_dir, id))
end

IO.puts("Loaded Common Ground (#{scenario_id}) for #{email}")

# ── Mars Colony ─────────────────────────────────────────────────────────────
System.put_env("MARS_OWNER_EMAIL", email)
Code.require_file("priv/repo/seeds_mars_colony.exs")
