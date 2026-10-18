# Mars Colony — the showcase scenario behind the Scenex tutorial.
#
# Design brief: studio/docs/scenarios/mars-colony/design-brief.md. Five
# colony teams, five values, a Prologue on Earth, a constructive Act 1 and a
# dust-storm crisis in Act 2. Authored in English (the source locale).
#
# Re-runnable: it deletes any existing scenario with handle "mars_colony"
# first (children cascade), then rebuilds it for the owner below. It refuses
# if that scenario already has live sessions.
#
#     mix run priv/repo/seeds_mars_colony.exs
#
# Check the balance afterwards with `mix run priv/repo/balance_mars_colony.exs`.

import Ecto.Query

Logger.configure(level: :info)

alias Scenex.{Accounts, Authoring, Repo}
alias Scenex.Authoring.Scenario

owner_email = System.get_env("MARS_OWNER_EMAIL", "schub@example.com")

owner =
  Repo.get_by(Accounts.User, email: owner_email) ||
    raise "No account for #{owner_email} — register it first, or set MARS_OWNER_EMAIL."

existing = Repo.all(from s in Scenario, where: s.handle == "mars_colony")

# Sessions keep an append-only log against the scenario's groups; never delete
# them as a side effect of re-seeding.
if Repo.exists?(
     from s in Scenex.Play.Session, where: s.scenario_id in ^Enum.map(existing, & &1.id)
   ) do
  raise "The existing mars_colony scenario has sessions — delete them first (or reset the database)."
end

# Media rows cascade with the scenario, but their files would stay on disk.
existing |> Enum.flat_map(&Scenex.Media.list_files/1) |> Enum.each(&Scenex.Media.delete_file/1)
Enum.each(existing, &Repo.delete/1)

en = fn text -> %{"en" => String.trim(text)} end

# ── Scenario ────────────────────────────────────────────────────────────────
{:ok, scenario} =
  Authoring.create_scenario(owner, %{
    handle: "mars_colony",
    name: en.("Mars Colony"),
    tagline: en.("Twenty-five people. One red planet. No second chances."),
    description:
      en.("""
      You are the crew of humanity's first permanent settlement on Mars:
      twenty-five people in five teams, 225 million kilometres from home.

      The story starts on Earth, the night before launch, and follows the
      colony from touchdown through its first real crisis. First you build
      something together. Then a dust storm tests everything you built.

      Every team decides for itself — but the colony is only as strong as its
      weakest team.
      """),
    director_notes:
      en.("""
      **Running time:** 45–60 minutes for ~25 players (five teams of five).

      **Arc:** Prologue (Earth) → Act 1, building (Touchdown, Settling In) →
      Act 2, crisis (The Storm, Rationing, Earth's Offer) → Ending.

      **Suggested run sheet**

      1. Pages *Welcome* and *Mission Briefing* while people find their tables (5 min).
      2. *What to Bring* — the tutorial round, let the teams learn the boards (6 min).
      3. *Touchdown* and *Settling In* (12 min). Fire *Green Thumb* or *The Find* between them.
      4. **Morale tally #1** at the end of Act 1.
      5. Page *Sol 40* as the act break, then *The Storm* (8 min).
      6. Pick **one** of the two *Rationing* shades (see its notes) (8 min). *Jury-Rig It* or *Triage* fit here.
      7. **Morale tally #2** at the peak of the crisis.
      8. *Earth's Offer* — only if Command called Earth during the storm (8 min). *Off the Record* is the perfect lead-in.
      9. Choose the ending, then the *Debrief* page.

      **Non-linear echoes.** Act 1 choices pay off in Act 2 *narratively*, not
      mechanically: when you announce *The Storm*, name what the teams built
      ("the solar field you expanded is now buried in dust"). The director's
      notes on each beat list the echoes worth calling out.
      """),
    source_locale: "en",
    change_highlight_seconds: 30,
    overall_index_name: en.("Colony Vitality"),
    overall_index_description:
      en.(
        "How well the colony is doing overall: life support, supplies and progress push it up, risk drags it down."
      ),
    overall_index_formula: "(life_support + supplies + progress + (10 - risk)) / 4",
    overall_index_min: 0.0,
    overall_index_max: 10.0,
    # The index realistically lives between ~2 and ~8; the narrower gauge
    # range makes a half-point swing visible on the scoreboard.
    overall_index_viz_min: 1.0,
    overall_index_viz_max: 9.0
  })

[
  "Barely Holding On",
  "Struggling",
  "Getting By",
  "Steady",
  "Thriving"
]
|> Enum.with_index(1)
|> Enum.each(fn {label, pos} ->
  {:ok, _} = Authoring.create_overall_index_band(scenario, %{label: en.(label), position: pos})
end)

# ── Media ───────────────────────────────────────────────────────────────────
# priv/repo/mars_colony/jezero-crater.png (rendered from the .svg next to it).
crater_png = Path.join(__DIR__, "mars_colony/jezero-crater.png")

{:ok, crater} =
  Scenex.Media.create_file(scenario, owner, %{
    filename: "jezero-crater.png",
    content_type: "image/png",
    size: File.stat!(crater_png).size,
    path: crater_png
  })

crater_url = Scenex.Media.public_path(crater)

