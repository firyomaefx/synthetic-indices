import pytest

from break100.decision.safe_ev import (
    Action,
    ActionEstimate,
    DecisionInputError,
    OutcomeEstimate,
    TradingCosts,
    choose_action,
    evaluate_action,
)


def test_safe_ev_includes_all_costs_and_uncertainty() -> None:
    estimate = evaluate_action(
        Action.ENTER_LONG,
        outcomes=(
            OutcomeEstimate(probability=0.6, payoff=12.0),
            OutcomeEstimate(probability=0.4, payoff=-8.0),
        ),
        costs=TradingCosts(spread=0.5, commission=0.2, slippage=0.3),
        uncertainty_penalty=0.75,
    )

    assert estimate.expected_value == pytest.approx(3.0)
    assert estimate.safe_ev == pytest.approx(2.25)
    assert estimate.total_cost == pytest.approx(1.0)


@pytest.mark.parametrize(
    ("outcomes", "reason_code"),
    [
        (
            (OutcomeEstimate(0.8, 1.0), OutcomeEstimate(0.3, -1.0)),
            "PROBABILITY_SUM_INVALID",
        ),
        ((OutcomeEstimate(-0.1, 1.0), OutcomeEstimate(1.1, -1.0)), "PROBABILITY_INVALID"),
    ],
)
def test_invalid_probability_models_fail_closed(
    outcomes: tuple[OutcomeEstimate, ...], reason_code: str
) -> None:
    with pytest.raises(DecisionInputError, match=reason_code) as denied:
        evaluate_action(
            Action.ENTER_LONG,
            outcomes=outcomes,
            costs=TradingCosts(0.0, 0.0, 0.0),
            uncertainty_penalty=0.0,
        )
    assert denied.value.reason_code == reason_code


def test_negative_cost_or_uncertainty_is_rejected() -> None:
    with pytest.raises(DecisionInputError, match="COST_INVALID"):
        evaluate_action(
            Action.ENTER_SHORT,
            outcomes=(OutcomeEstimate(1.0, 1.0),),
            costs=TradingCosts(spread=-0.1, commission=0.0, slippage=0.0),
            uncertainty_penalty=0.0,
        )

    with pytest.raises(DecisionInputError, match="UNCERTAINTY_INVALID"):
        evaluate_action(
            Action.ENTER_SHORT,
            outcomes=(OutcomeEstimate(1.0, 1.0),),
            costs=TradingCosts(0.0, 0.0, 0.0),
            uncertainty_penalty=-0.1,
        )


def test_choose_action_requires_health_and_positive_unique_safe_ev() -> None:
    positive = ActionEstimate(Action.ENTER_LONG, 2.0, 1.0, 0.5, 0.5)
    negative = ActionEstimate(Action.ENTER_SHORT, -1.0, -2.0, 0.5, 0.5)

    unhealthy = choose_action((positive, negative), health_gates_passed=False)
    assert unhealthy.action is Action.NO_TRADE
    assert unhealthy.reason_code == "HEALTH_GATE_FAILED"

    no_edge = choose_action((negative,), health_gates_passed=True)
    assert no_edge.action is Action.NO_TRADE
    assert no_edge.reason_code == "NO_POSITIVE_SAFEEV"

    selected = choose_action((positive, negative), health_gates_passed=True)
    assert selected.action is Action.ENTER_LONG
    assert selected.safe_ev == pytest.approx(1.0)
    assert selected.reason_code == "POSITIVE_SAFEEV"


def test_equal_best_safe_ev_abstains_as_ambiguous() -> None:
    long = ActionEstimate(Action.ENTER_LONG, 2.0, 1.0, 0.5, 0.5)
    short = ActionEstimate(Action.ENTER_SHORT, 2.0, 1.0, 0.5, 0.5)

    decision = choose_action((long, short), health_gates_passed=True)

    assert decision.action is Action.NO_TRADE
    assert decision.reason_code == "AMBIGUOUS_ACTION"


def test_no_trade_cannot_be_evaluated_as_a_trade_candidate() -> None:
    with pytest.raises(DecisionInputError, match="ACTION_INVALID"):
        evaluate_action(
            Action.NO_TRADE,
            outcomes=(OutcomeEstimate(1.0, 0.0),),
            costs=TradingCosts(0.0, 0.0, 0.0),
            uncertainty_penalty=0.0,
        )

