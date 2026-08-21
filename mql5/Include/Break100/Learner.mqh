#ifndef BREAK100_LEARNER_MQH
#define BREAK100_LEARNER_MQH

// Causal UCB + MFE/MAE quantile TP/SL. Trains only on closed labels.

#define B100_LEARN_MIN    16
#define B100_LEARN_MAX    400
#define B100_LEARN_ARMS   4

struct B100Arm
  {
   string            id;
   double            sl_r;
   double            tp1_r;
   double            tp2_r;
   double            tp3_r;
  };

struct B100LearnSample
  {
   int               side;
   string            label;
   double            mfe;
   double            mae;
   double            hw;
   int               arm;
  };

struct B100LearnPolicy
  {
   bool              ready;
   string            source;
   int               n;
   string            arm_id;
   int               arm;
   double            sl_r;
   double            tp1_r;
   double            tp2_r;
   double            tp3_r;
   double            mean_r;
   double            p_up;
   double            p_dn;
   double            p_fail;
   string            dir_gate;
  };

struct B100Learner
  {
   B100LearnSample   samples[];
   int               n;
   int               last_arm;
   B100Arm           arms[B100_LEARN_ARMS];
  };

void B100LearnerInit(B100Learner &L)
  {
   L.n = 0;
   L.last_arm = 0;
   ArrayResize(L.samples, B100_LEARN_MAX);
   L.arms[0].id = "balanced"; L.arms[0].sl_r = 1.00; L.arms[0].tp1_r = 1.00; L.arms[0].tp2_r = 2.00; L.arms[0].tp3_r = 3.00;
   L.arms[1].id = "tight";    L.arms[1].sl_r = 0.85; L.arms[1].tp1_r = 0.80; L.arms[1].tp2_r = 1.50; L.arms[1].tp3_r = 2.20;
   L.arms[2].id = "wide";     L.arms[2].sl_r = 1.35; L.arms[2].tp1_r = 1.20; L.arms[2].tp2_r = 2.40; L.arms[2].tp3_r = 4.00;
   L.arms[3].id = "runner";   L.arms[3].sl_r = 1.10; L.arms[3].tp1_r = 1.60; L.arms[3].tp2_r = 3.00; L.arms[3].tp3_r = 5.00;
  }

double B100Clamp(const double x, const double lo, const double hi)
  {
   return MathMin(hi, MathMax(lo, x));
  }

void B100FillDirGate(const B100Learner &L, B100LearnPolicy &p);

double B100RealizedR(const B100LearnSample &s, const double sl_r, const double tp3_r)
  {
   const double hw = MathMax(s.hw, 1e-9);
   const double stop = sl_r * hw;
   const double tp3 = tp3_r * hw;
   const double cost = 0.12;
   if(MathAbs(s.mae) >= stop)
      return -1.0 - cost;
   const double captured = MathMin(MathMax(0.0, s.mfe), tp3);
   return captured / stop - cost;
  }

int B100PickArm(const B100Learner &L, const int side)
  {
   int counts[B100_LEARN_ARMS];
   double sums[B100_LEARN_ARMS];
   int n_side = 0;
   for(int a = 0; a < B100_LEARN_ARMS; a++)
     {
      counts[a] = 0;
      sums[a] = 0.0;
     }
   for(int i = 0; i < L.n; i++)
     {
      if(side != 0 && L.samples[i].side != side)
         continue;
      n_side++;
      const int a = L.samples[i].arm;
      if(a < 0 || a >= B100_LEARN_ARMS)
         continue;
      counts[a]++;
      sums[a] += B100RealizedR(L.samples[i], L.arms[a].sl_r, L.arms[a].tp3_r);
     }
   if(n_side < B100_LEARN_MIN)
      return 0;
   const double logN = MathLog(n_side + 1.0);
   int best = 0;
   double best_score = -1.0e100;
   for(int a = 0; a < B100_LEARN_ARMS; a++)
     {
      if(counts[a] == 0)
         return a;
      const double mean = sums[a] / counts[a];
      const double score = mean + 1.15 * MathSqrt(logN / counts[a]);
      if(score > best_score)
        {
         best_score = score;
         best = a;
        }
     }
   return best;
  }

void B100QuantileOf(const double &src[], const int n, const double q, double &out)
  {
   if(n <= 0)
     {
      out = 0.0;
      return;
     }
   double tmp[];
   ArrayResize(tmp, n);
   for(int i = 0; i < n; i++)
      tmp[i] = src[i];
   ArraySort(tmp);
   int idx = (int)MathFloor(q * (n - 1));
   if(idx < 0) idx = 0;
   if(idx > n - 1) idx = n - 1;
   out = tmp[idx];
  }

