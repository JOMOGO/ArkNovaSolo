// Vitest setup file. Runs before any helper module is imported, which matters:
// lodash captures `Math.random` at load time (lodash.js `nativeRandom`), so the stub
// must be in place first. The stub delegates to a reseedable global generator.
import { mulberry32, Rng } from './mulberry32'

const g = globalThis as unknown as { __arnoRng: Rng }
g.__arnoRng = mulberry32(1)
Math.random = () => g.__arnoRng.next()

export function reseed(seed: number): void {
  g.__arnoRng = mulberry32(seed)
}