# ── Values ──────────────────────────────────────────────────────────────────
# {key, name, formula, description, director's notes}
per_group_values = [
  {"life_support", "Life Support", "min",
   "Air, water, heat and shelter. The colony's reading is its **weakest** team's — one failing habitat endangers everyone.",
   "Aggregated with `min`: whoever is lowest *is* the colony's number. Point this out when one team lags behind — it is the strongest prompt for teams to talk to each other."},
  {"supplies", "Supplies", "(avg + min) / 2",
   "Food, spare parts, medicine, fuel. Counts the colony's average stock, but won't let any team be left with nothing.",
   "Half average, half minimum: hoarding by one team helps a little, but lifting the poorest team helps more."},
  {"progress", "Progress", "median",
   "Research, discoveries, new skills — how far the colony has come from just surviving.",
   "`median` stops one brilliant team (usually Science) from making the whole colony look more advanced than it is."},
  {"risk", "Risk", "max",
   "Strain, danger, things that could go wrong. The colony's reading is its **most** endangered team's. Lower is better.",
   "The only value where high is bad. `max` means a single reckless team sets the colony's risk."}
]

value_by_key =
  per_group_values
  |> Enum.with_index(1)
  |> Map.new(fn {{key, name, formula, desc, notes}, pos} ->
    {:ok, vd} =
      Authoring.create_value_dimension(scenario, %{
        key: key,
        name: en.(name),
        description: en.(desc),
        director_notes: en.(notes),
        aggregation: formula,
        input_scope: :per_group,
        min: 0.0,
        max: 10.0,
        default_value: 5.0,
        position: pos
      })

    {key, vd}
  end)

{:ok, morale} =
  Authoring.create_value_dimension(scenario, %{
    key: "morale",
    name: en.("Morale"),
    description: en.("How the crew is actually feeling — asked in the room, by show of hands."),
    director_notes:
      en.("""
      Never moved by options. Run a hand count at two moments: the end of Act
      1 (after *Settling In*) and the peak of the crisis (after *Rationing*).
      Ask: "Hands up — how are you feeling about life in the colony right
      now?" and count each step. Not part of Colony Vitality on purpose: it
      jumps at tally moments, so it gets its own readout.
      """),
    aggregation: "avg",
    input_scope: :per_participant,
    position: 5
  })

[
  {"😫", "Miserable"},
  {"😟", "Worried"},
  {"😐", "Okay"},
  {"🙂", "Good"},
  {"🤩", "Great"}
]
|> Enum.with_index(1)
|> Enum.each(fn {{emoji, label}, pos} ->
  {:ok, _} =
    Authoring.create_value_dimension_step(morale, %{
      emoji: emoji,
      label: en.(label),
      position: pos
    })
end)

# ── Groups ──────────────────────────────────────────────────────────────────
# Baseline 5 everywhere, ±2 for one strength and one weakness (see the brief).
group_desc = fn role, goal, tensions ->
  """
  #{role}

  **Your job:** #{goal}

  **What you'll argue about:**
  #{Enum.map_join(tensions, "\n", &("- " <> &1))}
  """
end

groups = [
  %{
    handle: "engineering",
    name: "Engineering & Habitat",
    desc:
      group_desc.(
        "Power, air, water pipes, airlocks — you build the colony and keep it standing.",
        "a colony that doesn't break.",
        ["Build fast or build safe?", "Your machines need parts that every other team wants too."]
      ),
    notes:
      "Strong on Life Support, weak on Progress: they know how to keep people alive, not how to invent. Their Act 1 power choices are what *The Storm* hits — remind them of it.",
    start: %{"life_support" => 7, "supplies" => 5, "progress" => 3, "risk" => 5}
  },
  %{
    handle: "science",
    name: "Science & Exploration",
    desc:
      group_desc.(
        "Geologists, astronomers, explorers. You are here to find out what Mars is hiding.",
        "discoveries that make the whole journey worth it.",
        ["Curiosity vs. safety.", "Your experiments eat supplies the colony may need."]
      ),
    notes:
      "Strong on Progress, short on Supplies. Tempt them with discoveries; let the others decide whether that is worth the cost.",
    start: %{"life_support" => 5, "supplies" => 3, "progress" => 7, "risk" => 5}
  },
  %{
    handle: "agriculture",
    name: "Agriculture & Life Systems",
    desc:
      group_desc.(
        "Greenhouses, algae tanks, water recycling — the living side of survival.",
        "feed twenty-five people on a planet where nothing has ever grown.",
        [
          "Proven methods vs. experiments that could change everything.",
          "Your greenhouse needs light, water and power — all scarce."
        ]
      ),
    notes:
      "The one deliberately high-Risk team: experimental farming is unpredictable. If the colony's Risk is high, it is usually them — which makes them a natural centre of attention.",
    start: %{"life_support" => 7, "supplies" => 5, "progress" => 5, "risk" => 7}
  },
  %{
    handle: "medical",
    name: "Medical & Crew Welfare",
    desc:
      group_desc.(
        "Doctors, nurses, and the person everyone talks to when they can't sleep.",
        "keep all twenty-five people healthy — in body and mind.",
        [
          "Treat everyone equally, or the people the colony needs most?",
          "Medicine runs out. Worry doesn't."
        ]
      ),
    notes:
      "Cautious by nature (lowest Risk) but short on Supplies. They are the team most likely to speak about Morale — invite them to when you run a tally.",
    start: %{"life_support" => 5, "supplies" => 3, "progress" => 5, "risk" => 3}
  },
  %{
    handle: "command",
    name: "Command & Earth Relations",
    desc:
      group_desc.(
        "Mission commander, logistics, and the only radio link back to Earth.",
        "keep the mission on course — and decide what Earth gets to know.",
        [
          "Honesty with Earth vs. keeping its support.",
          "You hold the most supplies, but your own quarters are the most fragile."
        ]
      ),
    notes:
      "Rich in Supplies, poor in Life Support — and Life Support uses `min`, so **Command starts as the colony's weakest link**. That is deliberate: the room should discover it. Command alone can call Earth during *The Storm*, which unlocks *Earth's Offer*.",
    start: %{"life_support" => 3, "supplies" => 7, "progress" => 5, "risk" => 5}
  }
]

