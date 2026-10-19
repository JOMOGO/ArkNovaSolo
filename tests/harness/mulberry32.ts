// mulberry32 PRNG: the reference for arno/core/rng.lua. Both sides must produce the
// same stream for the same seed (checked by known-answer tests).
export interface Rng {
  s: number
  next(): number
}

export function mulberry32(seed: number): Rng {
  const rng = {
    s: seed >>> 0,
    next(): number {
      const a = (rng.s + 0x6D2B79F5) >>> 0
      rng.s = a
      let t = Math.imul(a ^ (a >>> 15), 1 | a)
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    },
  }
  return rng
}
