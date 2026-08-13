"""Stop-risk sizing and hard loss/drawdown controls."""

from dataclasses import dataclass
from decimal import ROUND_FLOOR, Decimal


HARD_MAX_RISK_FRACTION = Decimal("0.0025")
HARD_ROLLING_24H_LOSS_STOP = Decimal("0.01")
HARD_WEEKLY_LOSS_STOP = Decimal("0.03")
HARD_TOTAL_DRAWDOWN_STOP = Decimal("0.05")


@dataclass(frozen=True, slots=True)
class RiskLimits:
    """Hard-coded safety ceilings expressed as equity fractions."""

    max_risk_fraction: Decimal = HARD_MAX_RISK_FRACTION
    rolling_24h_loss_stop: Decimal = HARD_ROLLING_24H_LOSS_STOP
    weekly_loss_stop: Decimal = HARD_WEEKLY_LOSS_STOP
    total_drawdown_stop: Decimal = HARD_TOTAL_DRAWDOWN_STOP
    max_positions_per_symbol: int = 1


@dataclass(frozen=True, slots=True)
class RiskSnapshot:
    """Current loss, drawdown, and symbol-exposure state."""

    rolling_24h_loss_fraction: Decimal
    weekly_loss_fraction: Decimal
    total_drawdown_fraction: Decimal
    open_positions_for_symbol: int


@dataclass(frozen=True, slots=True)
class SymbolRiskSpec:
    """Verified symbol metadata required for stop-risk sizing."""

    tick_size: Decimal
    tick_value_per_lot: Decimal
    contract_size: Decimal
    volume_min: Decimal
    volume_max: Decimal
    volume_step: Decimal
    minimum_stop_distance: Decimal


@dataclass(frozen=True, slots=True)
class PositionSizing:
    """Normalised position size and bounded loss at the selected stop."""

    risk_money: Decimal
    stop_ticks: Decimal
    lots: Decimal
    expected_loss_at_stop: Decimal
    reason_code: str


@dataclass(frozen=True, slots=True)
class RiskGateResult:
    """Reason-coded result from the hard risk gate."""

    allowed: bool
    reason_code: str


class RiskInputError(ValueError):
    """Raised with a stable reason code for invalid risk inputs."""

    def __init__(self, reason_code: str, detail: str) -> None:
        self.reason_code = reason_code
        super().__init__(f"{reason_code}: {detail}")


def calculate_position_size(
    equity: Decimal,
    risk_fraction: Decimal,
    entry_price: Decimal,
    stop_loss: Decimal,
    symbol: SymbolRiskSpec,
    *,
    limits: RiskLimits | None = None,
) -> PositionSizing:
    """Size by stop-loss risk, always rounding volume down."""
    active_limits = limits or RiskLimits()
    _validate_limits(active_limits)
    _validate_symbol(symbol)
    if not equity.is_finite() or equity <= 0:
        raise RiskInputError("EQUITY_INVALID", "equity must be finite and positive")
    if not risk_fraction.is_finite() or risk_fraction <= 0:
        raise RiskInputError("RISK_FRACTION_INVALID", "risk fraction must be positive")
    if risk_fraction > active_limits.max_risk_fraction:
        raise RiskInputError("RISK_CEILING_EXCEEDED", "risk exceeds the configured safe ceiling")
    if not entry_price.is_finite() or not stop_loss.is_finite():
        raise RiskInputError("PRICE_INVALID", "entry and stop prices must be finite")

    stop_distance = abs(entry_price - stop_loss)
    if stop_distance < symbol.minimum_stop_distance or stop_distance == 0:
        raise RiskInputError("STOP_DISTANCE_INVALID", "stop is inside the approved minimum")

    risk_money = equity * risk_fraction
    stop_ticks = stop_distance / symbol.tick_size
    loss_per_lot = stop_ticks * symbol.tick_value_per_lot
    raw_lots = risk_money / loss_per_lot
    if raw_lots < symbol.volume_min:
        return PositionSizing(
            risk_money,
            stop_ticks,
            Decimal("0"),
            Decimal("0"),
            "BELOW_MINIMUM_VOLUME",
        )

    capped_lots = min(raw_lots, symbol.volume_max)
    steps_above_minimum = (
        (capped_lots - symbol.volume_min) / symbol.volume_step
    ).to_integral_value(rounding=ROUND_FLOOR)
    lots = symbol.volume_min + steps_above_minimum * symbol.volume_step

    expected_loss = lots * loss_per_lot
    return PositionSizing(risk_money, stop_ticks, lots, expected_loss, "SIZE_APPROVED")


