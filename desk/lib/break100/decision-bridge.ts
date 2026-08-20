import type { ChannelEvent, DeskConfig } from "./schemas";
import {
  Action,
  chooseAction,
  evaluateAction,
  type ActionDecision,
  type ActionEstimate,
  type TradingCosts,
} from "./safe-ev";

export type LabelCounts = {
  BREAKOUT_UP: number;
  BREAKOUT_DOWN: number;
  BOUNCE: number;
  CENSORED_OR_AMBIGUOUS: number;
};

export function countLabels(events: readonly ChannelEvent[]): LabelCounts {
  const c: LabelCounts = {
    BREAKOUT_UP: 0,
    BREAKOUT_DOWN: 0,
    BOUNCE: 0,
    CENSORED_OR_AMBIGUOUS: 0,
  };
  for (const e of events) c[e.label] += 1;
  return c;
}

function laplace(win: number, n: number): number {
  return (win + 1) / (n + 2);
}

/**
 * Constant-probability baseline from session labels.
 * Insufficient samples inflate uncertainty so SafeEV abstains.
 */
export function sessionEstimates(
  events: readonly ChannelEvent[],
  config: DeskConfig,
): { estimates: ActionEstimate[]; n: number; uncertainty: number; costs: TradingCosts } {
  const counts = countLabels(events);
  const n = events.length;
  const uncertainty =
    n < config.min_samples_for_edge
      ? config.uncertainty_k * 4
      : config.uncertainty_k / Math.sqrt(n);

  const pUp = laplace(counts.BREAKOUT_UP, n);
  const pDown = laplace(counts.BREAKOUT_DOWN, n);
  const pFade = 1 - pUp - pDown;
  const fade = Math.max(0, pFade);

  const costs: TradingCosts = { ...config.costs };
  const long = evaluateAction(
    Action.ENTER_LONG,
    [
      { probability: pUp, payoff: 8 },
      { probability: pDown, payoff: -10 },
      { probability: fade, payoff: -1.5 },
    ],
    costs,
    uncertainty,
  );
  const short = evaluateAction(
    Action.ENTER_SHORT,
    [
      { probability: pDown, payoff: 8 },
      { probability: pUp, payoff: -10 },
      { probability: fade, payoff: -1.5 },
    ],
    costs,
    uncertainty,
  );
  return { estimates: [long, short], n, uncertainty, costs };
}

export function observeDecision(
  events: readonly ChannelEvent[],
  config: DeskConfig,
  health: boolean,
  orderIntentPermitted: boolean,
): ActionDecision & { hypothetical: ActionDecision } {
  const { estimates } = sessionEstimates(events, config);
  const hypothetical = chooseAction(estimates, health);
  if (!orderIntentPermitted) {
    return {
      action: Action.NO_TRADE,
      safe_ev: hypothetical.safe_ev,
      reason_code: "ORDER_INTENT_BLOCKED_OBSERVE",
      hypothetical,
    };
  }
  return { ...hypothetical, hypothetical };
}
