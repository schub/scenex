// The screencast's storyboard. Each scene is one narration line (`say`), a
// short description of what's on screen (`screen`, for reviewing the script
// in storyboard.md) and what the camera does while it is spoken (`act`).
// record.mjs holds every scene for the length of its spoken line plus a pause.
//
// `h` is the toolbox from record.mjs:
//   h.cam        the recorded browser page (what viewers see)
//   h.ctl        a logged-in page that is NOT recorded (backstage actions;
//                never use it while the camera shows what it changes)
//   h.go(url)    navigate the camera and wait for LiveView
//   h.click(sel) move the visible pointer to an element and click it
//   h.fill(sel, text), h.point(sel), h.pointAt(x, y), h.scroll(sel), h.top(),
//   h.wait(ms)
//   h.card(title, subtitle, { image })   a full-screen title card
//   h.image(file, { fit, background })   a full-screen image
//   h.state      URLs remembered between scenes
//
// Common Ground is the example; Mars Colony appears once, to show that the
// same building blocks carry a completely different game.

import { BASE } from "../lib.mjs";

const CG = "COMMON GROUND";
const card = (title) => `section:has(h3:has-text("${title}"))`;
const KE3_HIGH = `section:has(h3:has-text("Irresistable Proposal")):has-text("High Democracy Score")`;

// Backstage: the GM's routine clicks the camera doesn't need to see.
const ctlChoose = async (h, title, options) => {
  const c = h.ctl.locator("section").filter({ has: h.ctl.locator(`h3:has-text("${title}")`) }).first();
  for (const option of options) {
    await c.locator(`[phx-click=choose]:has-text("${option}")`).first().click();
    await h.ctl.waitForTimeout(150);
  }
};

async function openEditor(h, handle) {
  await h.go(BASE + "/scenarios");
  const path = await h.cam.evaluate((name) => {
    const title = [...document.querySelectorAll("*")].find(
      (el) => el.children.length === 0 && el.textContent.trim() === name
    );
    let c = title?.parentElement;
    while (c && ![...c.querySelectorAll("a")].some((a) => a.textContent.includes("Open editor"))) {
      c = c.parentElement;
    }
    return new URL([...c.querySelectorAll("a")].find((a) => a.textContent.includes("Open editor")).href).pathname;
  }, handle);
  await h.wait(600);
  await h.click(`a[href="${path}"]`);
  await h.cam.waitForURL(/\/scenarios\/[0-9a-f-]+$/);
}

