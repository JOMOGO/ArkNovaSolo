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

Steam Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3822969956
(subscribe, then pick it in TTS under Games → Workshop). Or from a local build:

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
python tools/tts_build.py mods/original/3812420704.json --arno --out dist/ArkNova_Scripted_ARNO.json
```

`src/` holds the base mod's scripts with this project's edits in place (CHANGES.md §1).
The branch `upstream` holds them exactly as extracted from the base mod, so this shows
every edit:

```
git diff upstream -- src
```

The build:
1. takes `src/Global.lua` and bundles `arno/` into it;
2. compile-checks the result under MoonSharp (TTS's Lua);
3. changes only the Global script and SaveName;
4. cuts ARNO's real action cards from `reference/ARNO_3.0_Cards_EN.pdf` into two 4x2
   sheets (`arno_cards_1.jpg` = side I, `arno_cards_2.jpg` = side II) in
   `Documents\My Games\Tabletop Simulator\ARNO_cards\` (local `file:///` images, visible on
   this PC only). For hosted sheets (for example Steam Cloud, so other players see them),
   upload those two files and put their URLs in `tools/arno_card_urls.json`
   (`{"face": "...", "back": "..."}`). Without the PDF, ARNO keeps the mod's action cards.
   A copy of the sheets is kept in `assets/arno_cards/` (not used by the build);
5. copies the result into the TTS Saves folder (override the folder with `ARNO_TTS_SAVES`,
   skip the copy with `--no-install`).

**Updating to a new base-mod version:** the new version goes onto `upstream`, then
`upstream` is merged into `master`. Git carries the edits over and stops with a conflict
where the mod author changed the same lines. From the repo root:

```
git worktree add ../ArkNovaSolo-upstream upstream
# copy the new Workshop JSON over ../ArkNovaSolo-upstream/mods/original/3812420704.json
python tools/tts_extract.py ../ArkNovaSolo-upstream/mods/original/3812420704.json --out ../ArkNovaSolo-upstream/src
git -C ../ArkNovaSolo-upstream add -A
git -C ../ArkNovaSolo-upstream commit -m "Base mod vX.Y.Z"
git worktree remove ../ArkNovaSolo-upstream
git merge upstream
python tools/run_tests.py
```

Use the extractor from `master` (as above), not the one in the worktree. Resolve conflicts
in `src/Global.lua` by keeping the author's new code and re-applying the edit (CHANGES.md
§1 says what each one is for). A merge without conflicts can still land an edit next to
changed code, so run the tests: `tests/test_arno_build.py` checks that every edit is in the
build.

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

## Backups (not used by the build)

- `assets/arno_cards/`: the two ARNO card sheets (`python tools/arno_cards.py`).
- `assets/mod_assets/`: every Steam Cloud file the base saves link to (images, models,
  PDFs, music), with `manifest.json` mapping each URL to its file
  (`python tools/download_assets.py`). Stored with Git LFS (`git lfs install` before cloning).

## Credits and licence

- A.R.N.O. solo mode and the ARNO action-card images: Andre K. (BGG anke79).
- Ark Nova Solo Helper (logic ported here): Stefan Seifert, Apache License 2.0.
- "Ark Nova - Complete Scripted" TTS mod: its author. This is a modified version; credit them
  when sharing.
- Ark Nova: Mathias Wigge / Feuerland Spiele / Capstone Games. No Ark Nova card art or text
  is added by this project.
- Code in `arno/`, `tools/`, `tests/`: Apache License 2.0, with attribution as in `NOTICE`.
