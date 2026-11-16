defmodule Scenex.Authoring.Copy do
  @moduledoc """
  Copy a whole scenario ([ADR 0024](docs/adr/0024-shared-scenario-vs-copies.md)).

  A copy, not a fork: everything authored is duplicated under new ids, the
  copy never syncs with its original and doesn't record where it came from.
  The copying user becomes its owner; it starts as a draft.

  Copied: the scenario's settings, value dimensions (with steps), groups
  (with initial values), labels, timeline elements with their options,
  effects and labels, endings, pages, Overall Index bands, and the media
  files including their bytes. Not copied: sessions, memberships,
  invitations, and archived groups (they only exist for old sessions) —
  together with their options and effects.

  Every localized field can be limited to a set of locales (the source
  locale is always kept). Every `/media/<id>/` reference in localized text
  is rewritten to the copy's own file, so the copy keeps working when the
  original is deleted.
  """

  import Ecto.Query, warn: false

  alias Scenex.Accounts.User
  alias Scenex.Media
  alias Scenex.Media.{MediaFile, Storage}
  alias Scenex.Repo

  alias Scenex.Authoring.{
    DecisionOption,
    Ending,
    Group,
    GroupInitialValue,
    Label,
    OptionEffect,
    OverallIndexBand,
    Page,
    Scenario,
    ScenarioMembership,
    TimelineElement,
    ValueDimension,
    ValueDimensionStep
  }

  @doc """
  Copy `scenario` for `user`. Options: `:key` (the copy's key; default
  `"<name> (copy)"` in the source locale), `:locales` (the locales to keep;
  default all).
  """
  def copy(%User{} = user, %Scenario{} = source, opts \\ []) do
    locales = opts |> Keyword.get(:locales) |> keep_locales(source)
    media = Repo.all(from f in MediaFile, where: f.scenario_id == ^source.id)
    media_ids = Map.new(media, &{&1.id, Ecto.UUID.generate()})
    ctx = %{locales: locales, media_ids: media_ids}

    result =
      try do
        Repo.transaction(fn ->
          scenario =
            clone(ctx, source, %{
              key: Keyword.get(opts, :key) || default_key(source),
              visibility: :draft
            })

          %ScenarioMembership{}
          |> ScenarioMembership.changeset(%{
            scenario_id: scenario.id,
            user_id: user.id,
            role: :owner
          })
          |> Repo.insert!()

          copy_media(media, media_ids, scenario, user)
          ids = %{scenario: scenario.id}
          ids = Map.put(ids, :values, copy_value_dimensions(ctx, source, ids))
          ids = Map.put(ids, :groups, copy_groups(ctx, source, ids))
          ids = Map.put(ids, :labels, copy_children(ctx, Label, source, ids))
          copy_timeline(ctx, source, ids)

          for schema <- [Ending, Page, OverallIndexBand],
              do: copy_children(ctx, schema, source, ids)

          scenario
        end)
      rescue
        error in [Ecto.InvalidChangesetError, Ecto.ConstraintError] -> {:error, error}
      end

    with {:error, _reason} <- result do
      # The rows rolled back; remove whatever bytes were already copied.
      for file <- media, do: Storage.delete(Media.key(%{file | id: media_ids[file.id]}))
      result
    end
  end

  defp keep_locales(nil, _source), do: nil
  defp keep_locales(locales, source), do: Enum.uniq([source.source_locale | locales])

  defp default_key(%Scenario{} = source) do
    name = Scenex.I18n.t!(source.name, source.source_locale, default: source.key)
    "#{name} (copy)"
  end

  # ── Media ─────────────────────────────────────────────────────────────

  # Bytes are copied inside the transaction; if anything fails later, the
  # rows roll back and `copy/3` removes the already-copied bytes.
  defp copy_media(media, media_ids, scenario, user) do
    Enum.each(media, fn file ->
      copy =
        Repo.insert!(%MediaFile{
          id: media_ids[file.id],
          scenario_id: scenario.id,
          filename: file.filename,
          content_type: file.content_type,
          size: file.size,
          uploaded_by_id: user.id
        })

      with {:error, reason} <- Storage.copy(Media.key(file), Media.key(copy)),
           do: Repo.rollback({:storage, reason})
    end)
  end

  # ── Definition graph ──────────────────────────────────────────────────

  defp copy_value_dimensions(ctx, source, ids) do
    for vd <- children(ValueDimension, source), into: %{} do
      copy = clone(ctx, vd, %{scenario_id: ids.scenario})

      for step <- Repo.all(from s in ValueDimensionStep, where: s.value_dimension_id == ^vd.id),
          do: clone(ctx, step, %{value_dimension_id: copy.id})

      {vd.id, copy.id}
    end
  end

  defp copy_groups(ctx, source, ids) do
    groups =
      Repo.all(from g in Group, where: g.scenario_id == ^source.id and is_nil(g.archived_at))

    for group <- groups, into: %{} do
      copy = clone(ctx, group, %{scenario_id: ids.scenario})

      for iv <- Repo.all(from i in GroupInitialValue, where: i.group_id == ^group.id),
          do:
            clone(ctx, iv, %{
              group_id: copy.id,
              value_dimension_id: ids.values[iv.value_dimension_id]
            })

      {group.id, copy.id}
    end
  end

  defp copy_timeline(ctx, source, ids) do
    for element <- children(TimelineElement, source) do
      copy = clone(ctx, element, %{scenario_id: ids.scenario})

      options =
        Repo.all(
          from o in DecisionOption, where: o.timeline_element_id == ^element.id, preload: :labels
        )

      # Options and effects aimed at an archived group stay behind with it.
      for option <- options, kept?(option.group_id, ids) do
        option_copy =
          clone(ctx, option, %{
            timeline_element_id: copy.id,
            group_id: ids.groups[option.group_id]
          })

        for effect <- Repo.all(from e in OptionEffect, where: e.decision_option_id == ^option.id),
            kept?(effect.group_id, ids) do
          clone(ctx, effect, %{
            decision_option_id: option_copy.id,
            value_dimension_id: ids.values[effect.value_dimension_id],
            group_id: ids.groups[effect.group_id]
          })
        end

        rows =
          for label <- option.labels,
              do: %{
                decision_option_id: dump(option_copy.id),
                label_id: dump(ids.labels[label.id])
              }

        Repo.insert_all("decision_option_labels", rows)
      end
    end
  end

  defp kept?(nil, _ids), do: true
  defp kept?(group_id, ids), do: Map.has_key?(ids.groups, group_id)

  defp dump(uuid), do: Ecto.UUID.dump!(uuid)

  defp copy_children(ctx, schema, source, ids) do
    for row <- children(schema, source), into: %{} do
      {row.id, clone(ctx, row, %{scenario_id: ids.scenario}).id}
    end
  end

  defp children(schema, source),
    do: Repo.all(from r in schema, where: field(r, :scenario_id) == ^source.id)

  # Insert a copy of `row` under a new id: every localized (map) field
  # filtered to the kept locales and its media links pointed at the copies.
  defp clone(ctx, %schema{} = row, overrides) do
    attrs =
      for field <- schema.__schema__(:fields),
          field not in [:id, :inserted_at, :updated_at],
          into: %{} do
        value = Map.fetch!(row, field)

        if schema.__schema__(:type, field) == :map,
          do: {field, localized(ctx, value)},
          else: {field, value}
      end

    Repo.insert!(struct(schema, Map.merge(attrs, overrides)))
  end

  defp localized(_ctx, nil), do: nil

  defp localized(ctx, translations) do
    translations
    |> then(&if(ctx.locales, do: Map.take(&1, ctx.locales), else: &1))
    |> Map.new(fn {locale, text} -> {locale, relink(text, ctx.media_ids)} end)
  end

  defp relink(text, media_ids) when is_binary(text) and media_ids != %{} do
    Enum.reduce(media_ids, text, fn {old, new}, acc ->
      String.replace(acc, "/media/#{old}/", "/media/#{new}/")
    end)
  end

  defp relink(text, _media_ids), do: text
end
