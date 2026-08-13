import pytest

from break100.broker.mtrading import (
    BrokerPolicyError,
    MTRADING_BROKER_NAME,
    MtradingAccount,
    MtradingPolicy,
)


def test_policy_is_explicitly_mtrading_only() -> None:
    policy = MtradingPolicy(
        approved_accounts=frozenset({1001}),
        approved_symbols=frozenset({"BREAK100"}),
    )

    assert policy.broker_name == MTRADING_BROKER_NAME
    assert policy.broker_name == "Mtrading"


def test_policy_accepts_only_allowlisted_mtrading_account_and_symbol() -> None:
    policy = MtradingPolicy(
        approved_accounts=frozenset({1001}),
        approved_symbols=frozenset({"BREAK100"}),
    )
    account = MtradingAccount(broker_name="Mtrading", account_id=1001, is_demo=True)

    policy.require_authorized(account, "BREAK100")


@pytest.mark.parametrize(
    ("account", "symbol", "reason_code"),
    [
        (MtradingAccount("Monaxa", 1001, True), "BREAK100", "BROKER_IDENTITY_MISMATCH"),
        (MtradingAccount("Mtrading", 2002, True), "BREAK100", "ACCOUNT_NOT_APPROVED"),
        (MtradingAccount("Mtrading", 1001, True), "OTHER100", "SYMBOL_NOT_APPROVED"),
    ],
)
def test_policy_rejects_non_mtrading_or_non_allowlisted_targets(
    account: MtradingAccount, symbol: str, reason_code: str
) -> None:
    policy = MtradingPolicy(
        approved_accounts=frozenset({1001}),
        approved_symbols=frozenset({"BREAK100"}),
    )

    with pytest.raises(BrokerPolicyError, match=reason_code) as denied:
        policy.require_authorized(account, symbol)
    assert denied.value.reason_code == reason_code


def test_empty_allowlists_fail_closed() -> None:
    policy = MtradingPolicy()

    with pytest.raises(BrokerPolicyError, match="ACCOUNT_NOT_APPROVED"):
        policy.require_authorized(MtradingAccount("Mtrading", 1001, True), "BREAK100")


def test_account_identifier_and_symbol_must_be_valid() -> None:
    with pytest.raises(BrokerPolicyError, match="ACCOUNT_INVALID"):
        MtradingAccount("Mtrading", 0, True)
    with pytest.raises(BrokerPolicyError, match="SYMBOL_INVALID"):
        MtradingPolicy(approved_accounts=frozenset({1001}), approved_symbols=frozenset({""}))
