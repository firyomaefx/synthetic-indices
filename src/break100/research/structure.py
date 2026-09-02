"""Structure battery: decide whether a price series is tradeable at all.

The point of this module is to fail fast. BREAK100 absorbed a lot of effort
before anyone measured whether its price process contained anything to trade;
it did not. Running this first is cheaper than running a backtest.

Two ideas do the real work:

*Skewness* separates a Boom/Crash-style instrument (many small drifts one way,
rare violent spikes the other — mean near zero, tail strongly one-sided) from a
symmetric process. *Kurtosis* separates a spiky process from a plain walk. A
pure random walk has skew 0 and kurtosis 3; BREAK100 has skew 0 with high
kurtosis; UP500/DOWN500 should show significant skew.

Statistical significance is not enough on its own. With millions of ticks a
2.5pp bias is overwhelmingly significant and still ~200x too small to pay the
spread, so every verdict is also weighed against the cost hurdle.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from enum import StrEnum


class Verdict(StrEnum):
    """What the battery concluded about a series."""

    RANDOM_WALK = "RANDOM_WALK"
    FAT_TAILED_SYMMETRIC = "FAT_TAILED_SYMMETRIC"
    ASYMMETRIC = "ASYMMETRIC"
    TRENDING = "TRENDING"
    MEAN_REVERTING = "MEAN_REVERTING"
    INSUFFICIENT_DATA = "INSUFFICIENT_DATA"


@dataclass(frozen=True, slots=True)
class Moments:
    """First four moments of the step distribution."""

    n: int
    mean: float
    sd: float
    skew: float
    kurtosis: float
    skew_z: float
    """Skew in units of its standard error, sqrt(6/n). |z| > 3 is meaningful."""
    drift_t: float
    """Mean step in units of its standard error."""


@dataclass(frozen=True, slots=True)
class SignBalance:
    """Up/down step counts and how far the split sits from a fair coin."""

    up: int
    down: int
    z: float


@dataclass(frozen=True, slots=True)
class SpikeBalance:
    """Counts and mean sizes of large moves, split by direction."""

    threshold: float
    up_count: int
    down_count: int
    up_mean: float
    down_mean: float
    count_z: float
    size_t: float


@dataclass(frozen=True, slots=True)
class StructureReport:
    """Everything the battery measured, plus its verdict."""

    symbol: str
    moments: Moments
    signs: SignBalance
    spikes: SpikeBalance
    autocorr: dict[int, float]
    autocorr_se: float
    variance_ratio: dict[int, float]
    spread: float
    cost_hurdle: float
    """Spread as a fraction of the median daily range."""
    verdict: Verdict
    notes: list[str] = field(default_factory=list)

    @property
    def tradeable(self) -> bool:
        """True only when structure exists *and* it is not a pure walk."""
        return self.verdict in {Verdict.ASYMMETRIC, Verdict.TRENDING, Verdict.MEAN_REVERTING}


def moments(steps: list[float]) -> Moments:
    """Mean, sd, skew and kurtosis of the step distribution, with test stats."""
    n = len(steps)
    if n < 2:
        return Moments(n, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    mean = math.fsum(steps) / n
    m2 = math.fsum((x - mean) ** 2 for x in steps) / n
    sd = math.sqrt(m2)
    if sd <= 0.0:
        return Moments(n, mean, 0.0, 0.0, 0.0, 0.0, 0.0)
    m3 = math.fsum((x - mean) ** 3 for x in steps) / n
    m4 = math.fsum((x - mean) ** 4 for x in steps) / n
    skew = m3 / sd**3
    kurt = m4 / sd**4
    # SE of skew for a normal sample; adequate as a scale reference here.
    skew_se = math.sqrt(6.0 / n)
    drift_se = sd / math.sqrt(n)
    return Moments(
        n=n,
        mean=mean,
        sd=sd,
        skew=skew,
        kurtosis=kurt,
        skew_z=skew / skew_se if skew_se else 0.0,
        drift_t=mean / drift_se if drift_se else 0.0,
    )


def sign_balance(steps: list[float]) -> SignBalance:
    """Count up versus down steps and z-test the split against 0.5."""
    up = sum(1 for x in steps if x > 0)
    down = sum(1 for x in steps if x < 0)
    total = up + down
    if total == 0:
        return SignBalance(0, 0, 0.0)
    z = (up - total / 2.0) / math.sqrt(total * 0.25)
    return SignBalance(up, down, z)


def spike_balance(steps: list[float], threshold: float) -> SpikeBalance:
    """Compare large up-moves against large down-moves in count and in size."""
    ups = [x for x in steps if x >= threshold]
    downs = [-x for x in steps if x <= -threshold]
    nu, nd = len(ups), len(downs)
    total = nu + nd
    count_z = (nu - total / 2.0) / math.sqrt(total * 0.25) if total else 0.0
    up_mean = math.fsum(ups) / nu if nu else 0.0
    down_mean = math.fsum(downs) / nd if nd else 0.0
    size_t = 0.0
    if nu > 1 and nd > 1:
        vu = math.fsum((x - up_mean) ** 2 for x in ups) / (nu - 1)
        vd = math.fsum((x - down_mean) ** 2 for x in downs) / (nd - 1)
        se = math.sqrt(vu / nu + vd / nd)
        if se > 0.0:
            size_t = (up_mean - down_mean) / se
    return SpikeBalance(threshold, nu, nd, up_mean, down_mean, count_z, size_t)


def autocorrelation(steps: list[float], lags: tuple[int, ...], stride: int = 1) -> dict[int, float]:
    """Autocorrelation at each lag. `stride` subsamples long series."""
    n = len(steps)
    if n < 3:
        return dict.fromkeys(lags, 0.0)
    mean = math.fsum(steps) / n
    var = math.fsum((x - mean) ** 2 for x in steps) / n
    out: dict[int, float] = {}
    for lag in lags:
        if lag >= n or var <= 0.0:
            out[lag] = 0.0
            continue
        idx = range(0, n - lag, stride)
        cov = math.fsum((steps[i] - mean) * (steps[i + lag] - mean) for i in idx) / len(idx)
        out[lag] = cov / var
    return out


def variance_ratio(steps: list[float], horizons: tuple[int, ...]) -> dict[int, float]:
    """Lo-MacKinlay variance ratio: Var(k-step) / (k * Var(1-step)).

    1.0 means a random walk. Above 1 is trending, below 1 mean-reverting.
    """
    n = len(steps)
    if n < 2:
        return dict.fromkeys(horizons, 1.0)
    mean = math.fsum(steps) / n
    var1 = math.fsum((x - mean) ** 2 for x in steps) / n
    out: dict[int, float] = {}
    for k in horizons:
        if k < 2 or k >= n or var1 <= 0.0:
            out[k] = 1.0
            continue
        agg = [math.fsum(steps[i : i + k]) for i in range(0, n - k, k)]
        if len(agg) < 2:
            out[k] = 1.0
            continue
        am = math.fsum(agg) / len(agg)
        vark = math.fsum((x - am) ** 2 for x in agg) / len(agg)
        out[k] = vark / (k * var1)
    return out


# Thresholds. Deliberately strict: a false "tradeable" costs far more than a
# false "noise", because it sends real money after a coin flip.
DRIFT_T = 3.0
VR_TOLERANCE = 0.10

# Asymmetry needs a *robust* witness, not just a large skew. `skew_z` divides by
# sqrt(6/n), which assumes normality; under the kurtosis these instruments carry
# (BREAK100 measures ~6400) that SE is meaningless and a couple of lopsided
# spikes manufacture a z in the thousands. Sign and spike-count imbalance are
# bounded counts and cannot be distorted that way, so they decide, and skew only
# corroborates the direction.
SKEW_MIN = 0.5
SIGN_Z = 10.0
SIGN_IMBALANCE = 0.02
SPIKE_Z = 5.0
SPIKE_IMBALANCE = 0.20
KURTOSIS_SKEW_UNRELIABLE = 100.0


def _imbalance(a: int, b: int) -> float:
    """|a - b| / (a + b), or 0 when there is nothing to compare."""
    total = a + b
    return abs(a - b) / total if total else 0.0


def classify(
    symbol: str,
    steps: list[float],
    spread: float,
    median_daily_range: float,
    spike_threshold: float | None = None,
    autocorr_stride: int = 1,
) -> StructureReport:
    """Run the full battery and return a verdict with its supporting numbers."""
    if len(steps) < 1000:
        empty = Moments(len(steps), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        return StructureReport(
            symbol=symbol,
            moments=empty,
            signs=SignBalance(0, 0, 0.0),
            spikes=SpikeBalance(0.0, 0, 0, 0.0, 0.0, 0.0, 0.0),
            autocorr={},
            autocorr_se=0.0,
            variance_ratio={},
            spread=spread,
            cost_hurdle=0.0,
            verdict=Verdict.INSUFFICIENT_DATA,
            notes=[f"only {len(steps)} steps; need >= 1000"],
        )

    mom = moments(steps)
    signs = sign_balance(steps)
    thr = spike_threshold if spike_threshold is not None else 10.0 * mom.sd
    spikes = spike_balance(steps, thr)
    lags = (1, 2, 3, 5, 10, 60, 300)
    ac = autocorrelation(steps, lags, stride=autocorr_stride)
    ac_se = 1.0 / math.sqrt(len(steps))
    vr = variance_ratio(steps, (2, 5, 10, 60, 300))
    hurdle = spread / median_daily_range if median_daily_range > 0 else float("inf")

    notes: list[str] = []
    verdict = Verdict.RANDOM_WALK

    sign_imb = _imbalance(signs.up, signs.down)
    spike_imb = _imbalance(spikes.up_count, spikes.down_count)
    robust_asym = (abs(signs.z) > SIGN_Z and sign_imb > SIGN_IMBALANCE) or (
        abs(spikes.count_z) > SPIKE_Z and spike_imb > SPIKE_IMBALANCE
    )
    if mom.kurtosis > KURTOSIS_SKEW_UNRELIABLE:
        notes.append(
            f"kurtosis {mom.kurtosis:.0f} — skew_z assumes normality and is not "
            f"trustworthy here; verdict rests on sign/spike counts"
        )

    if robust_asym and abs(mom.skew) > SKEW_MIN:
        verdict = Verdict.ASYMMETRIC
        direction = "upward" if mom.skew > 0 else "downward"
        notes.append(
            f"{direction} tail: skew {mom.skew:+.2f}, sign imbalance {sign_imb:.1%}, "
            f"spike imbalance {spike_imb:.1%}"
        )
    elif abs(mom.drift_t) > DRIFT_T:
        verdict = Verdict.TRENDING
        notes.append(f"drift t={mom.drift_t:+.1f}")
    else:
        far = [k for k, v in vr.items() if abs(v - 1.0) > VR_TOLERANCE]
        if far:
            worst = max(far, key=lambda k: abs(vr[k] - 1.0))
            verdict = Verdict.TRENDING if vr[worst] > 1.0 else Verdict.MEAN_REVERTING
            notes.append(f"variance ratio at k={worst} is {vr[worst]:.3f}")
        elif mom.kurtosis > 6.0:
            verdict = Verdict.FAT_TAILED_SYMMETRIC
            notes.append(f"kurtosis {mom.kurtosis:.1f} but symmetric — spikes both ways")

    # Economic reality check. Statistical structure that cannot pay the spread
    # is not an edge, so say so rather than letting the verdict imply otherwise.
    if verdict in {Verdict.ASYMMETRIC, Verdict.TRENDING, Verdict.MEAN_REVERTING}:
        drift_per_1k = abs(mom.mean) * 1000.0
        if drift_per_1k < spread:
            notes.append(
                f"structure found, but 1000 steps of drift ({drift_per_1k:.2f}) "
                f"is below the {spread:.2f} spread"
            )
    if abs(signs.z) > 3.0:
        notes.append(f"up/down split {signs.up}/{signs.down} (z={signs.z:+.1f})")

    return StructureReport(
        symbol=symbol,
        moments=mom,
        signs=signs,
        spikes=spikes,
        autocorr=ac,
        autocorr_se=ac_se,
        variance_ratio=vr,
        spread=spread,
        cost_hurdle=hurdle,
        verdict=verdict,
        notes=notes,
    )