group_by_handle =
  groups
  |> Enum.with_index(1)
  |> Map.new(fn {g, pos} ->
    {:ok, grp} =
      Authoring.create_group(scenario, %{
        handle: g.handle,
        name: en.(g.name),
        description: en.(g.desc),
        director_notes: en.(g.notes),
        position: pos
      })

    Enum.each(g.start, fn {key, v} ->
      {:ok, _} = Authoring.set_group_initial_value(grp, value_by_key[key], v * 1.0)
    end)

    {g.handle, grp}
  end)

# ── Labels ──────────────────────────────────────────────────────────────────
label_by_handle =
  [
    {"cautious", "Cautious", :info, "🛡️",
     "Plays it safe: lowers risk or protects what the team already has."},
    {"bold", "Bold", :warning, "🚀", "Goes for a big gain and accepts more risk or a cost."},
    {"team_player", "Team Player", :success, "🤝",
     "Helps the colony as a whole more than the team itself."}
  ]
  |> Enum.with_index(1)
  |> Map.new(fn {{handle, name, color, icon, notes}, pos} ->
    {:ok, l} =
      Authoring.create_label(scenario, %{
        handle: handle,
        name: en.(name),
        color: color,
        icon: icon,
        director_notes: en.(notes),
        position: pos
      })

    {handle, l}
  end)

# ── Helpers for timeline content ────────────────────────────────────────────
# Effect shorthand: ls / sup / pro / risk.
key_of = %{ls: "life_support", sup: "supplies", pro: "progress", risk: "risk"}

option_text = fn title, line -> "**#{title}** — #{line}" end

create_element = fn attrs ->
  {:ok, el} =
    Authoring.create_timeline_element(
      scenario,
      attrs
      |> Map.update(:title, nil, en)
      |> Map.update(:narrative, %{}, en)
      |> Map.update(:director_notes, %{}, en)
    )

  el
end

add_labels = fn option, labels ->
  {:ok, _} = Authoring.set_option_labels(option, Enum.map(labels, &label_by_handle[&1]))
end

# Event options: %{team => [{title, line, labels, effects, extra}]}. Effects hit
# the deciding team. `extra` may carry :default, :condition, :notes.
add_event_options = fn element, per_team ->
  Enum.each(per_team, fn {team, options} ->
    group = group_by_handle[team]

    options
    |> Enum.with_index(1)
    |> Enum.each(fn {{title, line, labels, effects, extra}, pos} ->
      {:ok, opt} =
        Authoring.create_decision_option(element, group, %{
          # Handles are unique per element: titles never repeat within a beat.
          handle: title,
          text: en.(option_text.(title, line)),
          condition: extra[:condition],
          is_default: Keyword.get(extra, :default, false),
          director_notes: if(extra[:notes], do: en.(extra[:notes]), else: %{}),
          position: pos
        })

      add_labels.(opt, labels)

      Enum.each(effects, fn {k, d} ->
        {:ok, _} = Authoring.set_option_effect(opt, value_by_key[key_of[k]], d * 1.0)
      end)
    end)
  end)
end

# Outcome matrix for Votes and Wildcards: %{team => [effects]}.
set_matrix = fn option, rows ->
  Enum.each(rows, fn {team, effects} ->
    Enum.each(effects, fn {k, d} ->
      {:ok, _} =
        Authoring.set_option_effect(
          option,
          value_by_key[key_of[k]],
          group_by_handle[team],
          d * 1.0
        )
    end)
  end)
end

add_outcomes = fn element, outcomes ->
  outcomes
  |> Enum.with_index(1)
  |> Enum.each(fn {{outcome, handle, text, rows}, pos} ->
    {:ok, opt} =
      Authoring.create_decision_option(element, nil, %{
        handle: handle,
        text: en.(text),
        outcome: outcome,
        position: pos
      })

    set_matrix.(opt, rows)
  end)
end

# ── Prologue: What to Bring ─────────────────────────────────────────────────
what_to_bring =
  create_element.(%{
    handle: "what_to_bring",
    kind: :event,
    position: 1,
    deadline_seconds: 300,
    title: "What to Bring",
    narrative: """
    **Prologue — Cape Canaveral, the night before launch.**

    The rocket is fuelled. The cargo hold has room for exactly one more
    crate per team. Whatever you pick tonight is what you will have on Mars
    — there is no next delivery for two years.

    *Choose your team's last crate. You have five minutes.*
    """,
    director_notes: """
    The tutorial round: low stakes, no wrong answers. Walk the room through
    the group boards while they decide. The five-minute deadline is real —
    a team that doesn't decide gets its ⏱ default crate.

    Every team's starting numbers are lopsided on purpose. Before you fire
    this, show the scoreboard: Colony Vitality starts in *Struggling*.
    """
  })

