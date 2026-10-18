# Mars Colony — complete content

> Generated from the database by `tutorial/reference.exs` — don't edit by
> hand; change the scenario (`priv/repo/seeds_mars_colony.exs` or the editor)
> and run `tutorial/run.sh` again.

[← Mars Colony](mars-colony.md) · [Contents](index.md)

**Overall Index:** Colony Vitality =
`(life_support + supplies + progress + (10 - risk)) / 4` (0–10)

## Values

| Value | Key | Scope | Formula | Range |
|---|---|---|---|---|
| Life Support | `life_support` | per group | `min` | 0–10 |
| Supplies | `supplies` | per group | `(avg + min) / 2` | 0–10 |
| Progress | `progress` | per group | `median` | 0–10 |
| Risk | `risk` | per group | `max` | 0–10 |
| Morale | `morale` | per participant | show of hands | steps 1–5 |

## Groups and starting values

| Group | Life Support | Supplies | Progress | Risk |
|---|---|---|---|---|
| Engineering & Habitat | 7 | 5 | 3 | 5 |
| Science & Exploration | 5 | 3 | 7 | 5 |
| Agriculture & Life Systems | 7 | 5 | 5 | 7 |
| Medical & Crew Welfare | 5 | 3 | 5 | 3 |
| Command & Earth Relations | 3 | 7 | 5 | 5 |

## Timeline

### 1. What to Bring (`what_to_bring`)

*Event · ⏱ 5 min*

| Group | Option | Labels | Effects | Gate |
|---|---|---|---|---|
| Engineering & Habitat | **Spare parts** ⏱ — Crates of valves, seals and circuit boards. Boring. Essential. | 🛡️ Cautious | Life Support +1, Supplies +1 |  |
| Engineering & Habitat | **3D printer** — A fabricator that can print almost any part — if you feed it. | 🚀 Bold | Supplies -1, Progress +2 |  |
| Engineering & Habitat | **Backup systems** — A second set of everything critical, just in case. | 🛡️ Cautious | Risk -2 |  |
| Science & Exploration | **Deep-drill rig** — Drill 100 metres down, where water and maybe life could be. | 🚀 Bold | Progress +2, Risk +1 |  |
| Science & Exploration | **Lab supplies** ⏱ — Sample freezers, chemicals, spare instruments. | 🛡️ Cautious | Supplies +2 |  |
| Science & Exploration | **Weather stations** — Twelve small sensors that watch the sky for the whole colony. | 🤝 Team Player | Progress +1, Risk -1 |  |
| Agriculture & Life Systems | **Seed vault** — Three hundred plant varieties, frozen and ready. |  | Supplies +1, Progress +1 |  |
| Agriculture & Life Systems | **Proven hydroponics** ⏱ — The system that already works on the space station. | 🛡️ Cautious | Risk -2 |  |
| Agriculture & Life Systems | **Gene-edited crops** — Fast-growing experimental plants. Nobody has tried them on Mars. | 🚀 Bold | Supplies +1, Progress +2, Risk +1 |  |
| Medical & Crew Welfare | **Surgical suite** — A full operating room, folded into one crate. | 🚀 Bold | Life Support +2, Supplies -1 |  |
| Medical & Crew Welfare | **Medicine stockpile** ⏱ — Two years of everything, for everyone. | 🛡️ Cautious | Supplies +2 |  |
| Medical & Crew Welfare | **Crew welfare kit** — Games, music, a VR headset with beaches. Sanity matters. | 🤝 Team Player | Life Support +1, Risk -1 |  |
| Command & Earth Relations | **Oxygen reserves** ⏱ — Extra tanks for your own quarters — the most fragile on board. | 🛡️ Cautious | Life Support +2, Supplies -1 |  |
| Command & Earth Relations | **High-gain antenna** — A fast, private link to Mission Control. |  | Supplies +1, Progress +1 |  |
| Command & Earth Relations | **Trade goods** — Things to bargain with later. Earth sponsors love souvenirs. | 🚀 Bold | Supplies +2, Risk +1 |  |

### 2. Touchdown (`touchdown`)

*Event*