def evaluate_risk_gate(snapshot: RiskSnapshot, limits: RiskLimits) -> RiskGateResult:
    """Block new entries at or beyond any configured hard stop."""
    _validate_limits(limits)
    _validate_snapshot(snapshot)
    if snapshot.rolling_24h_loss_fraction >= limits.rolling_24h_loss_stop:
        return RiskGateResult(False, "ROLLING_24H_LOSS_STOP")
    if snapshot.weekly_loss_fraction >= limits.weekly_loss_stop:
        return RiskGateResult(False, "WEEKLY_LOSS_STOP")
    if snapshot.total_drawdown_fraction >= limits.total_drawdown_stop:
        return RiskGateResult(False, "TOTAL_DRAWDOWN_STOP")
    if snapshot.open_positions_for_symbol >= limits.max_positions_per_symbol:
        return RiskGateResult(False, "MAX_POSITION_REACHED")
    return RiskGateResult(True, "RISK_GATE_PASSED")


def _validate_symbol(symbol: SymbolRiskSpec) -> None:
    numeric_values = (
        symbol.tick_size,
        symbol.tick_value_per_lot,
        symbol.contract_size,
        symbol.volume_min,
        symbol.volume_max,
        symbol.volume_step,
        symbol.minimum_stop_distance,
    )
    valid = (
        all(value.is_finite() and value > 0 for value in numeric_values)
        and symbol.volume_min <= symbol.volume_max
        and symbol.volume_step <= symbol.volume_max
    )
    if not valid:
        raise RiskInputError("SYMBOL_METADATA_INVALID", "symbol risk metadata is inconsistent")


def _validate_limits(limits: RiskLimits) -> None:
    fractions = (
        limits.max_risk_fraction,
        limits.rolling_24h_loss_stop,
        limits.weekly_loss_stop,
        limits.total_drawdown_stop,
    )
    valid = all(value.is_finite() and value > 0 for value in fractions)
    within_hard_ceilings = (
        limits.max_risk_fraction <= HARD_MAX_RISK_FRACTION
        and limits.rolling_24h_loss_stop <= HARD_ROLLING_24H_LOSS_STOP
        and limits.weekly_loss_stop <= HARD_WEEKLY_LOSS_STOP
        and limits.total_drawdown_stop <= HARD_TOTAL_DRAWDOWN_STOP
    )
    if not valid or not within_hard_ceilings:
        raise RiskInputError("RISK_LIMITS_INVALID", "limits exceed hard safety bounds")
    if limits.max_positions_per_symbol != 1:
        raise RiskInputError("RISK_LIMITS_INVALID", "only one position per symbol is allowed")


def _validate_snapshot(snapshot: RiskSnapshot) -> None:
    fractions = (
        snapshot.rolling_24h_loss_fraction,
        snapshot.weekly_loss_fraction,
        snapshot.total_drawdown_fraction,
    )
    if any(not value.is_finite() or value < 0 for value in fractions):
        raise RiskInputError(
            "RISK_SNAPSHOT_INVALID",
            "loss and drawdown values must be non-negative",
        )
    if snapshot.open_positions_for_symbol < 0:
        raise RiskInputError("RISK_SNAPSHOT_INVALID", "open position count cannot be negative")