add_event_options.(what_to_bring, %{
  "engineering" => [
    {"Spare parts", "Crates of valves, seals and circuit boards. Boring. Essential.",
     ["cautious"], [ls: 1, sup: 1], [default: true]},
    {"3D printer", "A fabricator that can print almost any part — if you feed it.", ["bold"],
     [pro: 2, sup: -1], []},
    {"Backup systems", "A second set of everything critical, just in case.", ["cautious"],
     [risk: -2], []}
  ],
  "science" => [
    {"Deep-drill rig", "Drill 100 metres down, where water and maybe life could be.", ["bold"],
     [pro: 2, risk: 1], []},
    {"Lab supplies", "Sample freezers, chemicals, spare instruments.", ["cautious"], [sup: 2],
     [default: true]},
    {"Weather stations", "Twelve small sensors that watch the sky for the whole colony.",
     ["team_player"], [pro: 1, risk: -1],
     [
       notes:
         "Echo: if Science brought these, they get to announce the storm in Act 2 — hand them the microphone."
     ]}
  ],
  "agriculture" => [
    {"Seed vault", "Three hundred plant varieties, frozen and ready.", [], [sup: 1, pro: 1], []},
    {"Proven hydroponics", "The system that already works on the space station.", ["cautious"],
     [risk: -2], [default: true]},
    {"Gene-edited crops", "Fast-growing experimental plants. Nobody has tried them on Mars.",
     ["bold"], [pro: 2, sup: 1, risk: 1], []}
  ],
  "medical" => [
    {"Surgical suite", "A full operating room, folded into one crate.", ["bold"],
     [ls: 2, sup: -1], []},
    {"Medicine stockpile", "Two years of everything, for everyone.", ["cautious"], [sup: 2],
     [default: true]},
    {"Crew welfare kit", "Games, music, a VR headset with beaches. Sanity matters.",
     ["team_player"], [ls: 1, risk: -1],
     [
       notes:
         "Good moment to mention Morale: this crate is why the first tally may come out high."
     ]}
  ],
  "command" => [
    {"Oxygen reserves", "Extra tanks for your own quarters — the most fragile on board.",
     ["cautious"], [ls: 2, sup: -1], [default: true]},
    {"High-gain antenna", "A fast, private link to Mission Control.", [], [pro: 1, sup: 1], []},
    {"Trade goods", "Things to bargain with later. Earth sponsors love souvenirs.", ["bold"],
     [sup: 2, risk: 1], []}
  ]
})

# ── Act 1: Touchdown ────────────────────────────────────────────────────────
touchdown =
  create_element.(%{
    handle: "touchdown",
    kind: :event,
    position: 2,
    title: "Touchdown",
    narrative: """
    **Act 1 — Sol 1, Jezero Crater.**

    ![Jezero Crater](#{crater_url})

    Seven months in space, seven minutes of terror, and then: dust settling
    on a silent red plain. The landing went *mostly* to plan. One cargo pod
    came down three kilometres off target.

    Everyone has a hundred things to do and only time for one. **What does
    your team do first?**
    """,
    director_notes: """
    Let the moment breathe — dim the lights, play a landing sound if you have
    one. No deadline: close it yourself when every team has chosen.

    Watch Command: if their Life Support is still the colony's lowest, say
    out loud that the whole colony's Life Support is only as good as theirs.
    """
  })

add_event_options.(touchdown, %{
  "engineering" => [
    {"Habitat first", "Inflate the living modules and get everyone out of their suits.",
     ["cautious"], [ls: 2, sup: -1], []},
    {"Solar field first",
     "Unroll the solar panels on the open plain — fast power, fully exposed.", ["bold"],
     [pro: 2, risk: 1],
     [notes: "Echo: this exposed solar field is what the storm buries in Act 2."]}
  ],
  "science" => [
    {"Explore the crater", "First humans on Mars. Go and look!", ["bold"], [pro: 2, risk: 1], []},
    {"Help unpack", "Science can carry boxes too.", ["team_player"], [sup: 2, ls: 1], []}
  ],
  "agriculture" => [
    {"Plant immediately", "Break ground on the greenhouse today. Every day counts.", ["bold"],
     [sup: 2, risk: 1], []},
    {"Test the soil first", "Mars soil contains perchlorates. Find out how much.", ["cautious"],
     [pro: 1, risk: -1], []}
  ],
  "medical" => [
    {"Health checks", "Scan all twenty-five people after the landing.", ["cautious"],
     [risk: -2, sup: -1], []},
    {"Open the common room", "Hot drinks, a place to sit, someone to talk to.", ["team_player"],
     [ls: 1, sup: 1], []}
  ],
  "command" => [
    {"Honest report", "Tell Earth everything, including the lost cargo pod.", ["team_player"],
     [risk: -1], []},
    {"Good-news report", "\"Landing perfect, morale excellent.\" Sponsors stay happy.", ["bold"],
     [sup: 2, risk: 1],
     [
       notes:
         "Echo: if Command polished the truth here, *Off the Record* gets much juicier later."
     ]},
    {"Recover the pod", "Lead a team out to the lost cargo before nightfall.", [],
     [ls: 2, sup: 1, risk: 1], []}
  ]
})

# ── Act 1: Settling In ──────────────────────────────────────────────────────
settling_in =
  create_element.(%{
    handle: "settling_in",
    kind: :event,
    position: 3,
    title: "Settling In",
    narrative: """
    **Act 1 — Sol 30.**

    The colony has a rhythm now: wake-up call, oatmeal, work, the evening
    broadcast from Earth. It is time to build something that will last.

    Each team can make **one big investment**. Some of them need resources
    your team may not have — look closely before you choose.
    """,
    director_notes: """
    This is the beat Act 2 pays off. Write down (or note in the console) what
    Engineering and Agriculture build: the storm hits power and the
    greenhouse hardest.

    Several options are **gated** (greyed out on the board) — a good moment
    to explain that a locked option shows its condition, so a team knows
    what it would need. Other teams can't transfer numbers, but they can
    argue.

    Afterwards: **Morale tally #1**.
    """
  })