| Group | Option | Labels | Effects | Gate |
|---|---|---|---|---|
| Engineering & Habitat | **Habitat first** — Inflate the living modules and get everyone out of their suits. | 🛡️ Cautious | Life Support +2, Supplies -1 |  |
| Engineering & Habitat | **Solar field first** — Unroll the solar panels on the open plain — fast power, fully exposed. | 🚀 Bold | Progress +2, Risk +1 |  |
| Science & Exploration | **Explore the crater** — First humans on Mars. Go and look! | 🚀 Bold | Progress +2, Risk +1 |  |
| Science & Exploration | **Help unpack** — Science can carry boxes too. | 🤝 Team Player | Life Support +1, Supplies +2 |  |
| Agriculture & Life Systems | **Plant immediately** — Break ground on the greenhouse today. Every day counts. | 🚀 Bold | Supplies +2, Risk +1 |  |
| Agriculture & Life Systems | **Test the soil first** — Mars soil contains perchlorates. Find out how much. | 🛡️ Cautious | Progress +1, Risk -1 |  |
| Medical & Crew Welfare | **Health checks** — Scan all twenty-five people after the landing. | 🛡️ Cautious | Supplies -1, Risk -2 |  |
| Medical & Crew Welfare | **Open the common room** — Hot drinks, a place to sit, someone to talk to. | 🤝 Team Player | Life Support +1, Supplies +1 |  |
| Command & Earth Relations | **Honest report** — Tell Earth everything, including the lost cargo pod. | 🤝 Team Player | Risk -1 |  |
| Command & Earth Relations | **Good-news report** — "Landing perfect, morale excellent." Sponsors stay happy. | 🚀 Bold | Supplies +2, Risk +1 |  |
| Command & Earth Relations | **Recover the pod** — Lead a team out to the lost cargo before nightfall. |  | Life Support +2, Supplies +1, Risk +1 |  |

### 3. Settling In (`settling_in`)

*Event*

| Group | Option | Labels | Effects | Gate |
|---|---|---|---|---|
| Engineering & Habitat | **Expand the solar field** — Double the panels. Power for every project anyone dreams up. | 🚀 Bold | Supplies -1, Progress +3, Risk +1 |  |
| Engineering & Habitat | **Bury the cables** — Protect the power lines under a metre of regolith. | 🛡️ Cautious | Supplies -1, Risk -2 | `self(supplies) >= 4` |
| Engineering & Habitat | **Battery bank** — Store power for the long night — or the day the sun goes out. | 🤝 Team Player 🛡️ Cautious | Life Support +2, Supplies -2, Risk -1 | `self(supplies) >= 5` |
| Science & Exploration | **Long expedition** — Two weeks in a rover, 400 kilometres, the old river delta. | 🚀 Bold | Progress +3, Risk +1 |  |
| Science & Exploration | **Weather radar** — Turn the weather stations into a real early-warning system. | 🤝 Team Player | Progress +2, Risk -2 | `self(progress) >= 9` |
| Science & Exploration | **Share the lab** — Lend equipment and people to Agriculture and Medical. | 🤝 Team Player | Life Support +1, Supplies +1 |  |
| Agriculture & Life Systems | **Second greenhouse** — Twice the food — and twice the power and water to run it. | 🚀 Bold | Supplies +3, Risk +1 | `self(supplies) >= 5` |
| Agriculture & Life Systems | **Water recycling loop** — Reclaim ninety-eight percent of every drop. | 🛡️ Cautious | Life Support +2 |  |
| Agriculture & Life Systems | **Algae tanks** — Ugly, green, and edible. Food that needs almost no light. | 🛡️ Cautious | Supplies +1, Risk -2 |  |
| Medical & Crew Welfare | **Radiation shelter** — A shielded sleeping area for everyone. | 🛡️ Cautious | Supplies -1, Risk -2 |  |
| Medical & Crew Welfare | **Mental health program** — Daily check-ins, a quiet room, a buddy system. | 🤝 Team Player | Life Support +2, Progress +1 |  |
| Medical & Crew Welfare | **First-aid training** — Teach every colonist to handle an emergency. | 🤝 Team Player | Progress +1, Risk -1 |  |
| Command & Earth Relations | **Colony council** — A daily meeting where every team has a voice. | 🤝 Team Player | Life Support +2, Risk -1 |  |
| Command & Earth Relations | **Emergency plan** — Rationing rules, ready before anyone needs them. | 🛡️ Cautious | Supplies +2, Risk -1 |  |
| Command & Earth Relations | **Media deal** — Sell live footage to an Earth streaming service. | 🚀 Bold | Supplies +2, Progress +1, Risk +1 |  |

### 4. Green Thumb (`green_thumb`)

*Wildcard*

| Outcome | Effects | Gate |
|---|---|---|
| **success: Potatoes on Mars** | Science & Exploration: Progress +1; Agriculture & Life Systems: Supplies +2, Progress +1, Risk -1 |  |
| **failure: Contaminated lab** | Science & Exploration: Supplies -1; Agriculture & Life Systems: Supplies -1, Risk +1 |  |

### 5. The Find (`the_find`)

