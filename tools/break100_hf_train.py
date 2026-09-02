#!/usr/bin/env python3
"""BREAK100 Hugging Face trainer.

Reads quality-gated BREAK100_train_*.csv (or learn.csv), trains:
  - direction posterior (UP / DOWN / FAIL)  — sklearn, via HF datasets
  - SL/TP multipliers                       — MAE/MFE quantiles + 4-arm UCB

Writes BREAK100_policy_<symbol>.csv that the EA already loads.
Does NOT send broker orders. Not a profit claim.

Optional: --push-hub username/break100-boom  uploads dataset + policy.

Why not DistilBERT by default: 16–400 tabular rows overfit a transformer.
When you have 500+ quality=1 rows, pass --text-model.
"""
from __future__ import annotations

import argparse
import csv
import glob
import math
import os
import sys
from pathlib import Path

ARMS = [
    ("balanced", 1.00, 1.00, 2.00, 3.00),
    ("tight", 0.85, 0.80, 1.50, 2.20),
    ("wide", 1.35, 1.20, 2.40, 4.00),
    ("runner", 1.10, 1.60, 3.00, 5.00),
]
MIN_N = 16
COST = 0.12


def clamp(x, lo, hi):
    return lo if x < lo else hi if x > hi else x


def realized_r(mfe, mae, hw, sl_r, tp3_r, b_mfe=0, b_mae=0):
    """Counterfactual R, respecting the order the extremes occurred in.

    Previously this returned a full stop-out whenever abs(mae) >= stop, with no
    regard for whether the stop came before the target — scoring a trade that
    banked its target and only later traded through the stop as a total loss.
    Mirrors the corrected B100RealizedR in Learner.mqh.
    """
    hw = hw if hw > 1e-9 else 1e-9
    stop = sl_r * hw
    tp3 = tp3_r * hw
    if stop <= 0.0:
        return -COST
    stopped = abs(mae) >= stop
    captured = min(max(0.0, mfe), tp3)
    if stopped and b_mae <= b_mfe:
        return -1.0 - COST
    if captured >= tp3:
        return tp3 / stop - COST
    if stopped:
        return -1.0 - COST
    return captured / stop - COST


def _plain_train(root: Path):
    exact_u = root / "BREAK100_train_unique_BREAK100.csv"
    if exact_u.exists():
        return exact_u
    exact = root / "BREAK100_train_BREAK100.csv"
    if exact.exists():
        return exact
    plains = [p for p in sorted(root.glob("BREAK100_train_*.csv"), key=lambda p: p.stat().st_mtime) if "unique" not in p.name]
    return plains[-1] if plains else None


def find_common_csv():
    app = os.environ.get("APPDATA", "")
    if app:
        root = Path(app) / "MetaQuotes" / "Terminal" / "Common" / "Files"
        hit = _plain_train(root)
        if hit:
            return hit
        # learn.csv is bounce duplicates — never train from it.
    return _plain_train(Path.cwd())


