"""Strict Mtrading identity and allowlist checks for future adapters."""

from dataclasses import dataclass


MTRADING_BROKER_NAME = "Mtrading"


class BrokerPolicyError(ValueError):
    """Raised with a stable reason code when Mtrading policy validation fails."""

    def __init__(self, reason_code: str, detail: str) -> None:
        self.reason_code = reason_code
        super().__init__(f"{reason_code}: {detail}")


@dataclass(frozen=True, slots=True)
class MtradingAccount:
    """Minimal independently-observed account identity for policy checks."""

    broker_name: str
    account_id: int
    is_demo: bool

    def __post_init__(self) -> None:
        if self.account_id <= 0:
            raise BrokerPolicyError("ACCOUNT_INVALID", "account identifier must be positive")


@dataclass(frozen=True, slots=True)
class MtradingPolicy:
    """Mtrading-only account and symbol authorization without embedded secrets."""

    approved_accounts: frozenset[int] = frozenset()
    approved_symbols: frozenset[str] = frozenset()
    broker_name: str = MTRADING_BROKER_NAME

    def __post_init__(self) -> None:
        if self.broker_name != MTRADING_BROKER_NAME:
            raise BrokerPolicyError(
                "BROKER_CONFIGURATION_INVALID",
                "the current system supports Mtrading only",
            )
        if any(
            account_id <= 0 for account_id in self.approved_accounts
        ):
            raise BrokerPolicyError(
                "ACCOUNT_INVALID",
                "approved account identifiers must be positive",
            )
        if any(not symbol.strip() for symbol in self.approved_symbols):
            raise BrokerPolicyError("SYMBOL_INVALID", "approved symbols must be non-empty")

    def require_authorized(self, account: MtradingAccount, symbol: str) -> None:
        """Require exact Mtrading identity plus explicit account/symbol allowlists."""
        if account.broker_name != MTRADING_BROKER_NAME:
            raise BrokerPolicyError(
                "BROKER_IDENTITY_MISMATCH",
                "reported broker is not Mtrading",
            )
        if account.account_id not in self.approved_accounts:
            raise BrokerPolicyError("ACCOUNT_NOT_APPROVED", "account is not allowlisted")
        if not symbol.strip():
            raise BrokerPolicyError("SYMBOL_INVALID", "symbol must be non-empty")
        if symbol not in self.approved_symbols:
            raise BrokerPolicyError("SYMBOL_NOT_APPROVED", "symbol is not allowlisted")
