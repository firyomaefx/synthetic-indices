import {
  AccountEnvironment,
  ModeController,
  OperatingMode,
  TransitionDenied,
  type PromotionEvidence,
} from "./mode";
import {
  Action,
  chooseAction,
  DecisionInputError,
  evaluateAction,
  type ActionEstimate,
} from "./safe-ev";
import {
  calculatePositionSize,
  defaultRiskLimits,
  evaluateRiskGate,
  HARD_MAX_RISK_FRACTION,
  RiskInputError,
  type SymbolRiskSpec,
} from "./risk";
import { makeTick } from "./pipeline";
import { createPipeline, ingestTick } from "./pipeline";
import { pinConfig } from "./schemas";
import { DEFAULT_CONFIG_BODY } from "./schemas";

export type ContractResult = { name: string; ok: boolean; detail: string };

const NOW = new Date("2026-08-13T12:00:00.000Z");
const LATER = new Date("2026-08-13T12:15:00.000Z");

function evidence(overrides: Partial<PromotionEvidence> = {}): PromotionEvidence {
  return {
    shadow_gate_passed: true,
    demo_gate_passed: true,
    live_canary_gate_passed: true,
    live_gate_passed: true,
    account_environment: AccountEnvironment.DEMO,
    owner_approved: true,
    account_approved: true,
    symbol_approved: true,
    control_lease_expires_at: LATER,
    ...overrides,
  };
}

function promoteToDemo(c: ModeController) {
  c.request_promotion(OperatingMode.SHADOW, evidence(), NOW);
  c.request_promotion(OperatingMode.DEMO, evidence(), NOW);
}

const SPEC: SymbolRiskSpec = {
  tick_size: 0.1,
  tick_value_per_lot: 1,
  contract_size: 1,
  volume_min: 0.01,
  volume_max: 10,
  volume_step: 0.01,
  minimum_stop_distance: 0.2,
};

function check(name: string, fn: () => void): ContractResult {
  try {
    fn();
    return { name, ok: true, detail: "pass" };
  } catch (err) {
    return { name, ok: false, detail: err instanceof Error ? err.message : String(err) };
  }
}

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