def load_rows(path: Path):
    rows = []
    with path.open(newline="", encoding="utf-8", errors="replace") as f:
        r = csv.DictReader(f)
        fields = r.fieldnames or []
        wide = "quality" in fields
        for rec in r:
            try:
                if wide:
                    q = int(float(rec.get("quality", "1") or 1))
                    if q == 0:
                        continue
                    side = int(float(rec.get("side", "0") or 0))
                    label = rec.get("label", "")
                    mfe = float(rec.get("mfe", "0") or 0)
                    mae = float(rec.get("mae", "0") or 0)
                    hw = float(rec.get("hw", "0") or 0)
                    arm = int(float(rec.get("arm", "0") or 0))
                    extra = {
                        "height": float(rec.get("height") or 0),
                        "atr": float(rec.get("atr") or 0),
                        "spread": float(rec.get("spread") or 0),
                        "bars_box": float(rec.get("bars_box") or 0),
                        "hour": float(rec.get("hour") or 0),
                        "dow": float(rec.get("dow") or 0),
                        "mfe_r": float(rec.get("mfe_r") or 0),
                        "mae_r": float(rec.get("mae_r") or 0),
                    }
                else:
                    # learn.csv: side,label,mfe,mae,hw,arm
                    side = int(float(rec.get("side", "0") or 0))
                    label = rec.get("label", "")
                    mfe = float(rec.get("mfe", "0") or 0)
                    mae = float(rec.get("mae", "0") or 0)
                    hw = float(rec.get("hw", "0") or 0)
                    arm = int(float(rec.get("arm", "0") or 0))
                    extra = {}
            except (TypeError, ValueError):
                continue
            if hw <= 0:
                continue
            if arm < 0 or arm > 3:
                arm = 0
            y = "FAIL"
            if "BREAKOUT_UP" in label:
                y = "UP"
            elif "BREAKOUT_DOWN" in label:
                y = "DOWN"
            rec_out = {"side": side, "label": label, "mfe": mfe, "mae": mae, "hw": hw, "arm": arm, "y": y}
            rec_out.update(extra)
            eid = str(rec.get("episode_id") or "").strip()
            rec_out["episode_id"] = eid
            rows.append(rec_out)
    if any(r.get("episode_id") for r in rows):
        by = {}
        for r in rows:
            k = r.get("episode_id") or rec_id_fallback(r)
            by[k] = r
        rows = list(by.values())
    return rows


def rec_id_fallback(r: dict) -> str:
    return "|".join(str(r.get(k, "")) for k in ("side", "label", "mfe", "mae", "hw"))


def load_human_boxes(root: Path) -> list:
    """Rectangles: pause then first M30 close outside = UP/DN big move."""
    rows = []
    for p in sorted(root.glob("BREAK100_human_box_*.csv")):
        with p.open(newline="", encoding="utf-8", errors="replace") as f:
            for rec in csv.DictReader(f):
                after = (rec.get("after_dir") or rec.get("after") or "").strip().upper()
                if after not in ("UP", "DN"):
                    continue
                try:
                    hw = float(rec.get("height") or 0)
                    sz = float(rec.get("after_size") or 0)
                except (TypeError, ValueError):
                    continue
                if hw <= 0:
                    continue
                side = 1 if after == "UP" else -1
                lab = "BREAKOUT_UP" if side > 0 else "BREAKOUT_DOWN"
                eid = "H|" + str(rec.get("t_left") or "") + "|" + str(rec.get("name") or p.name)
                rows.append(
                    {
                        "side": side,
                        "label": lab,
                        "mfe": max(0.0, sz),
                        "mae": 0.0,
                        "hw": hw,
                        "arm": 0,
                        "y": after,
                        "episode_id": eid,
                    }
                )
    return rows


def as_hf_dataset(rows):
    try:
        from datasets import Dataset
    except ImportError:
        return None
    return Dataset.from_list(rows)


def quantile(vals, q):
    if not vals:
        return 0.0
    xs = sorted(vals)
    idx = int(math.floor(q * (len(xs) - 1)))
    idx = max(0, min(len(xs) - 1, idx))
    return xs[idx]


def pick_ucb(rows):
    n = len(rows)
    counts = [0] * 4
    sums = [0.0] * 4
    for r in rows:
        a = r["arm"]
        sl, t3 = ARMS[a][1], ARMS[a][4]
        counts[a] += 1
        sums[a] += realized_r(r["mfe"], r["mae"], r["hw"], sl, t3)
    if n < MIN_N:
        return 0
    logn = math.log(n + 1.0)
    best, best_sc = 0, -1e100
    for a in range(4):
        if counts[a] == 0:
            return a
        mean = sums[a] / counts[a]
        sc = mean + 1.15 * math.sqrt(logn / counts[a])
        if sc > best_sc:
            best_sc, best = sc, a
    return best