add_event_options.(settling_in, %{
  "engineering" => [
    {"Expand the solar field", "Double the panels. Power for every project anyone dreams up.",
     ["bold"], [pro: 3, sup: -1, risk: 1],
     [notes: "Echo: the bigger the solar field, the harder The Storm lands."]},
    {"Bury the cables", "Protect the power lines under a metre of regolith.", ["cautious"],
     [risk: -2, sup: -1], [condition: "self(supplies) >= 4"]},
    {"Battery bank", "Store power for the long night — or the day the sun goes out.",
     ["cautious", "team_player"], [ls: 2, risk: -1, sup: -2],
     [
       condition: "self(supplies) >= 5",
       notes:
         "Echo: if they built this, tell them during The Storm that the batteries are what's keeping the lights on."
     ]}
  ],
  "science" => [
    {"Long expedition", "Two weeks in a rover, 400 kilometres, the old river delta.", ["bold"],
     [pro: 3, risk: 1], []},
    {"Weather radar", "Turn the weather stations into a real early-warning system.",
     ["team_player"], [pro: 2, risk: -2], [condition: "self(progress) >= 9"]},
    {"Share the lab", "Lend equipment and people to Agriculture and Medical.", ["team_player"],
     [sup: 1, ls: 1], []}
  ],
  "agriculture" => [
    {"Second greenhouse", "Twice the food — and twice the power and water to run it.", ["bold"],
     [sup: 3, risk: 1], [condition: "self(supplies) >= 5"]},
    {"Water recycling loop", "Reclaim ninety-eight percent of every drop.", ["cautious"], [ls: 2],
     []},
    {"Algae tanks", "Ugly, green, and edible. Food that needs almost no light.", ["cautious"],
     [sup: 1, risk: -2], []}
  ],
  "medical" => [
    {"Radiation shelter", "A shielded sleeping area for everyone.", ["cautious"],
     [risk: -2, sup: -1], []},
    {"Mental health program", "Daily check-ins, a quiet room, a buddy system.", ["team_player"],
     [ls: 2, pro: 1], []},
    {"First-aid training", "Teach every colonist to handle an emergency.", ["team_player"],
     [risk: -1, pro: 1], []}
  ],
  "command" => [
    {"Colony council", "A daily meeting where every team has a voice.", ["team_player"],
     [risk: -1, ls: 2], []},
    {"Emergency plan", "Rationing rules, ready before anyone needs them.", ["cautious"],
     [sup: 2, risk: -1], []},
    {"Media deal", "Sell live footage to an Earth streaming service.", ["bold"],
     [sup: 2, pro: 1, risk: 1], []}
  ]
})

# ── Wildcards (GM-adjudicated, any time) ────────────────────────────────────
green_thumb =
  create_element.(%{
    handle: "green_thumb",
    kind: :sidequest,
    position: 4,
    title: "Green Thumb",
    narrative: """
    One of the farmers has a wild idea: grow potatoes in pure Mars soil,
    treated with a trick nobody has tried yet. But the experiment needs a
    corner of the Science lab — and nobody asked Science.

    **Your mission:** convince Science to lend you the space, then try it.
    """,
    director_notes: """
    Give this card quietly to one Agriculture player. **Success** if Science
    agrees openly. **Failure** if the farmer goes ahead without asking, or
    Science says no and the experiment happens anyway.
    """
  })

add_outcomes.(green_thumb, [
  {:success, "Potatoes on Mars", "The potatoes grow. Science gets a paper out of it, too.",
   %{"agriculture" => [sup: 2, pro: 1, risk: -1], "science" => [pro: 1]}},
  {:failure, "Contaminated lab", "The soil leaks perchlorate dust across the lab bench.",
   %{"agriculture" => [risk: 1, sup: -1], "science" => [sup: -1]}}
])

the_find =
  create_element.(%{
    handle: "the_find",
    kind: :sidequest,
    position: 5,
    title: "The Find",
    narrative: """
    The drill brings up something strange: layered crystals with a pattern
    no one can explain. It could be the discovery of the century — or
    nothing at all.

    **Your mission:** decide whether to tell everyone now, or keep digging in
    secret until you are sure.
    """,
    director_notes: """
    Give this to one Science player. **Success** if they share the find
    openly with the colony (and Command passes it on to Earth). **Failure**
    if they keep it secret and another team finds out.
    """
  })

add_outcomes.(the_find, [
  {:success, "Shared with the world", "Earth goes wild. Funding and attention pour in.",
   %{"science" => [pro: 3], "command" => [sup: 1]}},
  {:failure, "Secret leaks", "The rumour spreads before the results do. Trust takes a hit.",
   %{"science" => [pro: -1, risk: 1], "command" => [sup: -1]}}
])

# ── Act 2: The Storm ────────────────────────────────────────────────────────
the_storm =
  create_element.(%{
    handle: "the_storm",
    kind: :event,
    position: 6,
    deadline_seconds: 240,
    title: "The Storm",
    narrative: """
    **Act 2 — Sol 112.**

    The sky turns orange, then brown, then black. A dust storm the size of a
    continent rolls over Jezero Crater. Solar power drops by eighty percent
    in an hour. Nobody knows how long it will last.

    There are no good options left — only less bad ones. **Decide fast: you
    have four minutes.**
    """,
    director_notes: """
    The tone shift. Lights down, storm sound up. Before you fire it, call the
    echoes: the solar field Engineering expanded, the greenhouse Agriculture
    built, the weather stations Science brought (or didn't).

    Every option costs something — that is the point. Teams that don't
    decide in time get their ⏱ default.

    **Command's fork:** if Command chooses *Call Earth*, the Vote *Earth's
    Offer* becomes available later. If not, skip it.
    """
  })

