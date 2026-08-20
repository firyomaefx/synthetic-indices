# One repo, two Grok Build agents

There is no live shared disk between **web Grok Build** (grok.com chat) and
**laptop Grok Build** (`Grok Build 1.0.5` at `C:\Users\User`). They integrate
only through this GitHub remote.

```
github.com/firyomaefx/synthetic-indices
        │
        ├── web Grok Build (this product UI / zip)
        └── laptop Grok Build (PowerShell, MetaEditor, your MT5)
```

## What each agent owns

| Agent | Can do | Cannot do |
|---|---|---|
| Web Grok Build | Edit sources, pack zip, Windows trainer `.exe` | Touch your MT5, press F7, remote the PC |
| Laptop Grok Build | `git clone`, copy into `%APPDATA%\MetaQuotes`, run `metaeditor64.exe /compile` | See the web sandbox files until you `git pull` |

## Laptop — first run

In Grok Build 1.0.5: **New worktree** (`Ctrl+W`), then paste
`prompts/LAPTOP_GROK.md` or this:

```
git clone https://github.com/firyomaefx/synthetic-indices.git
cd synthetic-indices
git pull

Copy mql5/Experts, mql5/Indicators, mql5/Include/Break100 into every
%APPDATA%\MetaQuotes\Terminal\<hash>\MQL5\ matching folder.

Find metaeditor64.exe. Compile BREAK100_Channel.mq5 then BREAK100.mq5
with /compile /include /log. Both must be 0 errors. Version 1.42.

Do not add OrderSend. AutoTrading stays OFF. Real account is OK for ticks.
Then tell me how to attach BREAK100 to Boom 100 Index M1.
```

Or from PowerShell in the clone:

```powershell
# Install-BREAK100.ps1 expects a sibling MQL5\ tree. Create it once:
cd synthetic-indices
New-Item -ItemType Directory -Force mql5-pack\MQL5 | Out-Null
Copy-Item -Recurse -Force mql5\Experts, mql5\Indicators, mql5\Include mql5-pack\MQL5\
Copy-Item mql5\Install-BREAK100.ps1 mql5-pack\
cd mql5-pack
powershell -ExecutionPolicy Bypass -File .\Install-BREAK100.ps1
```

## Web — keep GitHub current

After this chat changes MQL5 or the learner, commit and `git push` to
`master`. On the laptop: `git pull`, then re-run the installer.

## Safety

Observe/Shadow only. No broker orders. Demo/Live remain NO-GO.
No profitability claim.
