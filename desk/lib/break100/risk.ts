/** Stop-risk sizing and hard loss/drawdown controls. */

export const HARD_MAX_RISK_FRACTION = 0.0025;
export const HARD_ROLLING_24H_LOSS_STOP = 0.01;
export const HARD_WEEKLY_LOSS_STOP = 0.03;
export const HARD_TOTAL_DRAWDOWN_STOP = 0.05;

export type RiskLimits = {
  max_risk_fraction: number;
  rolling_24h_loss_stop: number;
  weekly_loss_stop: number;
  total_drawdown_stop: number;
  max_positions_per_symbol: number;
};

export const defaultRiskLimits = (): RiskLimits => ({
  max_risk_fraction: HARD_MAX_RISK_FRACTION,
  rolling_24h_loss_stop: HARD_ROLLING_24H_LOSS_STOP,
  weekly_loss_stop: HARD_WEEKLY_LOSS_STOP,
  total_drawdown_stop: HARD_TOTAL_DRAWDOWN_STOP,
  max_positions_per_symbol: 1,
});

export type RiskSnapshot = {
  rolling_24h_loss_fraction: number;
  weekly_loss_fraction: number;
  total_drawdown_fraction: number;
  open_positions_for_symbol: number;
};

export type SymbolRiskSpec = {
  tick_size: number;
  tick_value_per_lot: number;
  contract_size: number;
  volume_min: number;
  volume_max: number;
  volume_step: number;
  minimum_stop_distance: number;
};

export type PositionSizing = {
  risk_money: number;
  stop_ticks: number;
  lots: number;
  expected_loss_at_stop: number;
  reason_code: string;
};

export type RiskGateResult = {
  allowed: boolean;
  reason_code: string;
};

export class RiskInputError extends Error {
  reason_code: string;
  constructor(reason_code: string, detail: string) {
    super(`${reason_code}: ${detail}`);
    this.name = "RiskInputError";
    this.reason_code = reason_code;
  }
}

const SCALE = 1_000_000n;

function toScaled(n: number): bigint {
  if (!Number.isFinite(n)) {
    throw new RiskInputError("PRICE_INVALID", "value must be finite");
  }
  return BigInt(Math.round(n * 1_000_000));
}

function fromScaled(n: bigint): number {
  return Number(n) / 1_000_000;
}

function floorDiv(a: bigint, b: bigint): bigint {
  if (b === 0n) throw new RiskInputError("PRICE_INVALID", "division by zero");
  return a / b;
}

export function calculatePositionSize(
  equity: number,
  risk_fraction: number,
  entry_price: number,
  stop_loss: number,
  symbol: SymbolRiskSpec,
  limits: RiskLimits = defaultRiskLimits(),
): PositionSizing {
  validateLimits(limits);
  validateSymbol(symbol);
  if (!Number.isFinite(equity) || equity <= 0) {
    throw new RiskInputError("EQUITY_INVALID", "equity must be finite and positive");
  }
  if (!Number.isFinite(risk_fraction) || risk_fraction <= 0) {
    throw new RiskInputError("RISK_FRACTION_INVALID", "risk fraction must be positive");
  }
  if (risk_fraction > limits.max_risk_fraction + 1e-18) {
    throw new RiskInputError("RISK_CEILING_EXCEEDED", "risk exceeds the configured safe ceiling");
  }
  if (!Number.isFinite(entry_price) || !Number.isFinite(stop_loss)) {
    throw new RiskInputError("PRICE_INVALID", "entry and stop prices must be finite");
  }

  const stopDistance = Math.abs(entry_price - stop_loss);
  if (stopDistance < symbol.minimum_stop_distance || stopDistance === 0) {
    throw new RiskInputError("STOP_DISTANCE_INVALID", "stop is inside the approved minimum");
  }

  const riskMoney = equity * risk_fraction;
  const stopTicks = stopDistance / symbol.tick_size;
  const lossPerLot = stopTicks * symbol.tick_value_per_lot;
  const rawLots = riskMoney / lossPerLot;

  if (rawLots < symbol.volume_min) {
    return {
      risk_money: riskMoney,
      stop_ticks: stopTicks,
      lots: 0,
      expected_loss_at_stop: 0,
      reason_code: "BELOW_MINIMUM_VOLUME",
    };
  }

  const cappedLots = Math.min(rawLots, symbol.volume_max);
  const stepsAboveMin = floorDiv(
    toScaled(cappedLots) - toScaled(symbol.volume_min),
    toScaled(symbol.volume_step),
  );
  const lots = fromScaled(
    toScaled(symbol.volume_min) + stepsAboveMin * toScaled(symbol.volume_step),
  );
  const expectedLoss = lots * lossPerLot;

  return {
    risk_money: riskMoney,
    stop_ticks: stopTicks,
    lots,
    expected_loss_at_stop: expectedLoss,
    reason_code: "SIZE_APPROVED",
  };
}