def blend(rows, arm):
    mae_r, mfe_r = [], []
    for r in rows:
        hw = max(r["hw"], 1e-9)
        mae_r.append(abs(r["mae"]) / hw)
        if "BREAKOUT" in r["label"]:
            mfe_r.append(max(0.0, r["mfe"]) / hw)
    sl0, t1, t2, t3 = ARMS[arm][1], ARMS[arm][2], ARMS[arm][3], ARMS[arm][4]
    qsl = quantile(mae_r, 0.75) if mae_r else sl0
    q1 = quantile(mfe_r, 0.40) if mfe_r else t1
    q2 = quantile(mfe_r, 0.65) if mfe_r else t2
    q3 = quantile(mfe_r, 0.85) if mfe_r else t3
    qsl = clamp(qsl, 0.7, 2.4)
    q1 = clamp(q1, 0.5, 3.0)
    q2 = clamp(max(q2, q1 + 0.15), q1 + 0.15, 5.0)
    q3 = clamp(max(q3, q2 + 0.15), q2 + 0.15, 8.0)
    sl = clamp(0.55 * sl0 + 0.45 * qsl, 0.7, 2.5)
    p1 = clamp(0.55 * t1 + 0.45 * q1, 0.5, 4.0)
    p2 = clamp(0.55 * t2 + 0.45 * q2, p1 + 0.2, 6.0)
    p3 = clamp(0.55 * t3 + 0.45 * q3, p2 + 0.2, 8.0)
    rs = [realized_r(r["mfe"], r["mae"], r["hw"], sl, p3) for r in rows]
    mean_r = sum(rs) / len(rs) if rs else 0.0
    return sl, p1, p2, p3, mean_r


def dir_posterior(rows):
    up = sum(1 for r in rows if r["y"] == "UP")
    dn = sum(1 for r in rows if r["y"] == "DOWN")
    fail = sum(1 for r in rows if r["y"] == "FAIL")
    tot = up + dn + fail + 3.0
    pu, pd, pf = (up + 1) / tot, (dn + 1) / tot, (fail + 1) / tot
    gate = "BOTH"
    if len(rows) >= MIN_N:
        if pf > pu and pf > pd and pf >= 0.42:
            gate = "SKIP"
        elif pu >= pd + 0.12 and pu >= 0.38:
            gate = "BUY"
        elif pd >= pu + 0.12 and pd >= 0.38:
            gate = "SELL"
    return pu, pd, pf, gate


def hf_direction_fit(rows):
    """Tabular logistic via sklearn; features from train.csv when present."""
    feat_keys = [k for k in ("height", "atr", "spread", "bars_box", "hour", "dow") if k in rows[0]]
    if not feat_keys or len(rows) < MIN_N:
        return dir_posterior(rows)
    try:
        import numpy as np
        from sklearn.linear_model import LogisticRegression
        from sklearn.preprocessing import StandardScaler
    except ImportError:
        print("sklearn not installed — using count posterior only")
        return dir_posterior(rows)
    X = np.array([[float(r.get(k, 0.0)) for k in feat_keys] for r in rows], dtype=float)
    ymap = {"UP": 0, "DOWN": 1, "FAIL": 2}
    y = np.array([ymap[r["y"]] for r in rows], dtype=int)
    if len(set(y.tolist())) < 2:
        return dir_posterior(rows)
    scaler = StandardScaler()
    Xs = scaler.fit_transform(X)
    clf = LogisticRegression(max_iter=400, class_weight="balanced")
    clf.fit(Xs, y)
    # NOTE: averaging predictions here discards per-box conditioning and yields
    # the base rate. Kept only for the legacy p_up/p_dn/p_fail columns; the
    # per-box model that actually gates trades now lives in
    # src/break100/research/policy.py and ships coefficients to the EA.
    proba = clf.predict_proba(Xs).mean(axis=0)
    # map classes back
    classes = list(clf.classes_)
    pu = pd = pf = 1.0 / 3.0
    for i, c in enumerate(classes):
        if c == 0:
            pu = float(proba[i])
        elif c == 1:
            pd = float(proba[i])
        else:
            pf = float(proba[i])
    s = pu + pd + pf
    if s > 0:
        pu, pd, pf = pu / s, pd / s, pf / s
    # blend with Dirichlet so a tiny set cannot lock SKIP
    cu, cd, cf, _ = dir_posterior(rows)
    pu, pd, pf = 0.5 * pu + 0.5 * cu, 0.5 * pd + 0.5 * cd, 0.5 * pf + 0.5 * cf
    gate = "BOTH"
    if pf > pu and pf > pd and pf >= 0.42:
        gate = "SKIP"
    elif pu >= pd + 0.12 and pu >= 0.38:
        gate = "BUY"
    elif pd >= pu + 0.12 and pd >= 0.38:
        gate = "SELL"
    return pu, pd, pf, gate


