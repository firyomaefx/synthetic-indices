from pathlib import Path

from break100.research.walkforward import evaluate_outcomes, load_outcomes


def test_empty_is_nogo() -> None:
    report = evaluate_outcomes([])
    assert report.decision == "NO-GO"
    assert report.n == 0


def test_dedup_armed_bar() -> None:
    rows = [
        {"armed_bar": "1", "label": "BREAKOUT_UP"},
        {"armed_bar": "1", "label": "BREAKOUT_UP"},
        {"armed_bar": "2", "label": "BREAKOUT_DOWN"},
    ]
    report = evaluate_outcomes(rows)
    assert report.n == 2
    assert report.n_up == 1
    assert report.n_dn == 1


def test_load_missing(tmp_path: Path) -> None:
    assert load_outcomes(tmp_path / "nope.csv") == []
