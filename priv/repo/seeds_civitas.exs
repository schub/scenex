# CIVITAS (Alpha v0.2) demo scenario.
#
# Loads the paper-prototype content from
# docs/legacy-docu/Mini-Megagame-Toolkit/designs into the database as a real
# scenario owned by the account below. Re-runnable: it deletes any existing
# scenario with handle "CIVITAS" first (children cascade).
#
#     mix run priv/repo/seeds_civitas.exs

import Ecto.Query

alias Scenex.{Accounts, Authoring, Repo}
alias Scenex.Authoring.Scenario

owner_email = System.get_env("CIVITAS_OWNER_EMAIL", "schub@example.com")
owner = Repo.get_by!(Accounts.User, email: owner_email)

Repo.all(from g in Scenario, where: g.handle == "CIVITAS") |> Enum.each(&Repo.delete/1)

# ── Markdown helpers ────────────────────────────────────────────────────────
bullets = fn items -> Enum.map_join(items, "\n", &("- " <> &1)) end

group_desc = fn subtitle, goal, tensions, questions ->
  """
  #{subtitle}

  **Ziel:** #{goal}

  **Typische Spannungen:**
  #{bullets.(tensions)}

  **Leitfragen:**
  #{bullets.(questions)}
  """
end

event_narr = fn subtitle, context, prompts ->
  """
  #{subtitle}

  **Kontext:**
  #{bullets.(context)}

  **Diskussionsimpulse:**
  #{bullets.(prompts)}
  """
end

opt_text = fn context, pros, cons ->
  """
  #{context}

  **Pro:** #{Enum.join(pros, "; ")}

  **Contra:** #{Enum.join(cons, "; ")}
  """
end

# ── Scenario ────────────────────────────────────────────────────────────────────
{:ok, scenario} =
  Authoring.create_scenario(owner, %{
    handle: "CIVITAS",
    name: %{"de" => "CIVITAS", "en" => "CIVITAS"},
    description: %{
      "de" =>
        "Mini-Megagame-Testszenario (Alpha v0.2): Drei Gruppen reagieren auf " <>
          "gesellschaftliche Krisen und verschieben mit ihren Entscheidungen die Werte."
    },
    source_locale: "de"
  })

# ── Values ──────────────────────────────────────────────────────────────────
values = [
  {"stability", "Stabilität", "Stability"},
  {"solidarity", "Solidarität", "Solidarity"},
  {"influence", "Einfluss", "Influence"},
  {"resources", "Ressourcen", "Resources"},
  {"risk", "Risiko", "Risk"}
]

value_by_key =
  values
  |> Enum.with_index(1)
  |> Map.new(fn {{key, de, en}, pos} ->
    {:ok, vd} =
      Authoring.create_value_dimension(scenario, %{
        key: key,
        name: %{"de" => de, "en" => en},
        aggregation: "avg",
        input_scope: :per_group,
        min: 0.0,
        max: 10.0,
        default_value: 5.0,
        position: pos
      })

    {key, vd}
  end)

# German value name (as used in the effect strings) -> value key
key_of = %{
  "Stabilität" => "stability",
  "Solidarität" => "solidarity",
  "Einfluss" => "influence",
  "Ressourcen" => "resources",
  "Risiko" => "risk"
}

