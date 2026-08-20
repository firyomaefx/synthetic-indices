/** Conservative after-cost expected-value evaluation. */

export const Action = {
  NO_TRADE: "NO_TRADE",
  ENTER_LONG: "ENTER_LONG",
  ENTER_SHORT: "ENTER_SHORT",
} as const;
export type Action = (typeof Action)[keyof typeof Action];

export type OutcomeEstimate = {
  probability: number;
  payoff: number;
};

export type TradingCosts = {
  spread: number;
  commission: number;
  slippage: number;
};

export function totalCost(costs: TradingCosts): number {
  return costs.spread + costs.commission + costs.slippage;
}

export type ActionEstimate = {
  action: Action;
  expected_value: number;
  safe_ev: number;
  total_cost: number;
  uncertainty_penalty: number;
};

export type ActionDecision = {
  action: Action;
  safe_ev: number;
  reason_code: string;
};

export class DecisionInputError extends Error {
  reason_code: string;
  constructor(reason_code: string, detail: string) {
    super(`${reason_code}: ${detail}`);
    this.name = "DecisionInputError";
    this.reason_code = reason_code;
  }
}

const FINITE = (n: number) => Number.isFinite(n);

export function evaluateAction(
  action: Action,
  outcomes: readonly OutcomeEstimate[],
  costs: TradingCosts,
  uncertainty_penalty: number,
): ActionEstimate {
  if (action === Action.NO_TRADE) {
    throw new DecisionInputError(
      "ACTION_INVALID",
      "NO_TRADE is an output, not a candidate",
    );
  }
  if (outcomes.length === 0) {
    throw new DecisionInputError("OUTCOMES_MISSING", "at least one outcome is required");
  }
  for (const outcome of outcomes) {
    if (!FINITE(outcome.probability) || outcome.probability < 0 || outcome.probability > 1) {
      throw new DecisionInputError(
        "PROBABILITY_INVALID",
        "probability must be finite in [0, 1]",
      );
    }
    if (!FINITE(outcome.payoff)) {
      throw new DecisionInputError("PAYOFF_INVALID", "payoff must be finite");
    }
  }
  const probabilitySum = outcomes.reduce((s, o) => s + o.probability, 0);
  if (Math.abs(probabilitySum - 1) > 1e-9) {
    throw new DecisionInputError(
      "PROBABILITY_SUM_INVALID",
      "outcome probabilities must sum to one",
    );
  }
  const costValues = [costs.spread, costs.commission, costs.slippage];
  if (costValues.some((v) => !FINITE(v) || v < 0)) {
    throw new DecisionInputError("COST_INVALID", "costs must be finite and non-negative");
  }
  if (!FINITE(uncertainty_penalty) || uncertainty_penalty < 0) {
    throw new DecisionInputError(
      "UNCERTAINTY_INVALID",
      "uncertainty penalty must be finite and non-negative",
    );
  }
  const grossEv = outcomes.reduce((s, o) => s + o.probability * o.payoff, 0);
  const expected_value = grossEv - totalCost(costs);
  const safe_ev = expected_value - uncertainty_penalty;
  return {
    action,
    expected_value,
    safe_ev,
    total_cost: totalCost(costs),
    uncertainty_penalty,
  };
}

export function chooseAction(
  estimates: readonly ActionEstimate[],
  health_gates_passed: boolean,
): ActionDecision {
  if (!health_gates_passed) {
    return { action: Action.NO_TRADE, safe_ev: 0, reason_code: "HEALTH_GATE_FAILED" };
  }
  if (estimates.length === 0) {
    return { action: Action.NO_TRADE, safe_ev: 0, reason_code: "NO_CANDIDATES" };
  }
  if (estimates.some((e) => e.action === Action.NO_TRADE)) {
    throw new DecisionInputError(
      "ACTION_INVALID",
      "candidate estimates cannot use NO_TRADE",
    );
  }
  if (estimates.some((e) => !FINITE(e.safe_ev))) {
    throw new DecisionInputError("SAFEEV_INVALID", "SafeEV values must be finite");
  }
  const bestSafeEv = Math.max(...estimates.map((e) => e.safe_ev));
  if (bestSafeEv <= 0) {
    return {
      action: Action.NO_TRADE,
      safe_ev: bestSafeEv,
      reason_code: "NO_POSITIVE_SAFEEV",
    };
  }
  const best = estimates.filter(
    (e) => Math.abs(e.safe_ev - bestSafeEv) <= 1e-12,
  );
  if (best.length !== 1) {
    return {
      action: Action.NO_TRADE,
      safe_ev: bestSafeEv,
      reason_code: "AMBIGUOUS_ACTION",
    };
  }
  return {
    action: best[0].action,
    safe_ev: best[0].safe_ev,
    reason_code: "POSITIVE_SAFEEV",
  };
}
