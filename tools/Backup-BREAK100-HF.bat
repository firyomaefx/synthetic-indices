@echo off
REM Always-on backup: train locally then push train.csv + policy.csv to HF dataset.
REM Set once:
REM   setx HF_TOKEN hf_xxx
REM   setx BREAK100_HF_DATASET yourname/break100-boom
cd /d "%~dp0"
python -m pip install -q -r requirements-hf.txt
if "%BREAK100_HF_DATASET%"=="" (
  echo Set BREAK100_HF_DATASET e.g. yourname/break100-boom
  echo Training locally only.
  python break100_hf_train.py %*
) else (
  python break100_hf_train.py %* --push-hub %BREAK100_HF_DATASET%
)
pause