void B100LearnerPolicy(B100Learner &L, const int side, B100LearnPolicy &p)
  {
   double maeR[];
   double mfeR[];
   int n_mae = 0;
   int n_mfe = 0;
   ArrayResize(maeR, L.n);
   ArrayResize(mfeR, L.n);
   int n_side = 0;
   for(int i = 0; i < L.n; i++)
     {
      if(side != 0 && L.samples[i].side != side)
         continue;
      n_side++;
      const double hw = MathMax(L.samples[i].hw, 1e-9);
      maeR[n_mae++] = MathAbs(L.samples[i].mae) / hw;
      if(L.samples[i].label == "BREAKOUT_UP" || L.samples[i].label == "BREAKOUT_DOWN")
         mfeR[n_mfe++] = MathMax(0.0, L.samples[i].mfe) / hw;
     }
   p.n = n_side;
   if(n_side < B100_LEARN_MIN)
     {
      p.ready   = false;
      p.source  = "DEFAULT";
      p.arm     = 0;
      p.arm_id  = L.arms[0].id;
      p.sl_r    = L.arms[0].sl_r;
      p.tp1_r   = L.arms[0].tp1_r;
      p.tp2_r   = L.arms[0].tp2_r;
      p.tp3_r   = L.arms[0].tp3_r;
      p.mean_r  = 0.0;
      p.p_up = p.p_dn = p.p_fail = 0.0;
      p.dir_gate = "BOTH";
      L.last_arm = 0;
      return;
     }
   const int arm = B100PickArm(L, side);
   L.last_arm = arm;
   p.ready  = true;
   p.source = "UCB_QUANTILE";
   p.arm    = arm;
   p.arm_id = L.arms[arm].id;
   double qsl, q1, q2, q3;
   B100QuantileOf(maeR, n_mae, 0.75, qsl);
   B100QuantileOf(mfeR, n_mfe, 0.40, q1);
   B100QuantileOf(mfeR, n_mfe, 0.65, q2);
   B100QuantileOf(mfeR, n_mfe, 0.85, q3);
   if(n_mae == 0) qsl = L.arms[arm].sl_r;
   if(n_mfe == 0) { q1 = L.arms[arm].tp1_r; q2 = L.arms[arm].tp2_r; q3 = L.arms[arm].tp3_r; }
   qsl = B100Clamp(qsl, 0.7, 2.4);
   q1  = B100Clamp(q1, 0.5, 3.0);
   q2  = B100Clamp(MathMax(q2, q1 + 0.15), q1 + 0.15, 5.0);
   q3  = B100Clamp(MathMax(q3, q2 + 0.15), q2 + 0.15, 8.0);
   p.sl_r  = B100Clamp(0.55 * L.arms[arm].sl_r  + 0.45 * qsl, 0.7, 2.5);
   p.tp1_r = B100Clamp(0.55 * L.arms[arm].tp1_r + 0.45 * q1,  0.5, 4.0);
   p.tp2_r = B100Clamp(0.55 * L.arms[arm].tp2_r + 0.45 * q2,  p.tp1_r + 0.2, 6.0);
   p.tp3_r = B100Clamp(0.55 * L.arms[arm].tp3_r + 0.45 * q3,  p.tp2_r + 0.2, 8.0);
   double sum = 0.0;
   int k = 0;
   for(int i = 0; i < L.n; i++)
     {
      if(side != 0 && L.samples[i].side != side)
         continue;
      sum += B100RealizedR(L.samples[i], p.sl_r, p.tp3_r);
      k++;
     }
   p.mean_r = (k > 0) ? sum / k : 0.0;
   B100FillDirGate(L, p);
  }

void B100FillDirGate(const B100Learner &L, B100LearnPolicy &p)
  {
   int n_up = 0, n_dn = 0, n_fail = 0;
   for(int i = 0; i < L.n; i++)
     {
      if(L.samples[i].label == "BREAKOUT_UP")
         n_up++;
      else if(L.samples[i].label == "BREAKOUT_DOWN")
         n_dn++;
      else
         n_fail++;
     }
   const double tot = (double)(n_up + n_dn + n_fail + 3);
   double pu = (n_up + 1.0) / tot;
   double pd = (n_dn + 1.0) / tot;
   double pf = (n_fail + 1.0) / tot;
   if(p.p_up + p.p_dn + p.p_fail > 0.5)
     {
      pu = 0.5 * pu + 0.5 * p.p_up;
      pd = 0.5 * pd + 0.5 * p.p_dn;
      pf = 0.5 * pf + 0.5 * p.p_fail;
     }
   p.p_up = pu;
   p.p_dn = pd;
   p.p_fail = pf;
   p.dir_gate = "BOTH";
   if(p.n < B100_LEARN_MIN)
      return;
   if(pf > pu && pf > pd && pf >= 0.42)
     {
      p.dir_gate = "SKIP";
      return;
     }
   if(pu >= pd + 0.12 && pu >= 0.38)
      p.dir_gate = "BUY";
   else if(pd >= pu + 0.12 && pd >= 0.38)
      p.dir_gate = "SELL";
  }

