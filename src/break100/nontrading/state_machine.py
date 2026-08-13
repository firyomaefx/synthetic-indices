"""Fail-closed operating-mode contracts without broker dependencies."""

from dataclasses import dataclass
from datetime import datetime, timedelta
from enum import StrEnum


class OperatingMode(StrEnum):
    """Ordered system modes from safest to most privileged."""

    OBSERVE = "OBSERVE"
    SHADOW = "SHADOW"
    DEMO = "DEMO"
    LIVE_CANARY = "LIVE_CANARY"
    LIVE = "LIVE"


class SystemState(StrEnum):
    """Health state controlling whether promotion is possible."""

    HEALTHY = "HEALTHY"
    BLOCKED = "BLOCKED"
    FAULT = "FAULT"


class AccountEnvironment(StrEnum):
    """Verified broker account environment supplied by an outer adapter."""

    UNKNOWN = "UNKNOWN"
    DEMO = "DEMO"
    LIVE = "LIVE"


@dataclass(frozen=True, slots=True)
class PromotionEvidence:
    """Immutable gate facts used to adjudicate one mode promotion."""

    shadow_gate_passed: bool = False
    demo_gate_passed: bool = False
    live_canary_gate_passed: bool = False
    live_gate_passed: bool = False
    account_environment: AccountEnvironment = AccountEnvironment.UNKNOWN
    owner_approved: bool = False
    account_approved: bool = False
    symbol_approved: bool = False
    control_lease_expires_at: datetime | None = None


class TransitionDenied(ValueError):
    """Raised with a stable reason code when a promotion fails closed."""

    def __init__(self, reason_code: str, detail: str) -> None:
        self.reason_code = reason_code
        super().__init__(f"{reason_code}: {detail}")


class ModeController:
    """Authorize mode intent without importing or invoking execution code."""

    _SEQUENCE = (
        OperatingMode.OBSERVE,
        OperatingMode.SHADOW,
        OperatingMode.DEMO,
        OperatingMode.LIVE_CANARY,
        OperatingMode.LIVE,
    )

    def __init__(self) -> None:
        self._mode = OperatingMode.OBSERVE
        self._system_state = SystemState.HEALTHY
        self._block_reason = ""
        self._control_lease_expires_at: datetime | None = None

    @property
    def mode(self) -> OperatingMode:
        """Return the current operating mode."""
        return self._mode

    @property
    def system_state(self) -> SystemState:
        """Return the current health state."""
        return self._system_state

    @property
    def block_reason(self) -> str:
        """Return the stable reason that most recently forced a safe state."""
        return self._block_reason

    @property
    def broker_order_intent_permitted(self) -> bool:
        """Return time-independent intent, which is conservative for Live modes."""
        return self._system_state is SystemState.HEALTHY and self._mode is OperatingMode.DEMO

    def broker_order_intent_permitted_at(self, now: datetime) -> bool:
        """Return intent at a UTC instant, disabling Live modes at lease expiry."""
        if now.tzinfo is None or now.utcoffset() != timedelta(0):
            return False
        if self._system_state is not SystemState.HEALTHY:
            return False
        if self._mode is OperatingMode.DEMO:
            return True
        return (
            self._mode in {OperatingMode.LIVE_CANARY, OperatingMode.LIVE}
            and self._control_lease_expires_at is not None
            and now < self._control_lease_expires_at
        )

    def request_promotion(
        self,
        target: OperatingMode,
        evidence: PromotionEvidence,
        *,
        now: datetime,
    ) -> None:
        """Promote exactly one mode when all target-specific evidence is valid."""
        self._require_utc(now)
        if self._system_state is not SystemState.HEALTHY:
            raise TransitionDenied("SYSTEM_NOT_HEALTHY", "recover in OBSERVE before promotion")

        current_index = self._SEQUENCE.index(self._mode)
        target_is_next = (
            current_index + 1 < len(self._SEQUENCE)
            and self._SEQUENCE[current_index + 1] is target
        )
        if not target_is_next:
            raise TransitionDenied("MODE_SEQUENCE", "promotions must advance exactly one mode")

        if target is OperatingMode.SHADOW:
            self._require(
                evidence.shadow_gate_passed,
                "SHADOW_GATE_MISSING",
                "G2/G3 evidence absent",
            )
        elif target is OperatingMode.DEMO:
            self._require(
                evidence.demo_gate_passed,
                "DEMO_GATE_MISSING",
                "Demo gate evidence absent",
            )
            self._require(
                evidence.account_environment is AccountEnvironment.DEMO,
                "DEMO_ACCOUNT_REQUIRED",
                "Demo mode rejects unknown and Live accounts",
            )
        elif target is OperatingMode.LIVE_CANARY:
            self._require(
                evidence.live_canary_gate_passed,
                "LIVE_CANARY_GATE_MISSING",
                "Live Canary gate evidence absent",
            )
            self._require_live_controls(evidence, now)
        elif target is OperatingMode.LIVE:
            self._require(
                evidence.live_gate_passed,
                "LIVE_GATE_MISSING",
                "Live gate evidence absent",
            )
            self._require_live_controls(evidence, now)

        self._mode = target
        self._control_lease_expires_at = (
            evidence.control_lease_expires_at
            if target in {OperatingMode.LIVE_CANARY, OperatingMode.LIVE}
            else None
        )
        self._block_reason = ""

    def fail_closed(self, reason_code: str) -> None:
        """Return immediately to faulted Observe and block all order intent."""
        self._mode = OperatingMode.OBSERVE
        self._system_state = SystemState.FAULT
        self._block_reason = reason_code or "UNSPECIFIED_CRITICAL_FAILURE"
        self._control_lease_expires_at = None

    @staticmethod
    def _require(condition: bool, reason_code: str, detail: str) -> None:
        if not condition:
            raise TransitionDenied(reason_code, detail)

    @staticmethod
    def _require_utc(value: datetime) -> None:
        if value.tzinfo is None or value.utcoffset() != timedelta(0):
            raise TransitionDenied("UTC_CLOCK_REQUIRED", "an aware UTC clock is mandatory")

    def _require_live_controls(self, evidence: PromotionEvidence, now: datetime) -> None:
        self._require(
            evidence.account_environment is AccountEnvironment.LIVE,
            "LIVE_ACCOUNT_REQUIRED",
            "Live modes require a verified Live account environment",
        )
        self._require(evidence.owner_approved, "OWNER_APPROVAL_MISSING", "owner approval absent")
        self._require(evidence.account_approved, "ACCOUNT_NOT_APPROVED", "account not allowlisted")
        self._require(evidence.symbol_approved, "SYMBOL_NOT_APPROVED", "symbol not allowlisted")

        lease_expiry = evidence.control_lease_expires_at
        lease_valid = (
            lease_expiry is not None
            and lease_expiry.tzinfo is not None
            and lease_expiry.utcoffset() == timedelta(0)
            and lease_expiry > now
        )
        self._require(
            lease_valid,
            "CONTROL_LEASE_INVALID",
            "control lease is missing, non-UTC, or expired",
        )