export const scenes = [
  // ── Opening ───────────────────────────────────────────────────────────────
  {
    id: "hello",
    screen: "Title card on the Common Ground artwork: “Welcome to Scenex”",
    say: "Hi, and welcome to Scenex, the stage manager for your megagame. In this video you'll see how a megagame is built, and how it's played. Our example is Common Ground: a game about a town in crisis, and the art of compromise.",
    act: (h) => h.card("Welcome to Scenex", "Write and run megagames — a tour with Common Ground", { image: "display-page-title.png" })
  },
  {
    id: "megagame",
    screen: "Card: “Everybody plays”",
    say: "First, a quick reminder. In a megagame, everybody plays. There is no audience. The room splits into groups, a story unfolds, and every decision leaves its mark on the world.",
    act: (h) => h.card("Everybody plays", "groups · a story · decisions with consequences")
  },
  {
    id: "nobody-wins",
    screen: "Card: “Nobody wins”",
    say: "Nobody wins. The real question is: what kind of world do we build, together?",
    act: (h) => h.card("Nobody wins", "what kind of world do we build together?")
  },
  {
    id: "room-tables",
    screen: "Illustration of the room — pointer on the tables and their tablets",
    say: "So what does that look like in the room? Every group sits at its own table, with one tablet. That's the group board. It shows the group's own numbers, and the choices it has to make.",
    act: async (h) => {
      await h.image("the-room.svg", { fit: "contain", background: "#2b2140" });
      await h.wait(1500);
      await h.pointAt(470, 560);
      await h.wait(1200);
      await h.pointAt(200, 470);
    }
  },
  {
    id: "room-wall",
    screen: "The room — pointer on the projector",
    say: "On the wall, the projector shows the whole town: how everybody is doing, together.",
    act: (h) => h.pointAt(640, 170)
  },
  {
    id: "room-gm",
    screen: "The room — pointer on the game master's desk",
    say: "And at a desk on the side sits the game master, with the console: the control room of the evening. The players never log in. Every table simply scans a QR code.",
    act: (h) => h.pointAt(1110, 610)
  },
  {
    id: "loop",
    screen: "Diagram: the game loop",
    say: "Every game in Scenex runs on the same loop. The game master fires a beat. The groups talk, and decide. Their numbers move. The whole town reacts. And the game master reads the room, and picks what happens next.",
    act: (h) => h.image("game-loop.svg", { fit: "contain", background: "#fbf8f2" })
  },
  {
    id: "script",
    screen: "Card: “Script & performance”",
    say: "Just like in the theatre, there's the script, and there's the performance. You write a scenario once, in the editor. Every time you play it, that's a session: a new evening, with a new room, new decisions, and its own ending.",
    act: (h) => h.card("Script & performance", "the scenario is written once · every session is a new evening")
  },

  // ── The building blocks ───────────────────────────────────────────────────
  {
    id: "part-blocks",
    screen: "Card: “The building blocks”",
    say: "Let's open the script, and look at the building blocks.",
    act: (h) => h.card("The building blocks", "what every scenario is made of")
  },
  {
    id: "editor",
    screen: "Editor: Common Ground, Settings tab — pointer on the row of tabs",
    say: "Here's Common Ground in the editor. Each of these tabs holds one building block.",
    act: async (h) => {
      await openEditor(h, CG);
      h.state.editor = h.cam.url();
      await h.wait(800);
      await h.point("[role=tablist]");
    }
  },
  {
    id: "groups",
    screen: "Groups tab — the five groups, Chamber of Commerce open",
    say: "Groups are the teams at the tables. Common Ground has five: the Chamber of Commerce, Arts, Culture and Sport, Customer's Protection, the Voluntary Sector, and Public Services.",
    act: async (h) => {
      await h.click("[role=tab][phx-value-section=groups]");
      await h.click('[phx-click=edit_group]:has-text("Chamber of Commerce")');
    }
  },
  {
    id: "values",
    screen: "Values tab — Stability open",
    say: "Values are the pulse of the town. Every group has its own number for stability, solidarity, prosperity, and fairness, on a scale from zero to twenty.",
    act: async (h) => {
      await h.click("[role=tab][phx-value-section=values]");
      await h.click('[phx-click=edit_value]:has-text("stability")');
    }
  },
  {
    id: "initial",
    screen: "Initial tab — everyone at 8",
    say: "In Common Ground, everybody starts equal: eight, in everything. The differences grow out of the decisions the groups make.",
    act: async (h) => {
      await h.click("[role=tab][phx-value-section=initial]");
      await h.point("tbody tr >> nth=2");
    }
  },
  {
    id: "score",
    screen: "Overall index tab — the Democracy Score, its formula and bands",
    say: "From all these numbers, Scenex works out how the whole town is doing, and rolls it into one headline: the Democracy Score. It moves from Breakdown, all the way up to In Bloom.",
    act: async (h) => {
      await h.click("[role=tab][phx-value-section=overall_index]");
      await h.wait(1000);
      await h.scroll("text=Score bands");
    }
  },
  {
    id: "wellbeing",
    screen: "Values tab — Well-Being with its four emoji steps",
    say: "And then there is well-being. That one isn't calculated at all. The game master asks the room how people feel, and counts the hands. It's a reality check against the numbers.",
    act: async (h) => {
      await h.top();
      await h.click("[role=tab][phx-value-section=values]");
      await h.click('[phx-click=edit_value]:has-text("well_being")');
      await h.wait(800);
      await h.scroll("text=Readout steps");
    }
  },
  {
    id: "event",
    screen: "Timeline tab — Key Event 1 “Positive Starting Proposal” with every group's options",
    say: "The timeline is the running order of the evening. An event is a moment that every group answers on its own. In the Positive Starting Proposal, each group decides what to build in its corner of the old Hat Factory.",
    act: async (h) => {
      await h.top();
      await h.click("[role=tab][phx-value-section=timeline]");
      await h.click('[phx-click=open_event]:has-text("Key Event 1")');
      await h.wait(800);
      await h.scroll("h3:has-text('Options')");
    }
  },
  {
    id: "option",
    screen: "Option editor — “public market”, its effects",
    say: "Every option nudges the deciding group's numbers. A public market for the Chamber of Commerce: prosperity plus two, fairness plus one.",
    act: async (h) => {
      await h.click('li:has-text("A) Chamber of Commerce - public market") [phx-click=edit_option]');
      await h.wait(700);
      await h.scroll("text=Effects on");
    }
  },
  {
    id: "vote",
    screen: "Timeline — Referendum 2, its three ballot options",
    say: "A vote is one question for the whole room. One person, one vote. Here: should the town ban social media for young people, regulate it, or educate?",
    act: async (h) => {
      await h.click("text=← Back");
      await h.top();
      await h.click('[phx-click=open_event]:has-text("Referendum 2")');
      await h.wait(800);
      await h.scroll("h3:has-text('Options')");
    }
  },
  {
    id: "vote-matrix",
    screen: "Ballot option “Ban” opened — the outcome matrix, a row per group",
    say: "Each answer has an outcome matrix: its own consequences for every single group. Here's what happens to everyone, if the room votes to ban.",
    act: async (h) => {
      await h.click('li:has-text("Social Media Policy A - Ban") [phx-click=edit_option]');
      await h.wait(800);
      await h.scroll("text=Outcome matrix");
    }
  },
  {
    id: "wildcard",
    screen: "Timeline — the Freeze Card for the Chamber of Commerce",
    say: "A wildcard is a card for one single player. The Freeze Card is a little facilitation trick: when one person takes over their group, they sit the next decision out.",
    act: async (h) => {
      await h.click("text=← Back");
      await h.top();
      await h.click('[phx-click=open_event]:has-text("WILD CARD FREEZE COC")');
      await h.wait(800);
      await h.scroll("text=Narrative");
    }
  },
  {
    id: "wildcard-outcomes",
    screen: "Freeze Card — its Success and Failure outcomes",
    say: "Afterwards, the game master judges. Did they hold back? Success. Did they interfere? Failure. Each outcome has its own effects.",
    act: (h) => h.scroll("h3:has-text('Options')")
  },
  {
    id: "languages",
    screen: "Working locale switched to German — a German name typed for the Chamber of Commerce",
    say: "Common Ground speaks many languages. Switch the editor to yours, type your translation, and play in your own language. Anything you haven't translated yet simply shows in English.",
    act: async (h) => {
      await h.top();
      await h.click("[phx-click=set_locale][phx-value-locale=de]");
      await h.click("[role=tab][phx-value-section=groups]");
      await h.click('[phx-click=edit_group]:has-text("Chamber of Commerce")');
      await h.fill("input[name='group[name][de]']", "Handelskammer");
      await h.wait(800);
      await h.click("[phx-click=set_locale][phx-value-locale=en]");
    }
  },
  {
    id: "mars",
    screen: "Mars Colony's title picture",
    say: "And Scenex doesn't mind what your story is about. Here's a completely different game: Mars Colony, built from the very same blocks.",
    act: (h) => h.image("display-page-mars.png")
  },
  {
    id: "mars-trick",
    screen: "Mars Colony editor — the “Battery bank” option and its condition",
    say: "It even uses a trick Common Ground doesn't: options that only unlock when a team can afford them. Engineering can only build a battery bank with at least five supplies.",
    act: async (h) => {
      await openEditor(h, "mars_colony");
      await h.click("[role=tab][phx-value-section=timeline]");
      await h.click('[phx-click=open_event]:has-text("settling_in")');
      await h.click('li:has-text("Battery bank") [phx-click=edit_option]');
      await h.point("input[name*='condition']");
    }
  },
  {
    id: "dryrun",
    screen: "Common Ground's dry run — slogans being picked",
    say: "Back to the town. Before anyone plays, you can rehearse the numbers on your own, in the dry run. Pick a slogan for every group,",
    act: async (h) => {
      await h.go(h.state.editor + "/simulate");
      await h.wait(800);
      for (const slogan of ["Slogan COC 1", "Slogan ASR 2", "Slogan CONA 1", "Slogan CA 2.0", "Slogan PS 3"]) {
        await h.click(`[phx-click=toggle_option]:has-text("${slogan}")`);
      }
    }
  },
  {
    id: "dryrun-score",
    screen: "Dry run — scrolled up to the board, pointer on the Democracy Score",
    say: "and watch the Democracy Score climb.",
    act: async (h) => {
      await h.top();
      await h.point("text=Democracy Score");
    }
  },

  // ── Showtime ──────────────────────────────────────────────────────────────
  {
    id: "showtime",
    screen: "Card: “Showtime!”",
    say: "Showtime!",
    act: (h) => h.card("Showtime!", "an evening of Common Ground")
  },
  {
    id: "session",
    screen: "Sessions page — a new session “Friday Premiere” is created",
    say: "A session is one performance. Give it a name, pick the language, and the groups that play tonight.",
    act: async (h) => {
      await h.go(h.state.editor + "/sessions");
      await h.fill("input[name='session[label]']", "Common Ground — Friday Premiere");
      await h.wait(600);
      await h.click("button:has-text('Create session')");
      await h.cam.waitForURL(/\/console$/);
      h.state.console = h.cam.url();
    }
  },
  {
    id: "codes",
    screen: "Console — Access & QR: a code for every table and the projector",
    say: "Every table gets its own QR code, and so does the projector. You can print them all on one sheet.",
    act: async (h) => {
      await h.scroll("h3:has-text('Access')");
      for (const team of ["Chamber of Commerce", "Arts, Culture", "Customer", "Voluntary", "Public Services", "projected display"]) {
        await h.click(`button:has-text("+ Code: ${team}")`);
      }
      const links = await h.cam.$$eval("a[target=_blank]", (as) => as.map((a) => a.href));
      h.state.board = links.find((l) => l.includes("/play/"));
      h.state.display = links.find((l) => l.includes("/display/"));
      await h.point("text=Download all as PDF");
      await h.ctl.goto(h.state.console);
      await h.ctl.waitForSelector(".phx-connected");
    }
  },
  {
    id: "doors",
    screen: "Console: the GM clicks the page “Common Ground Title” → the projector shows it",
    say: "While the audience comes in, the game master puts the title on the projector.",
    act: async (h) => {
      await h.top();
      await h.click('[phx-click=show_page]:has-text("Common Ground Title")');
      await h.wait(600);
      await h.go(h.state.display);
    }
  },
  {
    id: "start",
    screen: "Console: back to the scoreboard, Start session, Trigger “Choose your slogan!”",
    say: "When everyone has found a table, the show begins. The game master starts the clock, and fires the very first beat: choose your slogan!",
    act: async (h) => {
      await h.go(h.state.console);
      await h.click("button:has-text('Back to scoreboard')");
      await h.click("button:has-text('Start session')");
      await h.scroll(card("Choose your slogan"));
      await h.click(`${card("Choose your slogan")} button:has-text('Trigger')`);
    }
  },
  {
    id: "board",
    screen: "The Chamber of Commerce's tablet — the question and its three slogans",
    say: "At the Chamber of Commerce table, the group reads the question, talks it through, and picks its slogan.",
    act: async (h) => {
      await h.go(h.state.board);
      await h.wait(1800);
      await h.click("[phx-click=select]:has-text('Come on in')");
    }
  },
  {
    id: "board-confirm",
    screen: "Tablet — the confirmation, then “Decision confirmed”",
    say: "Choosing takes two taps, so nobody decides for the whole table by accident.",
    act: async (h) => {
      await h.wait(800);
      await h.click("[phx-click=choose]");
    }
  },
  {
    id: "console",
    screen: "Console — the other four groups' decisions are entered",
    say: "The game master sees every decision come in, and can fix any mistake. The last decision always counts.",
    act: async (h) => {
      await h.go(h.state.console);
      await h.scroll(card("Choose your slogan"));
      for (const slogan of ["Slogan ASR 2", "Slogan CONA 1", "Slogan CA 2.0", "Slogan PS 3"]) {
        await h.click(`${card("Choose your slogan")} [phx-click=choose]:has-text("${slogan}")`);
      }
    }
  },
  {
    id: "display",
    screen: "The projector — four value bars and the Democracy Score gauge",
    say: "And on the wall, the whole town: the four values, and the Democracy Score, moving between Breakdown and In Bloom.",
    act: (h) => h.go(h.state.display)
  },
  {
    id: "survey-ask",
    screen: "Console: the GM clicks “Happiness Survey” → the projector shows the survey page",
    say: "Time to ask the room. The game master puts up the happiness survey: how are you feeling, right now?",
    act: async (h) => {
      await h.go(h.state.console);
      await h.click('[phx-click=show_page]:has-text("Happiness Survey")');
      await h.wait(600);
      await h.go(h.state.display);
    }
  },
  {
    id: "survey-count",
    screen: "Console: back to the scoreboard, the show of hands typed into Well-Being",
    say: "Count the hands, type them in, and the room's mood appears on the wall, as an emoji.",
    act: async (h) => {
      await h.go(h.state.console);
      await h.click("button:has-text('Back to scoreboard')");
      await h.scroll("section:has(h3:has-text('Well-Being'))");
      for (const [score, count] of [[4, 9], [3, 14], [2, 8], [1, 3]]) {
        await h.fill(`input[name='counts[${score}]']`, String(count));
      }
      await h.click("button:has-text('Record tally')");
    }
  },
  {
    id: "later",
    screen: "Card: “Later that evening…”",
    say: "Later that evening.",
    act: (h) => h.card("Later that evening…", "the Hat Factory · the mineral spring · an irresistible offer")
  },
  {
    id: "countdown",
    screen: "Console: Trigger “Positive Starting Proposal” → the tablet shows the options and a 5-minute countdown",
    say: "Now the key events begin. The Positive Starting Proposal comes with a five-minute countdown, on every table, and on the wall. Pressure makes good theatre.",
    act: async (h) => {
      await h.go(h.state.console);
      await h.scroll(card("Positive Starting Proposal"));
      await h.click(`${card("Positive Starting Proposal")} button:has-text('Trigger')`);
      await h.wait(800);
      await h.go(h.state.board);
      await ctlChoose(h, "Positive Starting Proposal", [
        "B) Arts & CO",
        "B) Customer's Protections",
        "C) Voluntary Sector",
        "A) Public Services"
      ]);
    }
  },
  {
    id: "versions",
    screen: "Console — the two versions of Key Event 3; the GM triggers the “higher Democracy Score” one",
    say: "Some moments are written in two versions. Is the Democracy Score high, or low? The game master looks, and fires the version of the Irresistible Proposal that fits the evening.",
    act: async (h) => {
      await h.go(h.state.console);
      await h.scroll(KE3_HIGH);
      await h.wait(1500);
      await h.click(`${KE3_HIGH} button:has-text('Trigger')`);
    }
  },
  {
    id: "freeze-live",
    screen: "Console — Freeze Card triggered and judged a success",
    say: "When a group needs it, the Freeze Card comes into play. Afterwards, one click: success.",
    act: async (h) => {
      await h.scroll(card("Freeze Card"));
      await h.click(`${card("Freeze Card")} button:has-text('Trigger')`);
      await h.wait(800);
      await h.click(`${card("Freeze Card")} [phx-click=adjudicate]:has-text('success')`);
    }
  },
  {
    id: "referendum",
    screen: "Console — Referendum 2: the hand count is typed in, “Regulate” wins",
    say: "Referendum time. The candidates have made their speeches. The game master counts the hands, and declares the result.",
    act: async (h) => {
      const vote = card("Referendum 2");
      await h.scroll(vote);
      await h.click(`${vote} button:has-text('Trigger')`);
      await h.wait(600);
      for (const [option, n] of [["A - Ban", 9], ["B - Regulate", 21], ["C - Educate", 14]]) {
        await h.fill(`${vote} div:has(> label:has-text("${option}")) input[type=number]`, String(n));
      }
      await h.click(`${vote} label:has-text('B - Regulate') input[type=radio]`);
      await h.click(`${vote} button:has-text('Declare result')`);
    }
  },
  {
    // The console's board, not the projector: in a 720 px window the display
    // squeezes a long vote result into its bars (fine on a real 1080p
    // projector, see docs/tutorial/images/display-vote-result.png).
    id: "result",
    screen: "Console — the live board, every group's numbers changed",
    say: "And the whole town feels it: every group's numbers move.",
    act: async (h) => {
      await h.top();
      await h.point("table");
    }
  },
  {
    id: "finale",
    screen: "Console: End, then the page “Final – Good Ending” → the projector shows the finale",
    say: "At the end of the evening, the game master looks at the Democracy Score, and puts up the finale.",
    act: async (h) => {
      await h.click("button:has-text('End')");
      await h.wait(800);
      await h.click('[phx-click=show_page]:has-text("Final - Good Ending")');
      await h.wait(600);
      await h.go(h.state.display);
    }
  },
  {
    id: "goodbye",
    screen: "Card on the Common Ground artwork: “Have a wonderful show!”",
    say: "That's Scenex. Everything you've seen, and a lot more, is in the written tutorial. Now go, and make Common Ground your own. Have a wonderful show!",
    act: (h) => h.card("Have a wonderful show!", "the full tutorial: scenex docs → tutorial", { image: "display-page-title.png" })
  }
];