void B100LearnerObserve(B100Learner &L, const int side, const string label, const double mfe, const double mae, const double hw)
  {
   if(L.n >= B100_LEARN_MAX)
     {
      for(int i = 1; i < L.n; i++)
         L.samples[i - 1] = L.samples[i];
      L.n--;
     }
   const int i = L.n;
   L.samples[i].side  = side;
   L.samples[i].label = label;
   L.samples[i].mfe   = mfe;
   L.samples[i].mae   = mae;
   L.samples[i].hw    = hw;
   L.samples[i].arm   = L.last_arm;
   L.n++;
  }

string B100LearnerFileName(void)
  {
   string sym = _Symbol;
   StringReplace(sym, " ", "_");
   return "BREAK100_learn_" + sym + ".csv";
  }

void B100LearnerSave(const B100Learner &L)
  {
   const int fh = FileOpen(B100LearnerFileName(), FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(fh == INVALID_HANDLE)
      return;
   FileWrite(fh, "side", "label", "mfe", "mae", "hw", "arm");
   for(int i = 0; i < L.n; i++)
      FileWrite(fh, L.samples[i].side, L.samples[i].label, L.samples[i].mfe, L.samples[i].mae, L.samples[i].hw, L.samples[i].arm);
   FileClose(fh);
  }

void B100LearnerLoad(B100Learner &L)
  {
   const int fh = FileOpen(B100LearnerFileName(), FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(fh == INVALID_HANDLE)
      return;
   FileReadString(fh); FileReadString(fh); FileReadString(fh);
   FileReadString(fh); FileReadString(fh); FileReadString(fh);
   while(!FileIsEnding(fh) && L.n < B100_LEARN_MAX)
     {
      const int i = L.n;
      L.samples[i].side  = (int)FileReadNumber(fh);
      L.samples[i].label = FileReadString(fh);
      L.samples[i].mfe   = FileReadNumber(fh);
      L.samples[i].mae   = FileReadNumber(fh);
      L.samples[i].hw    = FileReadNumber(fh);
      L.samples[i].arm   = (int)FileReadNumber(fh);
      if(L.samples[i].hw > 0.0)
         L.n++;
     }
   FileClose(fh);
  }

string B100PolicyFileName(void)
  {
   string sym = _Symbol;
   StringReplace(sym, " ", "_");
   return "BREAK100_policy_" + sym + ".csv";
  }

bool B100PolicyLoad(B100LearnPolicy &p)
  {
   const int fh = FileOpen(B100PolicyFileName(), FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(fh == INVALID_HANDLE)
      return false;
   int ncols = 0;
   while(!FileIsEnding(fh) && !FileIsLineEnding(fh) && ncols < 20)
     {
      FileReadString(fh);
      ncols++;
     }
   p.ready  = (FileReadNumber(fh) != 0.0);
   p.source = FileReadString(fh);
   p.n      = (int)FileReadNumber(fh);
   p.arm    = (int)FileReadNumber(fh);
   p.sl_r   = FileReadNumber(fh);
   p.tp1_r  = FileReadNumber(fh);
   p.tp2_r  = FileReadNumber(fh);
   p.tp3_r  = FileReadNumber(fh);
   p.mean_r = FileReadNumber(fh);
   p.p_up = p.p_dn = p.p_fail = 0.0;
   p.dir_gate = "BOTH";
   if(ncols >= 13 && !FileIsEnding(fh))
     {
      p.p_up     = FileReadNumber(fh);
      p.p_dn     = FileReadNumber(fh);
      p.p_fail   = FileReadNumber(fh);
      p.dir_gate = FileReadString(fh);
     }
   FileClose(fh);
   if(p.arm < 0) p.arm = 0;
   if(p.arm > 3) p.arm = 3;
   if(p.source == "")
      p.source = "RL_UCB";
   if(p.dir_gate == "")
      p.dir_gate = "BOTH";
   p.arm_id = (p.arm == 1 ? "tight" : p.arm == 2 ? "wide" : p.arm == 3 ? "runner" : "balanced");
   return (p.sl_r > 0.0 && p.tp3_r > 0.0);
  }

#endif
