from decimal import Decimal

import pytest

from break100.risk.engine import (
    RiskInputError,
    RiskLimits,
    RiskSnapshot,
    SymbolRiskSpec,
    calculate_position_size,
    evaluate_risk_gate,
)


D = Decimal
SPEC = SymbolRiskSpec(
    tick_size=D("0.1"),
    tick_value_per_lot=D("1.0"),
    contract_size=D("1"),
    volume_min=D("0.01"),
    volume_max=D("10.0"),
    volume_step=D("0.01"),
    minimum_stop_distance=D("0.2"),
)


def test_position_size_uses_stop_risk_and_rounds_down() -> None:
    sizing = calculate_position_size(
        equity=D("10000"),
        risk_fraction=D("0.001"),
        entry_price=D("100.0"),
        stop_loss=D("98.3"),
        symbol=SPEC,
    )

    assert sizing.risk_money == D("10.000")
    assert sizing.stop_ticks == D("17")
    assert sizing.lots == D("0.58")
    assert sizing.expected_loss_at_stop == D("9.860")
    assert sizing.expected_loss_at_stop <= sizing.risk_money
    assert sizing.reason_code == "SIZE_APPROVED"


def test_position_size_is_symmetric_for_long_and_short_stops() -> None:
    long = calculate_position_size(D("10000"), D("0.001"), D("100"), D("98.3"), SPEC)
    short = calculate_position_size(D("10000"), D("0.001"), D("100"), D("101.7"), SPEC)

    assert long.lots == D("0.58")
    assert short.lots == D("0.58")


def test_risk_fraction_above_hard_ceiling_is_rejected() -> None:
    with pytest.raises(RiskInputError, match="RISK_CEILING_EXCEEDED") as denied:
        calculate_position_size(D("10000"), D("0.0026"), D("100"), D("99"), SPEC)
    assert denied.value.reason_code == "RISK_CEILING_EXCEEDED"


def test_configured_risk_ceiling_can_be_lower_than_hard_ceiling() -> None:
    limits = RiskLimits(max_risk_fraction=D("0.001"))

    with pytest.raises(RiskInputError, match="RISK_CEILING_EXCEEDED"):
        calculate_position_size(
            D("10000"),
            D("0.0011"),
            D("100"),
            D("99"),
            SPEC,
            limits=limits,
        )


def test_volume_steps_are_anchored_at_broker_minimum() -> None:
    offset_spec = SymbolRiskSpec(
        tick_size=D("1"),
        tick_value_per_lot=D("10"),
        contract_size=D("1"),
        volume_min=D("0.10"),
        volume_max=D("1.00"),
        volume_step=D("0.03"),
        minimum_stop_distance=D("1"),
    )

    sizing = calculate_position_size(
        D("1600"), D("0.001"), D("100"), D("99"), offset_spec
    )

    assert sizing.lots == D("0.16")
    assert (sizing.lots - offset_spec.volume_min) % offset_spec.volume_step == D("0")


def test_too_close_stop_and_below_minimum_volume_fail_closed() -> None:
    with pytest.raises(RiskInputError, match="STOP_DISTANCE_INVALID"):
        calculate_position_size(D("10000"), D("0.001"), D("100"), D("99.9"), SPEC)

    sizing = calculate_position_size(D("100"), D("0.0005"), D("100"), D("90"), SPEC)
    assert sizing.lots == D("0")
    assert sizing.expected_loss_at_stop == D("0")
    assert sizing.reason_code == "BELOW_MINIMUM_VOLUME"


@pytest.mark.parametrize(
    ("snapshot", "reason_code"),
    [
        (RiskSnapshot(D("0.01"), D("0"), D("0"), 0), "ROLLING_24H_LOSS_STOP"),
        (RiskSnapshot(D("0"), D("0.03"), D("0"), 0), "WEEKLY_LOSS_STOP"),
        (RiskSnapshot(D("0"), D("0"), D("0.05"), 0), "TOTAL_DRAWDOWN_STOP"),
        (RiskSnapshot(D("0"), D("0"), D("0"), 1), "MAX_POSITION_REACHED"),
    ],
)
def test_risk_gate_blocks_at_each_hard_limit(
    snapshot: RiskSnapshot, reason_code: str
) -> None:
    result = evaluate_risk_gate(snapshot, RiskLimits())

    assert result.allowed is False
    assert result.reason_code == reason_code


def test_risk_gate_allows_healthy_snapshot_below_limits() -> None:
    result = evaluate_risk_gate(
        RiskSnapshot(D("0.009"), D("0.029"), D("0.049"), 0),
        RiskLimits(),
    )

    assert result.allowed is True
    assert result.reason_code == "RISK_GATE_PASSED"


@pytest.mark.parametrize(
    "limits",
    [
        RiskLimits(rolling_24h_loss_stop=D("0.011")),
        RiskLimits(weekly_loss_stop=D("0.031")),
        RiskLimits(total_drawdown_stop=D("0.051")),
        RiskLimits(max_positions_per_symbol=2),
    ],
)
def test_risk_limits_cannot_weaken_hard_stops(limits: RiskLimits) -> None:
    with pytest.raises(RiskInputError, match="RISK_LIMITS_INVALID"):
        evaluate_risk_gate(RiskSnapshot(D("0"), D("0"), D("0"), 0), limits)


def test_invalid_symbol_metadata_is_rejected() -> None:
    invalid = SymbolRiskSpec(
        tick_size=D("0"),
        tick_value_per_lot=D("1"),
        contract_size=D("1"),
        volume_min=D("0.01"),
        volume_max=D("1"),
        volume_step=D("0.01"),
        minimum_stop_distance=D("0.1"),
    )

    with pytest.raises(RiskInputError, match="SYMBOL_METADATA_INVALID"):
        calculate_position_size(D("10000"), D("0.001"), D("100"), D("99"), invalid)
