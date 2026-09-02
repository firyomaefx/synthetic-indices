"""Pins for the anti-self-deception machinery.

These tests exist because the failure mode here is silent: a search that peeks at
the holdout, or a winner picked from twenty tries and reported as if it were the
only one, produces a number that looks fine and means nothing.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import pytest

from break100.research.holdout import (
    HoldoutSealed,
    TrialLedger,
    chronological_split,
    noise_threshold,
    pass_bar,
)


@dataclass(frozen=True)
class Row:
    t: int
    r: float


def rows(n: int = 100) -> list[Row]:
    return [Row(t=i, r=float(i)) for i in range(n)]


# --- the seal ---------------------------------------------------------------


def test_holdout_raises_rather_than_leaking() -> None:
    split = chronological_split(rows())
    with pytest.raises(HoldoutSealed):
        _ = split.holdout


def test_holdout_size_is_readable_while_outcomes_are_not() -> None:
    # Knowing how much data is held back is not peeking; the outcomes are.
    split = chronological_split(rows())
    assert split.holdout_size == 25
    with pytest.raises(HoldoutSealed):
        _ = split.holdout


def test_unsealing_requires_a_stated_reason() -> None:
    split = chronological_split(rows())
    with pytest.raises(ValueError):
        split.unseal("   ")
    assert len(split.unseal("final evaluation, configuration frozen")) == 25


# --- chronology -------------------------------------------------------------


def test_split_is_chronological_not_shuffled() -> None:
    split = chronological_split(rows())
    assert [r.t for r in split.train] == list(range(50))
    assert [r.t for r in split.validation] == list(range(50, 75))
    assert [r.t for r in split.unseal("test")] == list(range(75, 100))


def test_out_of_order_input_is_sorted_by_key_before_splitting() -> None:
    scrambled = [Row(t=t, r=0.0) for t in (7, 1, 9, 3, 5, 0, 8, 2, 6, 4)]
    split = chronological_split(scrambled, key="t")
    assert [r.t for r in split.train] == [0, 1, 2, 3, 4]
    assert max(r.t for r in split.train) < min(r.t for r in split.unseal("test"))


def test_invalid_fractions_are_rejected() -> None:
    with pytest.raises(ValueError):
        chronological_split(rows(), train=0.8, validation=0.3)


# --- the multiple-testing bar -----------------------------------------------


def test_bar_rises_with_trial_count() -> None:
    assert noise_threshold(1) == 0.0
    assert math.isclose(noise_threshold(20), math.sqrt(2 * math.log(20)), abs_tol=1e-12)
    assert noise_threshold(100) > noise_threshold(20) > noise_threshold(5)


def test_twenty_trials_sets_the_bar_near_two_and_a_half() -> None:
    # The number quoted to the user for the 20-config sweep.
    assert 2.4 < noise_threshold(20) < 2.5


def test_pass_bar_never_falls_below_conventional_significance() -> None:
    # noise_threshold(1) is correctly 0.0 -- no selection has happened -- but a
    # single trial still has to clear ordinary significance to mean anything.
    assert noise_threshold(1) == 0.0
    assert pass_bar(1) == 2.0
    assert pass_bar(20) == noise_threshold(20)  # selection bar binds once it exceeds 2.0


def test_ledger_counts_every_trial(tmp_path) -> None:
    ledger = TrialLedger(tmp_path / "trials.jsonl")
    assert ledger.count() == 0
    for i in range(3):
        ledger.record(f"cfg{i}", {"tp1_r": i}, {"roi": -0.01 * i})
    assert ledger.count() == 3


def test_a_weak_winner_from_many_trials_fails(tmp_path) -> None:
    # The real case: +0.035R on 121 trades after 20 configurations.
    ledger = TrialLedger(tmp_path / "trials.jsonl")
    for i in range(20):
        ledger.record(f"cfg{i}", {}, {})
    v = ledger.judge(expectancy_r=0.035, sd_r=1.0, n=121)
    assert not v.passed
    assert v.observed_t < v.bar
    assert "FAIL" in v.summary()


def test_a_genuinely_strong_result_passes(tmp_path) -> None:
    ledger = TrialLedger(tmp_path / "trials.jsonl")
    for i in range(20):
        ledger.record(f"cfg{i}", {}, {})
    v = ledger.judge(expectancy_r=0.40, sd_r=1.0, n=400)
    assert v.passed, v.summary()


def test_positive_but_insignificant_is_not_a_pass(tmp_path) -> None:
    # Profitable on paper, indistinguishable from noise. Must not pass.
    ledger = TrialLedger(tmp_path / "trials.jsonl")
    ledger.record("only", {}, {})
    v = ledger.judge(expectancy_r=0.01, sd_r=1.0, n=9)
    assert not v.passed
