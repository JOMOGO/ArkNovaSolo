// Produces build/harness/ts_reference.json: reference results computed by the ORIGINAL
// helper code (vendor/ark-nova-solo-helper @ f4cda53) under a seeded Math.random.
// tests/lua/test_differential.lua must reproduce every value exactly.
//
// Two levels of evidence (docs/DESIGN.md §12):
//  * services/* and util/NavigationState are imported and run unchanged;
//  * dice that live in Vue component methods cannot run headless; they are transcribed
//    below, each citing its source file and line.
import { describe, it, expect } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createPinia, setActivePinia } from 'pinia'
import rollDice from '@brdgm/brdgm-commons/src/util/random/rollDice'
import rollDiceDifferentValue from '@brdgm/brdgm-commons/src/util/random/rollDiceDifferentValue'
import randomEnum from '@brdgm/brdgm-commons/src/util/random/randomEnum'
import randomEnumDifferentValue from '@brdgm/brdgm-commons/src/util/random/randomEnumDifferentValue'
import Cards from '@/services/Cards'
import CardSlots from '@/services/CardSlots'
import BotActions from '@/services/BotActions'
import ProjectModuleTracker from '@/services/ProjectModuleTracker'
import CardName from '@/services/enum/CardName'
import AnimalType from '@/services/enum/AnimalType'
import DifficultyLevel from '@/services/enum/DifficultyLevel'
import NavigationState from '@/util/NavigationState'
import { useStateStore } from '@/store/state'
import { mulberry32 } from './mulberry32'
import { reseed } from './rng_stub'

const OUT = fileURLToPath(new URL('../../build/harness/ts_reference.json', import.meta.url))

// ---- transcriptions of component methods (source: src/components/round/*) ----

// PickConservationProject.vue:130-152 pickConservationProject()
function pickConservationProject(fromHand: number, fromBoardNoToken: number, fromBoardAvailable: number) {
  const preferFromHand = rollDice(2) == 1
  if (fromHand >= 2 || (fromHand == 1 && preferFromHand) || (fromHand == 1 && fromBoardNoToken == 0 && fromBoardAvailable == 0)) {
    return { source: 'mat', number: rollDice(fromHand) }
  }
  if (fromBoardNoToken > 0) {
    return { source: 'no_token', number: rollDice(fromBoardNoToken) }
  }
  if (fromBoardAvailable > 0) {
    return { source: 'available', number: rollDice(fromBoardAvailable) }
  }
  return { source: 'none', number: 0 }
}

// ActionCards.vue:99-105 upgradeCard()
function upgradeCard(cardSlots: CardSlots) {
  const standardCards = cardSlots.slots.filter(card => !cardSlots.isUpgraded(card))
  const upgradeCardNo = rollDice(standardCards.length)
  cardSlots.upgradeCard(standardCards[upgradeCardNo - 1])
  return standardCards[upgradeCardNo - 1].name
}

// GainPartnerZoo.vue:27 data() randomNumber / :31-33 reroll()
// GainPartnerUniversity.vue:39-40 setup() / :50-55 reroll(), rerollAnimalType()
// BotActions.vue:130 takeCardRandomNumber; BonusTile.vue:82-84; GainPartnerZooOrUniversity.vue:49-51

const enumValues = <T extends Record<string, unknown>>(e: T) => Object.values(e) as string[]

