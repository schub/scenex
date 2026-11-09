-- Exports one scenario's authored content (no accounts, memberships, sessions
-- or logs) as CSV files into the current directory, for tutorial/setup.exs.
-- Run by export.sh against a restored copy of the production database.
--
-- Clean-up on the way out: English only (source locale "en"), stray
-- "_unused_*" keys dropped, absolute media links made relative, media not
-- attributed to any user.

\set ON_ERROR_STOP on

create temporary table cg as select id from scenarios where key = :'key';

-- Keep only a non-empty English entry of a localized field. Media links are
-- made host-relative (/media/<id>/<file>), so they work on any instance.
create function pg_temp.en_only(f jsonb) returns jsonb language sql immutable as $$
  select case
    when coalesce(f->>'en', '') <> ''
      then jsonb_build_object('en', regexp_replace(f->>'en', 'https?://[^/)\s]+/media/', '/media/', 'g'))
    else '{}'::jsonb
  end
$$;

\copy (select id, key, pg_temp.en_only(name) name, pg_temp.en_only(description) description, 'en' source_locale, 'draft' visibility, inserted_at, updated_at, pg_temp.en_only(director_notes) director_notes, change_highlight_seconds, pg_temp.en_only(tagline) tagline, pg_temp.en_only(overall_index_name) overall_index_name, pg_temp.en_only(overall_index_description) overall_index_description, overall_index_formula, overall_index_min, overall_index_max, overall_index_viz_min, overall_index_viz_max from scenarios where id in (select id from cg)) to 'scenarios.csv' csv header

\copy (select id, scenario_id, key, pg_temp.en_only(name) name, input_scope, aggregation, min, max, default_value, position, inserted_at, updated_at, pg_temp.en_only(description) description, pg_temp.en_only(director_notes) director_notes from value_dimensions where scenario_id in (select id from cg)) to 'value_dimensions.csv' csv header

\copy (select s.id, s.value_dimension_id, s.emoji, pg_temp.en_only(s.name) name, s.position, s.inserted_at, s.updated_at from value_dimension_steps s join value_dimensions v on v.id = s.value_dimension_id where v.scenario_id in (select id from cg)) to 'value_dimension_steps.csv' csv header

\copy (select id, scenario_id, key, pg_temp.en_only(name) name, pg_temp.en_only(description) description, position, inserted_at, updated_at, pg_temp.en_only(director_notes) director_notes, archived_at from groups where scenario_id in (select id from cg) and archived_at is null) to 'groups.csv' csv header

\copy (select i.* from group_initial_values i join groups g on g.id = i.group_id where g.scenario_id in (select id from cg) and g.archived_at is null) to 'group_initial_values.csv' csv header

\copy (select id, scenario_id, key, pg_temp.en_only(name) name, color, icon, position, inserted_at, updated_at, pg_temp.en_only(director_notes) director_notes from labels where scenario_id in (select id from cg)) to 'labels.csv' csv header

\copy (select id, scenario_id, key, pg_temp.en_only(title) title, pg_temp.en_only(description) description, position, kind, trigger, deadline_seconds, inserted_at, updated_at, pg_temp.en_only(director_notes) director_notes from timeline_elements where scenario_id in (select id from cg)) to 'timeline_elements.csv' csv header

\copy (select o.id, o.timeline_element_id, o.group_id, o.key, pg_temp.en_only(o.name) name, o.condition, o.outcome, o.is_default, o.position, o.inserted_at, o.updated_at, pg_temp.en_only(o.director_notes) director_notes from decision_options o join timeline_elements t on t.id = o.timeline_element_id where t.scenario_id in (select id from cg) and (o.group_id is null or o.group_id in (select id from groups where archived_at is null))) to 'decision_options.csv' csv header

\copy (select e.* from option_effects e join decision_options o on o.id = e.decision_option_id join timeline_elements t on t.id = o.timeline_element_id where t.scenario_id in (select id from cg) and (o.group_id is null or o.group_id in (select id from groups where archived_at is null)) and (e.group_id is null or e.group_id in (select id from groups where archived_at is null))) to 'option_effects.csv' csv header

\copy (select l.* from decision_option_labels l join decision_options o on o.id = l.decision_option_id join timeline_elements t on t.id = o.timeline_element_id where t.scenario_id in (select id from cg)) to 'decision_option_labels.csv' csv header

\copy (select id, scenario_id, key, pg_temp.en_only(title) title, pg_temp.en_only(description) description, condition, priority, inserted_at, updated_at, pg_temp.en_only(director_notes) director_notes from endings where scenario_id in (select id from cg)) to 'endings.csv' csv header

\copy (select id, scenario_id, key, pg_temp.en_only(content) content, position, inserted_at, updated_at from pages where scenario_id in (select id from cg)) to 'pages.csv' csv header

\copy (select id, scenario_id, pg_temp.en_only(name) name, position, inserted_at, updated_at from overall_index_bands where scenario_id in (select id from cg)) to 'overall_index_bands.csv' csv header

\copy (select id, scenario_id, filename, content_type, size, null uploaded_by_id, inserted_at, updated_at from media_files where scenario_id in (select id from cg)) to 'media_files.csv' csv header
