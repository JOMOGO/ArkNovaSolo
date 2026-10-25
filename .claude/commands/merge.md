---
description: Merge a branch into master, run the tests, build the save into TTS and write the Workshop release notes
argument-hint: "[branch] (default: refactor/general)"
---

Merge the branch `$ARGUMENTS` (if empty: `refactor/general`) into `master` and get it ready
for a Workshop upload:

1. Check `git status`: stop and tell me if there are uncommitted changes to tracked files
   (untracked `.claude/` and `reference/*.mp4` are fine).
2. `git checkout master`, then `git merge --ff-only <branch>`. If it cannot fast-forward,
   do a normal `git merge <branch>`; on a conflict, stop and show me the conflicting files.
3. Run `python tools/run_tests.py`. If anything fails, stop and show the failures; do not
   build or write notes.
4. Build and install the save:
   `python tools/tts_build.py mods/original/3812420704.json --arno --out dist/ArkNova_Scripted_ARNO.json`
   (it copies the save into `Documents\My Games\Tabletop Simulator\Saves\`). Confirm the
   "installed" line.
5. Write the Workshop release notes for what the merge brought in (read the commits and the
   new FIX / AUTO / H rows in `CHANGES.md` since the previous master). Follow the
   "Workshop change notes" rule in `CLAUDE.md`: simple, player-facing, one bullet per change
   in the game, nothing about tests, tooling or refactors.
6. Do not push, do not delete the branch. Report: the new master commit, test result, the
   installed save path, and the release notes ready to paste.
