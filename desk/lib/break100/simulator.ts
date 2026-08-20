import type { SymbolId } from "./schemas";
import { SYMBOL_META } from "./schemas";

/** Seeded PRNG — deterministic replay of simulated Observe ticks. */
export function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export type SimState = {
  symbol: SymbolId;
  seed: number;
  seq: number;
  price: number;
  rng: () => number;
};

export function createSim(symbol: SymbolId, seed: number, seq = 0): SimState {
  const rng = mulberry32(seed + symbol.charCodeAt(0) * 17);
  return {
    symbol,
    seed,
    seq,
    price: SYMBOL_META[symbol].basePrice,
    rng,
  };
}

function gaussian(rng: () => number): number {
  const u = Math.max(1e-12, rng());
  const v = rng();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

/** One causal tick. Never looks ahead. */
export function stepSim(state: SimState): { bid: number; ask: number } {
  const { symbol, rng } = state;
  const tick = SYMBOL_META[symbol].tickSize;
  let delta = 0;

  switch (symbol) {
    case "BOOM100": {
      const spike = rng() < 0.012;
      delta = spike ? Math.abs(gaussian(rng)) * 18 + 6 : gaussian(rng) * 0.55;
      break;
    }
    case "CRASH100": {
      const spike = rng() < 0.012;
      delta = spike ? -(Math.abs(gaussian(rng)) * 18 + 6) : gaussian(rng) * 0.55;
      break;
    }
    case "VOL100":
      delta = gaussian(rng) * 0.35;
      break;
    case "STEP":
      delta = (rng() < 0.5 ? -1 : 1) * tick * (1 + Math.floor(rng() * 3));
      break;
    case "RANGEBREAK100": {
      const mean = SYMBOL_META[symbol].basePrice;
      const revert = (mean - state.price) * 0.004;
      const brk = rng() < 0.006 ? (rng() < 0.5 ? -1 : 1) * (8 + rng() * 14) : 0;
      delta = revert + gaussian(rng) * 0.45 + brk;
      break;
    }
  }

  state.price = Math.max(tick, state.price + delta);
  state.seq += 1;
  const spread = Math.max(tick, tick * (1 + rng() * 0.8));
  const mid = state.price;
  return { bid: mid - spread / 2, ask: mid + spread / 2 };
}