# ── Groups (modifiers become initial values) ────────────────────────────────
groups = [
  %{
    gid: "G-REG",
    handle: "Regierung",
    name: "Regierung",
    pos: 1,
    desc:
      group_desc.(
        "Institutionen • Ordnung • Legitimität",
        "Funktionsfähigkeit des Landes sichern und Entscheidungen ermöglichen.",
        ["Ordnung vs. Freiheit", "Stabilität (kurz) vs. Legitimität (lang)"],
        [
          "Was stabilisiert sofort?",
          "Was kostet Solidarität?",
          "Wo entsteht Eskalation?",
          "Wo ist Dialog möglich?"
        ]
      ),
    inits: [{"stability", 2}, {"solidarity", -1}, {"influence", 1}]
  },
  %{
    gid: "G-BAS",
    handle: "Basisbewegung",
    name: "Basisbewegung",
    pos: 2,
    desc:
      group_desc.(
        "Zivilgesellschaft • Teilhabe • Gerechtigkeit",
        "Gesellschaftlichen Zusammenhalt stärken und Stimmen sichtbar machen.",
        ["Druck vs. Dialog", "Radikalität vs. Anschlussfähigkeit"],
        [
          "Wessen Stimmen fehlen?",
          "Wann wird Protest destruktiv?",
          "Wie entsteht echte Solidarität?",
          "Wo kippt Mobilisierung in Eskalation?"
        ]
      ),
    inits: [{"solidarity", 3}, {"stability", -1}, {"influence", -1}]
  },
  %{
    gid: "G-ECO",
    handle: "Wirtschaft-Medien",
    name: "Wirtschaft / Medien",
    pos: 3,
    desc:
      group_desc.(
        "Märkte • Öffentlichkeit • Narrative",
        "Wirtschaftliche Handlungsfähigkeit sichern und Deutungshoheit gewinnen.",
        ["Profit vs. Verantwortung", "Aufmerksamkeit vs. Vertrauen"],
        [
          "Was bringt kurzfristig Gewinn?",
          "Was zerstört langfristig Vertrauen?",
          "Welche Narrative dominieren?",
          "Wo liegt mediale Verantwortung?"
        ]
      ),
    inits: [{"resources", 2}, {"solidarity", -1}, {"risk", 1}]
  }
]

# Every value starts at 5; a group's modifiers are applied on top.
base_values = Map.new(Map.keys(value_by_key), &{&1, 5})

group_by_gid =
  Map.new(groups, fn g ->
    {:ok, grp} =
      Authoring.create_group(scenario, %{
        handle: g.handle,
        name: %{"de" => g.name},
        description: %{"de" => g.desc},
        position: g.pos
      })

    starting =
      Enum.reduce(g.inits, base_values, fn {k, delta}, acc ->
        Map.update!(acc, k, &(&1 + delta))
      end)

    Enum.each(starting, fn {k, v} ->
      Authoring.set_group_initial_value(grp, value_by_key[k], v * 1.0)
    end)

    {g.gid, grp}
  end)

# ── Labels (escalation markers) ─────────────────────────────────────────────
labels = [
  {"Eskalation", "Eskalation", "Escalation", :error, "🔺", 1},
  {"Deeskalation", "Deeskalation", "De-escalation", :success, "🔻", 2},
  {"Neutral", "Neutral", "Neutral", :neutral, "⚪", 3}
]

label_by_name =
  Map.new(labels, fn {handle, de, en, color, icon, pos} ->
    {:ok, l} =
      Authoring.create_label(scenario, %{
        handle: handle,
        name: %{"de" => de, "en" => en},
        color: color,
        icon: icon,
        position: pos
      })

    {de, l}
  end)

marker_label = fn marker ->
  cond do
    String.contains?(marker, "Deeskalation") -> label_by_name["Deeskalation"]
    String.contains?(marker, "Eskalation") -> label_by_name["Eskalation"]
    true -> label_by_name["Neutral"]
  end
end