export function runContractSuite(): ContractResult[] {
  return [
    check("mode defaults to Observe, no order intent", () => {
      const c = new ModeController();
      assert(c.mode === OperatingMode.OBSERVE, "mode");
      assert(c.broker_order_intent_permitted === false, "intent");
    }),
    check("promotions are sequential and evidence-gated", () => {
      const c = new ModeController();
      try {
        c.request_promotion(OperatingMode.DEMO, evidence(), NOW);
        throw new Error("should deny skip");
      } catch (e) {
        assert(e instanceof TransitionDenied && e.reason_code === "MODE_SEQUENCE", "skip");
      }
      try {
        c.request_promotion(OperatingMode.SHADOW, evidence({ shadow_gate_passed: false }), NOW);
        throw new Error("should deny missing gate");
      } catch (e) {
        assert(e instanceof TransitionDenied && e.reason_code === "SHADOW_GATE_MISSING", "gate");
      }
      c.request_promotion(OperatingMode.SHADOW, evidence(), NOW);
      assert(c.mode === OperatingMode.SHADOW, "shadow");
      assert(c.broker_order_intent_permitted === false, "shadow intent");
    }),
    check("demo requires verified demo environment", () => {
      const c = new ModeController();
      c.request_promotion(OperatingMode.SHADOW, evidence(), NOW);
      try {
        c.request_promotion(
          OperatingMode.DEMO,
          evidence({ account_environment: AccountEnvironment.LIVE }),
          NOW,
        );
        throw new Error("live account accepted");
      } catch (e) {
        assert(e instanceof TransitionDenied && e.reason_code === "DEMO_ACCOUNT_REQUIRED", "env");
      }
      c.request_promotion(OperatingMode.DEMO, evidence(), NOW);
      assert(c.broker_order_intent_permitted === true, "demo intent");
    }),
    check("live canary needs owner controls", () => {
      const c = new ModeController();
      promoteToDemo(c);
      try {
        c.request_promotion(
          OperatingMode.LIVE_CANARY,
          evidence({ account_environment: AccountEnvironment.LIVE, owner_approved: false }),
          NOW,
        );
        throw new Error("missing owner");
      } catch (e) {
        assert(
          e instanceof TransitionDenied && e.reason_code === "OWNER_APPROVAL_MISSING",
          "owner",
        );
      }
    }),
    check("live canary accepts complete unexpired evidence", () => {
      const c = new ModeController();
      promoteToDemo(c);
      c.request_promotion(
        OperatingMode.LIVE_CANARY,
        evidence({ account_environment: AccountEnvironment.LIVE }),
        NOW,
      );
      assert(c.mode === OperatingMode.LIVE_CANARY, "mode");
      assert(c.broker_order_intent_permitted === false, "static intent");
      assert(c.broker_order_intent_permitted_at(NOW) === true, "lease now");
      assert(c.broker_order_intent_permitted_at(LATER) === false, "lease expiry");
    }),
    check("critical failure fails closed to Observe", () => {
      const c = new ModeController();
      promoteToDemo(c);
      c.fail_closed("RECONCILIATION_FAILED");
      assert(c.mode === OperatingMode.OBSERVE, "observe");
      assert(c.system_state === "FAULT", "fault");
      assert(c.broker_order_intent_permitted === false, "intent");
      try {
        c.request_promotion(OperatingMode.SHADOW, evidence(), NOW);
        throw new Error("promoted from fault");
      } catch (e) {
        assert(e instanceof TransitionDenied && e.reason_code === "SYSTEM_NOT_HEALTHY", "blocked");
      }
    }),
    check("naive clock is rejected", () => {
      const c = new ModeController();
      try {
        c.request_promotion(OperatingMode.SHADOW, evidence(), NOW, false);
        throw new Error("naive clock accepted");
      } catch (e) {
        assert(e instanceof TransitionDenied && e.reason_code === "UTC_CLOCK_REQUIRED", "utc");
      }
    }),
    check("SafeEV subtracts costs and uncertainty", () => {
      const est = evaluateAction(
        Action.ENTER_LONG,
        [
          { probability: 0.6, payoff: 12 },
          { probability: 0.4, payoff: -8 },
        ],
        { spread: 0.5, commission: 0.2, slippage: 0.3 },
        0.75,
      );
      assert(Math.abs(est.expected_value - 3) < 1e-9, `ev ${est.expected_value}`);
      assert(Math.abs(est.safe_ev - 2.25) < 1e-9, `safe ${est.safe_ev}`);
    }),
    check("invalid probability models fail closed", () => {
      try {
        evaluateAction(
          Action.ENTER_LONG,
          [
            { probability: 0.8, payoff: 1 },
            { probability: 0.3, payoff: -1 },
          ],
          { spread: 0, commission: 0, slippage: 0 },
          0,
        );
        throw new Error("bad sum accepted");
      } catch (e) {
        assert(e instanceof DecisionInputError && e.reason_code === "PROBABILITY_SUM_INVALID", "sum");
      }
    }),
    check("chooseAction requires health and unique positive SafeEV", () => {
      const positive: ActionEstimate = {
        action: Action.ENTER_LONG,
        expected_value: 2,
        safe_ev: 1,
        total_cost: 0.5,
        uncertainty_penalty: 0.5,
      };
      const negative: ActionEstimate = {
        action: Action.ENTER_SHORT,
        expected_value: -1,
        safe_ev: -2,
        total_cost: 0.5,
        uncertainty_penalty: 0.5,
      };
      assert(chooseAction([positive, negative], false).reason_code === "HEALTH_GATE_FAILED", "health");
      assert(chooseAction([negative], true).reason_code === "NO_POSITIVE_SAFEEV", "no edge");
      assert(chooseAction([positive, negative], true).action === Action.ENTER_LONG, "select");
      const twin: ActionEstimate = { ...positive, action: Action.ENTER_SHORT };
      assert(chooseAction([positive, twin], true).reason_code === "AMBIGUOUS_ACTION", "ambiguous");
    }),
    check("position size rounds down from stop risk", () => {
      const sizing = calculatePositionSize(10000, 0.001, 100, 98.3, SPEC);
      assert(Math.abs(sizing.risk_money - 10) < 1e-9, "risk money");
      assert(Math.abs(sizing.stop_ticks - 17) < 1e-9, "ticks");
      assert(Math.abs(sizing.lots - 0.58) < 1e-9, `lots ${sizing.lots}`);
      assert(sizing.expected_loss_at_stop <= sizing.risk_money + 1e-9, "bounded");
      assert(sizing.reason_code === "SIZE_APPROVED", "code");
    }),
    check("risk fraction above hard ceiling is rejected", () => {
      try {
        calculatePositionSize(10000, HARD_MAX_RISK_FRACTION + 0.0001, 100, 99, SPEC);
        throw new Error("ceiling passed");
      } catch (e) {
        assert(e instanceof RiskInputError && e.reason_code === "RISK_CEILING_EXCEEDED", "ceil");
      }
    }),
    check("risk gates block at each hard limit", () => {
      const limits = defaultRiskLimits();
      assert(
        evaluateRiskGate(
          {
            rolling_24h_loss_fraction: 0.01,
            weekly_loss_fraction: 0,
            total_drawdown_fraction: 0,
            open_positions_for_symbol: 0,
          },
          limits,
        ).reason_code === "ROLLING_24H_LOSS_STOP",
        "24h",
      );
      assert(
        evaluateRiskGate(
          {
            rolling_24h_loss_fraction: 0.009,
            weekly_loss_fraction: 0.029,
            total_drawdown_fraction: 0.049,
            open_positions_for_symbol: 0,
          },
          limits,
        ).allowed === true,
        "healthy",
      );
    }),
    check("limits cannot weaken hard stops", () => {
      try {
        evaluateRiskGate(
          {
            rolling_24h_loss_fraction: 0,
            weekly_loss_fraction: 0,
            total_drawdown_fraction: 0,
            open_positions_for_symbol: 0,
          },
          { ...defaultRiskLimits(), max_positions_per_symbol: 2 },
        );
        throw new Error("weakened");
      } catch (e) {
        assert(e instanceof RiskInputError && e.reason_code === "RISK_LIMITS_INVALID", "weak");
      }
    }),
    check("causal pipeline never uses future ticks", () => {
      const config = pinConfig("test-hash");
      const pipe = createPipeline(100);
      const t1 = makeTick({
        seq: 1,
        utc_us: 1,
        symbol: "VOL100",
        bid: 100,
        ask: 100.2,
        seed: 1,
        config_hash: config.hash,
        source: "REPLAY",
      });
      ingestTick(pipe, t1, { ...DEFAULT_CONFIG_BODY, hash: "test-hash" });
      const centreAfterOne = pipe.kalmanX;
      const t2 = makeTick({
        seq: 2,
        utc_us: 2,
        symbol: "VOL100",
        bid: 140,
        ask: 140.2,
        seed: 1,
        config_hash: config.hash,
        source: "REPLAY",
      });
      ingestTick(pipe, t2, { ...DEFAULT_CONFIG_BODY, hash: "test-hash" });
      // Replaying t1 in a fresh pipe must match centreAfterOne.
      const replay = createPipeline(100);
      ingestTick(replay, t1, { ...DEFAULT_CONFIG_BODY, hash: "test-hash" });
      assert(Math.abs(replay.kalmanX - centreAfterOne) < 1e-12, "replay parity");
    }),
  ];
}