def policy_path(csv_path: Path) -> Path:
    """EA loads BREAK100_policy_<symbol>.csv — never policy_unique_..."""
    name = csv_path.name
    if name.endswith(".csv"):
        name = name[:-4]
    while "unique_" in name:
        name = name.replace("unique_", "")
    if name.startswith("BREAK100_train_"):
        name = "BREAK100_policy_v2_" + name[len("BREAK100_train_") :]
    elif name.startswith("BREAK100_learn_"):
        name = "BREAK100_policy_v2_" + name[len("BREAK100_learn_") :]
    else:
        name = "BREAK100_policy_v2_BREAK100"
    if not name.endswith(".csv"):
        name += ".csv"
    return csv_path.with_name(name)


def write_policy(path: Path, ready, source, n, arm, sl, t1, t2, t3, mean_r, pu, pd, pf, gate):
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(
            ["ready", "source", "n", "arm", "sl_r", "tp1_r", "tp2_r", "tp3_r", "mean_r", "p_up", "p_dn", "p_fail", "gate"]
        )
        w.writerow(
            [
                int(ready),
                source,
                n,
                arm,
                f"{sl:.6f}",
                f"{t1:.6f}",
                f"{t2:.6f}",
                f"{t3:.6f}",
                f"{mean_r:.6f}",
                f"{pu:.6f}",
                f"{pd:.6f}",
                f"{pf:.6f}",
                gate,
            ]
        )


def push_hub(repo, csv_path: Path, policy: Path, rows, token):
    try:
        from huggingface_hub import HfApi, login
    except ImportError:
        print("huggingface_hub not installed — skip push")
        return
    if token:
        login(token=token)
    api = HfApi()
    api.create_repo(repo, exist_ok=True, repo_type="dataset", private=True)
    api.upload_file(path_or_fileobj=str(csv_path), path_in_repo=csv_path.name, repo_id=repo, repo_type="dataset")
    api.upload_file(path_or_fileobj=str(policy), path_in_repo=policy.name, repo_id=repo, repo_type="dataset")
    readme = (
        "# BREAK100 train set\n\n"
        f"n={len(rows)} quality-gated episodes. Research data. Not a profit claim.\n"
    )
    api.upload_file(path_or_fileobj=readme.encode(), path_in_repo="README.md", repo_id=repo, repo_type="dataset")
    print(f"Pushed dataset {repo}")