# ── Events ──────────────────────────────────────────────────────────────────
timeline_elements = [
  %{
    eid: "E-01",
    title: "Massive Proteste",
    pos: 1,
    narrative:
      event_narr.(
        "Öffentlicher Druck • Blockaden • Eskalationsgefahr",
        [
          "Im ganzen Land kommt es zu spontanen Demonstrationen.",
          "Unterschiedliche Gruppen gehen aus unterschiedlichen Gründen auf die Straße.",
          "Verkehrswege sind blockiert, die Stimmung ist aufgeheizt."
        ],
        [
          "Was passiert, wenn Ordnung wichtiger wird als Vertrauen?",
          "Wie viel Konflikt hält Demokratie aus?",
          "Wer spricht — und wer wird überhört?"
        ]
      )
  },
  %{
    eid: "E-02",
    title: "Ökonomische Instabilität",
    pos: 2,
    narrative:
      event_narr.(
        "Inflation • Unsicherheit • Verteilungskonflikte",
        [
          "Die Wirtschaft gerät ins Wanken, Preise steigen spürbar.",
          "Kleinere Betriebe schließen, Zukunftsangst breitet sich aus.",
          "Politik, Medien und Zivilgesellschaft geraten unter Zugzwang."
        ],
        [
          "Wer trägt die Kosten der Krise?",
          "Welche Maßnahmen sind schnell — und welche gerecht?",
          "Wie kippt ökonomischer Stress in politische Radikalisierung?"
        ]
      )
  },
  %{
    eid: "E-03",
    title: "Informationschaos",
    pos: 3,
    narrative:
      event_narr.(
        "Falschinformationen • Vertrauensverlust • Polarisierung",
        [
          "Gerüchte, Halbwahrheiten und Manipulation verbreiten sich rasant.",
          "Institutionen werden infrage gestellt, Konflikte werden angeheizt.",
          "Die Gesellschaft ist verunsichert: Wem kann man noch glauben?"
        ],
        [
          "Wie bekämpft man Desinformation ohne Zensurvorwurf?",
          "Was stabilisiert Vertrauen — Fakten, Werte oder Macht?",
          "Welche Rolle spielen Medien und Plattformen?"
        ]
      )
  }
]

event_by_eid =
  Map.new(timeline_elements, fn e ->
    {:ok, ev} =
      Authoring.create_timeline_element(scenario, %{
        handle: e.title,
        title: %{"de" => e.title},
        narrative: %{"de" => e.narrative},
        kind: :event,
        position: e.pos
      })

    {e.eid, ev}
  end)

