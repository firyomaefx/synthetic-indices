from datetime import UTC, datetime, timedelta

import pytest

from break100.nontrading.state_machine import (
    AccountEnvironment,
    ModeController,
    OperatingMode,
    PromotionEvidence,
    SystemState,
    TransitionDenied,
)


NOW = datetime(2026, 8, 13, 12, 0, tzinfo=UTC)


def evidence(**overrides: object) -> PromotionEvidence:
    """Build complete positive evidence with selected fields overridden."""
    values: dict[str, object] = {
        "shadow_gate_passed": True,
        "demo_gate_passed": True,
        "live_canary_gate_passed": True,
        "live_gate_passed": True,
        "account_environment": AccountEnvironment.DEMO,
        "owner_approved": True,
        "account_approved": True,
        "symbol_approved": True,
        "control_lease_expires_at": NOW + timedelta(minutes=15),
    }
    values.update(overrides)
    return PromotionEvidence(**values)


def promote_to_demo(controller: ModeController) -> None:
    """Promote a controller through the two non-live stages."""
    controller.request_promotion(OperatingMode.SHADOW, evidence(), now=NOW)
    controller.request_promotion(OperatingMode.DEMO, evidence(), now=NOW)


def test_controller_defaults_to_non_trading_observe() -> None:
    controller = ModeController()

    assert controller.mode is OperatingMode.OBSERVE
    assert controller.system_state is SystemState.HEALTHY
    assert controller.broker_order_intent_permitted is False
    assert controller.block_reason == ""


def test_promotions_must_be_sequential_and_evidence_gated() -> None:
    controller = ModeController()

    with pytest.raises(TransitionDenied, match="MODE_SEQUENCE") as skipped:
        controller.request_promotion(OperatingMode.DEMO, evidence(), now=NOW)
    assert skipped.value.reason_code == "MODE_SEQUENCE"

    with pytest.raises(TransitionDenied, match="SHADOW_GATE_MISSING") as missing:
        controller.request_promotion(
            OperatingMode.SHADOW,
            evidence(shadow_gate_passed=False),
            now=NOW,
        )
    assert missing.value.reason_code == "SHADOW_GATE_MISSING"

    controller.request_promotion(OperatingMode.SHADOW, evidence(), now=NOW)

    assert controller.mode is OperatingMode.SHADOW
    assert controller.broker_order_intent_permitted is False


def test_demo_requires_verified_demo_environment() -> None:
    controller = ModeController()
    controller.request_promotion(OperatingMode.SHADOW, evidence(), now=NOW)

    with pytest.raises(TransitionDenied, match="DEMO_ACCOUNT_REQUIRED") as live_account:
        controller.request_promotion(
            OperatingMode.DEMO,
            evidence(account_environment=AccountEnvironment.LIVE),
            now=NOW,
        )
    assert live_account.value.reason_code == "DEMO_ACCOUNT_REQUIRED"

    controller.request_promotion(OperatingMode.DEMO, evidence(), now=NOW)

    assert controller.mode is OperatingMode.DEMO
    assert controller.broker_order_intent_permitted is True


@pytest.mark.parametrize(
    ("overrides", "reason_code"),
    [
        ({"owner_approved": False}, "OWNER_APPROVAL_MISSING"),
        ({"account_approved": False}, "ACCOUNT_NOT_APPROVED"),
        ({"symbol_approved": False}, "SYMBOL_NOT_APPROVED"),
        ({"control_lease_expires_at": None}, "CONTROL_LEASE_INVALID"),
        (
            {"control_lease_expires_at": NOW - timedelta(seconds=1)},
            "CONTROL_LEASE_INVALID",
        ),
    ],
)
def test_live_canary_requires_all_owner_controls(
    overrides: dict[str, object], reason_code: str
) -> None:
    controller = ModeController()
    promote_to_demo(controller)

    with pytest.raises(TransitionDenied, match=reason_code) as denied:
        controller.request_promotion(
            OperatingMode.LIVE_CANARY,
            evidence(account_environment=AccountEnvironment.LIVE, **overrides),
            now=NOW,
        )
    assert denied.value.reason_code == reason_code
    assert controller.mode is OperatingMode.DEMO


def test_live_canary_accepts_complete_unexpired_evidence() -> None:
    controller = ModeController()
    promote_to_demo(controller)

    controller.request_promotion(
        OperatingMode.LIVE_CANARY,
        evidence(account_environment=AccountEnvironment.LIVE),
        now=NOW,
    )

    assert controller.mode is OperatingMode.LIVE_CANARY
    assert controller.broker_order_intent_permitted is False
    assert controller.broker_order_intent_permitted_at(NOW) is True
    assert controller.broker_order_intent_permitted_at(NOW + timedelta(minutes=15)) is False


def test_critical_failure_fails_closed_to_observe() -> None:
    controller = ModeController()
    promote_to_demo(controller)

    controller.fail_closed("RECONCILIATION_FAILED")

    assert controller.mode is OperatingMode.OBSERVE
    assert controller.system_state is SystemState.FAULT
    assert controller.broker_order_intent_permitted is False
    assert controller.block_reason == "RECONCILIATION_FAILED"

    with pytest.raises(TransitionDenied, match="SYSTEM_NOT_HEALTHY") as denied:
        controller.request_promotion(OperatingMode.SHADOW, evidence(), now=NOW)
    assert denied.value.reason_code == "SYSTEM_NOT_HEALTHY"


def test_naive_clock_is_rejected_fail_closed() -> None:
    controller = ModeController()

    with pytest.raises(TransitionDenied, match="UTC_CLOCK_REQUIRED") as denied:
        controller.request_promotion(
            OperatingMode.SHADOW,
            evidence(),
            now=datetime(2026, 8, 13, 12, 0),
        )
    assert denied.value.reason_code == "UTC_CLOCK_REQUIRED"
    assert controller.mode is OperatingMode.OBSERVE
