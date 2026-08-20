Clone or pull https://github.com/firyomaefx/synthetic-indices.git in this worktree.

Install the BREAK100 Observe/Shadow EA on this Windows machine:

1. Copy mql5/Experts/BREAK100.mq5, mql5/Indicators/BREAK100_Channel.mq5, and the whole mql5/Include/Break100 folder into every MetaQuotes Terminal MQL5 data folder under $env:APPDATA\MetaQuotes\Terminal.
2. Find metaeditor64.exe (origin.txt next to each terminal, or Program Files).
3. Compile the indicator first, then the EA: metaeditor64.exe /compile:<file> /include:<MQL5 dir> /log:<file.log>
4. Both logs must show 0 errors. EA #property version must be 1.42.
5. Do not add OrderSend, CTrade, or Live trading. AutoTrading stays OFF.
6. Real synthetic account is OK for tick data. issued action is always NO_TRADE.
7. After compile: tell me the log summary and the exact steps to attach BREAK100 to Boom 100 Index M1.

Optional: if mql5/Install-BREAK100.ps1 can be pointed at a pack with a sibling MQL5 folder, run that instead.

Then keep this worktree as the laptop half of the project. Web Grok Build syncs via git push/pull only. There is no live shared filesystem.
