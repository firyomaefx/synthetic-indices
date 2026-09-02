# Quarantined v1 data — do not train on these

Retained as evidence of three defects fixed on `feat/validated-signal`. Nothing in
the pipeline reads these files: the loaders now use `*_v2_*` filenames, so the v1
files are retired without being deleted.

## `BREAK100_train_BREAK100.v1-corrupt.csv`

Every *filled* row has `mfe == -mae`. `Train.mqh` computed `adv = -fav` and then
took `min(adv)`, which is identically `-max(fav)` — so MAE was never an
independent measurement. Verify:

```bash
awk -F, 'NR>1 && $8!="TRAP" {n++; if($3==-$4) m++} END {print n" filled rows, "m" mirrored"}' BREAK100_train_BREAK100.v1-corrupt.csv
```

Prints `13 filled rows, 13 mirrored`. Every adverse-excursion figure recorded for
a filled trade was a mirror of the favourable one.

The 2 remaining rows (15 total) are `TRAP` — boxes that were never filled. They
escape the defect only because `B100TrainFail()` writes `mfe = 0, mae = -hw`
directly instead of going through `B100TrainStep()`.

## `BREAK100_learn_BREAK100.v1-corrupt.csv`

400 samples: 233 `BREAKOUT_UP`, 159 `BOUNCE`, 6 `BREAKOUT_DOWN`, 2 censored.
`BOUNCE` is a channel-strategy label the box strategy never emits — box exits
were being sized by a policy fitted largely on another strategy's outcomes.
Side mix 314 up / 84 down gave `p_dn = 0.0035`.

## `BREAK100_policy_BREAK100.v1-corrupt.csv`

The policy those two produced:

```
ready,source,n,arm,sl_r,tp1_r,tp2_r,tp3_r,mean_r,p_up,p_dn,p_fail,gate
1,HF_TABULAR,400,3,0.92,2.23,3.404,4.5715,1.363484,0.381625,0.003534,0.614841,SKIP
```

Note `gate=SKIP` — the model concluded the setup fails more often than it works
(`p_fail = 0.615`). The live EA never acted on it: `allow_buy`/`allow_sell` were
written `true` in four places in `Box.mqh` and set `false` nowhere, and `dir_gate`
appeared only inside `Print()` calls.

`mean_r = 1.36` is not evidence of edge. It came from `B100RealizedR()` reading
the mirrored MAE above.
