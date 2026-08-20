import type {
  ChannelEvent,
  DeskConfig,
  EventLabel,
  FeatureSnapshot,
  SymbolId,
  Tick,
} from "./schemas";
import {
  EVENT_SCHEMA_VERSION,
  FEATURE_SCHEMA_VERSION,
  TICK_SCHEMA_VERSION,
} from "./schemas";

type Pending = {
  side: "UP" | "DOWN";
  startSeq: number;
  startUtc: number;
  centre: number;
  halfWidth: number;
  touchPrice: number;
  extreme: number;
  mfe: number;
  mae: number;
  ticksOutside: number;
};

export type ChannelPoint = {
  seq: number;
  utc_us: number;
  bid: number;
  ask: number;
  mid: number;
  centre: number;
  halfWidth: number;
};

export type PipelineState = {
  kalmanX: number;
  kalmanP: number;
  residuals: number[];
  lastMid: number;
  lastSign: number;
  run: number;
  pending: Pending | null;
  events: ChannelEvent[];
  points: ChannelPoint[];
  touchCount: number;
  seq: number;
};

export function createPipeline(firstMid: number): PipelineState {
  return {
    kalmanX: firstMid,
    kalmanP: 1,
    residuals: [],
    lastMid: firstMid,
    lastSign: 0,
    run: 0,
    pending: null,
    events: [],
    points: [],
    touchCount: 0,
    seq: 0,
  };
}

function median(values: number[]): number {
  if (values.length === 0) return 0;
  const s = [...values].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

function mad(values: number[]): number {
  if (values.length === 0) return 0;
  const med = median(values);
  return median(values.map((v) => Math.abs(v - med)));
}

export function ingestTick(
  pipe: PipelineState,
  tick: Tick,
  config: DeskConfig,
): { event: ChannelEvent | null; feature: FeatureSnapshot } {
  const mid = (tick.bid + tick.ask) / 2;
  const spread = tick.ask - tick.bid;
  const R = Math.max(config.kalman_r_floor, spread * spread);
  // Predict
  pipe.kalmanP += config.kalman_q;
  const K = pipe.kalmanP / (pipe.kalmanP + R);
  pipe.kalmanX += K * (mid - pipe.kalmanX);
  pipe.kalmanP *= 1 - K;

  const residual = mid - pipe.kalmanX;
  pipe.residuals.push(residual);
  if (pipe.residuals.length > config.mad_window) pipe.residuals.shift();

  const scale = 1.4826 * mad(pipe.residuals);
  const halfWidth = Math.max(
    config.mad_k * Math.max(scale, spread),
    2 * spread,
    tick.ask - tick.bid,
  );
  const channelWidth = 2 * halfWidth;
  const touchDistance = Math.max(2 * spread, 0.05 * channelWidth);

  const sign = residual === 0 ? 0 : residual > 0 ? 1 : -1;
  if (sign !== 0 && sign === pipe.lastSign) pipe.run += 1;
  else pipe.run = sign === 0 ? 0 : 1;
  if (sign !== 0) pipe.lastSign = sign;

  const approach = mid - pipe.lastMid;
  pipe.lastMid = mid;
  pipe.seq = tick.seq;

  const point: ChannelPoint = {
    seq: tick.seq,
    utc_us: tick.utc_us,
    bid: tick.bid,
    ask: tick.ask,
    mid,
    centre: pipe.kalmanX,
    halfWidth,
  };
  pipe.points.push(point);
  if (pipe.points.length > 1400) pipe.points.shift();

  let labeled: ChannelEvent | null = null;
  const outside = Math.abs(residual) >= halfWidth - touchDistance;
  const farOutside = Math.abs(residual) >= halfWidth;
  const nearCentre = Math.abs(residual) <= 0.22 * halfWidth;

  if (pipe.pending) {
    const p = pipe.pending;
    const excursion = (mid - p.touchPrice) * (p.side === "UP" ? 1 : -1);
    p.mfe = Math.max(p.mfe, excursion);
    p.mae = Math.min(p.mae, excursion);
    p.extreme = p.side === "UP" ? Math.max(p.extreme, mid) : Math.min(p.extreme, mid);
    if (farOutside && ((p.side === "UP" && residual > 0) || (p.side === "DOWN" && residual < 0))) {
      p.ticksOutside += 1;
    }
    const horizonHit = tick.seq - p.startSeq >= config.label_horizon;
    const flipped =
      (p.side === "UP" && residual < -0.6 * halfWidth) ||
      (p.side === "DOWN" && residual > 0.6 * halfWidth);

    let label: EventLabel | null = null;
    if (p.ticksOutside >= config.persist_ticks && farOutside) {
      label = p.side === "UP" ? "BREAKOUT_UP" : "BREAKOUT_DOWN";
    } else if (nearCentre && tick.seq - p.startSeq >= 3) {
      label = "BOUNCE";
    } else if (flipped || horizonHit) {
      label = "CENSORED_OR_AMBIGUOUS";
    }

    if (label) {
      labeled = {
        schema: EVENT_SCHEMA_VERSION,
        id: `ev-${p.startSeq}-${tick.seq}`,
        symbol: tick.symbol,
        start_seq: p.startSeq,
        end_seq: tick.seq,
        start_utc_us: p.startUtc,
        end_utc_us: tick.utc_us,
        side: p.side,
        label,
        centre: p.centre,
        half_width: p.halfWidth,
        touch_price: p.touchPrice,
        extreme: p.extreme,
        mfe: p.mfe,
        mae: p.mae,
        config_hash: config.hash,
      };
      pipe.events.push(labeled);
      if (pipe.events.length > 200) pipe.events.shift();
      pipe.pending = null;
    }
  } else if (outside && pipe.residuals.length > 12) {
    pipe.touchCount += 1;
    pipe.pending = {
      side: residual > 0 ? "UP" : "DOWN",
      startSeq: tick.seq,
      startUtc: tick.utc_us,
      centre: pipe.kalmanX,
      halfWidth,
      touchPrice: mid,
      extreme: mid,
      mfe: 0,
      mae: 0,
      ticksOutside: farOutside ? 1 : 0,
    };
  }

  const feature: FeatureSnapshot = {
    schema: FEATURE_SCHEMA_VERSION,
    seq: tick.seq,
    utc_us: tick.utc_us,
    symbol: tick.symbol,
    centre: pipe.kalmanX,
    half_width: halfWidth,
    residual,
    spread,
    approach_velocity: approach,
    tick_sign_run: pipe.run * pipe.lastSign,
    session_touch_count: pipe.touchCount,
    pending: pipe.pending !== null,
  };

  return { event: labeled, feature };
}

export function makeTick(args: {
  seq: number;
  utc_us: number;
  symbol: SymbolId;
  bid: number;
  ask: number;
  seed: number;
  config_hash: string;
  source: Tick["source"];
}): Tick {
  return {
    schema: TICK_SCHEMA_VERSION,
    seq: args.seq,
    utc_us: args.utc_us,
    symbol: args.symbol,
    bid: args.bid,
    ask: args.ask,
    spread: args.ask - args.bid,
    source: args.source,
    provenance: { seed: args.seed, config_hash: args.config_hash },
  };
}