*Wildcard*

| Outcome | Effects | Gate |
|---|---|---|
| **success: Shared with the world** | Science & Exploration: Progress +3; Command & Earth Relations: Supplies +1 |  |
| **failure: Secret leaks** | Science & Exploration: Progress -1, Risk +1; Command & Earth Relations: Supplies -1 |  |

### 6. The Storm (`the_storm`)

*Event · ⏱ 4 min*

| Group | Option | Labels | Effects | Gate |
|---|---|---|---|---|
| Engineering & Habitat | **Repair outside** — Suit up and clear the panels in the storm. Dangerous. | 🚀 Bold | Life Support +1, Supplies -1, Risk +2 |  |
| Engineering & Habitat | **Power down** ⏱ — Switch off everything that isn't keeping someone alive. | 🛡️ Cautious | Life Support -1, Supplies -1, Progress -2 |  |
| Engineering & Habitat | **Drain the batteries** — Run the colony on stored power and pray the sun comes back. |  | Supplies -2 |  |
| Science & Exploration | **Track the storm** — Feed the colony live forecasts, hour by hour. | 🤝 Team Player | Supplies -1, Progress -1, Risk -1 |  |
| Science & Exploration | **Save the samples** ⏱ — Keep the freezers running. Two years of work are in there. | 🚀 Bold | Life Support -2, Supplies -1 |  |
| Science & Exploration | **Join Engineering** — Close the lab and lend every hand to the repair crews. | 🤝 Team Player | Supplies +1, Progress -2 |  |
| Agriculture & Life Systems | **Keep the lights on** — Run the grow lights on emergency power. | 🚀 Bold | Life Support -1, Supplies -1, Risk +1 |  |
| Agriculture & Life Systems | **Let the crops sleep** ⏱ — Put the greenhouse into dormancy and hope. | 🛡️ Cautious | Supplies -2 |  |
| Agriculture & Life Systems | **Harvest everything** — Pick all of it now, ripe or not. |  | Supplies +1, Progress -2, Risk +1 |  |
| Medical & Crew Welfare | **Shelter in the core** ⏱ — Move everyone into the best-shielded module. | 🛡️ Cautious | Life Support -1, Supplies -1, Risk -1 |  |
| Medical & Crew Welfare | **Keep the clinic open** — Full power to the medical bay, whatever it costs. |  | Supplies -2, Risk -1 |  |
| Medical & Crew Welfare | **Ration the medicine** — Prepare for a long storm: hold back what you can. | 🛡️ Cautious | Life Support -2, Supplies +1 |  |
| Command & Earth Relations | **Call Earth** — Admit we need help. Open the emergency channel. | 🤝 Team Player | Supplies -1, Progress -1, Risk -1 |  |
| Command & Earth Relations | **We handle this** ⏱ — No call, no excuses. The colony fixes its own problems. | 🚀 Bold | Supplies -1, Progress +1, Risk +1 |  |
| Command & Earth Relations | **Lockdown** — Everyone indoors, all teams under Command's orders. | 🛡️ Cautious | Life Support -1, Supplies -1, Progress -1, Risk -1 |  |

### 7. Rationing (`rationing_holding`)

*Event*

| Group | Option | Labels | Effects | Gate |
|---|---|---|---|---|
| Engineering & Habitat | **Patch and pray** — Keep everything half-running with improvised fixes. | 🚀 Bold | Life Support -1, Risk +1 |  |
| Engineering & Habitat | **Shut one module** — Close the workshop and give its power away. | 🤝 Team Player | Progress -1 |  |
| Science & Exploration | **Pause the research** — Freeze every experiment until the sun comes back. | 🤝 Team Player | Progress -1 |  |
| Science & Exploration | **Keep one project** — Protect the most important experiment, cut the rest. |  | Supplies -1 |  |
| Agriculture & Life Systems | **Ration the greenhouse** — Half the light, half the harvest. | 🛡️ Cautious | Supplies -1 |  |
| Agriculture & Life Systems | **Feed the algae** — Shift everything to the algae tanks. Nobody will love the menu. | 🤝 Team Player | Life Support -1, Supplies +1 |  |
| Medical & Crew Welfare | **Triage the equipment** — Only life-critical machines stay on. | 🛡️ Cautious | Life Support -1 |  |
| Medical & Crew Welfare | **Night clinic** — Run the medical bay only at night, when demand is low. |  | Supplies +1, Risk +1 |  |
| Command & Earth Relations | **Cut the Earth link** — One message a day. The rest of the bandwidth goes to the teams. | 🤝 Team Player | Progress -1, Risk -1 |  |
| Command & Earth Relations | **Fair shares** — Every team gets exactly the same power, no exceptions. | 🛡️ Cautious | Supplies -1, Risk -1 |  |