add_event_options.(the_storm, %{
  "engineering" => [
    {"Repair outside", "Suit up and clear the panels in the storm. Dangerous.", ["bold"],
     [ls: 1, risk: 2, sup: -1], []},
    {"Power down", "Switch off everything that isn't keeping someone alive.", ["cautious"],
     [pro: -2, ls: -1, sup: -1], [default: true]},
    {"Drain the batteries", "Run the colony on stored power and pray the sun comes back.", [],
     [sup: -2], [notes: "Only makes sense if they built the Battery bank — say so."]}
  ],
  "science" => [
    {"Track the storm", "Feed the colony live forecasts, hour by hour.", ["team_player"],
     [pro: -1, risk: -1, sup: -1], []},
    {"Save the samples", "Keep the freezers running. Two years of work are in there.", ["bold"],
     [ls: -2, sup: -1], [default: true]},
    {"Join Engineering", "Close the lab and lend every hand to the repair crews.",
     ["team_player"], [pro: -2, sup: 1], []}
  ],
  "agriculture" => [
    {"Keep the lights on", "Run the grow lights on emergency power.", ["bold"],
     [ls: -1, risk: 1, sup: -1], []},
    {"Let the crops sleep", "Put the greenhouse into dormancy and hope.", ["cautious"], [sup: -2],
     [default: true]},
    {"Harvest everything", "Pick all of it now, ripe or not.", [], [sup: 1, pro: -2, risk: 1], []}
  ],
  "medical" => [
    {"Shelter in the core", "Move everyone into the best-shielded module.", ["cautious"],
     [ls: -1, risk: -1, sup: -1], [default: true]},
    {"Keep the clinic open", "Full power to the medical bay, whatever it costs.", [],
     [sup: -2, risk: -1], []},
    {"Ration the medicine", "Prepare for a long storm: hold back what you can.", ["cautious"],
     [sup: 1, ls: -2], []}
  ],
  "command" => [
    {"Call Earth", "Admit we need help. Open the emergency channel.", ["team_player"],
     [risk: -1, pro: -1, sup: -1],
     [
       notes:
         "This unlocks the Vote *Earth's Offer*. Make it visible — announce that Earth will answer."
     ]},
    {"We handle this", "No call, no excuses. The colony fixes its own problems.", ["bold"],
     [pro: 1, risk: 1, sup: -1], [default: true]},
    {"Lockdown", "Everyone indoors, all teams under Command's orders.", ["cautious"],
     [ls: -1, risk: -1, pro: -1, sup: -1], []}
  ]
})

# ── Act 2: Rationing (two shades — the GM fires exactly one) ────────────────
rationing_notes = fn shade ->
  """
  **Shade: #{shade}.** *Rationing* exists in two versions; fire exactly
  **one**. Choose by where Colony Vitality stands after *The Storm*:

  - *Getting By* or better → **Holding Together** (milder trade-offs).
  - *Struggling* or worse → **Struggling** (harsher ones).

  The players never know there was another version. Afterwards:
  **Morale tally #2**.
  """
end

rationing_holding =
  create_element.(%{
    handle: "rationing_holding",
    kind: :event,
    position: 7,
    title: "Rationing",
    narrative: """
    **Act 2 — Sol 130.** The storm has lasted eighteen days.

    The colony has held together so far — but the power budget is a
    quarter of what it was. Greenhouse lights, medical equipment, the labs
    and the Earth link all compete for the same few kilowatts.

    **Every team has to give something up. What will it be?**
    """,
    director_notes: rationing_notes.("Holding Together")
  })

add_event_options.(rationing_holding, %{
  "engineering" => [
    {"Patch and pray", "Keep everything half-running with improvised fixes.", ["bold"],
     [ls: -1, risk: 1], []},
    {"Shut one module", "Close the workshop and give its power away.", ["team_player"], [pro: -1],
     []}
  ],
  "science" => [
    {"Pause the research", "Freeze every experiment until the sun comes back.", ["team_player"],
     [pro: -1], []},
    {"Keep one project", "Protect the most important experiment, cut the rest.", [], [sup: -1],
     []}
  ],
  "agriculture" => [
    {"Ration the greenhouse", "Half the light, half the harvest.", ["cautious"], [sup: -1], []},
    {"Feed the algae", "Shift everything to the algae tanks. Nobody will love the menu.",
     ["team_player"], [sup: 1, ls: -1], []}
  ],
  "medical" => [
    {"Triage the equipment", "Only life-critical machines stay on.", ["cautious"], [ls: -1], []},
    {"Night clinic", "Run the medical bay only at night, when demand is low.", [],
     [risk: 1, sup: 1], []}
  ],
  "command" => [
    {"Cut the Earth link", "One message a day. The rest of the bandwidth goes to the teams.",
     ["team_player"], [pro: -1, risk: -1], []},
    {"Fair shares", "Every team gets exactly the same power, no exceptions.", ["cautious"],
     [sup: -1, risk: -1], []}
  ]
})

rationing_struggling =
  create_element.(%{
    handle: "rationing_struggling",
    kind: :event,
    position: 8,
    title: "Rationing",
    narrative: """
    **Act 2 — Sol 130.** The storm has lasted eighteen days.

    Things are bad. Two habitat modules are already dark and cold. People
    are sleeping in shifts in the warm ones. The power budget is barely
    enough to keep twenty-five people breathing.

    **Every team has to give something up — and it is going to hurt.**
    """,
    director_notes: rationing_notes.("Struggling")
  })

