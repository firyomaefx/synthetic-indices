@echo off
REM Train BREAK100 policy with Hugging Face datasets + sklearn.
REM Drag BREAK100_train_*.csv onto this bat, or run it from Common\Files.
cd /d "%~dp0"
python -m pip install -q -r requirements-hf.txt
if "%~1"=="" (
  python break100_hf_train.py
) else (
  python break100_hf_train.py "%~1"
)
pause
