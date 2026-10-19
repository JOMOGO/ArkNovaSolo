// Differential harness: runs the ORIGINAL helper TypeScript (vendor/ark-nova-solo-helper)
// with a seeded Math.random and writes reference results to build/harness/.
// Run via: python tools/run_tests.py  (or the vitest binary from the helper's node_modules)
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vitest/config'

const helperSrc = fileURLToPath(new URL('../../vendor/ark-nova-solo-helper/src', import.meta.url))

export default defineConfig({
  resolve: { alias: { '@': helperSrc } },
  test: {
    root: fileURLToPath(new URL('.', import.meta.url)),
    include: ['*.spec.ts'],
    environment: 'node',
    setupFiles: ['./rng_stub.ts'],
    testTimeout: 120000,
  },
})