add_event_options.(rationing_struggling, %{
  "engineering" => [
    {"Patch and pray", "Keep everything half-running with improvised fixes.", ["bold"],
     [ls: -1, risk: 2], []},
    {"Shut one module", "Close the workshop and give its power away.", ["team_player"],
     [pro: -2, sup: -1], []}
  ],
  "science" => [
    {"Pause the research", "Freeze every experiment until the sun comes back.", ["team_player"],
     [pro: -2], []},
    {"Keep one project", "Protect the most important experiment, cut the rest.", [],
     [sup: -2, risk: 1], []}
  ],
  "agriculture" => [
    {"Ration the greenhouse", "A third of the light, a third of the harvest.", ["cautious"],
     [sup: -2], []},
    {"Feed the algae", "Shift everything to the algae tanks. Nobody will love the menu.",
     ["team_player"], [sup: 1, ls: -2], []}
  ],
  "medical" => [
    {"Triage the equipment", "Only life-critical machines stay on.", ["cautious"],
     [ls: -1, risk: 1], []},
    {"Night clinic", "Run the medical bay only at night, when demand is low.", [],
     [risk: 1, sup: 1], []}
  ],
  "command" => [
    {"Cut the Earth link", "One message a day. The rest of the bandwidth goes to the teams.",
     ["team_player"], [pro: -1, risk: -1], []},
    {"Fair shares", "Every team gets exactly the same power, no exceptions.", ["cautious"],
     [sup: -2], []}
  ]
})

# ── More Wildcards for Act 2 ────────────────────────────────────────────────
jury_rig =
  create_element.(%{
    handle: "jury_rig_it",
    kind: :sidequest,
    position: 9,
    title: "Jury-Rig It",
    narrative: """
    An engineer knows a shortcut: rewire the greenhouse's backup pump to
    power the airlock heaters. It would work. Probably. But the pump belongs
    to Agriculture.

    **Your mission:** get the fix done — with or without asking.
    """,
    director_notes: """
    For one Engineering player. **Success** if Agriculture agrees to the
    trade (or the engineer finds another way). **Failure** if they take the
    pump without asking and get caught.
    """
  })

add_outcomes.(jury_rig, [
  {:success, "It holds", "The heaters run, and Agriculture gets the pump back by morning.",
   %{"engineering" => [ls: 2, risk: -1], "agriculture" => [sup: -1]}},
  {:failure, "Caught red-handed", "The pump fails mid-rewire. Two teams are now furious.",
   %{"engineering" => [risk: 1, ls: -1], "agriculture" => [sup: -2]}}
])

triage =
  create_element.(%{
    handle: "triage",
    kind: :sidequest,
    position: 10,
    title: "Triage",
    narrative: """
    Three colonists are sick, and there is medicine for two. Someone has to
    decide — and someone has to announce it to the colony.

    **Your mission:** make the call, and explain it to everyone.
    """,
    director_notes: """
    For one Medical player. **Success** if they announce a clear decision
    *and* the reasoning to the whole room. **Failure** if they avoid the
    decision or keep it secret. Keep it gentle — nobody dies in this
    scenario; the third patient simply recovers more slowly.
    """
  })

add_outcomes.(triage, [
  {:success, "A fair call",
   "The colony accepts the decision. It hurts, but people trust Medical.",
   %{"medical" => [ls: 2, risk: -1]}},
  {:failure, "Whispers", "Rumours fill the silence. People stop coming to the clinic.",
   %{"medical" => [ls: -2, risk: 1]}}
])

off_the_record =
  create_element.(%{
    handle: "off_the_record",
    kind: :sidequest,
    position: 11,
    title: "Off the Record",
    narrative: """
    You overheard something you weren't supposed to: Earth has already
    replied to the colony's emergency call — and their offer has strings
    attached.

    **Your mission:** decide what to do with what you know.
    """,
    director_notes: """
    For one player of **any team except Command**, and only if Command chose
    *Call Earth*. Ideal lead-in to the Vote. **Success** if the player gets
    Command to put the offer openly before the colony. **Failure** if it
    spreads as a rumour first.
    """
  })

add_outcomes.(off_the_record, [
  {:success, "Out in the open", "Command reads Earth's message aloud. Nothing is hidden.",
   %{"command" => [risk: -1, ls: 1]}},
  {:failure, "Rumour mill", "By dinner everyone has heard a different version.",
   %{"command" => [risk: 1, sup: -1], "medical" => [risk: 1]}}
])

# ── Act 2: the Vote ─────────────────────────────────────────────────────────
earths_offer =
  create_element.(%{
    handle: "earths_offer",
    kind: :election,
    position: 12,
    deadline_seconds: 480,
    title: "Earth's Offer",
    narrative: """
    **Act 2 — Sol 140.** Mission Control has answered the emergency call.

    A resupply rocket can launch next week — but someone has to pay for it.
    There are three ways forward. **The whole colony votes. One person, one
    vote.**
    """,
    director_notes: """
    Only fire this if Command chose *Call Earth* during *The Storm*.

    The ballot isn't shown on any screen by itself: put up the page *Earth's
    Offer* so the room can read the three options, and read them aloud. Then
    give the room three minutes to campaign: each team may send one speaker.
    Then a show of hands per option; enter the count in the console. On a
    tie, you decide. If time runs out, the ⏱ default (the sponsor deal)
    wins.

    *Go it alone* is gated on the colony's Supplies — a colony that is
    already starving cannot afford pride. If the colony's Supplies are below
    3, take it off the ballot and say why.
    """
  })

{:ok, sponsor} =
  Authoring.create_decision_option(earths_offer, nil, %{
    handle: "Sponsor deal",
    text: en.("Take the sponsor deal"),
    is_default: true,
    position: 1
  })

add_labels.(sponsor, ["cautious"])