# ── Decision options (3 timeline_elements × 3 groups × 3 options) ──────────────────────
# {eid, gid, pos, name, marker, context, pros, cons, effects}
options = [
  # TimelineElement 1 — Massive Proteste
  {"E-01", "G-REG", 1, "Polizei massiv einsetzen", "🔺 Eskalation",
   "Schnelle Kontrolle der Straße – mit Kosten für Vertrauen.",
   ["Ordnung schnell wiederherstellen", "Signalisiert Handlungsfähigkeit", "Kurzfristig stabilisierend"],
   ["Vertrauensverlust", "Radikalisierung möglich", "Internationale Kritik / Legitimitätsverlust"],
   ["+2 Stabilität", "−2 Solidarität", "+2 Risiko"]},
  {"E-01", "G-REG", 2, "Dialogangebot", "🔻 Deeskalation",
   "Verhandeln statt durchgreifen – Konflikt senken, aber Tempo verlieren.",
   ["Spannungen abbauen", "Stärkt Zusammenhalt", "Senkt Eskalationsgefahr"],
   ["Wirkt evtl. schwach", "Braucht Zeit", "Ordnung nicht sofort garantiert"],
   ["−1 Stabilität", "+2 Solidarität", "−1 Risiko"]},
  {"E-01", "G-REG", 3, "Medienkampagne für Ruhe", "⚪ Neutral",
   "Narrativ steuern, ohne direkt zu eskalieren – aber mit Reibung.",
   ["Geringe direkte Kosten", "Kein unmittelbarer Zwang", "Kontrolliert das Narrativ"],
   ["Wirkung unsicher", "Propaganda-Vorwurf möglich", "Kann indirekt eskalieren"],
   ["+1 Einfluss", "+1 Solidarität", "+1 Risiko"]},
  {"E-01", "G-BAS", 1, "Proteste verstärken", "🔺 Eskalation",
   "Mehr Druck aufbauen – mit höherem Eskalationsrisiko.",
   ["Erhöht politischen Druck", "Mehr Sichtbarkeit", "Mobilisiert Unterstützer"],
   ["Eskalationsgefahr", "Repression wahrscheinlicher", "Moderate Unterstützer verlieren"],
   ["+2 Einfluss", "+2 Risiko", "−1 Stabilität"]},
  {"E-01", "G-BAS", 2, "Vermittlung", "🔻 Deeskalation",
   "Brücken bauen – Druck reduzieren, aber Vertrauen gewinnen.",
   ["Konstruktiver Akteur", "Stärkt Zusammenhalt", "Senkt Gewaltpotenzial"],
   ["Weniger Druck", "Gefahr übergangen zu werden", "Wirkt nach innen evtl. weich"],
   ["+2 Solidarität", "−1 Einfluss", "−1 Risiko"]},
  {"E-01", "G-BAS", 3, "Forderungskatalog übergeben", "🔻 Deeskalation",
   "Protest wird politisch konkret – Anschlussfähigkeit steigt.",
   ["Klare Position", "Verbindet Protest & Dialog", "Breit anschlussfähig"],
   ["Umsetzung ungewiss", "Weniger medialer Effekt", "Kann verwässert werden"],
   ["+1 Einfluss", "+1 Solidarität"]},
  {"E-01", "G-ECO", 1, "Polarisierende Berichte", "🔺 Eskalation",
   "Aufmerksamkeit maximieren – Konflikt verschärfen.",
   ["Hohe Reichweite", "Klicks/Marktanteile", "Agenda-Setting"],
   ["Verschärft Konflikte", "Vertrauensverlust", "Langfristige Destabilisierung"],
   ["+2 Einfluss", "+2 Risiko"]},
  {"E-01", "G-ECO", 2, "Deeskalierende Berichterstattung", "🔻 Deeskalation",
   "Verantwortung übernehmen – weniger Aufmerksamkeit, mehr Vertrauen.",
   ["Senkt Eskalation", "Stärkt Zusammenhalt", "Glaubwürdigkeit"],
   ["Weniger Klicks", "Weniger Einnahmen", "Wirkt „zu weich“"],
   ["+1 Solidarität", "−1 Einfluss", "−1 Risiko"]},
  {"E-01", "G-ECO", 3, "Betriebe schließen", "🔻 Deeskalation",
   "Schutz & Ruhe – aber wirtschaftliche Kosten.",
   ["Schützt Mitarbeitende", "Senkt unmittelbare Eskalation", "Signalisiert Verantwortung"],
   ["Wirtschaftliche Verluste", "Versorgung/Services leiden", "Signalisiert Krise"],
   ["−2 Ressourcen", "−1 Risiko"]},

  # TimelineElement 2 — Ökonomische Instabilität
  {"E-02", "G-REG", 1, "Rettungspaket", "🔻 Deeskalation",
   "Staat greift ein – Stabilität kaufen mit Ressourcen.",
   ["Stabilisiert Wirtschaft", "Verhindert Massenarbeitslosigkeit", "Stärkt Vertrauen in Staat"],
   ["Hohe Kosten", "Verschuldung", "Politisch angreifbar"],
   ["−2 Ressourcen", "+2 Stabilität"]},
  {"E-02", "G-REG", 2, "Marktliberalisierung", "⚪ Neutral",
   "Wachstum durch Reformen – soziale Kosten möglich.",
   ["Fördert Wettbewerb", "Entlastet Staat", "Attraktiv für Investoren"],
   ["Ungleichheit steigt", "Kurzfristige Härten", "Solidarität sinkt"],
   ["+1 Ressourcen", "−2 Solidarität"]},
  {"E-02", "G-REG", 3, "Gespräche mit Wirtschaftsakteuren", "🔻 Deeskalation",
   "Konsens suchen – Wirkung verzögert, Konflikt sinkt.",
   ["Beruhigt Akteure", "Kompromisse möglich", "Legitimität durch Dialog"],
   ["Langsam", "Keine Soforthilfe", "Wirkt ausweichend"],
   ["+1 Stabilität", "−1 Einfluss"]},
  {"E-02", "G-BAS", 1, "Unterstützungsfonds", "🔻 Deeskalation",
   "Direkte Hilfe – Solidarität hoch, Ressourcen kosten.",
   ["Direkte Hilfe", "Stärkt soziale Netze", "Hohe Glaubwürdigkeit"],
   ["Begrenzte Mittel", "Nicht skalierbar", "Kann Staat entlasten (politisch)"],
   ["−1 Ressourcen", "+2 Solidarität"]},
  {"E-02", "G-BAS", 2, "Proteste gegen Ungleichheit", "🔺 Eskalation",
   "Druck erhöhen – Konflikt verschärfen möglich.",
   ["Erhöht Druck", "Macht Missstände sichtbar", "Mobilisiert Betroffene"],
   ["Eskalationsgefahr", "Schadet Wirtschaft kurzfr.", "Polarisierung"],
   ["+2 Einfluss", "+1 Risiko"]},
  {"E-02", "G-BAS", 3, "Bürgerforen organisieren", "🔻 Deeskalation",
   "Beteiligung statt Empörung – langsam, aber stabilisierend.",
   ["Teilhabe", "Deeskaliert", "Strukturiert Debatte"],
   ["Langsam", "Wenig unmittelbare Wirkung", "Kann elitär wirken"],
   ["+1 Solidarität", "−1 Risiko"]},
  {"E-02", "G-ECO", 1, "Preise erhöhen", "⚪ Neutral",
   "Überleben sichern – Bevölkerung zahlt.",
   ["Gewinne sichern", "Unternehmen überleben", "Planbarkeit"],
   ["Belastet Bevölkerung", "Solidarität sinkt", "Politischer Backlash"],
   ["+2 Ressourcen", "−1 Solidarität"]},
  {"E-02", "G-ECO", 2, "Kampagne „Kauft lokal“", "⚪ Neutral",
   "Positive Mobilisierung – begrenzte, aber stabile Wirkung.",
   ["Stärkt lokale Wirtschaft", "Positives Narrativ", "Gemeinschaftsgefühl"],
   ["Begrenzte Wirkung", "Marketingkosten", "Kann als PR wirken"],
   ["+1 Einfluss", "+1 Ressourcen"]},
  {"E-02", "G-ECO", 3, "Transparenzinitiative", "🔻 Deeskalation",
   "Vertrauen aufbauen – Macht abgeben.",
   ["Stärkt Vertrauen", "Langfristig stabil", "Reduziert Misstrauen"],
   ["Kurzfristig Image-Risiko", "Weniger Kontrolle", "Weniger Einfluss"],
   ["+1 Solidarität", "−1 Einfluss"]},

  # TimelineElement 3 — Informationschaos
  {"E-03", "G-REG", 1, "Faktencheck-Kampagne", "⚪ Neutral",
   "Glaubwürdigkeit kaufen – kostet Ressourcen.",
   ["Stärkt Glaubwürdigkeit", "Keine Repression", "Klare Linie"],
   ["Teuer", "Wirkung unsicher", "Erreicht nicht alle"],
   ["−1 Ressourcen", "+2 Einfluss"]},
  {"E-03", "G-REG", 2, "Sicherheitsgesetze verschärfen", "🔺 Eskalation",
   "Kontrolle erhöhen – Freiheit & Vertrauen riskieren.",
   ["Schnelle Eingriffe", "Signalisiert Kontrolle", "Beruhigt Teile der Bevölkerung"],
   ["Freiheitsrechte eingeschränkt", "Radikalisierung", "Zensur-/Machtmissbrauchsvorwurf"],
   ["+1 Stabilität", "−1 Solidarität", "+1 Risiko"]},
  {"E-03", "G-REG", 3, "Social-Media-Sperren", "🔺 Eskalation",
   "Plattformen kappen – Informationskrieg, aber Autoritarismus-Vorwurf.",
   ["Schnelle Eindämmung", "Unterbricht Gerüchtewellen", "Kontrolliert Kanäle"],
   ["Zensurvorwurf", "Vertrauensverlust", "Ausweichkanäle entstehen"],
   ["−1 Einfluss", "+1 Risiko"]},
  {"E-03", "G-BAS", 1, "Dialogarbeit", "🔻 Deeskalation",
   "Gesprächsräume schaffen – langsam, aber stabilisierend.",
   ["Stärkt Vertrauen", "Brücken bauen", "Senkt Polarisierung"],
   ["Langsam", "Begrenzte Reichweite", "Wirkt naiv gegenüber Manipulation"],
   ["+2 Solidarität", "−1 Einfluss"]},
  {"E-03", "G-BAS", 2, "Gegennarrative verbreiten", "🔺 Eskalation",
   "Gegenpropaganda – mobilisierend, aber polarisierend.",
   ["Hohe Sichtbarkeit", "Mobilisierung", "Kontrolliert Teilnarrative"],
   ["Polarisierung", "Fehlinfo-Risiko", "Konfliktspirale"],
   ["+1 Einfluss", "+1 Risiko"]},
  {"E-03", "G-BAS", 3, "Institutionen stärken", "🔻 Deeskalation",
   "Vertrauen in Regeln – weniger spektakulär, aber tragfähig.",
   ["Stabilisiert Demokratie", "Brücken zu Institutionen", "Reduziert Misstrauen"],
   ["Wenig spektakulär", "Schwer messbar", "Kann als systemtreu gelten"],
   ["+1 Solidarität", "+1 Einfluss"]},
  {"E-03", "G-ECO", 1, "Sensationsjournalismus", "🔺 Eskalation",
   "Aufmerksamkeit maximieren – Vertrauen opfern.",
   ["Reichweite", "Einnahmen", "Agenda-Setting"],
   ["Vertrauensverlust", "Eskalation", "Langfristige Instabilität"],
   ["+2 Einfluss", "+2 Risiko"]},
  {"E-03", "G-ECO", 2, "Klare Faktenlage", "🔻 Deeskalation",
   "Fakten priorisieren – Klicks verlieren, Vertrauen gewinnen.",
   ["Glaubwürdigkeit", "Verantwortung", "Senkt Polarisierung"],
   ["Weniger Klicks", "Weniger Einnahmen", "Wirkt ‚zu neutral‘"],
   ["+1 Solidarität", "−1 Einfluss"]},
  {"E-03", "G-ECO", 3, "Editorial „Rettet die Demokratie“", "🔻 Deeskalation",
   "Normative Klarheit – Orientierung geben, Parteinahme riskieren.",
   ["Orientierung", "Werte sichtbar machen", "Stärkt Zusammenhalt"],
   ["Vorwurf Parteinahme", "Polarisierung bei Gegnern", "Kann heuchlerisch wirken"],
   ["+1 Einfluss", "+1 Solidarität"]}
]

