defmodule Scenex.DemoScenario do
  @moduledoc """
  Creates the CIVITAS demo scenario for a given owner — the mini-megagame
  test scenario (alpha v0.2) in English: three groups (Government,
  Grassroots Movement, Economy/Media) respond to societal crises, and their
  decisions shift the shared values.

  Idempotent per user: refuses to create a second scenario with the same
  handle. Everything runs in one transaction — either the whole scenario
  exists afterwards, or nothing does.

  On production, run it via the release task:

      bin/scenex eval 'Scenex.Release.demo_scenario("owner@example.com")'
  """

  alias Scenex.Accounts.User
  alias Scenex.Authoring
  alias Scenex.Repo

  @handle "CIVITAS"

  @spec create(User.t()) :: {:ok, Authoring.Scenario.t()} | {:error, :already_exists}
  def create(%User{} = user) do
    if Enum.any?(Authoring.list_scenarios_for_user(user), &(&1.handle == @handle)) do
      {:error, :already_exists}
    else
      Repo.transaction(fn -> build(user) end)
    end
  end

  defp build(user) do
    {:ok, scenario} =
      Authoring.create_scenario(user, %{
        handle: @handle,
        name: en("CIVITAS"),
        description:
          en("""
          Mini-megagame test scenario (alpha v0.2): three groups respond to
          societal crises, and their decisions shift the shared values.
          """),
        source_locale: "en"
      })

    dims = create_dimensions(scenario)
    groups = create_groups(scenario, dims)
    labels = create_labels(scenario)
    create_timeline(scenario, dims, groups, labels)
    create_endings(scenario)
    scenario
  end

  defp en(text), do: %{"en" => text}

  # ── Value dimensions ──────────────────────────────────────────────────

  defp create_dimensions(scenario) do
    specs = [
      %{key: "well_being", name: "Well-being", input_scope: :per_participant, position: 0},
      %{key: "stability", name: "Stability", min: 0.0, max: 10.0, position: 1},
      %{key: "solidarity", name: "Solidarity", min: 0.0, max: 10.0, position: 2},
      %{key: "influence", name: "Influence", min: 0.0, max: 10.0, position: 3},
      %{key: "resources", name: "Resources", min: 0.0, max: 10.0, position: 4},
      %{key: "risk", name: "Risk", min: 0.0, max: 10.0, position: 5}
    ]

    for spec <- specs, into: %{} do
      attrs = spec |> Map.put(:name, en(spec.name)) |> Map.put_new(:input_scope, :per_group)
      {:ok, vd} = Authoring.create_value_dimension(scenario, attrs)
      {spec.key, vd}
    end
  end

  # ── Groups & initial values ───────────────────────────────────────────

  defp create_groups(scenario, dims) do
    groups = [
      %{
        handle: "Government",
        name: "Government",
        position: 1,
        initials: %{
          "stability" => 7.0,
          "solidarity" => 4.0,
          "influence" => 6.0,
          "resources" => 5.0,
          "risk" => 5.0
        },
        description: """
        Institutions • Order • Legitimacy

        **Goal:** Keep the country functioning and make decisions possible.

        **Typical tensions:**
        - Order vs. freedom
        - Stability (short term) vs. legitimacy (long term)

        **Guiding questions:**
        - What stabilises immediately?
        - What costs solidarity?
        - Where does escalation emerge?
        - Where is dialogue possible?
        """
      },
      %{
        handle: "Grassroots",
        name: "Grassroots Movement",
        position: 2,
        initials: %{
          "stability" => 4.0,
          "solidarity" => 8.0,
          "influence" => 4.0,
          "resources" => 5.0,
          "risk" => 5.0
        },
        description: """
        Civil society • Participation • Justice

        **Goal:** Strengthen social cohesion and make voices visible.

        **Typical tensions:**
        - Pressure vs. dialogue
        - Radicalism vs. broad appeal

        **Guiding questions:**
        - Whose voices are missing?
        - When does protest turn destructive?
        - How does real solidarity emerge?
        - Where does mobilisation tip into escalation?
        """
      },
      %{
        handle: "Economy-Media",
        name: "Economy / Media",
        position: 3,
        initials: %{
          "stability" => 5.0,
          "solidarity" => 4.0,
          "influence" => 5.0,
          "resources" => 7.0,
          "risk" => 6.0
        },
        description: """
        Markets • Public sphere • Narratives

        **Goal:** Preserve economic room to act and win the battle for interpretation.

        **Typical tensions:**
        - Profit vs. responsibility
        - Attention vs. trust

        **Guiding questions:**
        - What brings short-term gains?
        - What destroys trust in the long run?
        - Which narratives dominate?
        - Where does media responsibility lie?
        """
      }
    ]

    for spec <- groups, into: %{} do
      {:ok, group} =
        Authoring.create_group(scenario, %{
          handle: spec.handle,
          name: en(spec.name),
          description: en(spec.description),
          position: spec.position
        })

      for {key, initial} <- spec.initials do
        {:ok, _} = Authoring.set_group_initial_value(group, dims[key], initial)
      end

      {spec.handle, group}
    end
  end

  # ── Labels ────────────────────────────────────────────────────────────

  defp create_labels(scenario) do
    labels = [
      %{handle: "De-escalation", icon: "🔻", color: :success},
      %{handle: "Escalation", icon: "🔺", color: :error},
      %{handle: "Neutral", icon: "⚪", color: :neutral}
    ]

    for spec <- labels, into: %{} do
      {:ok, label} =
        Authoring.create_label(scenario, %{
          handle: spec.handle,
          name: en(spec.handle),
          icon: spec.icon,
          color: spec.color
        })

      {spec.handle, label}
    end
  end

  # ── Timeline ──────────────────────────────────────────────────────────

  defp create_timeline(scenario, dims, groups, labels) do
    for element_spec <- elements() do
      {:ok, element} =
        Authoring.create_timeline_element(
          scenario,
          element_spec
          |> Map.take([:handle, :kind, :position, :deadline_seconds])
          |> Map.put(:title, en(element_spec.title))
          |> Map.put(:narrative, en(element_spec.narrative))
          |> maybe_notes(element_spec)
        )

      for {option_spec, index} <- Enum.with_index(element_spec.options, 1) do
        group = option_spec[:group] && Map.fetch!(groups, option_spec.group)

        attrs =
          %{handle: option_spec.handle, text: en(option_spec.text), position: index}
          |> maybe_put(:condition, option_spec[:condition])
          |> maybe_put(:outcome, option_spec[:outcome])

        {:ok, option} = Authoring.create_decision_option(element, group, attrs)

        for {key, target_handle, delta} <- option_spec.effects do
          target = target_handle && Map.fetch!(groups, target_handle)
          {:ok, _} = Authoring.set_option_effect(option, Map.fetch!(dims, key), target, delta)
        end

        if label = option_spec[:label] do
          {:ok, _} = Authoring.set_option_labels(option, [Map.fetch!(labels, label)])
        end
      end
    end
  end

  defp maybe_notes(attrs, %{director_notes: notes}),
    do: Map.put(attrs, :director_notes, en(notes))

  defp maybe_notes(attrs, _spec), do: attrs

  defp maybe_put(attrs, _key, nil), do: attrs
  defp maybe_put(attrs, key, value), do: Map.put(attrs, key, value)

  defp elements do
    [
      %{
        handle: "Mass Protests",
        title: "Mass Protests",
        kind: :event,
        position: 1,
        deadline_seconds: 300,
        narrative: """
        Public pressure • Blockades • Risk of escalation

        **Context:**
        - Spontaneous demonstrations break out across the country.
        - Different groups take to the streets for different reasons.
        - Roads are blocked; the mood is heated.

        **Discussion prompts:**
        - What happens when order becomes more important than trust?
        - How much conflict can democracy withstand?
        - Who gets to speak — and who goes unheard?
        """,
        options: [
          %{
            group: "Government",
            handle: "Deploy police in force",
            label: "Escalation",
            effects: [{"stability", nil, 2.0}, {"solidarity", nil, -2.0}, {"risk", nil, 2.0}],
            text: """
            Fast control of the streets — at a cost to trust.

            **Pro:** Restores order quickly; Signals capacity to act; Stabilising in the short term

            **Contra:** Loss of trust; Possible radicalisation; International criticism / loss of legitimacy
            """
          },
          %{
            group: "Government",
            handle: "Offer of dialogue",
            label: "De-escalation",
            effects: [{"stability", nil, -1.0}, {"solidarity", nil, 2.0}, {"risk", nil, -1.0}],
            text: """
            Negotiate instead of cracking down — lower the conflict, but lose momentum.

            **Pro:** Reduces tensions; Strengthens cohesion; Lowers the risk of escalation

            **Contra:** May look weak; Takes time; Order not guaranteed immediately
            """
          },
          %{
            group: "Government",
            handle: "Media campaign for calm",
            label: "Neutral",
            effects: [{"solidarity", nil, 1.0}, {"influence", nil, 1.0}, {"risk", nil, 1.0}],
            text: """
            Steer the narrative without escalating directly — but with friction.

            **Pro:** Low direct cost; No immediate coercion; Controls the narrative

            **Contra:** Uncertain effect; Accusations of propaganda; Can escalate indirectly
            """
          },
          %{
            group: "Grassroots",
            handle: "Intensify the protests",
            label: "Escalation",
            effects: [{"stability", nil, -1.0}, {"influence", nil, 2.0}, {"risk", nil, 2.0}],
            text: """
            Build more pressure — at a higher risk of escalation.

            **Pro:** Raises political pressure; More visibility; Mobilises supporters

            **Contra:** Risk of escalation; Repression more likely; Moderate supporters drop away
            """
          },
          %{
            group: "Grassroots",
            handle: "Mediation",
            label: "De-escalation",
            effects: [{"solidarity", nil, 2.0}, {"influence", nil, -1.0}, {"risk", nil, -1.0}],
            text: """
            Build bridges — less pressure, but more trust.

            **Pro:** Constructive actor; Strengthens cohesion; Lowers the potential for violence

            **Contra:** Less pressure; Risk of being sidelined; May look soft internally
            """
          },
          %{
            group: "Grassroots",
            handle: "Hand over a list of demands",
            label: "De-escalation",
            effects: [{"solidarity", nil, 1.0}, {"influence", nil, 1.0}],
            text: """
            Protest becomes politically concrete — broader appeal.

            **Pro:** Clear position; Connects protest & dialogue; Broadly acceptable

            **Contra:** Implementation uncertain; Less media impact; Can get watered down
            """
          },
          %{
            group: "Economy-Media",
            handle: "Polarising coverage",
            label: "Escalation",
            effects: [{"influence", nil, 2.0}, {"risk", nil, 2.0}],
            text: """
            Maximise attention — sharpen the conflict.

            **Pro:** High reach; Clicks / market share; Agenda setting

            **Contra:** Sharpens conflicts; Loss of trust; Long-term destabilisation
            """
          },
          %{
            group: "Economy-Media",
            handle: "De-escalating reporting",
            label: "De-escalation",
            effects: [{"solidarity", nil, 1.0}, {"influence", nil, -1.0}, {"risk", nil, -1.0}],
            text: """
            Take responsibility — less attention, more trust.

            **Pro:** Lowers escalation; Strengthens cohesion; Credibility

            **Contra:** Fewer clicks; Less revenue; Looks "too soft"
            """
          },
          %{
            group: "Economy-Media",
            handle: "Close businesses",
            label: "De-escalation",
            effects: [{"resources", nil, -2.0}, {"risk", nil, -1.0}],
            text: """
            Protection & calm — but at an economic cost.

            **Pro:** Protects employees; Lowers immediate escalation; Signals responsibility

            **Contra:** Economic losses; Supply and services suffer; Signals crisis
            """
          }
        ]
      },
      %{
        handle: "Economic Instability",
        title: "Economic Instability",
        kind: :event,
        position: 2,
        narrative: """
        Inflation • Uncertainty • Distribution conflicts

        **Context:**
        - The economy falters; prices rise noticeably.
        - Smaller businesses close; fear for the future spreads.
        - Politics, media and civil society come under pressure to act.

        **Discussion prompts:**
        - Who bears the costs of the crisis?
        - Which measures are fast — and which are fair?
        - How does economic stress tip into political radicalisation?
        """,
        options: [
          %{
            group: "Government",
            handle: "Rescue package",
            label: "De-escalation",
            condition: "self(resources) >= 4",
            effects: [{"stability", nil, 2.0}, {"resources", nil, -2.0}],
            text: """
            The state steps in — buying stability with resources.

            **Pro:** Stabilises the economy; Prevents mass unemployment; Strengthens trust in the state

            **Contra:** High costs; Debt; Politically vulnerable
            """
          },
          %{
            group: "Government",
            handle: "Market liberalisation",
            label: "Neutral",
            effects: [{"solidarity", nil, -2.0}, {"resources", nil, 1.0}],
            text: """
            Growth through reform — social costs possible.

            **Pro:** Fosters competition; Relieves the state; Attractive to investors

            **Contra:** Inequality rises; Short-term hardship; Solidarity drops
            """
          },
          %{
            group: "Government",
            handle: "Talks with business leaders",
            label: "De-escalation",
            effects: [{"stability", nil, 1.0}, {"influence", nil, -1.0}],
            text: """
            Seek consensus — delayed effect, lower conflict.

            **Pro:** Calms the actors; Compromise possible; Legitimacy through dialogue

            **Contra:** Slow; No immediate relief; Looks evasive
            """
          },
          %{
            group: "Grassroots",
            handle: "Support fund",
            label: "De-escalation",
            effects: [{"solidarity", nil, 2.0}, {"resources", nil, -1.0}],
            text: """
            Direct help — high solidarity, at a resource cost.

            **Pro:** Direct help; Strengthens social networks; High credibility

            **Contra:** Limited means; Doesn't scale; Can let the state off the hook (politically)
            """
          },
          %{
            group: "Grassroots",
            handle: "Protests against inequality",
            label: "Escalation",
            effects: [{"influence", nil, 2.0}, {"risk", nil, 1.0}],
            text: """
            Increase the pressure — may sharpen the conflict.

            **Pro:** Raises pressure; Makes injustice visible; Mobilises those affected

            **Contra:** Risk of escalation; Hurts the economy short term; Polarisation
            """
          },
          %{
            group: "Grassroots",
            handle: "Organise citizens' forums",
            label: "De-escalation",
            effects: [{"solidarity", nil, 1.0}, {"risk", nil, -1.0}],
            text: """
            Participation instead of outrage — slow but stabilising.

            **Pro:** Participation; De-escalates; Structures the debate

            **Contra:** Slow; Little immediate effect; Can seem elitist
            """
          },
          %{
            group: "Economy-Media",
            handle: "Raise prices",
            label: "Neutral",
            effects: [{"solidarity", nil, -1.0}, {"resources", nil, 2.0}],
            text: """
            Secure survival — the public pays.

            **Pro:** Secures profits; Businesses survive; Predictability

            **Contra:** Burdens the public; Solidarity drops; Political backlash
            """
          },
          %{
            group: "Economy-Media",
            handle: "\"Buy local\" campaign",
            label: "Neutral",
            effects: [{"influence", nil, 1.0}, {"resources", nil, 1.0}],
            text: """
            Positive mobilisation — limited but steady effect.

            **Pro:** Strengthens the local economy; Positive narrative; Sense of community

            **Contra:** Limited effect; Marketing costs; Can come across as PR
            """
          },
          %{
            group: "Economy-Media",
            handle: "Transparency initiative",
            label: "De-escalation",
            effects: [{"solidarity", nil, 1.0}, {"influence", nil, -1.0}],
            text: """
            Build trust — give up power.

            **Pro:** Strengthens trust; Stable in the long run; Reduces mistrust

            **Contra:** Short-term image risk; Less control; Less influence
            """
          }
        ]
      },
      %{
        handle: "Information Chaos",
        title: "Information Chaos",
        kind: :event,
        position: 3,
        narrative: """
        Disinformation • Loss of trust • Polarisation

        **Context:**
        - Rumours, half-truths and manipulation spread rapidly.
        - Institutions are called into question; conflicts are inflamed.
        - Society is unsettled: who can still be believed?

        **Discussion prompts:**
        - How do you fight disinformation without being accused of censorship?
        - What stabilises trust — facts, values or power?
        - What role do media and platforms play?
        """,
        options: [
          %{
            group: "Government",
            handle: "Fact-checking campaign",
            label: "Neutral",
            condition: "self(resources) >= 3",
            effects: [{"influence", nil, 2.0}, {"resources", nil, -1.0}],
            text: """
            Buy credibility — costs resources.

            **Pro:** Strengthens credibility; No repression; Clear line

            **Contra:** Expensive; Uncertain effect; Doesn't reach everyone
            """
          },
          %{
            group: "Government",
            handle: "Tighten security laws",
            label: "Escalation",
            effects: [{"stability", nil, 1.0}, {"solidarity", nil, -1.0}, {"risk", nil, 1.0}],
            text: """
            Increase control — risking freedom and trust.

            **Pro:** Fast interventions; Signals control; Calms parts of the population

            **Contra:** Civil liberties restricted; Radicalisation; Accusations of censorship / abuse of power
            """
          },
          %{
            group: "Government",
            handle: "Social media shutdowns",
            label: "Escalation",
            effects: [{"influence", nil, -1.0}, {"risk", nil, 1.0}],
            text: """
            Cut the platforms — information war, and accusations of authoritarianism.

            **Pro:** Fast containment; Interrupts waves of rumours; Controls the channels

            **Contra:** Censorship accusations; Loss of trust; Alternative channels emerge
            """
          },
          %{
            group: "Grassroots",
            handle: "Dialogue work",
            label: "De-escalation",
            effects: [{"solidarity", nil, 2.0}, {"influence", nil, -1.0}],
            text: """
            Create spaces for conversation — slow but stabilising.

            **Pro:** Strengthens trust; Builds bridges; Lowers polarisation

            **Contra:** Slow; Limited reach; Looks naive against manipulation
            """
          },
          %{
            group: "Grassroots",
            handle: "Spread counter-narratives",
            label: "Escalation",
            effects: [{"influence", nil, 1.0}, {"risk", nil, 1.0}],
            text: """
            Counter-propaganda — mobilising but polarising.

            **Pro:** High visibility; Mobilisation; Controls part of the narrative

            **Contra:** Polarisation; Risk of misinformation; Spiral of conflict
            """
          },
          %{
            group: "Grassroots",
            handle: "Strengthen institutions",
            label: "De-escalation",
            effects: [{"solidarity", nil, 1.0}, {"influence", nil, 1.0}],
            text: """
            Trust in the rules — less spectacular, but durable.

            **Pro:** Stabilises democracy; Bridges to institutions; Reduces mistrust

            **Contra:** Not spectacular; Hard to measure; Can be seen as loyal to the system
            """
          },
          %{
            group: "Economy-Media",
            handle: "Sensationalist journalism",
            label: "Escalation",
            effects: [{"influence", nil, 2.0}, {"risk", nil, 2.0}],
            text: """
            Maximise attention — sacrifice trust.

            **Pro:** Reach; Revenue; Agenda setting

            **Contra:** Loss of trust; Escalation; Long-term instability
            """
          },
          %{
            group: "Economy-Media",
            handle: "Clear factual reporting",
            label: "De-escalation",
            effects: [{"solidarity", nil, 1.0}, {"influence", nil, -1.0}],
            text: """
            Prioritise facts — lose clicks, gain trust.

            **Pro:** Credibility; Responsibility; Lowers polarisation

            **Contra:** Fewer clicks; Less revenue; Looks "too neutral"
            """
          },
          %{
            group: "Economy-Media",
            handle: "Editorial: \"Save democracy\"",
            label: "De-escalation",
            effects: [{"solidarity", nil, 1.0}, {"influence", nil, 1.0}],
            text: """
            Normative clarity — give orientation, risk taking sides.

            **Pro:** Orientation; Makes values visible; Strengthens cohesion

            **Contra:** Accusations of partisanship; Polarises opponents; Can seem hypocritical
            """
          }
        ]
      },
      %{
        handle: "Investigation: The Dossier",
        title: "Investigation: The Dossier",
        kind: :sidequest,
        position: 4,
        narrative: """
        An anonymous tip: decisions in the crisis task force were allegedly
        made behind the backs of the official bodies. An internal dossier is
        said to exist.

        **Mission:** Obtain solid evidence and bring the dossier to the
        public — or deliberately decide against it.
        """,
        director_notes: """
        Hand this covertly to a single player in the Economy/Media group (a
        note or a whisper, not publicly). That person decides whom to let in
        on it. Success = the dossier is made public AND at least one other
        group publicly confirms the story. On success, consider staging a
        government press conference as a consequence.
        """,
        options: [
          %{
            handle: "Dossier published",
            outcome: :success,
            effects: [
              {"stability", "Government", -1.0},
              {"solidarity", "Economy-Media", 1.0},
              {"influence", "Government", -1.0},
              {"influence", "Economy-Media", 2.0}
            ],
            text: "The investigation succeeds: the dossier is published and confirmed."
          },
          %{
            handle: "Investigation exposed",
            outcome: :failure,
            effects: [{"influence", "Economy-Media", -1.0}, {"risk", "Economy-Media", 1.0}],
            text: """
            The source falls through and the allegation looks baseless — the shot backfires.
            """
          }
        ]
      },
      %{
        handle: "Referendum: Emergency Laws",
        title: "Referendum: Emergency Laws",
        kind: :election,
        position: 5,
        deadline_seconds: 30,
        narrative: """
        The crises keep piling up. The government puts a package of emergency
        laws to a public vote: faster decisions, expanded powers, less
        participation — temporary, of course.

        **The central question:** Can the community answer the crisis without
        hollowing out its own democratic values?

        Every player votes individually. The majority decides.
        """,
        director_notes: """
        Campaign phase of about 10 minutes before the vote: groups may give
        speeches, negotiate, make promises. Vote by show of hands or ballot;
        announce the result publicly and ceremoniously. The game master
        decides in case of a tie.
        """,
        options: [
          %{
            handle: "Yes — emergency laws",
            label: "Escalation",
            condition: "global(risk) >= 6",
            effects: [
              {"stability", "Government", 2.0},
              {"solidarity", "Grassroots", -1.0},
              {"influence", "Government", 2.0},
              {"influence", "Grassroots", -2.0},
              {"influence", "Economy-Media", -1.0},
              {"risk", "Government", 1.0},
              {"risk", "Economy-Media", 1.0},
              {"risk", "Grassroots", 1.0}
            ],
            text: """
            The package is adopted: order and speed first, oversight and participation later.
            """
          },
          %{
            handle: "No — democratic means",
            label: "De-escalation",
            effects: [
              {"stability", "Government", -1.0},
              {"solidarity", "Economy-Media", 1.0},
              {"solidarity", "Grassroots", 2.0},
              {"influence", "Grassroots", 1.0},
              {"influence", "Government", -1.0},
              {"risk", "Grassroots", -1.0}
            ],
            text: """
            The package is rejected: the crisis is handled through the normal
            democratic procedures — slower, but legitimate.
            """
          }
        ]
      }
    ]
  end

  # ── Endings ───────────────────────────────────────────────────────────

  defp create_endings(scenario) do
    endings = [
      %{
        handle: "Fragile Normality",
        title: "Fragile Normality",
        priority: 0,
        narrative: """
        The town has survived the crises — somehow. Nothing collapsed,
        nothing has healed. Everyday life returns, and with it the question
        of whether next time will take more than muddling through.
        """
      },
      %{
        handle: "Renewed Solidarity",
        title: "Renewed Solidarity",
        condition: "global(solidarity) >= 6.5",
        priority: 20,
        narrative: """
        The crises have left their marks — and uncovered something: the
        groups have learned to listen to each other. Not every problem is
        solved, but the town is deciding together again.
        """
      },
      %{
        handle: "Authoritarian Stabilisation",
        title: "Authoritarian Stabilisation",
        condition: "global(stability) >= 7",
        priority: 30,
        narrative: """
        Order reigns — but at what price? Decisions are made quickly; dissent
        has grown quieter. The town functions. Whether it is still a
        democracy is a question nobody dares to ask out loud.
        """
      },
      %{
        handle: "Collapse",
        title: "Systemic Collapse",
        condition: "global(risk) >= 8",
        priority: 40,
        narrative: """
        The escalation can no longer be contained. Institutions function only
        on paper; nobody trusts anybody. The town is no longer a community,
        just camps existing side by side.
        """
      }
    ]

    for spec <- endings do
      {:ok, _} =
        Authoring.create_ending(
          scenario,
          spec
          |> Map.take([:handle, :condition, :priority])
          |> Map.put(:title, en(spec.title))
          |> Map.put(:narrative, en(spec.narrative))
        )
    end
  end
end
