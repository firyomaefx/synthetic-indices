/** Causal TP/SL policy. Trains only on closed labels. No future ticks. */

export const LEARNER_MIN_SAMPLES = 16;
export const LEARNER_MAX_SAMPLES = 400;

export type ArmId = "balanced" | "tight" | "wide" | "runner";

export type Arm = {
  id: ArmId;
  sl_r: number;
  tp1_r: number;
  tp2_r: number;
  tp3_r: number;
};

export const ARMS: Arm[] = [
  { id: "balanced", sl_r: 1.0, tp1_r: 1.0, tp2_r: 2.0, tp3_r: 3.0 },
  { id: "tight", sl_r: 0.85, tp1_r: 0.8, tp2_r: 1.5, tp3_r: 2.2 },
  { id: "wide", sl_r: 1.35, tp1_r: 1.2, tp2_r: 2.4, tp3_r: 4.0 },
  { id: "runner", sl_r: 1.1, tp1_r: 1.6, tp2_r: 3.0, tp3_r: 5.0 },
];

export const DEFAULT_ARM = ARMS[0];

export type LearnSample = {
  side: "UP" | "DOWN";
  label: "BREAKOUT_UP" | "BREAKOUT_DOWN" | "BOUNCE" | "CENSORED_OR_AMBIGUOUS";
  mfe: number;
  mae: number;
  hw: number;
  arm: ArmId;
};

export type LevelPolicy = {
  ready: boolean;
  source: "DEFAULT" | "UCB_QUANTILE";
  n: number;
  arm: ArmId;
  sl_r: number;
  tp1_r: number;
  tp2_r: number;
  tp3_r: number;
  mean_r: number;
};

export function clamp(n: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, n));
}

export function quantile(values: number[], q: number): number {
  if (values.length === 0) return 0;
  const s = [...values].sort((a, b) => a - b);
  const i = Math.min(s.length - 1, Math.max(0, Math.floor(q * (s.length - 1))));
  return s[i]!;
}

export function realizedR(sample: LearnSample, sl_r: number, tp3_r: number, cost_r = 0.12): number {
  const hw = Math.max(sample.hw, 1e-9);
  const stop = sl_r * hw;
  const tp3 = tp3_r * hw;
  if (Math.abs(sample.mae) >= stop) return -1 - cost_r;
  const captured = Math.min(Math.max(0, sample.mfe), tp3);
  return captured / stop - cost_r;
}

function armById(id: ArmId): Arm {
  return ARMS.find((a) => a.id === id) ?? DEFAULT_ARM;
}

export function pickArm(samples: LearnSample[], explore = 1.15): Arm {
  if (samples.length < LEARNER_MIN_SAMPLES) return DEFAULT_ARM;
  const logN = Math.log(samples.length + 1);
  let best = DEFAULT_ARM;
  let bestScore = -Infinity;
  for (const arm of ARMS) {
    const mine = samples.filter((s) => s.arm === arm.id);
    if (mine.length === 0) return arm;
    const mean = mine.reduce((acc, s) => acc + realizedR(s, arm.sl_r, arm.tp3_r), 0) / mine.length;
    const score = mean + explore * Math.sqrt(logN / mine.length);
    if (score > bestScore) {
      bestScore = score;
      best = arm;
    }
  }
  return best;
}

export function quantileBlend(samples: LearnSample[], arm: Arm): Omit<LevelPolicy, "ready" | "source" | "n" | "arm" | "mean_r"> {
  const maeR = samples.map((s) => Math.abs(s.mae) / Math.max(s.hw, 1e-9));
  const mfeR = samples
    .filter((s) => s.label === "BREAKOUT_UP" || s.label === "BREAKOUT_DOWN")
    .map((s) => Math.max(0, s.mfe) / Math.max(s.hw, 1e-9));
  const qSl = maeR.length ? clamp(quantile(maeR, 0.75), 0.7, 2.4) : arm.sl_r;
  const q1 = mfeR.length ? clamp(quantile(mfeR, 0.4), 0.5, 3) : arm.tp1_r;
  const q2 = mfeR.length ? clamp(quantile(mfeR, 0.65), q1 + 0.15, 5) : arm.tp2_r;
  const q3 = mfeR.length ? clamp(quantile(mfeR, 0.85), q2 + 0.15, 8) : arm.tp3_r;
  const sl_r = clamp(0.55 * arm.sl_r + 0.45 * qSl, 0.7, 2.5);
  const tp1_r = clamp(0.55 * arm.tp1_r + 0.45 * q1, 0.5, 4);
  const tp2_r = clamp(0.55 * arm.tp2_r + 0.45 * q2, tp1_r + 0.2, 6);
  const tp3_r = clamp(0.55 * arm.tp3_r + 0.45 * q3, tp2_r + 0.2, 8);
  return { sl_r, tp1_r, tp2_r, tp3_r };
}

export class TpSlLearner {
  samples: LearnSample[] = [];
  lastArm: Arm = DEFAULT_ARM;

  observe(sample: Omit<LearnSample, "arm">) {
    this.samples.push({ ...sample, arm: this.lastArm.id });
    if (this.samples.length > LEARNER_MAX_SAMPLES) this.samples.shift();
  }

  policy(side?: "UP" | "DOWN"): LevelPolicy {
    const pool = side ? this.samples.filter((s) => s.side === side) : this.samples;
    const n = pool.length;
    if (n < LEARNER_MIN_SAMPLES) {
      this.lastArm = DEFAULT_ARM;
      return {
        ready: false,
        source: "DEFAULT",
        n,
        arm: DEFAULT_ARM.id,
        sl_r: DEFAULT_ARM.sl_r,
        tp1_r: DEFAULT_ARM.tp1_r,
        tp2_r: DEFAULT_ARM.tp2_r,
        tp3_r: DEFAULT_ARM.tp3_r,
        mean_r: 0,
      };
    }
    const arm = pickArm(pool);
    this.lastArm = arm;
    const blend = quantileBlend(pool, arm);
    const mean_r = pool.reduce((acc, s) => acc + realizedR(s, blend.sl_r, blend.tp3_r), 0) / n;
    return {
      ready: true,
      source: "UCB_QUANTILE",
      n,
      arm: arm.id,
      ...blend,
      mean_r,
    };
  }
}

export function policyToPrices(
  policy: LevelPolicy,
  dir: 1 | -1,
  entry: number,
  hw: number,
  spread: number,
) {
  const stop = Math.max(policy.sl_r * hw, 2 * spread);
  return {
    entry,
    r: stop,
    sl: entry - dir * stop,
    tp1: entry + dir * stop * (policy.tp1_r / policy.sl_r),
    tp2: entry + dir * stop * (policy.tp2_r / policy.sl_r),
    tp3: entry + dir * stop * (policy.tp3_r / policy.sl_r),
  };
}
