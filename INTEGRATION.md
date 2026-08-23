# One repo, two machines

Web Grok and laptop Grok do not share a disk. They meet only here:

`https://github.com/firyomaefx/synthetic-indices`

```
github.com/firyomaefx/synthetic-indices
        │
        ├── web Grok (edits in the cloud)
        └── laptop Grok (PowerShell, MetaEditor, your MT5)
```

## Who does what

| | Can | Cannot |
|---|---|---|
| Web Grok | Edit sources, rewrite docs | Touch your MT5, press F7 |
| Laptop Grok | `git pull`, copy into `%APPDATA%\MetaQuotes`, compile | See web files until you pull |

Current EA on the laptop: **v2.04**. Chart: **BREAK100 M30**. Live locked.

## Laptop — first run

```
git clone https://github.com/firyomaefx/synthetic-indices.git
cd synthetic-indices
git pull origin master
```

Copy `mql5/Experts/BREAK100.mq5` and `mql5/Include/Break100/*` into each terminal `MQL5` folder. Compile with MetaEditor. **0 errors.** Attach on **BREAK100 M30** only.

Or:

```powershell
cd synthetic-indices
New-Item -ItemType Directory -Force mql5-pack\MQL5 | Out-Null
Copy-Item -Recurse -Force mql5\Experts, mql5\Indicators, mql5\Include mql5-pack\MQL5\
Copy-Item mql5\Install-BREAK100.ps1 mql5-pack\
cd mql5-pack
powershell -ExecutionPolicy Bypass -File .\Install-BREAK100.ps1
```

Secrets stay in Common Files (`BREAK100_telegram.txt`, `BREAK100_hf.txt`). Never in git.
