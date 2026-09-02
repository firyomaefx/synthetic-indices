"""Validation gate for the structure battery.

Each process here has a known answer. If the battery cannot separate these, its
verdict on a real instrument means nothing — so these tests gate everything
downstream in the screening work.
"""

from __future__ import annotations

import random

from break100.research.structure import Verdict, classify, moments, variance_ratio

N = 60_000


def pure_walk(seed: int = 1, n: int = N) -> list[float]:
    """Fair coin, +/-1 steps. Skew 0, kurtosis ~1 (Bernoulli), VR 1."""
    rng = random.Random(seed)
    return [1.0 if rng.random() < 0.5 else -1.0 for _ in range(n)]


def boom_like(seed: int = 2, n: int = N, period: int = 500) -> list[float]:
    """Grinds down, spikes up. Mean ~0 by construction, strong positive skew.

    This is the UP500 shape: 'falling price, sharp upward spike ~1 in 500'.
    """
    rng = random.Random(seed)
    spike = float(period - 1)
    return [spike if rng.random() < 1.0 / period else -1.0 for _ in range(n)]


def crash_like(seed: int = 3, n: int = N, period: int = 500) -> list[float]:
    """Mirror of boom_like — the DOWN500 shape."""
    return [-x for x in boom_like(seed, n, period)]


def fat_symmetric(seed: int = 4, n: int = N) -> list[float]:
    """Symmetric spikes both ways: the BREAK100 shape. Skew 0, high kurtosis."""
    rng = random.Random(seed)
    out: list[float] = []
    for _ in range(n):
        if rng.random() < 1.0 / 500:
            out.append(rng.choice([100.0, -100.0]))
        else:
            out.append(rng.choice([1.0, -1.0]))
    return out


def trending(seed: int = 5, n: int = N) -> list[float]:
    """Random walk with a real positive drift."""
    rng = random.Random(seed)
    return [rng.gauss(0.05, 1.0) for _ in range(n)]


def mean_reverting(seed: int = 6, n: int = N) -> list[float]:
    """AR(1) with a negative coefficient — steps tend to undo themselves."""
    rng = random.Random(seed)
    out: list[float] = []
    prev = 0.0
    for _ in range(n):
        step = -0.4 * prev + rng.gauss(0.0, 1.0)
        out.append(step)
        prev = step
    return out


# --- negative controls: must NOT be called tradeable ------------------------


def test_pure_random_walk_is_reported_as_a_random_walk() -> None:
    r = classify("PURE_RW", pure_walk(), spread=1.0, median_daily_range=100.0)
    assert r.verdict is Verdict.RANDOM_WALK
    assert not r.tradeable


def test_symmetric_spikes_are_fat_tailed_not_tradeable() -> None:
    # The BREAK100 shape: spiky, but with no directional information.
    r = classify("FAT_SYM", fat_symmetric(), spread=5.0, median_daily_range=800.0)
    assert r.verdict is Verdict.FAT_TAILED_SYMMETRIC
    assert not r.tradeable
    assert r.moments.kurtosis > 6.0
    assert abs(r.moments.skew_z) < 3.0


# --- positive controls: must be detected ------------------------------------


def test_boom_shape_is_detected_as_asymmetric() -> None:
    r = classify("BOOM", boom_like(), spread=0.5, median_daily_range=200.0)
    assert r.verdict is Verdict.ASYMMETRIC
    assert r.tradeable
    assert r.moments.skew > 0, "upward spikes must give positive skew"


def test_crash_shape_is_detected_with_the_opposite_sign() -> None:
    r = classify("CRASH", crash_like(), spread=0.5, median_daily_range=200.0)
    assert r.verdict is Verdict.ASYMMETRIC
    assert r.moments.skew < 0


def test_real_drift_is_detected_as_trending() -> None:
    r = classify("TREND", trending(), spread=0.5, median_daily_range=200.0)
    assert r.verdict is Verdict.TRENDING
    assert r.moments.drift_t > 3.0


def test_ar1_reversion_is_detected() -> None:
    r = classify("REVERT", mean_reverting(), spread=0.5, median_daily_range=200.0)
    assert r.verdict is Verdict.MEAN_REVERTING
    assert r.autocorr[1] < 0


# --- the economic guard -----------------------------------------------------


def test_structure_too_small_to_pay_the_spread_is_flagged() -> None:
    # Real drift, but a spread far larger than the drift can accumulate.
    r = classify("TINY_EDGE", trending(), spread=500.0, median_daily_range=200.0)
    assert r.verdict is Verdict.TRENDING
    assert any("below the" in n for n in r.notes), r.notes


# --- component sanity -------------------------------------------------------


def test_variance_ratio_is_one_for_a_random_walk() -> None:
    vr = variance_ratio(pure_walk(), (2, 5, 10))
    for k, v in vr.items():
        assert abs(v - 1.0) < 0.1, f"k={k} gave {v}"


def test_moments_recover_a_known_skew_sign() -> None:
    assert moments(boom_like()).skew > 1.0
    assert moments(pure_walk()).skew == 0.0 or abs(moments(pure_walk()).skew) < 0.05


def test_short_series_refuses_to_guess() -> None:
    r = classify("SHORT", [1.0, -1.0] * 100, spread=1.0, median_daily_range=10.0)
    assert r.verdict is Verdict.INSUFFICIENT_DATA
    assert not r.tradeable
