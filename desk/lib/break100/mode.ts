/** Fail-closed operating-mode contracts without broker dependencies. */

export const OperatingMode = {
  OBSERVE: "OBSERVE",
  SHADOW: "SHADOW",
  DEMO: "DEMO",
  LIVE_CANARY: "LIVE_CANARY",
  LIVE: "LIVE",
} as const;
export type OperatingMode = (typeof OperatingMode)[keyof typeof OperatingMode];

export const SystemState = {
  HEALTHY: "HEALTHY",
  BLOCKED: "BLOCKED",
  FAULT: "FAULT",
} as const;
export type SystemState = (typeof SystemState)[keyof typeof SystemState];

export const AccountEnvironment = {
  UNKNOWN: "UNKNOWN",
  DEMO: "DEMO",
  LIVE: "LIVE",
} as const;
export type AccountEnvironment =
  (typeof AccountEnvironment)[keyof typeof AccountEnvironment];

export type PromotionEvidence = {
  shadow_gate_passed: boolean;
  demo_gate_passed: boolean;
  live_canary_gate_passed: boolean;
  live_gate_passed: boolean;
  account_environment: AccountEnvironment;
  owner_approved: boolean;
  account_approved: boolean;
  symbol_approved: boolean;
  control_lease_expires_at: Date | null;
};

export const emptyEvidence = (): PromotionEvidence => ({
  shadow_gate_passed: false,
  demo_gate_passed: false,
  live_canary_gate_passed: false,
  live_gate_passed: false,
  account_environment: AccountEnvironment.UNKNOWN,
  owner_approved: false,
  account_approved: false,
  symbol_approved: false,
  control_lease_expires_at: null,
});

export class TransitionDenied extends Error {
  reason_code: string;
  constructor(reason_code: string, detail: string) {
    super(`${reason_code}: ${detail}`);
    this.name = "TransitionDenied";
    this.reason_code = reason_code;
  }
}

const SEQUENCE: OperatingMode[] = [
  OperatingMode.OBSERVE,
  OperatingMode.SHADOW,
  OperatingMode.DEMO,
  OperatingMode.LIVE_CANARY,
  OperatingMode.LIVE,
];

function isUtc(value: Date): boolean {
  return !Number.isNaN(value.getTime()) && value.getUTCFullYear() > 0;
}

function requireUtc(value: Date): void {
  // JS Date is always an absolute instant; reject Invalid Date and require
  // callers to pass an explicit UTC ISO source (checked by the desk clock).
  if (Number.isNaN(value.getTime())) {
    throw new TransitionDenied(
      "UTC_CLOCK_REQUIRED",
      "an aware UTC clock is mandatory",
    );
  }
  void isUtc;
}

export class ModeController {
  private _mode: OperatingMode = OperatingMode.OBSERVE;
  private _system_state: SystemState = SystemState.HEALTHY;
  private _block_reason = "";
  private _control_lease_expires_at: Date | null = null;

  get mode(): OperatingMode {
    return this._mode;
  }
  get system_state(): SystemState {
    return this._system_state;
  }
  get block_reason(): string {
    return this._block_reason;
  }
  get control_lease_expires_at(): Date | null {
    return this._control_lease_expires_at;
  }

  /** Time-independent intent — conservative: Live modes are not permitted. */
  get broker_order_intent_permitted(): boolean {
    return (
      this._system_state === SystemState.HEALTHY &&
      this._mode === OperatingMode.DEMO
    );
  }

  broker_order_intent_permitted_at(now: Date, offsetAware = true): boolean {
    if (!offsetAware || Number.isNaN(now.getTime())) return false;
    if (this._system_state !== SystemState.HEALTHY) return false;
    if (this._mode === OperatingMode.DEMO) return true;
    return (
      (this._mode === OperatingMode.LIVE_CANARY ||
        this._mode === OperatingMode.LIVE) &&
      this._control_lease_expires_at !== null &&
      now.getTime() < this._control_lease_expires_at.getTime()
    );
  }

