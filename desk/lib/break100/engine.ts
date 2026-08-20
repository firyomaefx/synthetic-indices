import { appendAudit } from "./audit";
import { observeDecision, sessionEstimates, type LabelCounts, countLabels } from "./decision-bridge";
import { TpSlLearner, type LevelPolicy } from "./learner";
import { ModeController, OperatingMode, TransitionDenied, emptyEvidence } from "./mode";
import {
  createPipeline,
  ingestTick,
  makeTick,
  type ChannelPoint,
  type PipelineState,
} from "./pipeline";
import {
  DEFAULT_CONFIG_BODY,
  type AuditEvent,
  type ChannelEvent,
  type DeskConfig,
  type FeatureSnapshot,
  type SymbolId,
  type Tick,
} from "./schemas";
import { createSim, stepSim, type SimState } from "./simulator";
import { Action, type ActionDecision, type ActionEstimate } from "./safe-ev";
import { evaluateRiskGate, defaultRiskLimits, type RiskGateResult } from "./risk";

export type EngineSnapshot = {
  symbol: SymbolId;
  seed: number;
  running: boolean;
  speed: 1 | 2 | 4;
  seq: number;
  lastTick: Tick | null;
  lastFeature: FeatureSnapshot | null;
  points: ChannelPoint[];
  events: ChannelEvent[];
  labels: LabelCounts;
  decision: ActionDecision & { hypothetical: ActionDecision };
  estimates: ActionEstimate[];
  sampleN: number;
  uncertainty: number;
  mode: ReturnType<ModeController["snapshot"]>;
  risk: RiskGateResult;
  audit: AuditEvent[];
  config: DeskConfig;
  lastDeny: string;
  learn: LevelPolicy;
};

const MAX_AUDIT = 80;
const TICK_MS = 90;

export class DeskEngine {
  readonly controller = new ModeController();
  config: DeskConfig;
  symbol: SymbolId;
  seed: number;
  sim: SimState;
  pipe: PipelineState;
  running = true;
  speed: 1 | 2 | 4 = 1;
  lastTick: Tick | null = null;
  lastFeature: FeatureSnapshot | null = null;
  audit: AuditEvent[] = [];
  lastDeny = "";
  source: Tick["source"] = "SIMULATED_OBSERVE";
  originUs = Date.now() * 1000;
  listeners = new Set<() => void>();
  private cached: EngineSnapshot | null = null;
  readonly learners = new Map<SymbolId, TpSlLearner>();

  learner(): TpSlLearner {
    let L = this.learners.get(this.symbol);
    if (!L) {
      L = new TpSlLearner();
      this.learners.set(this.symbol, L);
    }
    return L;
  }

  constructor(config: DeskConfig, symbol: SymbolId = "RANGEBREAK100", seed = 100100) {
    this.config = config;
    this.symbol = symbol;
    this.seed = seed;
    this.sim = createSim(symbol, seed);
    this.pipe = createPipeline(this.sim.price);
  }

  subscribe(fn: () => void) {
    this.listeners.add(fn);
    return () => {
      this.listeners.delete(fn);
    };
  }

  private emit() {
    this.cached = null;
    for (const fn of this.listeners) fn();
  }

  async boot() {
    await this.note("SESSION_START", "OBSERVE_DEFAULT", {
      symbol: this.symbol,
      seed: this.seed,
      config_hash: this.config.hash,
    });
    await this.note("CONFIG_PINNED", this.config.version, {
      hash: this.config.hash,
      schema: this.config.schema,
    });
    this.emit();
  }

  snapshot(): EngineSnapshot {
    if (this.cached) return this.cached;
    const events = this.pipe.events;
    const { estimates, n, uncertainty } = sessionEstimates(events, this.config);
    const health = this.controller.system_state === "HEALTHY";
    const decision = observeDecision(
      events,
      this.config,
      health,
      this.controller.broker_order_intent_permitted,
    );
    const risk = evaluateRiskGate(
      {
        rolling_24h_loss_fraction: 0,
        weekly_loss_fraction: 0,
        total_drawdown_fraction: 0,
        open_positions_for_symbol: 0,
      },
      defaultRiskLimits(),
    );
    this.cached = {
      symbol: this.symbol,
      seed: this.seed,
      running: this.running,
      speed: this.speed,
      seq: this.sim.seq,
      lastTick: this.lastTick,
      lastFeature: this.lastFeature,
      points: this.pipe.points,
      events,
      labels: countLabels(events),
      decision,
      estimates,
      sampleN: n,
      uncertainty,
      mode: this.controller.snapshot(),
      risk,
      audit: this.audit,
      config: this.config,
      lastDeny: this.lastDeny,
      learn: this.learner().policy(
        this.pipe.pending?.side ?? this.pipe.events.at(-1)?.side,
      ),
    };
    return this.cached;
  }