parse_effect = fn s ->
  [num_str, name] = String.split(String.trim(s), " ", parts: 2)
  num = num_str |> String.replace("−", "-") |> String.replace("–", "-") |> String.to_integer()
  {key_of[String.trim(name)], num}
end

Enum.each(options, fn {eid, gid, pos, name, marker, context, pros, cons, effects} ->
  {:ok, opt} =
    Authoring.create_decision_option(event_by_eid[eid], group_by_gid[gid], %{
      handle: name,
      text: %{"de" => opt_text.(context, pros, cons)},
      position: pos
    })

  Authoring.set_option_labels(opt, [marker_label.(marker)])

  Enum.each(effects, fn e ->
    {k, d} = parse_effect.(e)
    Authoring.set_option_effect(opt, value_by_key[k], d * 1.0)
  end)
end)

# ── Gates on existing event options ─────────────────────────────────────────
# Spendable values get their meaning: you can only buy what you can afford.
gates = [
  {"E-02", "Rettungspaket", "self(resources) >= 4"},
  {"E-03", "Faktencheck-Kampagne", "self(resources) >= 3"}
]

Enum.each(gates, fn {eid, handle, condition} ->
  opt =
    event_by_eid[eid]
    |> Authoring.list_decision_options()
    |> Enum.find(&(&1.handle == handle))

  {:ok, _} = Authoring.update_decision_option(opt, %{condition: condition})
end)