export function evaluateRiskGate(
  snapshot: RiskSnapshot,
  limits: RiskLimits,
): RiskGateResult {
  validateLimits(limits);
  validateSnapshot(snapshot);
  if (snapshot.rolling_24h_loss_fraction >= limits.rolling_24h_loss_stop) {
    return { allowed: false, reason_code: "ROLLING_24H_LOSS_STOP" };
  }
  if (snapshot.weekly_loss_fraction >= limits.weekly_loss_stop) {
    return { allowed: false, reason_code: "WEEKLY_LOSS_STOP" };
  }
  if (snapshot.total_drawdown_fraction >= limits.total_drawdown_stop) {
    return { allowed: false, reason_code: "TOTAL_DRAWDOWN_STOP" };
  }
  if (snapshot.open_positions_for_symbol >= limits.max_positions_per_symbol) {
    return { allowed: false, reason_code: "MAX_POSITION_REACHED" };
  }
  return { allowed: true, reason_code: "RISK_GATE_PASSED" };
}

function validateSymbol(symbol: SymbolRiskSpec): void {
  const numeric = [
    symbol.tick_size,
    symbol.tick_value_per_lot,
    symbol.contract_size,
    symbol.volume_min,
    symbol.volume_max,
    symbol.volume_step,
    symbol.minimum_stop_distance,
  ];
  const valid =
    numeric.every((v) => Number.isFinite(v) && v > 0) &&
    symbol.volume_min <= symbol.volume_max &&
    symbol.volume_step <= symbol.volume_max;
  if (!valid) {
    throw new RiskInputError("SYMBOL_METADATA_INVALID", "symbol risk metadata is inconsistent");
  }
}

export function validateLimits(limits: RiskLimits): void {
  const fractions = [
    limits.max_risk_fraction,
    limits.rolling_24h_loss_stop,
    limits.weekly_loss_stop,
    limits.total_drawdown_stop,
  ];
  const valid = fractions.every((v) => Number.isFinite(v) && v > 0);
  const within =
    limits.max_risk_fraction <= HARD_MAX_RISK_FRACTION + 1e-18 &&
    limits.rolling_24h_loss_stop <= HARD_ROLLING_24H_LOSS_STOP + 1e-18 &&
    limits.weekly_loss_stop <= HARD_WEEKLY_LOSS_STOP + 1e-18 &&
    limits.total_drawdown_stop <= HARD_TOTAL_DRAWDOWN_STOP + 1e-18;
  if (!valid || !within) {
    throw new RiskInputError("RISK_LIMITS_INVALID", "limits exceed hard safety bounds");
  }
  if (limits.max_positions_per_symbol !== 1) {
    throw new RiskInputError("RISK_LIMITS_INVALID", "only one position per symbol is allowed");
  }
}

function validateSnapshot(snapshot: RiskSnapshot): void {
  const fractions = [
    snapshot.rolling_24h_loss_fraction,
    snapshot.weekly_loss_fraction,
    snapshot.total_drawdown_fraction,
  ];
  if (fractions.some((v) => !Number.isFinite(v) || v < 0)) {
    throw new RiskInputError(
      "RISK_SNAPSHOT_INVALID",
      "loss and drawdown values must be non-negative",
    );
  }
  if (snapshot.open_positions_for_symbol < 0) {
    throw new RiskInputError("RISK_SNAPSHOT_INVALID", "open position count cannot be negative");
  }
}

export const DEFAULT_SYMBOL_SPEC: SymbolRiskSpec = {
  tick_size: 0.1,
  tick_value_per_lot: 1,
  contract_size: 1,
  volume_min: 0.01,
  volume_max: 10,
  volume_step: 0.01,
  minimum_stop_distance: 0.2,
};
