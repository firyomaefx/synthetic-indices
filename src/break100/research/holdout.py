"""Chronological splits, a trials ledger, and trial-count-deflated significance.

The purpose of this module is to make it hard to fool ourselves. Searching many
configurations over one dataset guarantees a winner even when every candidate is
worthless, so three rules are enforced mechanically rather than by intention:

1. Splits are **chronological**, never shuffled. Box outcomes overlap in time;
   a random split leaks the future into the training set.
2. The holdout is **sealed**. `Split.holdout` raises unless explicitly unsealed,
   so it cannot be read during a search by accident.
3. Every configuration tried is **counted**, and the bar a result must clear
   rises with that count.

The bar itself is `sqrt(2*ln(n))` — the expected maximum of n standard normals.
With 20 trials that is t = 2.45, so a t of 0.12 is not a small edge, it is
indistinguishable from the luckiest of 20 coin flips.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Generic, TypeVar

T = TypeVar("T")


class HoldoutSealed(Exception):
    """Raised when sealed holdout data is touched during a search."""


@dataclass(slots=True)
class Split(Generic[T]):
    """Chronological train / validation / holdout partition."""

    train: list[T]
    validation: list[T]
    _holdout: list[T]
    _unsealed: bool = False

    @property
    def holdout(self) -> list[T]:
        if not self._unsealed:
            raise HoldoutSealed(
                "The holdout is sealed. Search on train+validation only. "
                "Call unseal(reason=...) once, when the configuration is final — "
                "and treat the result as the answer whatever it says."
            )
        return self._holdout

    @property
    def holdout_size(self) -> int:
        """Size is safe to read; the outcomes are not."""
        return len(self._holdout)

    def unseal(self, reason: str) -> list[T]:
        """Open the holdout, once, deliberately."""
        if not reason.strip():
            raise ValueError("unsealing requires a stated reason")
        self._unsealed = True
        return self._holdout


def chronological_split(
    rows: list[T],
    key: object = None,
    train: float = 0.50,
    validation: float = 0.25,
) -> Split[T]:
    """Split in time order. `key` optionally names a sort attribute."""
    if not 0 < train < 1 or not 0 < validation < 1 or train + validation >= 1:
        raise ValueError("train and validation must be fractions summing below 1")
    ordered = list(rows)
    if isinstance(key, str):
        ordered.sort(key=lambda r: getattr(r, key, 0))
    n = len(ordered)
    a = int(n * train)
    b = a + int(n * validation)
    return Split(train=ordered[:a], validation=ordered[a:b], _holdout=ordered[b:])


# Conventional two-sided significance. The trials bar guards against *selection*;
# this guards against *sampling noise*. They are independent, so the bar a result
# must clear is the larger of the two — with one trial there is nothing to correct
# for, but that is not the same as needing no significance at all.
MIN_SIGNIFICANT_T = 2.0


def noise_threshold(trials: int) -> float:
    """t-stat the luckiest of `trials` zero-edge configurations typically reaches.

    Correctly 0.0 at one trial: no selection has occurred. Callers deciding
    pass/fail must floor this at `MIN_SIGNIFICANT_T` — see `pass_bar`.
    """
    if trials <= 1:
        return 0.0
    return math.sqrt(2.0 * math.log(trials))


def pass_bar(trials: int) -> float:
    """The t a result must actually clear: selection bar or significance, whichever binds."""
    return max(noise_threshold(trials), MIN_SIGNIFICANT_T)


@dataclass(frozen=True, slots=True)
class Verdict:
    """Outcome of the single holdout evaluation."""

    trials: int
    bar: float
    observed_t: float
    expectancy_r: float
    n: int
    passed: bool

    def summary(self) -> str:
        head = "PASS" if self.passed else "FAIL"
        return (
            f"{head}: expectancy {self.expectancy_r:+.3f}R over {self.n} trades, "
            f"t={self.observed_t:+.2f} against a {self.trials}-trial bar of {self.bar:.2f}"
        )


class TrialLedger:
    """Append-only record of every configuration tried."""

    def __init__(self, path: Path) -> None:
        self.path = path

    def count(self) -> int:
        if not self.path.exists():
            return 0
        return sum(1 for line in self.path.read_text(encoding="utf-8").splitlines() if line.strip())

    def record(self, label: str, config: dict[str, object], result: dict[str, object]) -> int:
        """Log one trial and return the running total."""
        self.path.parent.mkdir(parents=True, exist_ok=True)
        entry = {
            "utc": datetime.now(UTC).isoformat(timespec="seconds"),
            "label": label,
            "config": config,
            "result": result,
        }
        with self.path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry, sort_keys=True, default=str) + "\n")
        return self.count()

    def judge(self, expectancy_r: float, sd_r: float, n: int) -> Verdict:
        """Score a holdout result against the bar set by the trials tried so far."""
        trials = max(self.count(), 1)
        bar = pass_bar(trials)
        t = 0.0
        if n > 1 and sd_r > 0:
            t = expectancy_r / (sd_r / math.sqrt(n))
        return Verdict(
            trials=trials,
            bar=bar,
            observed_t=t,
            expectancy_r=expectancy_r,
            n=n,
            passed=bool(t > bar and expectancy_r > 0),
        )