# Matrix helper: rows of {group gid, [{value_key, delta}]}
set_matrix = fn option, rows ->
  Enum.each(rows, fn {gid, cells} ->
    Enum.each(cells, fn {key, delta} ->
      {:ok, _} =
        Authoring.set_option_effect(option, value_by_key[key], group_by_gid[gid], delta * 1.0)
    end)
  end)
end

# ── Sidequest: the dossier (individual scale) ───────────────────────────────
{:ok, sidequest} =
  Authoring.create_timeline_element(scenario, %{
    handle: "Recherche: Das Dossier",
    title: %{"de" => "Recherche: Das Dossier"},
    narrative: %{
      "de" => """
      Ein anonymer Hinweis: Im Krisenstab sollen Entscheidungen an den
      offiziellen Gremien vorbei getroffen worden sein. Es existiert angeblich
      ein internes Dossier.

      **Auftrag:** Beschaffe belastbare Belege und bringe das Dossier an die
      Öffentlichkeit — oder entscheide dich bewusst dagegen.
      """
    },
    director_notes: %{
      "de" => """
      Verdeckt an eine:n einzelne:n Spieler:in der Gruppe Wirtschaft/Medien
      übergeben (Zettel oder Flüstern, nicht öffentlich). Die Person entscheidet
      selbst, wen sie einweiht. Erfolg = das Dossier wird öffentlich gemacht UND
      mindestens eine andere Gruppe bestätigt die Geschichte öffentlich.
      Bei Erfolg ggf. als Folge eine Pressekonferenz der Regierung inszenieren.
      """
    },
    kind: :sidequest,
    position: 4
  })

