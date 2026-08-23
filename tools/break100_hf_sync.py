#!/usr/bin/env python3
"""Bidirectional BREAK100 sync: Common Files <-> Hugging Face dataset.

Keeps train.csv and policy.csv current on BOTH sides.
  - Merge train rows by episode_id (local wins on conflict)
  - Retrain if the merged table grew
  - Pull Hub policy if it is newer and has n >= local

Reads token/dataset from:
  %APPDATA%\\MetaQuotes\\Terminal\\Common\\Files\\BREAK100_hf.txt
  token=hf_...
  dataset=yourname/break100-boom

Free-tier Hub only: unique train + policy + outcome + dataset card.
No GPU Space. No ticks. No tokens. Does NOT send broker orders. Not a profit claim.
"""
from __future__ import annotations

import argparse
import csv
import os
import sys
import time
from io import StringIO
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import break100_hf_train as T  # noqa: E402

COMMON = Path(os.environ.get("APPDATA", "")) / "MetaQuotes" / "Terminal" / "Common" / "Files"
CFG_NAME = "BREAK100_hf.txt"
STATE_NAME = "BREAK100_hf_sync_state.txt"


def common_dir() -> Path:
    if COMMON.exists():
        return COMMON
    return Path.cwd()


def read_cfg(root: Path):
    token = os.environ.get("HF_TOKEN", "")
    dataset = os.environ.get("BREAK100_HF_DATASET", "")
    p = root / CFG_NAME
    if p.exists():
        for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if line.startswith("token="):
                token = line[6:].strip()
            elif line.startswith("dataset="):
                dataset = line[8:].strip()
    return token, dataset


def rows_from_path(path: Path):
    if not path.exists():
        return []
    return T.load_rows(path)


def raw_records(path: Path):
    if not path.exists():
        return [], []
    with path.open(newline="", encoding="utf-8", errors="replace") as f:
        r = csv.DictReader(f)
        fields = r.fieldnames or []
        recs = [dict(x) for x in r]
    return fields, recs


def rec_id(rec: dict) -> str:
    eid = str(rec.get("episode_id") or rec.get("id") or "").strip()
    if eid:
        return eid
    return "|".join(
        str(rec.get(k, "")) for k in ("side", "label", "mfe", "mae", "hw", "entry", "exit")
    )


def unique_quality(recs):
    """One row per episode_id, quality=1 only. Drops bounce-dupe learn.csv spam."""
    by = {}
    for rec in recs:
        try:
            q = int(float(rec.get("quality", "1") or 1))
        except (TypeError, ValueError):
            q = 1
        if q == 0:
            continue
        by[rec_id(rec)] = rec
    return list(by.values())


DATASET_CARD = """# BREAK100 backup (private, free tier)

This is **not** Boom tick data. It is the BREAK100 **M30 box** backup for Tengkolok.

## Files

| File | What |
|---|---|
| `BREAK100_train_BREAK100.csv` | Closed episodes (merged). Prefer unique quality=1. |
| `BREAK100_train_unique_BREAK100.csv` | One row per `episode_id`, `quality=1` only |
| `BREAK100_policy_BREAK100.csv` | One-row policy the MT5 EA loads (SL/TP in box heights) |
| `BREAK100_outcome_BREAK100.csv` | Fill labels (UP/DOWN/CENSOR) for arrows/journal |
| `BREAK100_human_box_BREAK100.csv` | Your MT5 rectangles (pause before the big move) |

Not stored: ticks, Telegram/HF tokens, account login, live orders.

## Use

PC task `break100_hf_sync.py` (every 15 min) is the always-on worker. Free Spaces **sleep**.

Need **16+** unique `quality=1` rows. RL does **not** drop OCO sides. **Not a profit claim.**
"""


def merge_records(local, hub):
    by = {}
    for rec in hub:
        by[rec_id(rec)] = rec
    for rec in local:
        by[rec_id(rec)] = rec  # local wins
    return list(by.values())


def write_records(path: Path, fields, recs):
    if not fields:
        fields = list(recs[0].keys()) if recs else ["side", "label", "mfe", "mae", "hw", "arm"]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        for rec in recs:
            w.writerow(rec)


def hub_download(repo, filename, token, dest: Path) -> bool:
    try:
        from huggingface_hub import hf_hub_download
    except ImportError:
        print("huggingface_hub missing — Hub pull skipped")
        return False
    try:
        local = hf_hub_download(
            repo_id=repo, filename=filename, repo_type="dataset", token=token or None
        )
        Path(dest).write_bytes(Path(local).read_bytes())
        return True
    except Exception as e:
        print(f"Hub pull {filename}: {e}")
        return False


def hub_upload(repo, path: Path, token):
    try:
        from huggingface_hub import HfApi, login
    except ImportError:
        print("huggingface_hub missing — Hub push skipped")
        return False
    try:
        if token:
            login(token=token)
        api = HfApi()
        api.create_repo(repo, exist_ok=True, repo_type="dataset", private=True)
        api.upload_file(
            path_or_fileobj=str(path),
            path_in_repo=path.name,
            repo_id=repo,
            repo_type="dataset",
        )
        print(f"Hub push {path.name} -> {repo}")
        return True
    except Exception as e:
        print(f"Hub push {path.name}: {e}")
        return False