def train_file(csv_path) -> dict:
    """Train from a CSV path. Returns a result dict and writes policy next to the CSV."""
    path = Path(csv_path)
    rows = load_rows(path)
    human = load_human_boxes(path.parent)
    if human:
        by = {r.get("episode_id") or rec_id_fallback(r): r for r in rows}
        for h in human:
            by[h["episode_id"]] = h
        rows = list(by.values())
    n = len(rows)
    out = policy_path(path)
    result = {
        "input": str(path),
        "policy": str(out),
        "n": n,
        "ready": 0,
        "source": "DEFAULT",
        "arm": 0,
        "arm_id": ARMS[0][0],
        "sl": ARMS[0][1],
        "tp1": ARMS[0][2],
        "tp2": ARMS[0][3],
        "tp3": ARMS[0][4],
        "mean_r": 0.0,
        "oos_r": 0.0,
        "p_up": 0.0,
        "p_dn": 0.0,
        "p_fail": 0.0,
        "gate": "BOTH",
        "log": "",
    }
    lines = [f"Input {path}", f"quality rows n={n}"]
    if n < MIN_N:
        pu, pd, pf, gate = dir_posterior(rows)
        sl0 = ARMS[0][1]
        write_policy(out, 0, "DEFAULT", n, 0, sl0, sl0, max(ARMS[0][3], 2.0 * sl0), max(ARMS[0][4], 3.0 * sl0), 0.0, pu, pd, pf, "BOTH")
        result.update(p_up=pu, p_dn=pd, p_fail=pf, gate="BOTH", policy=str(out))
        result["log"] = "\n".join(lines + [f"Need {MIN_N} rows. Wrote DEFAULT OCO policy."])
        return result

    rows.sort(key=lambda r: str(r.get("episode_id") or "0"))
    split = max(MIN_N, int(n * 0.7))
    train, hold = rows[:split], rows[split:]
    arm = pick_ucb(train)
    sl, t1, t2, t3, mean_r = blend(train, arm)
    t1 = sl
    t2 = max(t2, 2.0 * sl)
    t3 = max(t3, t2 + 0.2 * sl)
    pu, pd, pf, _ignored = hf_direction_fit(train)
    gate = "BOTH"
    oos = 0.0
    if hold:
        oos = sum(realized_r(r["mfe"], r["mae"], r["hw"], sl, t3) for r in hold) / len(hold)
    write_policy(out, 1, "HF_TABULAR", n, arm, sl, t1, t2, t3, mean_r, pu, pd, pf, gate)
    lines += [
        f"arm={ARMS[arm][0]} ({arm})",
        f"SL/hw {sl:.3f}  TP1=1R {t1:.3f}  TP2 {t2:.3f}  TP3 {t3:.3f}",
        f"in-sample R {mean_r:.4f}  holdout R {oos:.4f}",
        f"p_up={pu:.3f} p_dn={pd:.3f} p_fail={pf:.3f} gate=BOTH (OCO)",
        "Holdout R is a research score. Not expected profit.",
        f"Wrote {out}",
    ]
    result.update(
        ready=1,
        source="HF_TABULAR",
        arm=arm,
        arm_id=ARMS[arm][0],
        sl=sl,
        tp1=t1,
        tp2=t2,
        tp3=t3,
        mean_r=mean_r,
        oos_r=oos,
        p_up=pu,
        p_dn=pd,
        p_fail=pf,
        gate="BOTH",
        log="\n".join(lines),
    )
    return result


def main():
    ap = argparse.ArgumentParser(description="BREAK100 HF trainer — writes EA policy.csv")
    ap.add_argument("csv", nargs="?", help="BREAK100_train_*.csv path")
    ap.add_argument("--push-hub", default=os.environ.get("BREAK100_HF_DATASET", ""),
                    help="HF dataset repo id (backup). Env BREAK100_HF_DATASET also works.")
    ap.add_argument("--hf-token", default=os.environ.get("HF_TOKEN", ""))
    args = ap.parse_args()

    print("============================================")
    print(" BREAK100 Hugging Face trainer  v1.85")
    print(" Tabular (datasets + sklearn). Not a profit claim.")
    print(" Does NOT send broker orders.")
    print("============================================\n")

    path = Path(args.csv) if args.csv else find_common_csv()
    if path is None or not Path(path).exists():
        print("No BREAK100_train_*.csv found.")
        print("Pass the file, or put it in Common\\Files and re-run.")
        return 1
    path = Path(path)
    print(f"Input  {path}")
    result = train_file(path)
    print(result["log"])
    if result["n"] < MIN_N and result["source"] == "DEFAULT":
        if args.push_hub:
            rows = load_rows(path)
            push_hub(args.push_hub, path, Path(result["policy"]), rows, args.hf_token)
        return 0
    print("Copy into Common\\Files if it is not already there, then reattach the EA.")
    print("Keep InpUseLearner = true. AutoTrading stays OFF on real.\n")
    if args.push_hub:
        push_hub(args.push_hub, path, Path(result["policy"]), load_rows(path), args.hf_token)
    return 0


if __name__ == "__main__":
    sys.exit(main())