set_matrix.(sponsor, %{
  "engineering" => [sup: 2],
  "science" => [sup: 2, pro: -2],
  "agriculture" => [sup: 2],
  "medical" => [sup: 2],
  "command" => [sup: 1, risk: 1]
})

{:ok, extend} =
  Authoring.create_decision_option(earths_offer, nil, %{
    handle: "Extend the mission",
    text: en.("Extend the mission"),
    position: 2
  })

add_labels.(extend, ["team_player"])

set_matrix.(extend, %{
  "engineering" => [sup: 2, ls: 1],
  "science" => [sup: 2, pro: 1],
  "agriculture" => [sup: 2, ls: 1],
  "medical" => [sup: 1, risk: 1],
  "command" => [sup: 1, ls: 1]
})

{:ok, alone} =
  Authoring.create_decision_option(earths_offer, nil, %{
    handle: "Go it alone",
    text: en.("Go it alone"),
    condition: "global(supplies) >= 3",
    director_notes:
      en.("Gated: only on the ballot if the colony still has Supplies of 3 or more."),
    position: 3
  })

add_labels.(alone, ["bold"])

set_matrix.(alone, %{
  "engineering" => [pro: 1, sup: -1],
  "science" => [pro: 2, sup: -1],
  "agriculture" => [risk: 1, sup: -1],
  "medical" => [sup: -1],
  "command" => [risk: 1, pro: 1]
})

# ── Endings ─────────────────────────────────────────────────────────────────
# Conditions only see globals, so they spell out Colony Vitality's formula.
vitality = "(global(life_support) + global(supplies) + global(progress) + 10 - global(risk)) / 4"

endings = [
  {"colony_holds", "The Colony Holds", "#{vitality} >= 5.5", 30,
   """
   The storm passes on Sol 151. The first sunlight in five weeks hits the
   solar panels, and someone starts cheering over the intercom.

   The colony made it — not because nothing went wrong, but because
   twenty-five people kept talking to each other when it did. Earth calls it
   a miracle. You know it was a lot of hard choices.
   """,
   "Warm and celebratory. Bring the teams together in the middle of the room and read the narrative aloud."},
  {"getting_by", "Getting By", "#{vitality} >= 3.5", 20,
   """
   The storm passes on Sol 151. The colony is still here — cold, tired, a
   little smaller in its ambitions than it was at launch.

   Something was traded away to get through it: time, freedom, or the
   discoveries you came for. Was it the right trade? You will have years to
   argue about it.
   """,
   "Honest and open-ended. Ask each team what they would trade differently next time — straight into the debrief."},
  {"on_the_brink", "On the Brink", "#{vitality} < 3.5", 10,
   """
   The storm passes on Sol 151, and the colony is barely holding on. Half
   the modules are dark. The greenhouse is a graveyard of brown leaves.

   But all twenty-five of you are alive, and on the horizon the sun is
   coming up. You can rebuild. The question is whether you will do it
   together this time.
   """,
   "Sobering, never hopeless — this is for teenagers. End on the sunrise line, then go straight to the debrief: what would have changed the outcome?"}
]

Enum.each(endings, fn {handle, title, condition, priority, narrative, notes} ->
  {:ok, _} =
    Authoring.create_ending(scenario, %{
      handle: handle,
      title: en.(title),
      narrative: en.(narrative),
      director_notes: en.(notes),
      condition: condition,
      priority: priority
    })
end)

# ── Pages (scoreboard slides) ───────────────────────────────────────────────
pages = [
  {"Title",
   """
   ![Mars Colony — Jezero Crater at dawn](#{crater_url})
   """},
  {"Welcome",
   """
   # 🚀 Mars Colony

   ### Twenty-five people. One red planet. No second chances.

   Please find your team's table. Scan the QR code on it with one phone or tablet.
   """},
  {"Mission Briefing",
   """
   # Mission Briefing

   You are the crew of humanity's first permanent colony on Mars.

   - **Five teams**, each with its own job — and its own numbers.
   - The **GM** tells the story. When a moment comes, your team decides together on your screen.
   - Every choice moves your team's numbers. The colony's numbers on this screen are built from all five teams.

   **Life Support** is only as good as the *weakest* team. **Risk** is as bad as the *most reckless* one.

   Talk to each other.
   """},
  {"Sol 40",
   """
   # Sol 40

   The colony is running. The greenhouse is green. Earth is impressed.

   ### Then the weather report changes.
   """},
  {"Earth's Offer",
   """
   # Earth's Offer

   A resupply rocket can launch next week. Who pays for it?

   1. **Take the sponsor deal** — a tech company pays. In return, it owns every discovery made on Mars.
   2. **Extend the mission** — Earth pays, if the crew stays four extra years before anyone can go home.
   3. **Go it alone** — thank Earth, and refuse. We get through this ourselves, and own what we build.

   *One person, one vote.*
   """},
  {"Debrief",
   """
   # Debrief

   - Which decision mattered most — and who made it?
   - When did your team help another team? When did it not?
   - What would you trade differently next time?

   *Thank you for playing Mars Colony.*
   """}
]

pages
|> Enum.with_index(1)
|> Enum.each(fn {{handle, content}, pos} ->
  {:ok, _} =
    Authoring.create_page(scenario, %{handle: handle, content: en.(content), position: pos})
end)

IO.puts("""
Seeded Mars Colony:
  owner:     #{owner.email}
  scenario:  #{scenario.id}
  values:    #{map_size(value_by_key)} per-group + 1 per-participant (morale)
  groups:    #{map_size(group_by_handle)}
  timeline:  #{length(Authoring.list_timeline_elements(scenario))} elements
  endings:   #{length(endings)}
  pages:     #{length(pages)}
  media:     #{crater_url}
""")
