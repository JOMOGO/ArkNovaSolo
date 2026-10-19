# ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator)

Adds the unofficial **A.R.N.O. 3.0** solo/extra opponent (design: Andre K.) as fully
automated players to the scripted Tabletop Simulator mod "Ark Nova - Complete Scripted":
- 1–4 humans plus 1–3 ARNOs;
- difficulty levels 1–10;
- optional ARNO project module;
- Marine Worlds supported.

ARNO's decisions are a tested Lua port of the
[Ark Nova Solo Helper](https://github.com/brdgm/ark-nova-solo-helper) by Stefan Seifert
(Apache-2.0); see `NOTICE`.

## Play

1. The build installs `ArkNova_Scripted_ARNO.json` in
   `Documents\My Games\Tabletop Simulator\Saves\` automatically (manual: copy
   `dist/ArkNova_Scripted_ARNO.json` there).
2. In TTS: **Games → Save & Load**, then pick **"Ark Nova - Complete Scripted + ARNO 3.0"**.
3. Sit in a colour, click **Setup Game**. For each free colour choose
   *ARNO opponent: Level 1–10* (or Off), then *Proceed*.
4. Play your turns as usual. ARNO's turns run on their own; the ARNO panel (top right)
   shows his cards, debt, tokens and a log. *Auto: off* makes him wait for
   *Run ARNO turn*.

The mod's assets (card images etc.) are loaded from the original mod's Steam URLs, as in
the base mod. The original Workshop file is not modified.

## Build

Requires Python 3.11+ with Pillow, and the .NET SDK 9+.

```
python tools/tts_extract.py mods/original/3812420704.json --out src     # only after a base-mod update
python tools/tts_build.py mods/original/3812420704.json --arno --out dist/ArkNova_Scripted_ARNO.json
```

The build:
1. applies `hooks/hooks.json` (it fails if the base mod changed under an anchor);
2. bundles `arno/`;
3. compile-checks the result under MoonSharp (TTS's Lua);
4. changes only the Global script and SaveName;
5. cuts ARNO's real action cards from `reference/ARNO_3.0_Cards_EN.pdf` into
   `Documents\My Games\Tabletop Simulator\ARNO_cards\` (local `file:///` images, visible on
   this PC only). For hosted images (for example Steam Cloud, so other players see them),
   put their URLs in `tools/arno_card_urls.json` (`{"animals_g": {"face": ..., "back": ...}, ...}`,
   keys as in `tools/arno_cards.py`). Without the PDF, ARNO keeps the mod's action cards;
6. copies the result into the TTS Saves folder (override the folder with `ARNO_TTS_SAVES`,
   skip the copy with `--no-install`).

**Updating to a new base-mod version:**
1. Copy the new Workshop JSON to `mods/original/`.
2. Re-extract.
3. Rebuild.
4. Run the tests.

If a hook anchor no longer matches, the build names it.

## Test

```
python tools/run_tests.py            # everything (needs Node >= 20.19 for the TypeScript parts)
python tools/run_tests.py --skip-node
```

| Suite | What it checks |
|---|---|
| Python | extract/build round trip (byte-identical) |
| helper | the helper app's own unit tests (original TypeScript) |
| differential | seeded original TypeScript vs the Lua port: 2,400 action cases, 300 full games, 400 dice sets, shuffles, tracker, RNG |
| Lua | ported helper specs, ARNO rules (plan) |
| integration | the **built** mod + ARNO executed headless: claims engine, 60-turn soak, replay determinism, setup cards, breaks, scoring, ties |

In-game checklist: `TESTING.md`.

## Docs

| File | Contents |
|---|---|
| `docs/MOD_ARCHITECTURE.md` | how the base mod works |
| `docs/ARNO_LOGIC.md` | what the helper app computes and asks |
| `docs/DECISION.md` | options studied, and why this one |
| `docs/DESIGN.md` | architecture, hooks, RNG, persistence, rulings R1–R21 |
| `docs/MOD_PRIMITIVES.md` | mod functions used for each ARNO step |
| `CHANGES.md` | every change to the base mod |

## Credits and licence

- A.R.N.O. solo mode: Andre K. (BGG anke79).
- Ark Nova Solo Helper (logic ported here): Stefan Seifert, Apache License 2.0.
- "Ark Nova - Complete Scripted" TTS mod: its author. This is a modified version; credit them
  when sharing.
- Ark Nova: Mathias Wigge / Feuerland Spiele / Capstone Games. No card art or text is added
  by this project.
- Code in `arno/`, `tools/`, `tests/`: Apache License 2.0, with attribution as in `NOTICE`.
