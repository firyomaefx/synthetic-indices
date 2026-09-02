"""Per-box policy: skip decision, SL/TP geometry, runner levels.

Replaces the collapsed model in `tools/break100_hf_train.py`, which fitted a
logistic regression and then did `predict_proba(X).mean(axis=0)` — averaging
every prediction into one global number. That discards the conditioning that
makes a classifier worth having: the result is the base rate, reachable by
counting, and it cannot say "this box, not that one".

The fix is architectural. A logistic model is just weights and an intercept, so
those are exported into the policy CSV and the EA evaluates them **per box**.
Inference moves to where the box actually is, and Python stays responsible only
for fitting.

Stdlib only, matching the package's zero-dependency contract. Gradient descent
on a few hundred rows is not the bottleneck here — sample size is.
"""

from __future__ import annotations

import csv
import math
from dataclasses import dataclass, field
from pathlib import Path

# Cost charged per round trip in R, matching the MQL5 learner's constant.
COST_R = 0.12

FEATURES = (
    "height",
    "spread_arm",
    "touches_hi",
    "touches_lo",
    "close_loc",
    "compress",
    "h_vs_h4",
    "imp_dir",
)


@dataclass(frozen=True, slots=True)
class Sample:
    """One closed box outcome from the shadow ledger."""

    features: dict[str, float]
    r_multiple: float
    exec_decision: str
    dir: int

    @property
    def is_loss(self) -> bool:
        return self.r_multiple <= 0.0


@dataclass(frozen=True, slots=True)
class LogisticModel:
    """Weights the EA evaluates per box. `p = sigmoid(b0 + sum(w_i * z_i))`."""

    intercept: float
    weights: dict[str, float]
    mean: dict[str, float]
    sd: dict[str, float]
    n: int

    def score(self, features: dict[str, float]) -> float:
        z = self.intercept
        for k, w in self.weights.items():
            sd = self.sd.get(k, 1.0) or 1.0
            z += w * ((features.get(k, 0.0) - self.mean.get(k, 0.0)) / sd)
        return 1.0 / (1.0 + math.exp(-max(-60.0, min(60.0, z))))


@dataclass(frozen=True, slots=True)
class Geometry:
    """Stop and target multiples, in box heights."""

    sl_r: float
    tp1_r: float
    tp2_r: float
    tp3_r: float


@dataclass(frozen=True, slots=True)
class Policy:
    """Everything the EA needs, fitted from the shadow ledger."""

    n: int
    skip_model: LogisticModel | None
    geometry: Geometry
    mean_r: float
    source: str = "SHADOW_V1"
    notes: list[str] = field(default_factory=list)


def realized_r(
    mfe: float,
    mae: float,
    hw: float,
    sl_r: float,
    tp3_r: float,
    bars_to_mfe: int = 0,
    bars_to_mae: int = 0,
) -> float:
    """Counterfactual R under a candidate (sl_r, tp3_r), respecting path order.

    The original charged a full stop-out whenever `abs(mae) >= stop`, regardless
    of whether the stop preceded the target — so a trade that banked its target
    and only later traded through the stop level was scored as a full loss. The
    bar index of each extreme decides the order, mirroring the corrected
    `B100RealizedR` in `Learner.mqh`.
    """
    hw = hw if hw > 1e-9 else 1e-9
    stop = sl_r * hw
    tp3 = tp3_r * hw
    if stop <= 0.0:
        return -COST_R
    stopped = abs(mae) >= stop
    captured = min(max(0.0, mfe), tp3)
    if stopped and bars_to_mae <= bars_to_mfe:
        return -1.0 - COST_R
    if captured >= tp3:
        return tp3 / stop - COST_R
    if stopped:
        return -1.0 - COST_R
    return captured / stop - COST_R


