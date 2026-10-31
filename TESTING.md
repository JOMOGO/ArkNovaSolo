# In-game test checklist (Tabletop Simulator)

The automated tests (`python tools/run_tests.py`) cover ARNO's decisions and the interplay
with the mod's code headlessly. What only the real game can show is the physical side:
objects moving, panels appearing, rewind. Tick these off once and report anything odd.
**Tip:** open the TTS chat; every ARNO action is logged there as `[ARNO] ...`.

Install: see README ("Play").

## A. Setup

- [ ] **A1 — 1 human + ARNO (Yellow).** Sit in Red, click *Setup Game*.
  - The panel shows "ARNO opponent (White/Blue/Yellow)" rows and "ARNO project module".
  - Set Yellow to Level 3 and Proceed. Chat: "Setting up a 2-Player game", "1 ARNO opponent(s), seed …".
  - Interactive effects are locked to Disabled.
- [ ] **A2 — components.** Yellow keeps its board, counters and tokens. The break token
  starts at 9 (2-player). Neutral blocker cubes sit on the base projects and donation spots.
- [ ] **A3 — start player is you.** Chat: "<your name> is the starting player". Yellow has
  appeal 1 (2nd player).
- [ ] **A4 — ARNO's mat.**
  - Map A image on Yellow's board.
  - 5 action cards: Animals in slot 1.
  - 1 face-down final scoring card on the left of his board.
  - 0–2 project cards on his mat. His other starting cards went to the discard pile.
  - Panel shows "CP debt 5".
- [ ] **A5 — only you get prompts:** map selection, setup discard. No hang waiting for Yellow.
- [ ] **A6 — Marine Worlds variant.** You draw 3 new action cards and pick 2 (ARNO doesn't
  draft). ARNO's panel shows CP debt 3.
- [ ] **A7 — 2 ARNOs** (e.g. Blue L2 + Yellow L5).
  - Both get set up, named "ARNO 1" / "ARNO 2".
  - Turn order follows seats, and a human starts.
- [ ] **A8 — no ARNO** (all rows Off): plays exactly like the base mod. With 1 seated
  player, the official solo challenge starts as before.

## B. ARNO's turns

- [ ] **B1.** After your turn the panel says ARNO is about to play. After ~2 s ARNO plays.
  - Chat lists the slot, the card and each action.
  - His action cards re-order: the used card goes to slot 1.
- [ ] **B2 — tracks.** His appeal, reputation and CP markers move; the break token moves left.
  He gets **no money** and **no X-token**, even when he triggers a break.
- [ ] **B3 — display snap.** A display card goes to ARNO.
  - An animal lands on his mat: his icon counters increase, and your "whenever any player…"
    sponsors pay you.
  - A sponsor goes to the discard pile.
  - A project stays on his mat.
  - The display refills.
- [ ] **B4 — Association.**
  - A worker moves to a task (never one where ARNO already has a worker).
  - Partner zoo / university tiles move to his board.
  - His 2nd partner zoo flips one of his action cards (upgrade).
  - On Association II he also donates: a Yellow cube on the next donation spot, +1 CP.
- [ ] **B5 — conservation project.** A Yellow cube appears on a project:
  - L1–2 on the right condition, L3–4 middle, L5+ left;
  - if that one is taken, the next one to the left.
  He gains its CP (and reputation for breeding projects).
- [ ] **B6 — CP milestones.**
  - At 2 CP (after the debt) he unlocks a worker.
  - At 5/8 CP one of the two variable bonus tiles is flipped (removed for you too).
  - At 10 CP you are asked to discard a final scoring card.
- [ ] **B7 — Auto / manual.**
  - Switch *Auto: off*: ARNO waits; *Run ARNO turn* plays it.
  - *Hide* collapses the panel.
- [ ] **B8 — undo hint.** Your action panel shows "Undo a choice: press the rewind arrow
  twice."

## C. Breaks

- [ ] **C1.** A break (triggered by you or ARNO) runs normally for you.
  - ARNO is not asked to discard.
  - His workers return.
  - In his income slot he draws 3 cards: the first project stays on his mat, the first animal
    goes on his mat (it can trigger your effects), the rest are discarded.
- [ ] **C2.** With the project module on: sponsors ARNO discards move the panel's
  "module: …, kiosks …" status.

## D. Game end and scoring

- [ ] **D1.** ARNO can trigger the end (his markers cross). If you trigger it, ARNO still
  gets one more turn.
- [ ] **D2.** Final scoring: you discard/score as usual. Chat shows "ARNO final scoring: N
  CP from tokens".
- [ ] **D3.** The winner panel is correct. **On a tie, ARNO wins.**

## E. Rewind, save and load