def policy_n(path: Path) -> int:
    if not path.exists():
        return -1
    try:
        with path.open(newline="", encoding="utf-8", errors="replace") as f:
            r = csv.DictReader(f)
            row = next(r, None)
        if not row:
            return -1
        return int(float(row.get("n", "0") or 0))
    except Exception:
        return -1


def sync_one(train_path: Path, token: str, dataset: str) -> str:
    logs = [f"== {train_path.name} =="]
    fields, local_recs = raw_records(train_path)
    hub_recs = []
    tmp = train_path.with_suffix(".hub.csv")
    if dataset:
        if hub_download(dataset, train_path.name, token, tmp):
            hf, hub_recs = raw_records(tmp)
            if not fields:
                fields = hf
            logs.append(f"hub train rows {len(hub_recs)}")
        if tmp.exists():
            try:
                tmp.unlink()
            except OSError:
                pass
    merged = merge_records(local_recs, hub_recs)
    logs.append(f"local {len(local_recs)}  merged {len(merged)}")
    grew = len(merged) > len(local_recs)
    if merged and (grew or len(merged) != len(local_recs)):
        write_records(train_path, fields, merged)
        logs.append("wrote merged train.csv locally")
    if dataset and merged:
        hub_upload(dataset, train_path, token)

    uniq = unique_quality(merged)
    uniq_path = train_path.with_name(train_path.name.replace("BREAK100_train_", "BREAK100_train_unique_"))
    if uniq_path == train_path:
        uniq_path = train_path.with_name("BREAK100_train_unique_" + train_path.name)
    if uniq:
        write_records(uniq_path, fields, uniq)
        logs.append(f"unique quality=1 rows {len(uniq)}")
        if dataset:
            hub_upload(dataset, uniq_path, token)

    outcome = train_path.with_name(train_path.name.replace("BREAK100_train_", "BREAK100_outcome_"))
    if outcome.exists() and dataset:
        hub_upload(dataset, outcome, token)

    if dataset:
        card = train_path.parent / "BREAK100_HF_README.md"
        card.write_text(DATASET_CARD, encoding="utf-8")
        try:
            from huggingface_hub import HfApi, login

            if token:
                login(token=token)
            HfApi().upload_file(
                path_or_fileobj=str(card),
                path_in_repo="README.md",
                repo_id=dataset,
                repo_type="dataset",
            )
            logs.append("Hub dataset card README.md")
        except Exception as e:
            logs.append(f"Hub dataset card: {e}")

    pol = T.policy_path(train_path)
    train_for_fit = uniq_path if uniq_path.exists() and len(uniq) >= T.MIN_N else train_path
    n_good = len(T.load_rows(train_for_fit))
    local_pn = policy_n(pol)
    need_train = n_good >= T.MIN_N and (local_pn < n_good or not pol.exists())
    if need_train:
        result = T.train_file(train_for_fit)
        logs.append(result["log"] + f"  (fit on {train_for_fit.name})")
        if dataset:
            hub_upload(dataset, Path(result["policy"]), token)
    elif dataset:
        remote_pol = pol.with_suffix(".hub-policy.csv")
        if hub_download(dataset, pol.name, token, remote_pol):
            rn = policy_n(remote_pol)
            if rn >= local_pn:
                pol.write_bytes(remote_pol.read_bytes())
                logs.append(f"pulled Hub policy n={rn}")
            try:
                remote_pol.unlink()
            except OSError:
                pass
    stamp = common_dir() / "BREAK100_sync_needed.txt"
    if stamp.exists():
        try:
            stamp.unlink()
        except OSError:
            pass
    return "\n".join(logs)


def run_once():
    root = common_dir()
    token, dataset = read_cfg(root)
    print(f"Common {root}")
    print(f"dataset {dataset or '(none — local only)'}")
    trains = sorted(root.glob("BREAK100_train_*.csv"))
    if not trains:
        trains = sorted(Path.cwd().glob("BREAK100_train_*.csv"))
    if not trains:
        print("No BREAK100_train_*.csv yet. Leave the EA on M30.")
    else:
        for p in trains:
            print(sync_one(p, token, dataset))
    if dataset:
        for p in sorted(root.glob("BREAK100_human_box_*.csv")):
            hub_upload(dataset, p, token)
    (root / STATE_NAME).write_text(str(int(time.time())), encoding="utf-8")
    return 0


def main():
    ap = argparse.ArgumentParser(description="BREAK100 HF bidirectional sync")
    ap.add_argument("--loop", type=int, default=0, help="Repeat every N seconds (0 = once)")
    args = ap.parse_args()
    print("BREAK100 HF sync  — both sides current. No broker orders.")
    while True:
        run_once()
        if args.loop <= 0:
            break
        time.sleep(args.loop)
    return 0


if __name__ == "__main__":
    sys.exit(main())