describe('ARNO reference results', () => {
  it('writes ts_reference.json', () => {
    const ref: Record<string, unknown> = {}

    // 1. card data, verbatim (used to generate arno/core/cards_data.lua)
    ref.cards = Cards.getAll()
    ref.enums = { animalType: enumValues(AnimalType), cardName: enumValues(CardName) }

    // 2. PRNG known answers
    ref.rng = [1, 42, 123456789, 4294967295].map(seed => {
      const r = mulberry32(seed)
      return { seed, values: Array.from({ length: 16 }, () => r.next()) }
    })

    // 3. BotActions exhaustive (no randomness)
    const botActions: unknown[] = []
    for (const card of Cards.getAll()) {
      for (const upgraded of [false, true]) {
        for (let slot = 1; slot <= 5; slot++) {
          for (let level = 1; level <= 6; level++) {
            for (let tokens = 0; tokens <= 7; tokens++) {
              const others = Cards.getAll().filter(c => c.name != card.name)
              const slots = [...others.slice(0, slot - 1), card, ...others.slice(slot - 1)].slice(0, 5)
              const cs = new CardSlots(slots, upgraded ? [card.name] : [])
              const ba = BotActions.newWithSlot(cs, level as DifficultyLevel, slot, tokens)
              botActions.push({
                card: card.name, upgraded, slot, level, tokens,
                actions: ba.actions, fallback: ba.fallbackActions,
                tokenScoring: ba.getTokenScoringCardCount(), tokenNotepad: ba.getTokenNotepadCount(),
                appeal: ba.getAppealCount(),
              })
            }
          }
        }
      }
    }
    ref.botActions = botActions

    // 4. ProjectModuleTracker (no randomness)
    ref.tracker = Array.from({ length: 90 }, (_, discards) => {
      const t = new ProjectModuleTracker(discards)
      return { discards, position: t.trackerPosition, slot: t.projectSlot, kiosk: t.kioskCount,
        preferred: t.getPreferredProjectSlots() }
    })

    // 5. Whole games through NavigationState (original code), with scheduled upgrades
    const games: unknown[] = []
    for (let g = 0; g < 300; g++) {
      const seed = 1000 + g
      const plan = mulberry32(seed * 7 + 3)              // schedule, independent of the game RNG
      const level = Math.floor(plan.next() * 6) + 1
      const rounds = 10 + Math.floor(plan.next() * 25)
      const upgradeAfter: number[] = []
      for (let r = 1; r <= rounds; r++) if (plan.next() < 0.18) upgradeAfter.push(r)

      setActivePinia(createPinia())
      const state = useStateStore()
      state.setup.playerSetup = { playerCount: 1, botCount: 1, playerColors: state.setup.playerSetup.playerColors }
      state.setup.difficultyLevels = [level]
      reseed(seed)
      const out: unknown[] = []
      for (let r = 1; r <= rounds; r++) {
        const nav = new NavigationState({ name: 'RoundBot', params: { round: String(r), bot: '1' } } as never)
        const br = nav.botRound!
        const entry: Record<string, unknown> = {
          slots: [...br.cardSlots.slots], upgradedAtDraw: [...br.cardSlots.upgradedCards],
          slot: br.slotNumber, tokenScoring: br.tokenScoringCardCount, tokenNotepad: br.tokenNotepadCount,
        }
        if (upgradeAfter.includes(r)) {
          const cs = CardSlots.fromPersistence(br.cardSlots)
          if (cs.canUpgradeCard()) {
            entry.upgraded = upgradeCard(cs)
            br.cardSlots = cs.toPersistence()
            state.round(br)
          }
        }
        out.push(entry)
      }
      games.push({ seed, level, rounds, upgradeAfter, turns: out })
    }
    ref.games = games

    // 6. component dice, seeded
    const dice: unknown[] = []
    for (let i = 0; i < 400; i++) {
      const seed = 50000 + i
      const p = mulberry32(seed + 11)
      const hand = Math.floor(p.next() * 4), noToken = Math.floor(p.next() * 4), available = Math.floor(p.next() * 5)
      const universityCount = p.next() < 0.5 ? 3 : 4
      reseed(seed)
      const project = pickConservationProject(hand, noToken, available)
      const takeCard = rollDice(6)
      const zoo = rollDice(5)
      const zooReroll = rollDiceDifferentValue(5, zoo)
      const zooReroll2 = rollDiceDifferentValue(5, zoo, zooReroll)
      const university = rollDice(universityCount)
      const universityReroll = rollDiceDifferentValue(universityCount, university)
      const animal = randomEnum(AnimalType)
      const animalReroll = randomEnumDifferentValue(AnimalType, animal)
      const zooOrUniversity = rollDice(2)
      const bonusTile = rollDice(2)
      dice.push({ seed, hand, noToken, available, universityCount, project, takeCard, zoo, zooReroll,
        zooReroll2, university, universityReroll, animal, animalReroll, zooOrUniversity, bonusTile })
    }
    ref.dice = dice

    // 7. CardSlots.new() alone
    ref.newSlots = Array.from({ length: 200 }, (_, i) => {
      reseed(7000 + i)
      return { seed: 7000 + i, slots: CardSlots.new().slots.map(c => c.name) }
    })

    fs.mkdirSync(path.dirname(OUT), { recursive: true })
    fs.writeFileSync(OUT, JSON.stringify(ref))
    expect(games.length).toBe(300)
  })
})