  step(count = 1) {
    for (let i = 0; i < count; i++) {
      const { bid, ask } = stepSim(this.sim);
      const utc_us = this.originUs + this.sim.seq * TICK_MS * 1000;
      const tick = makeTick({
        seq: this.sim.seq,
        utc_us,
        symbol: this.symbol,
        bid,
        ask,
        seed: this.seed,
        config_hash: this.config.hash,
        source: this.source,
      });
      const { event, feature } = ingestTick(this.pipe, tick, this.config);
      this.lastTick = tick;
      this.lastFeature = feature;
      if (event) {
        const L = this.learner();
        L.policy(event.side);
        L.observe({
          side: event.side,
          label: event.label,
          mfe: event.mfe,
          mae: event.mae,
          hw: event.half_width,
        });
        void this.note("EVENT_LABELED", event.label, {
          id: event.id,
          side: event.side,
          seq: event.end_seq,
        });
        const health = this.controller.system_state === "HEALTHY";
        const decision = observeDecision(
          this.pipe.events,
          this.config,
          health,
          this.controller.broker_order_intent_permitted,
        );
        void this.note("DECISION", decision.reason_code, {
          action: decision.action,
          hypothetical: decision.hypothetical.action,
          safe_ev: Number(decision.safe_ev.toFixed(4)),
        });
      }
    }
    this.emit();
  }

  async setSymbol(symbol: SymbolId) {
    this.symbol = symbol;
    this.sim = createSim(symbol, this.seed);
    this.pipe = createPipeline(this.sim.price);
    this.lastTick = null;
    this.lastFeature = null;
    this.originUs = Date.now() * 1000;
    await this.note("SYMBOL_CHANGE", symbol, { seed: this.seed });
    this.emit();
  }

  async setSeed(seed: number) {
    this.seed = seed >>> 0;
    this.sim = createSim(this.symbol, this.seed);
    this.pipe = createPipeline(this.sim.price);
    this.lastTick = null;
    this.lastFeature = null;
    this.originUs = Date.now() * 1000;
    this.source = "REPLAY";
    await this.note("REPLAY_START", String(this.seed), { symbol: this.symbol });
    this.emit();
  }

  pause() {
    this.running = false;
    void this.note("STREAM_PAUSE", "OPERATOR", { seq: this.sim.seq });
    this.emit();
  }

  resume() {
    this.running = true;
    this.source = "SIMULATED_OBSERVE";
    void this.note("STREAM_RESUME", "OPERATOR", { seq: this.sim.seq });
    this.emit();
  }

  setSpeed(speed: 1 | 2 | 4) {
    this.speed = speed;
    this.emit();
  }

  requestNextMode() {
    const order: OperatingMode[] = [
      OperatingMode.OBSERVE,
      OperatingMode.SHADOW,
      OperatingMode.DEMO,
      OperatingMode.LIVE_CANARY,
      OperatingMode.LIVE,
    ];
    const idx = order.indexOf(this.controller.mode);
    const target = order[idx + 1];
    if (!target) {
      this.lastDeny = "MODE_SEQUENCE: already at LIVE";
      this.emit();
      return;
    }
    try {
      this.controller.request_promotion(target, emptyEvidence(), new Date(), true);
      this.lastDeny = "";
    } catch (err) {
      const msg = err instanceof TransitionDenied ? `${err.reason_code}: ${err.message}` : String(err);
      this.lastDeny = msg;
      void this.note("PROMOTION_DENIED", err instanceof TransitionDenied ? err.reason_code : "DENIED", {
        target,
        detail: msg,
      });
    }
    this.emit();
  }

  failClosed(reason = "OPERATOR_FAULT_INJECTION") {
    this.controller.fail_closed(reason);
    this.running = false;
    void this.note("FAIL_CLOSED", reason, {});
    this.emit();
  }

  recover() {
    this.controller.recover_observe();
    void this.note("RECOVER_OBSERVE", "OPERATOR", {});
    this.emit();
  }

  private async note(
    kind: AuditEvent["kind"],
    reason_code: string,
    payload: Record<string, unknown>,
  ) {
    const next = await appendAudit(this.audit.at(-1) ?? null, kind, reason_code, payload);
    this.audit = [...this.audit, next].slice(-MAX_AUDIT);
    this.emit();
  }
}

export function defaultConfig(hash: string): DeskConfig {
  return { ...DEFAULT_CONFIG_BODY, hash };
}