{:ok, sq_success} =
  Authoring.create_decision_option(sidequest, nil, %{
    handle: "Dossier veröffentlicht",
    text: %{"de" => "Die Recherche gelingt: Das Dossier wird öffentlich und bestätigt."},
    outcome: :success,
    position: 1
  })

set_matrix.(sq_success, [
  {"G-ECO", [{"influence", 2}, {"solidarity", 1}]},
  {"G-REG", [{"stability", -1}, {"influence", -1}]}
])

{:ok, sq_failure} =
  Authoring.create_decision_option(sidequest, nil, %{
    handle: "Recherche aufgeflogen",
    text: %{"de" => "Die Quelle platzt, der Vorwurf wirkt haltlos — der Schuss geht nach hinten los."},
    outcome: :failure,
    position: 2
  })

set_matrix.(sq_failure, [
  {"G-ECO", [{"influence", -1}, {"risk", 1}]}
])

# ── Election: emergency-powers referendum (collective scale, finale) ────────
{:ok, election} =
  Authoring.create_timeline_element(scenario, %{
    handle: "Referendum: Notstandsgesetze",
    title: %{"de" => "Referendum: Notstandsgesetze"},
    narrative: %{
      "de" => """
      Die Krisen häufen sich. Die Regierung legt der Stadt ein Paket von
      Notstandsgesetzen zur Abstimmung vor: schnellere Entscheidungen,
      erweiterte Befugnisse, weniger Mitsprache — befristet, versteht sich.

      **Die zentrale Frage:** Kann die Gemeinschaft auf die Krise antworten,
      ohne ihre eigenen demokratischen Werte auszuhöhlen?

      Alle Spieler:innen stimmen einzeln ab. Die Mehrheit entscheidet.
      """
    },
    director_notes: %{
      "de" => """
      Kampagnenphase von ca. 10 Minuten vor der Abstimmung: Gruppen dürfen
      Reden halten, verhandeln, Zusagen machen. Abstimmung per Handzeichen
      oder Stimmzettel; das Ergebnis öffentlich und feierlich verkünden.
      Bei Gleichstand entscheidet die Spielleitung.
      """
    },
    kind: :election,
    position: 5,
    deadline_seconds: 600
  })

{:ok, el_yes} =
  Authoring.create_decision_option(election, nil, %{
    handle: "Ja — Notstandsgesetze",
    text: %{
      "de" =>
        "Das Paket wird angenommen: Ordnung und Tempo zuerst, Kontrolle und Mitsprache später."
    },
    condition: "global(risk) >= 6",
    position: 1
  })

Authoring.set_option_labels(el_yes, [label_by_name["Eskalation"]])