def quantile(values: list[float], q: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = int(math.floor(q * (len(ordered) - 1)))
    return ordered[max(0, min(idx, len(ordered) - 1))]


def _standardise(
    rows: list[Sample], keys: tuple[str, ...]
) -> tuple[dict[str, float], dict[str, float]]:
    mean: dict[str, float] = {}
    sd: dict[str, float] = {}
    for k in keys:
        vals = [r.features.get(k, 0.0) for r in rows]
        m = math.fsum(vals) / len(vals)
        var = math.fsum((v - m) ** 2 for v in vals) / len(vals)
        mean[k] = m
        sd[k] = math.sqrt(var) or 1.0
    return mean, sd


def fit_logistic(
    rows: list[Sample],
    label: list[int],
    keys: tuple[str, ...] = FEATURES,
    epochs: int = 400,
    lr: float = 0.1,
    l2: float = 0.01,
) -> LogisticModel | None:
    """Plain regularised logistic regression. Returns None when unfittable."""
    if len(rows) < 20 or len(set(label)) < 2:
        return None
    keys = tuple(k for k in keys if any(r.features.get(k) is not None for r in rows))
    mean, sd = _standardise(rows, keys)
    x = [[(r.features.get(k, 0.0) - mean[k]) / sd[k] for k in keys] for r in rows]
    w = [0.0] * len(keys)
    b = 0.0
    n = len(rows)
    for _ in range(epochs):
        gw = [0.0] * len(keys)
        gb = 0.0
        for xi, yi in zip(x, label, strict=True):
            z = b + sum(wj * xj for wj, xj in zip(w, xi, strict=True))
            p = 1.0 / (1.0 + math.exp(-max(-60.0, min(60.0, z))))
            err = p - yi
            gb += err
            for j, xj in enumerate(xi):
                gw[j] += err * xj
        b -= lr * gb / n
        for j in range(len(w)):
            w[j] -= lr * (gw[j] / n + l2 * w[j])
    return LogisticModel(
        intercept=b,
        weights=dict(zip(keys, w, strict=True)),
        mean=mean,
        sd=sd,
        n=n,
    )


def load_shadow_ledger(path: Path) -> list[Sample]:
    """Read `BREAK100_shadow_v1_<sym>.csv` produced by the EA."""
    if not path.exists():
        return []
    out: list[Sample] = []
    with path.open(newline="", encoding="utf-8", errors="replace") as fh:
        for row in csv.DictReader(fh):
            try:
                r = float(row.get("r_multiple", "0") or 0.0)
                feats = {k: float(row.get(k, "0") or 0.0) for k in FEATURES}
                out.append(
                    Sample(
                        features=feats,
                        r_multiple=r,
                        exec_decision=(row.get("exec_decision") or "").strip(),
                        dir=int(float(row.get("dir", "0") or 0)),
                    )
                )
            except (TypeError, ValueError):
                continue
    return out


def fit_policy(samples: list[Sample], min_n: int = 30) -> Policy:
    """Fit the skip model and the geometry from closed shadow outcomes."""
    notes: list[str] = []
    default = Geometry(sl_r=1.15, tp1_r=1.0, tp2_r=2.0, tp3_r=3.0)
    if len(samples) < min_n:
        notes.append(f"only {len(samples)} closed rows; need {min_n} — defaults kept")
        return Policy(n=len(samples), skip_model=None, geometry=default, mean_r=0.0, notes=notes)

    losses = [1 if s.is_loss else 0 for s in samples]
    model = fit_logistic(samples, losses)
    if model is None:
        notes.append("skip model unfittable (one class or too few rows)")

    # Geometry from the realised R distribution rather than assumed multiples.
    wins = [s.r_multiple for s in samples if s.r_multiple > 0]
    tp1 = max(0.5, min(quantile(wins, 0.40) if wins else 1.0, 4.0))
    tp2 = max(tp1 + 0.2, min(quantile(wins, 0.65) if wins else 2.0, 6.0))
    tp3 = max(tp2 + 0.2, min(quantile(wins, 0.85) if wins else 3.0, 8.0))
    geom = Geometry(sl_r=default.sl_r, tp1_r=tp1, tp2_r=tp2, tp3_r=tp3)
    mean_r = math.fsum(s.r_multiple for s in samples) / len(samples)
    if mean_r <= 0:
        notes.append(f"measured expectancy {mean_r:+.3f}R — negative, as the tick data predicts")
    return Policy(n=len(samples), skip_model=model, geometry=geom, mean_r=mean_r, notes=notes)


def write_policy_csv(policy: Policy, path: Path, symbol: str = "BREAK100") -> None:
    """Emit the v2 policy the EA loads, including per-box model coefficients.

    `B100PolicyLoad` counts header columns before reading, so appending the
    coefficient columns is backward compatible with an EA that ignores them.
    """
    header = [
        "ready", "source", "n", "arm", "sl_r", "tp1_r", "tp2_r", "tp3_r",
        "mean_r", "p_up", "p_dn", "p_fail", "gate",
    ]
    row: list[str] = [
        "1", policy.source, str(policy.n), "0",
        f"{policy.geometry.sl_r:.4f}", f"{policy.geometry.tp1_r:.4f}",
        f"{policy.geometry.tp2_r:.4f}", f"{policy.geometry.tp3_r:.4f}",
        f"{policy.mean_r:.4f}", "0.3333", "0.3333", "0.3334", "BOTH",
    ]
    if policy.skip_model is not None:
        header += ["skip_b0"]
        row += [f"{policy.skip_model.intercept:.6f}"]
        for k in FEATURES:
            header += [f"skip_w_{k}", f"skip_mu_{k}", f"skip_sd_{k}"]
            row += [
                f"{policy.skip_model.weights.get(k, 0.0):.6f}",
                f"{policy.skip_model.mean.get(k, 0.0):.6f}",
                f"{policy.skip_model.sd.get(k, 1.0):.6f}",
            ]
    path.write_text(",".join(header) + "\n" + ",".join(row) + "\n", encoding="ascii")