- [ ] **E1. Rewind in the middle of an ARNO turn** (press rewind while ARNO's actions are
  still being applied).
  - If the mod shows "press the rewind arrow once more", do so.
  - The game returns to the start of ARNO's turn, and he then plays **exactly the same
    turn** again (same card, same dice).
- [ ] **E2. Rewind into your own turn** (twice after choosing an action): your turn restarts.
  ARNO's following turn is the same as before.
- [ ] **E3. Rewind during ARNO's break draw.** It resumes at his income slot, with the same
  three cards.
- [ ] **E4. Save & load at the start of a turn** (Games → Save, then load it). The ARNO
  panel comes back (seed, log, his slots), and the game continues.
- [ ] **E5.** After a rewind, the panel's seed is unchanged and his card slots match the
  physical cards.

## F. Card fixes (every game, with or without ARNO)

- [ ] **F1 — African Spurred Tortoise (#471)** can be played into a Reptile House
  (FIX471).
- [ ] **F2 — Sea Animal Management Plan (#138, Marine Worlds).** Play two sea animals with
  a reef effect, then support the project in its left slot: you get 2 CP and each reef
  effect, and the turn goes on (FIX138).
- [ ] **F3 — upgrade with nothing left to upgrade.** With all five action cards upgraded,
  take an upgrade reward (for example your 2nd partner zoo): chat says you have no action
  card left to upgrade, and the turn goes on (FIXFLIP).
- [ ] **F4 — the same reward twice.** Get the same reward from two sources in one go (for
  example two sponsors paying 2 money for one icon): both are paid at once, without a
  claims panel. So are appeal, money and X-tokens together. Appeal plus reputation still asks
  for the order (AUTOSAME).
- [ ] **F5 — no click without a choice.** With one final scoring card in hand, the 10 CP
  discard happens by itself; with one action card left to upgrade, an upgrade reward
  upgrades it; supporting a project with only one project and one open slot goes straight
  to the project cube, but with a Wildcard token the slot is still asked (AUTOONE).

## H. AI opponent (branch `ai-opponent`, docs/AI_OPPONENT.md)

The AI plays a full seat by the human rules through the same panels. Headless tests cover
its decisions and whole games; these are the physical things only TTS can show.

- [ ] **H1 — hand of an empty seat (check P1, the most important one).** Sit in Red, set Blue
  to *AI Medium* (click the row past ARNO Level 10), Proceed. After setup Blue has 8 cards in
  its hand zone, then 4 after the setup discard. You see card backs only, not their faces.
- [ ] **H2 — setup prompts.** The AI discards its 4 cards on its own and the game starts when
  you confirm yours. With Marine Worlds it drafts by itself. Classic map match: it readies
  on its own. Custom map setup: it plays map A and you only place your own tile.
- [ ] **H3 — an AI turn.** It picks an action and plays it through: cards leave its hand, tiles
  land on its map, money and appeal move. About a third of a second between its inputs.
  No visible freeze while it thinks.
- [ ] **H4 — building.** Its building tiles sit on valid spots of its map (not floating, not
  overlapping) and its enclosures fill with its animals.
- [ ] **H5 — breaks and game end.** At a break it discards down to its hand limit and takes
  its income; at the end it discards its final scoring card if asked and is scored.
- [ ] **H6 — rewind.** Rewind during an AI turn: it replays the same moves.
- [ ] **H7 — levels.** Play Easy and Expert once each: Easy makes visibly weaker choices.
- [ ] **H8 — stuck AI.** If the chat says "The AI (colour) is stuck", sit in that colour to
  finish the move, and report the message.

## I. Dead-end fixes (every game)

- [ ] **I1 — BUILD greyed out.** Fill your map (or have too little money for anything that
  fits): the BUILD row in the action panel is greyed out. With room again it is offered.
- [ ] **I2 — venom fee with 1 money** (Marine Worlds). End a turn with a venom token on one
  of your action cards and 1 money: the button reads "Pay Venom Fee: 1 Money (all you have)",
  it takes the 1 and the next player's turn starts.
- [ ] **I3 — animal that cannot be played.** Choose ANIMALS, pick an animal you cannot
  afford: the panel says "Cannot be played (Insufficient money: need N)", there is no
  Confirm, and "Back to action choice" is still there.
- [ ] **I4 — scavenging with a short discard pile.** Scavenge with fewer cards in the
  discard pile than asked: you get the cards that are there (none: a chat line, play goes on).
- [ ] **I5 — the discard pile down to one card, or gone, then a discard:** the card lands
  in the discard pile spot and later discards stack on it.

## G. Things to report if they happen

- Chat: `[ARNO] ERROR in step …` (the turn continues; press *Run ARNO turn* or rewind).
- Any panel or prompt that seems to wait for Yellow, or a game that stops advancing.
- A Yellow cube, tile or card landing somewhere odd (positions on ARNO's mat are guesses
  until checked in-game).
