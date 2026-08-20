import { z } from "zod";

/** Versioned G1 config / tick / event / audit schemas. */

export const CONFIG_SCHEMA_VERSION = "break100.config.v1";
export const TICK_SCHEMA_VERSION = "break100.tick.v1";
export const EVENT_SCHEMA_VERSION = "break100.event.v1";
export const AUDIT_SCHEMA_VERSION = "break100.audit.v1";
export const FEATURE_SCHEMA_VERSION = "break100.feature.v1";

export const SymbolId = z.enum([
  "BOOM100",
  "CRASH100",
  "VOL100",
  "STEP",
  "RANGEBREAK100",
]);
export type SymbolId = z.infer<typeof SymbolId>;

export const SYMBOL_META: Record<
  SymbolId,
  { label: string; digits: number; tickSize: number; basePrice: number }
> = {
  BOOM100: { label: "Boom 100", digits: 2, tickSize: 0.1, basePrice: 12480 },
  CRASH100: { label: "Crash 100", digits: 2, tickSize: 0.1, basePrice: 8620 },
  VOL100: { label: "Volatility 100", digits: 2, tickSize: 0.01, basePrice: 240.5 },
  STEP: { label: "Step Index", digits: 1, tickSize: 0.1, basePrice: 8750 },
  RANGEBREAK100: { label: "Range Break 100", digits: 2, tickSize: 0.1, basePrice: 5100 },
};

export const TickSchema = z.object({
  schema: z.literal(TICK_SCHEMA_VERSION),
  seq: z.number().int().nonnegative(),
  utc_us: z.number().int().positive(),
  symbol: SymbolId,
  bid: z.number().finite(),
  ask: z.number().finite(),
  spread: z.number().nonnegative(),
  source: z.enum(["SIMULATED_OBSERVE", "REPLAY"]),
  provenance: z.object({
    seed: z.number().int(),
    config_hash: z.string().min(8),
  }),
});
export type Tick = z.infer<typeof TickSchema>;

export const EventLabel = z.enum([
  "BREAKOUT_UP",
  "BREAKOUT_DOWN",
  "BOUNCE",
  "CENSORED_OR_AMBIGUOUS",
]);
export type EventLabel = z.infer<typeof EventLabel>;

export const ChannelEventSchema = z.object({
  schema: z.literal(EVENT_SCHEMA_VERSION),
  id: z.string(),
  symbol: SymbolId,
  start_seq: z.number().int(),
  end_seq: z.number().int(),
  start_utc_us: z.number().int(),
  end_utc_us: z.number().int(),
  side: z.enum(["UP", "DOWN"]),
  label: EventLabel,
  centre: z.number(),
  half_width: z.number(),
  touch_price: z.number(),
  extreme: z.number(),
  mfe: z.number(),
  mae: z.number(),
  config_hash: z.string(),
});
export type ChannelEvent = z.infer<typeof ChannelEventSchema>;

export const FeatureSnapshotSchema = z.object({
  schema: z.literal(FEATURE_SCHEMA_VERSION),
  seq: z.number().int(),
  utc_us: z.number().int(),
  symbol: SymbolId,
  centre: z.number(),
  half_width: z.number(),
  residual: z.number(),
  spread: z.number(),
  approach_velocity: z.number(),
  tick_sign_run: z.number().int(),
  session_touch_count: z.number().int(),
  pending: z.boolean(),
});
export type FeatureSnapshot = z.infer<typeof FeatureSnapshotSchema>;

export const AuditKind = z.enum([
  "SESSION_START",
  "CONFIG_PINNED",
  "SYMBOL_CHANGE",
  "EVENT_LABELED",
  "DECISION",
  "PROMOTION_DENIED",
  "FAIL_CLOSED",
  "RECOVER_OBSERVE",
  "REPLAY_START",
  "REPLAY_STOP",
  "STREAM_PAUSE",
  "STREAM_RESUME",
]);
export type AuditKind = z.infer<typeof AuditKind>;

export const AuditEventSchema = z.object({
  schema: z.literal(AUDIT_SCHEMA_VERSION),
  id: z.string(),
  utc: z.string(),
  kind: AuditKind,
  reason_code: z.string(),
  payload: z.record(z.string(), z.unknown()),
  prev_hash: z.string(),
  hash: z.string(),
});
export type AuditEvent = z.infer<typeof AuditEventSchema>;

export const ConfigSchema = z.object({
  schema: z.literal(CONFIG_SCHEMA_VERSION),
  version: z.string(),
  hash: z.string(),
  kalman_q: z.number().positive(),
  kalman_r_floor: z.number().positive(),
  mad_window: z.number().int().min(20).max(2000),
  mad_k: z.number().positive(),
  persist_ticks: z.number().int().min(2).max(40),
  label_horizon: z.number().int().min(8).max(400),
  costs: z.object({
    spread: z.number().nonnegative(),
    commission: z.number().nonnegative(),
    slippage: z.number().nonnegative(),
  }),
  uncertainty_k: z.number().nonnegative(),
  min_samples_for_edge: z.number().int().min(5),
  risk_fraction: z.number().positive(),
});
export type DeskConfig = z.infer<typeof ConfigSchema>;

export const DEFAULT_CONFIG_BODY = {
  schema: CONFIG_SCHEMA_VERSION,
  version: "g1.2.0-observe",
  kalman_q: 0.08,
  kalman_r_floor: 0.04,
  mad_window: 160,
  mad_k: 2.4,
  persist_ticks: 6,
  label_horizon: 48,
  costs: { spread: 0.4, commission: 0.15, slippage: 0.25 },
  uncertainty_k: 1.4,
  min_samples_for_edge: 12,
  risk_fraction: 0.002,
} as const;

export async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export function pinConfig(hash: string): DeskConfig {
  return { ...DEFAULT_CONFIG_BODY, hash };
}

export function formatPrice(symbol: SymbolId, price: number): string {
  return price.toFixed(SYMBOL_META[symbol].digits);
}