set_matrix.(el_yes, [
  {"G-REG", [{"stability", 2}, {"influence", 2}, {"risk", 1}]},
  {"G-BAS", [{"influence", -2}, {"solidarity", -1}, {"risk", 1}]},
  {"G-ECO", [{"influence", -1}, {"risk", 1}]}
])

{:ok, el_no} =
  Authoring.create_decision_option(election, nil, %{
    handle: "Nein — demokratische Mittel",
    text: %{
      "de" =>
        "Das Paket wird abgelehnt: Die Krise wird mit den normalen demokratischen Verfahren bewältigt — langsamer, aber legitim."
    },
    position: 2
  })

Authoring.set_option_labels(el_no, [label_by_name["Deeskalation"]])

set_matrix.(el_no, [
  {"G-REG", [{"stability", -1}, {"influence", -1}]},
  {"G-BAS", [{"solidarity", 2}, {"influence", 1}, {"risk", -1}]},
  {"G-ECO", [{"solidarity", 1}]}
])

# ── Endings: what became of the community? ──────────────────────────────────
endings = [
  {"Zusammenbruch", "Systemischer Zusammenbruch", "global(risk) >= 8", 40,
   """
   Die Eskalation ist nicht mehr einzufangen. Institutionen funktionieren nur
   noch auf dem Papier, niemand traut niemandem. Die Stadt ist keine
   Gemeinschaft mehr, sondern ein Nebeneinander von Lagern.
   """,
   "Düster inszenieren: Licht runter, Gruppen räumlich trennen, keine gemeinsame Schlussrunde im Spiel — erst im Debriefing wieder zusammenführen."},
  {"Autoritäre Stabilisierung", "Autoritäre Stabilisierung", "global(stability) >= 7", 30,
   """
   Es herrscht Ordnung — aber zu welchem Preis? Entscheidungen fallen schnell,
   Widerspruch ist leiser geworden. Die Stadt funktioniert. Ob sie noch eine
   Demokratie ist, traut sich niemand laut zu fragen.
   """,
   "Ambivalent spielen: kein Triumph, keine Katastrophe. Die Frage 'War es das wert?' offen ins Debriefing tragen."},
  {"Erneuerte Solidarität", "Erneuerte Solidarität", "global(solidarity) >= 6.5", 20,
   """
   Die Krisen haben Spuren hinterlassen — und etwas freigelegt: Die Gruppen
   haben gelernt, einander zuzuhören. Nicht alle Probleme sind gelöst, aber
   die Stadt entscheidet wieder gemeinsam.
   """,
   "Warm inszenieren: alle Gruppen in die Mitte, letzte Entscheidung gemeinsam verlesen."},
  {"Zerbrechliche Normalität", "Zerbrechliche Normalität", nil, 0,
   """
   Die Stadt hat die Krisen überstanden — irgendwie. Nichts ist zusammengebrochen,
   nichts ist geheilt. Der Alltag kehrt zurück und mit ihm die Frage, ob beim
   nächsten Mal mehr nötig sein wird als Durchwursteln.
   """,
   "Der Standard-Ausgang, wenn kein anderes Ende empfohlen wird. Nüchtern und offen enden."}
]

Enum.each(endings, fn {handle, title, condition, priority, narrative, notes} ->
  {:ok, _} =
    Authoring.create_ending(scenario, %{
      handle: handle,
      title: %{"de" => title},
      narrative: %{"de" => narrative},
      director_notes: %{"de" => notes},
      condition: condition,
      priority: priority
    })
end)

IO.puts("""
Seeded CIVITAS:
  owner:      #{owner.email}
  scenario:   #{scenario.id}
  values:     #{map_size(value_by_key)}
  groups:     #{map_size(group_by_gid)}
  labels:     #{map_size(label_by_name)}
  events:     #{map_size(event_by_eid)} (+ 1 sidequest, + 1 election)
  options:    #{length(options)} event options (+ 2 outcomes, + 2 ballot options)
  gates:      #{length(gates)} on event options, 1 on the election
  endings:    #{length(endings)}
""")
