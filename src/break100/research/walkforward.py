"""Walk-forward metrics from BREAK100_outcome CSV. No fake fills."""

from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class WalkForwardReport:
    n: int
    n_up: int
    n_dn: int
    n_fail: int
    unique_armed: int
    up_rate: float
    baseline: str
    decision: str
    notes: str


def load_outcomes(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def evaluate_outcomes(rows: list[dict[str, str]]) -> WalkForwardReport:
    if not rows:
        return WalkForwardReport(0, 0, 0, 0, 0, 0.0, "none", "NO-GO", "no outcome rows")
    seen: set[str] = set()
    unique: list[dict[str, str]] = []
    for row in rows:
        key = row.get("armed_bar", "")
        if key in seen:
            continue
        seen.add(key)
        unique.append(row)
    n_up = sum(1 for r in unique if r.get("label") == "BREAKOUT_UP")
    n_dn = sum(1 for r in unique if r.get("label") == "BREAKOUT_DOWN")
    n_fail = sum(1 for r in unique if "CENSORED" in (r.get("label") or ""))
    n = len(unique)
    up_rate = n_up / n if n else 0.0
    # Not a profitability claim: direction mix only. Costs not in this file.
    decision = "NO-GO"
    notes = "unique events only; no net-PnL column — cannot certify edge"
    if n >= 16:
        decision = "LIMITED GO"
        notes = "enough unique pauses for baseline rates; still no after-cost walk-forward PnL"
    return WalkForwardReport(
        n=n,
        n_up=n_up,
        n_dn=n_dn,
        n_fail=n_fail,
        unique_armed=n,
        up_rate=up_rate,
        baseline="BOX_OCO_UCB_v1",
        decision=decision,
        notes=notes,
    )