### 8. Rationing (`rationing_struggling`)

*Event*

| Group | Option | Labels | Effects | Gate |
|---|---|---|---|---|
| Engineering & Habitat | **Patch and pray** — Keep everything half-running with improvised fixes. | 🚀 Bold | Life Support -1, Risk +2 |  |
| Engineering & Habitat | **Shut one module** — Close the workshop and give its power away. | 🤝 Team Player | Supplies -1, Progress -2 |  |
| Science & Exploration | **Pause the research** — Freeze every experiment until the sun comes back. | 🤝 Team Player | Progress -2 |  |
| Science & Exploration | **Keep one project** — Protect the most important experiment, cut the rest. |  | Supplies -2, Risk +1 |  |
| Agriculture & Life Systems | **Ration the greenhouse** — A third of the light, a third of the harvest. | 🛡️ Cautious | Supplies -2 |  |
| Agriculture & Life Systems | **Feed the algae** — Shift everything to the algae tanks. Nobody will love the menu. | 🤝 Team Player | Life Support -2, Supplies +1 |  |
| Medical & Crew Welfare | **Triage the equipment** — Only life-critical machines stay on. | 🛡️ Cautious | Life Support -1, Risk +1 |  |
| Medical & Crew Welfare | **Night clinic** — Run the medical bay only at night, when demand is low. |  | Supplies +1, Risk +1 |  |
| Command & Earth Relations | **Cut the Earth link** — One message a day. The rest of the bandwidth goes to the teams. | 🤝 Team Player | Progress -1, Risk -1 |  |
| Command & Earth Relations | **Fair shares** — Every team gets exactly the same power, no exceptions. | 🛡️ Cautious | Supplies -2 |  |

### 9. Jury-Rig It (`jury_rig_it`)

*Wildcard*

| Outcome | Effects | Gate |
|---|---|---|
| **success: It holds** | Engineering & Habitat: Life Support +2, Risk -1; Agriculture & Life Systems: Supplies -1 |  |
| **failure: Caught red-handed** | Engineering & Habitat: Life Support -1, Risk +1; Agriculture & Life Systems: Supplies -2 |  |

### 10. Triage (`triage`)

*Wildcard*

| Outcome | Effects | Gate |
|---|---|---|
| **success: A fair call** | Medical & Crew Welfare: Life Support +2, Risk -1 |  |
| **failure: Whispers** | Medical & Crew Welfare: Life Support -2, Risk +1 |  |

### 11. Off the Record (`off_the_record`)

*Wildcard*

| Outcome | Effects | Gate |
|---|---|---|
| **success: Out in the open** | Command & Earth Relations: Life Support +1, Risk -1 |  |
| **failure: Rumour mill** | Medical & Crew Welfare: Risk +1; Command & Earth Relations: Supplies -1, Risk +1 |  |

### 12. Earth's Offer (`earths_offer`)

*Vote · ⏱ 8 min*

| Outcome | Effects | Gate |
|---|---|---|
| **Sponsor deal** ⏱ | Engineering & Habitat: Supplies +2; Science & Exploration: Supplies +2, Progress -2; Agriculture & Life Systems: Supplies +2; Medical & Crew Welfare: Supplies +2; Command & Earth Relations: Supplies +1, Risk +1 |  |
| **Extend the mission** | Engineering & Habitat: Life Support +1, Supplies +2; Science & Exploration: Supplies +2, Progress +1; Agriculture & Life Systems: Life Support +1, Supplies +2; Medical & Crew Welfare: Supplies +1, Risk +1; Command & Earth Relations: Life Support +1, Supplies +1 |  |
| **Go it alone** | Engineering & Habitat: Supplies -1, Progress +1; Science & Exploration: Supplies -1, Progress +2; Agriculture & Life Systems: Supplies -1, Risk +1; Medical & Crew Welfare: Supplies -1; Command & Earth Relations: Progress +1, Risk +1 | `global(supplies) >= 3` |

⏱ after an option = the default applied when the deadline runs out.

## Endings

| Ending | Condition | Priority |
|---|---|---|
| The Colony Holds | `(global(life_support) + global(supplies) + global(progress) + 10 - global(risk)) / 4 >= 5.5` | 30 |
| Getting By | `(global(life_support) + global(supplies) + global(progress) + 10 - global(risk)) / 4 >= 3.5` | 20 |
| On the Brink | `(global(life_support) + global(supplies) + global(progress) + 10 - global(risk)) / 4 < 3.5` | 10 |
