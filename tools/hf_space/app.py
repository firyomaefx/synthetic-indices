"""BREAK100 always-on Hugging Face Space — backup trainer.

Upload BREAK100_train_*.csv (or load a Hub dataset), train, download policy.csv
for the EA. Does not send broker orders. Not a profit claim.
"""
from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

import gradio as gr

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT.parent))

import break100_hf_train as T  # noqa: E402

WORK = ROOT / "work"
WORK.mkdir(exist_ok=True)


def _run(csv_path: Path, hub_repo: str, token: str):
    result = T.train_file(csv_path)
    policy = Path(result["policy"])
    if hub_repo.strip():
        try:
            T.push_hub(hub_repo.strip(), csv_path, policy, T.load_rows(csv_path), token.strip())
            result["log"] += f"\nBacked up to dataset {hub_repo.strip()}"
        except Exception as e:
            result["log"] += f"\nHub backup failed: {e}"
    return result, policy if policy.exists() else None


def train_upload(file, hub_repo, token):
    if file is None:
        return "Upload BREAK100_train_*.csv first.", None
    src = Path(file.name if hasattr(file, "name") else file)
    dest = WORK / src.name
    shutil.copy(src, dest)
    result, policy = _run(dest, hub_repo or os.environ.get("BREAK100_HF_DATASET", ""), token or os.environ.get("HF_TOKEN", ""))
    return result["log"], str(policy) if policy else None


def train_hub(hub_repo, token, filename):
    hub_repo = (hub_repo or os.environ.get("BREAK100_HF_DATASET", "")).strip()
    token = (token or os.environ.get("HF_TOKEN", "")).strip()
    filename = (filename or "BREAK100_train_BREAK100.csv").strip()
    if not hub_repo:
        return "Set dataset repo id (e.g. you/break100-boom).", None
    try:
        from huggingface_hub import hf_hub_download
    except ImportError:
        return "huggingface_hub missing", None
    local = hf_hub_download(repo_id=hub_repo, filename=filename, repo_type="dataset", token=token or None)
    dest = WORK / Path(local).name
    shutil.copy(local, dest)
    result, policy = _run(dest, hub_repo, token)
    return result["log"], str(policy) if policy else None


with gr.Blocks(title="BREAK100 HF backup trainer") as demo:
    gr.Markdown(
        """# BREAK100 backup trainer (free CPU)

No GPU. No Pro. Spaces **sleep** — PC `break100_hf_sync.py` is always-on.

1. Dataset `Tengkolok/break100-boom` holds unique train + policy  
2. Pull + train here **or** upload `BREAK100_train_unique_*.csv`  
3. Put `policy.csv` in MT5 Common Files, reattach EA  

Need **16+** unique quality=1 rows. **Not a profit claim. No broker orders.**  
OCO (BUY fill cancels SELL, and the reverse) is the chart EA, not this Space.
"""
    )
    with gr.Tab("Upload CSV"):
        f = gr.File(label="BREAK100_train_*.csv", file_types=[".csv"])
        hub1 = gr.Textbox(label="Backup dataset repo (optional)", placeholder="yourname/break100-boom")
        tok1 = gr.Textbox(label="HF token (optional, write)", type="password")
        btn1 = gr.Button("Train", variant="primary")
        log1 = gr.Textbox(label="Result", lines=14)
        out1 = gr.File(label="policy.csv for the EA")
        btn1.click(train_upload, [f, hub1, tok1], [log1, out1])
    with gr.Tab("From Hub dataset"):
        hub2 = gr.Textbox(label="Dataset repo", placeholder="yourname/break100-boom")
        fn2 = gr.Textbox(label="Filename", value="BREAK100_train_unique_BREAK100.csv")
        tok2 = gr.Textbox(label="HF token", type="password")
        btn2 = gr.Button("Pull + train", variant="primary")
        log2 = gr.Textbox(label="Result", lines=14)
        out2 = gr.File(label="policy.csv for the EA")
        btn2.click(train_hub, [hub2, tok2, fn2], [log2, out2])

if __name__ == "__main__":
    demo.launch(server_name="0.0.0.0", server_port=int(os.environ.get("PORT", "7860")))
