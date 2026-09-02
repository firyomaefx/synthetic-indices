"""Pins for the per-box policy fitter and the corrected reward function."""

from __future__ import annotations

import math

from break100.research.policy import (
    FEATURES,
    Sample,
    fit_logistic,
    fit_policy,
    quantile,
    realized_r,
)


def sample(height: float, r: float, **over: float) -> Sample:
    feats = dict.fromkeys(FEATURES, 0.0)
    feats["height"] = height
    feats.update(over)
    return Sample(features=feats, r_multiple=r, exec_decision="SKIP_MODE", dir=1)


# --- the path-order fix -----------------------------------------------------


def test_stop_before_target_is_a_full_loss() -> None:
    # Adverse extreme came first (bar 1) and reached the stop.
    r = realized_r(mfe=100.0, mae=-100.0, hw=50.0, sl_r=1.0, tp3_r=3.0,
                   bars_to_mfe=5, bars_to_mae=1)
    assert r < -1.0


def test_target_banked_before_the_stop_is_not_a_loss() -> None:
    # Same excursions, opposite order: the target was reached first.
    r = realized_r(mfe=150.0, mae=-100.0, hw=50.0, sl_r=1.0, tp3_r=3.0,
                   bars_to_mfe=1, bars_to_mae=5)
    assert r > 0.0, "banking the target then touching the stop must not score as a full loss"


def test_order_is_what_separates_them() -> None:
    # The ONLY difference between these two is which extreme came first.
    early_win = realized_r(150.0, -100.0, 50.0, 1.0, 3.0, bars_to_mfe=1, bars_to_mae=9)
    early_loss = realized_r(150.0, -100.0, 50.0, 1.0, 3.0, bars_to_mfe=9, bars_to_mae=1)
    assert early_win > 0 > early_loss


def test_survivor_scores_by_captured_move_minus_cost() -> None:
    # Never stopped; captured 1R of a 3R ceiling.
    r = realized_r(mfe=50.0, mae=-10.0, hw=50.0, sl_r=1.0, tp3_r=3.0,
                   bars_to_mfe=3, bars_to_mae=1)
    assert math.isclose(r, 1.0 - 0.12, abs_tol=1e-9)


def test_zero_stop_distance_cannot_divide_by_zero() -> None:
    assert realized_r(10.0, -10.0, 50.0, 0.0, 3.0) == -0.12


# --- per-box inference, the thing the old model threw away ------------------


def test_model_discriminates_between_boxes_rather_than_averaging() -> None:
    # Small boxes lose, large boxes win. A per-box model must score them apart.
    rows = [sample(20.0, -1.0) for _ in range(40)] + [sample(120.0, +1.0) for _ in range(40)]
    labels = [1] * 40 + [0] * 40
    model = fit_logistic(rows, labels)
    assert model is not None
    p_small = model.score({**dict.fromkeys(FEATURES, 0.0), "height": 20.0})
    p_large = model.score({**dict.fromkeys(FEATURES, 0.0), "height": 120.0})
    assert p_small > 0.6, f"small box should score as likely-loss, got {p_small:.3f}"
    assert p_large < 0.4, f"large box should score as likely-win, got {p_large:.3f}"
    assert p_small - p_large > 0.3, "the whole point is separation between boxes"


def test_single_class_returns_no_model_rather_than_a_fake_one() -> None:
    rows = [sample(50.0, -1.0) for _ in range(40)]
    assert fit_logistic(rows, [1] * 40) is None


def test_too_few_rows_returns_no_model() -> None:
    rows = [sample(50.0, 1.0) for _ in range(5)]
    assert fit_logistic(rows, [0, 1, 0, 1, 0]) is None


# --- policy assembly --------------------------------------------------------


def test_thin_sample_keeps_defaults_and_says_so() -> None:
    pol = fit_policy([sample(50.0, 1.0) for _ in range(5)])
    assert pol.skip_model is None
    assert pol.geometry.tp1_r == 1.0
    assert any("defaults kept" in n for n in pol.notes)


def test_targets_come_from_the_realised_distribution_and_stay_ordered() -> None:
    rows = [sample(80.0, 1.0 + i * 0.05) for i in range(40)]
    rows += [sample(30.0, -1.0) for _ in range(20)]
    pol = fit_policy(rows)
    g = pol.geometry
    assert g.tp1_r < g.tp2_r < g.tp3_r, "targets must stay strictly ordered"
    assert 0.5 <= g.tp1_r <= 4.0


def test_negative_expectancy_is_reported_not_hidden() -> None:
    rows = [sample(40.0, -0.2) for _ in range(20)] + [sample(90.0, 0.1) for _ in range(20)]
    pol = fit_policy(rows)
    assert pol.mean_r < 0
    assert any("negative" in n for n in pol.notes)


def test_quantile_handles_empty_input() -> None:
    assert quantile([], 0.5) == 0.0