  request_promotion(
    target: OperatingMode,
    evidence: PromotionEvidence,
    now: Date,
    offsetAware = true,
  ): void {
    if (!offsetAware || Number.isNaN(now.getTime())) {
      throw new TransitionDenied(
        "UTC_CLOCK_REQUIRED",
        "an aware UTC clock is mandatory",
      );
    }
    requireUtc(now);
    if (this._system_state !== SystemState.HEALTHY) {
      throw new TransitionDenied(
        "SYSTEM_NOT_HEALTHY",
        "recover in OBSERVE before promotion",
      );
    }

    const currentIndex = SEQUENCE.indexOf(this._mode);
    const targetIsNext =
      currentIndex + 1 < SEQUENCE.length && SEQUENCE[currentIndex + 1] === target;
    if (!targetIsNext) {
      throw new TransitionDenied(
        "MODE_SEQUENCE",
        "promotions must advance exactly one mode",
      );
    }

    if (target === OperatingMode.SHADOW) {
      this.require(
        evidence.shadow_gate_passed,
        "SHADOW_GATE_MISSING",
        "G2/G3 evidence absent",
      );
    } else if (target === OperatingMode.DEMO) {
      this.require(
        evidence.demo_gate_passed,
        "DEMO_GATE_MISSING",
        "Demo gate evidence absent",
      );
      this.require(
        evidence.account_environment === AccountEnvironment.DEMO,
        "DEMO_ACCOUNT_REQUIRED",
        "Demo mode rejects unknown and Live accounts",
      );
    } else if (target === OperatingMode.LIVE_CANARY) {
      this.require(
        evidence.live_canary_gate_passed,
        "LIVE_CANARY_GATE_MISSING",
        "Live Canary gate evidence absent",
      );
      this.requireLiveControls(evidence, now);
    } else if (target === OperatingMode.LIVE) {
      this.require(
        evidence.live_gate_passed,
        "LIVE_GATE_MISSING",
        "Live gate evidence absent",
      );
      this.requireLiveControls(evidence, now);
    }

    this._mode = target;
    this._control_lease_expires_at =
      target === OperatingMode.LIVE_CANARY || target === OperatingMode.LIVE
        ? evidence.control_lease_expires_at
        : null;
    this._block_reason = "";
  }

  fail_closed(reason_code: string): void {
    this._mode = OperatingMode.OBSERVE;
    this._system_state = SystemState.FAULT;
    this._block_reason = reason_code || "UNSPECIFIED_CRITICAL_FAILURE";
    this._control_lease_expires_at = null;
  }

  /** Operator recovery to healthy Observe. Never enables order intent. */
  recover_observe(): void {
    this._mode = OperatingMode.OBSERVE;
    this._system_state = SystemState.HEALTHY;
    this._block_reason = "";
    this._control_lease_expires_at = null;
  }

  snapshot() {
    return {
      mode: this._mode,
      system_state: this._system_state,
      block_reason: this._block_reason,
      broker_order_intent_permitted: this.broker_order_intent_permitted,
      control_lease_expires_at: this._control_lease_expires_at
        ? this._control_lease_expires_at.toISOString()
        : null,
    };
  }

  private require(condition: boolean, reason_code: string, detail: string): void {
    if (!condition) throw new TransitionDenied(reason_code, detail);
  }

  private requireLiveControls(evidence: PromotionEvidence, now: Date): void {
    this.require(
      evidence.account_environment === AccountEnvironment.LIVE,
      "LIVE_ACCOUNT_REQUIRED",
      "Live modes require a verified Live account environment",
    );
    this.require(
      evidence.owner_approved,
      "OWNER_APPROVAL_MISSING",
      "owner approval absent",
    );
    this.require(
      evidence.account_approved,
      "ACCOUNT_NOT_APPROVED",
      "account not allowlisted",
    );
    this.require(
      evidence.symbol_approved,
      "SYMBOL_NOT_APPROVED",
      "symbol not allowlisted",
    );
    const lease = evidence.control_lease_expires_at;
    const leaseValid =
      lease !== null && !Number.isNaN(lease.getTime()) && lease.getTime() > now.getTime();
    this.require(
      leaseValid,
      "CONTROL_LEASE_INVALID",
      "control lease is missing, non-UTC, or expired",
    );
  }
}
