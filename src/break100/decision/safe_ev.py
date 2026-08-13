"""Conservative after-cost expected-value evaluation."""

from dataclasses import dataclass
from enum import StrEnum
from math import fsum, isclose, isfinite


class Action(StrEnum):
    """Permitted baseline decisions."""

    NO_TRADE = "NO_TRADE"
    ENTER_LONG = "ENTER_LONG"
    ENTER_SHORT = "ENTER_SHORT"


@dataclass(frozen=True, slots=True)
class OutcomeEstimate:
    """Calibrated probability and net-before-explicit-cost payoff pair."""

    probability: float
    payoff: float


@dataclass(frozen=True, slots=True)
class TradingCosts:
    """Explicit per-action trading costs in payoff units."""

    spread: float
    commission: float
    slippage: float

    @property
    def total(self) -> float:
        """Return the sum of all explicit costs."""
        return fsum((self.spread, self.commission, self.slippage))


@dataclass(frozen=True, slots=True)
class ActionEstimate:
    """Expected value and its conservative lower bound for one action."""

    action: Action
    expected_value: float
    safe_ev: float
    total_cost: float
    uncertainty_penalty: float


@dataclass(frozen=True, slots=True)
class ActionDecision:
    """Selected action or reason-coded abstention."""

    action: Action
    safe_ev: float
    reason_code: str


class DecisionInputError(ValueError):
    """Raised with a stable reason code for unsafe decision inputs."""

    def __init__(self, reason_code: str, detail: str) -> None:
        self.reason_code = reason_code
        super().__init__(f"{reason_code}: {detail}")


def evaluate_action(
    action: Action,
    *,
    outcomes: tuple[OutcomeEstimate, ...],
    costs: TradingCosts,
    uncertainty_penalty: float,
) -> ActionEstimate:
    """Calculate after-cost EV and SafeEV for one trade candidate."""
    if action is Action.NO_TRADE:
        raise DecisionInputError("ACTION_INVALID", "NO_TRADE is an output, not a candidate")
    if not outcomes:
        raise DecisionInputError("OUTCOMES_MISSING", "at least one outcome is required")

    for outcome in outcomes:
        if not isfinite(outcome.probability) or not 0.0 <= outcome.probability <= 1.0:
            raise DecisionInputError("PROBABILITY_INVALID", "probability must be finite in [0, 1]")
        if not isfinite(outcome.payoff):
            raise DecisionInputError("PAYOFF_INVALID", "payoff must be finite")

    probability_sum = fsum(outcome.probability for outcome in outcomes)
    if not isclose(probability_sum, 1.0, rel_tol=0.0, abs_tol=1e-9):
        raise DecisionInputError("PROBABILITY_SUM_INVALID", "outcome probabilities must sum to one")

    cost_values = (costs.spread, costs.commission, costs.slippage)
    if any(not isfinite(value) or value < 0.0 for value in cost_values):
        raise DecisionInputError("COST_INVALID", "costs must be finite and non-negative")
    if not isfinite(uncertainty_penalty) or uncertainty_penalty < 0.0:
        raise DecisionInputError(
            "UNCERTAINTY_INVALID",
            "uncertainty penalty must be finite and non-negative",
        )

    gross_ev = fsum(outcome.probability * outcome.payoff for outcome in outcomes)
    expected_value = gross_ev - costs.total
    safe_ev = expected_value - uncertainty_penalty
    return ActionEstimate(action, expected_value, safe_ev, costs.total, uncertainty_penalty)


def choose_action(
    estimates: tuple[ActionEstimate, ...],
    *,
    health_gates_passed: bool,
) -> ActionDecision:
    """Choose a unique positive SafeEV action or return NO_TRADE."""
    if not health_gates_passed:
        return ActionDecision(Action.NO_TRADE, 0.0, "HEALTH_GATE_FAILED")
    if not estimates:
        return ActionDecision(Action.NO_TRADE, 0.0, "NO_CANDIDATES")
    if any(estimate.action is Action.NO_TRADE for estimate in estimates):
        raise DecisionInputError("ACTION_INVALID", "candidate estimates cannot use NO_TRADE")
    if any(not isfinite(estimate.safe_ev) for estimate in estimates):
        raise DecisionInputError("SAFEEV_INVALID", "SafeEV values must be finite")

    best_safe_ev = max(estimate.safe_ev for estimate in estimates)
    if best_safe_ev <= 0.0:
        return ActionDecision(Action.NO_TRADE, best_safe_ev, "NO_POSITIVE_SAFEEV")

    best = tuple(
        estimate
        for estimate in estimates
        if isclose(estimate.safe_ev, best_safe_ev, rel_tol=0.0, abs_tol=1e-12)
    )
    if len(best) != 1:
        return ActionDecision(Action.NO_TRADE, best_safe_ev, "AMBIGUOUS_ACTION")
    return ActionDecision(best[0].action, best[0].safe_ev, "POSITIVE_SAFEEV")

